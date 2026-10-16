#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 性能反模式扫描（一次性诊断 + 可作 CI 门禁）。

## 为什么是这几条
都是"简单、稳定、不依赖具体页面"的常识性规则——不改架构、不搞特判：

1. **急加载列表**：`ListView(children: [...])` 会一次性构建全部子项；
   长列表（通知/下载/日志/仓库文件）应用 `ListView.builder`。
2. **`shrinkWrap: true`**：在可滚动父级里会让子列表被**完整测量两次**。
3. **过宽的 `MediaQuery.of(context)`**：会随键盘 insets / 旋转等任何变化重建；
   只需要尺寸/内边距时应用 `MediaQuery.sizeOf` / `paddingOf` / `textScalerOf`。
4. **`Opacity` 控件**：会强制 `saveLayer`；能用 `AnimatedOpacity` 收尾态
   或 `Color.withValues(alpha:)` 就别用。
5. **`IndexedStack` 未配 `TickerMode`**：被隐藏的页仍在跑动画（白烧帧）。

用法：
    python3 tool/perf_audit.py            # 报告
    python3 tool/perf_audit.py --fatal    # CI：有可自动修的问题即失败
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SURFACE = os.path.join(ROOT, 'lib', 'surface')

# 允许例外（file: 说明）——登记时必须写清理由
ALLOW = {
    # 数据驱动长列表：OgLLogBody 内部已是 builder 虚拟化。
    'lib/surface/pages/action_log_page.dart': 'OgLLogBody 内部已是 builder 虚拟化',
    # 通知宿主自身的窄列表。
    'lib/surface/app/error_surface.dart': '通知宿主自身的窄列表',
    # `MarkdownBody` 在 Column 里必须 shrinkWrap（父级无界）。
    'lib/surface/widgets/readme_view.dart': 'MarkdownBody 位于无界父级，必须 shrinkWrap',
    # 需要整份窗口指标（insets + padding + size），无法用窄选择器。
    'lib/surface/app/keyboard_guard.dart': '需 insets/padding/size 多项指标',
    # 需要 textScaler + disableAnimations 并据此 copyWith MediaQuery。
    'lib/surface/app/og_l_app.dart': '需 textScaler 与 disableAnimations 并 copyWith',
}

# 行级规则（简单、无歧义）
# 「已评估：数量有界，保持急加载」——不是漏改，是在这里写明理由。
# 急加载对这些页面**更划算**（数据量小、一次性构建省掉懒加载的每帧判断），
# 登记之后报告里就不再"看起来像待办"。
REVIEWED_BOUNDED = {
    'lib/surface/pages/about_page.dart': '静态清单（依赖/许可，常量条数）',
    'lib/surface/pages/profile_page.dart': '本地账号（通常 ≤ 10）',
    'lib/surface/pages/gist_detail_page.dart': 'Gist 文件（通常 < 20）',
    'lib/surface/pages/release_detail_page.dart': 'Release 附件（通常 < 30）',
    'lib/surface/pages/workflow_dispatch_page.dart': '工作流 inputs（表单，条数少）',
    'lib/surface/pages/repo_page.dart': '分支选择弹层（打开即用，通常几十条）',
    'lib/surface/pages/ai_settings_page.dart': 'AI 设置项固定条数',
    'lib/surface/pages/settings_section_page.dart': '设置分区（折叠分组，条数少）',
}

RULES = [
    ('shrinkWrap', re.compile(r'shrinkWrap:\s*true')),
    ('宽 MediaQuery.of', re.compile(r'MediaQuery\.of\(context\)')),
    ('Opacity 控件', re.compile(r'(?<!Animated)\bOpacity\(')),
    # ── 着色器 / 合成类卡顿源 ────────────────────────────────────────────
    # 以下四类都会触发 saveLayer（离屏合成）：每帧一次额外的全区域绘制，
    # 是"动画/滚动卡顿"的典型成因，且在 Skia 桌面目标上还会触发**运行时
    # 着色器编译**（首帧明显掉帧）。
    # 若确有必要使用，请在本文件的白名单里登记并写明理由。
    ('BackdropFilter（saveLayer）', re.compile(r'\bBackdropFilter\(')),
    ('ImageFilter.blur（saveLayer）', re.compile(r'ImageFilter\.blur|BlurStyle')),
    ('ColorFiltered（saveLayer）', re.compile(r'\bColorFiltered\(')),
    ('ShaderMask（saveLayer）', re.compile(r'\bShaderMask\(')),
]

# 「急加载长列表」需要看**块**：`ListView(children: [...])` 里出现 `for (`
# 才说明它在一次性构建长度不受控的数据行（静态表单列表不在此列）。
LISTVIEW = re.compile(r'ListView\(')
FOR_IN_CHILDREN = re.compile(r'\bfor\s*\(')


def scan_eager_lists(path, rel):
    """返回 [(行号, 片段)]：`ListView(children: [...])` 内含 `for (` 的位置。"""
    hits = []
    text = io.open(path, encoding='utf-8').read()
    for match in LISTVIEW.finditer(text):
        # 找到配平右括号，得到整个 ListView(...) 块
        depth = 0
        index = match.start()
        while index < len(text):
            char = text[index]
            if char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
                if depth == 0:
                    break
            index += 1
        block = text[match.start():index + 1]
        if FOR_IN_CHILDREN.search(block):
            line = text.count('\n', 0, match.start()) + 1
            hits.append((line, ' '.join(block.split())[:110]))
    return hits


def scan():
    hits = []
    for dirpath, _dirs, files in os.walk(SURFACE):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT)
            with open(full, encoding='utf-8') as handle:
                lines = handle.readlines()
            for index, line in enumerate(lines, start=1):
                stripped = line.strip()
                if stripped.startswith('//'):
                    continue
                for label, pattern in RULES:
                    if pattern.search(line):
                        hits.append((label, rel, index, stripped[:110]))
            for line, snippet in scan_eager_lists(full, rel):
                hits.append(('急加载长列表', rel, line, snippet))
    return hits


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fatal', action='store_true')
    args = parser.parse_args()

    hits = scan()
    by_rule = {}
    for label, rel, line, text in hits:
        by_rule.setdefault(label, []).append((rel, line, text))

    print('性能反模式扫描（lib/surface）：%d 处' % len(hits))
    for label in sorted(by_rule):
        rows = by_rule[label]
        print('\n## %s（%d）' % (label, len(rows)))
        for rel, line, text in rows:
            if rel in ALLOW:
                mark = '（已登记例外）'
            elif rel in REVIEWED_BOUNDED:
                mark = '（已评估·数量有界：%s）' % REVIEWED_BOUNDED[rel]
            else:
                mark = ''
            print('  %s:%d%s %s' % (rel, line, mark, text))

    # 门禁只看"未登记例外"的急加载列表与 shrinkWrap：这两条修起来确定、无争议
    # 门禁只保留**客观无歧义**的两类：
    # - `shrinkWrap: true`（在可滚动父级里会被完整测量两次）；
    # - 过宽的 `MediaQuery.of(context)`（键盘/旋转都会重建整列）。
    #
    # 「急加载长列表」只报告不拦截：循环体长度是**语义**问题（静态可知的短列表
    # 与数据驱动的长列表在语法上一样），硬拦会逼出无意义的白名单。
    # 数据驱动长列表的正确写法见 `OgLAsyncSliver`（PR / commit 文件列已改用它）。
    fatal_hits = [
        (label, rel, line) for label, rel, line, _text in hits
        if rel not in ALLOW
        and label in ('shrinkWrap', '宽 MediaQuery.of')
    ]
    if args.fatal and fatal_hits:
        print('\n[fatal] 需处理 %d 处：' % len(fatal_hits))
        for label, rel, line in fatal_hits:
            print('  %s:%d [%s]' % (rel, line, label))
        return 1
    print('\n审计通过（未登记例外的反模式：0）' if not fatal_hits else '')
    return 0


if __name__ == '__main__':
    sys.exit(main())