#!/usr/bin/env python3
"""OGL · UI 细节度门禁（设计令牌一致性）。

## 它防的是什么
本仓库曾出现：卡片圆角 2/6/8/12/24 五种并存、间距 10/20/28 等非刻度值散落、
同一角色的按钮两处圆角不同、硬编码 `Colors.red` 绕过 `colorScheme`。
这些都不是语法问题，编译器不会报错，但会让界面"看着不对劲"。

因此把**设计令牌之外的字面值**设为门禁：

| 规则 | 说明 |
| --- | --- |
| 裸 `EdgeInsets.*(数字)` | 必须用 `OgLSpace.*` |
| 裸 `SizedBox(height/width: 数字)` | 必须用 `OgLSpace.*` |
| 裸 `BorderRadius.circular(数字)` | 必须用 `OgLRadius.*` |
| 裸 `fontSize: 数字`（非等宽字体） | 必须用 `textTheme.*` |
| `Colors.<名>` / `Color(0x…)` | 必须用 `colorScheme.*` 或 `OgLSemanticColors` |
| `Duration(milliseconds: 数字)`（motion.dart 外） | 动效必须走档位表 |
| `Curves.<名>`（允许清单外） | 曲线必须走档位表 |

例外一律登记在 [ALLOW]，并写明**为什么它是数据而不是设计漂移**。

用法：
    python3 tool/ui_audit.py            # 报告
    python3 tool/ui_audit.py --fatal    # CI：有问题即失败
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib'

# ── 例外登记（文件 → 理由）────────────────────────────────────────────────
# 只登记"这些字面值本身就是数据"的文件，**不登记**"懒得改"的文件。
ALLOW = {
    'lib/surface/util/og_l_space.dart': '间距令牌定义自身',
    'lib/surface/util/og_l_radius.dart': '圆角 / 图标令牌定义自身',
    'lib/surface/theme.dart': '组件级主题 —— 设计令牌的唯一来源',
    'lib/surface/util/file_icons.dart': '文件类型图标色（GitHub 语言色，属数据）',
    'lib/surface/util/og_l_code_palette.dart': '代码配色色板（用户可选外观，属数据）',
    'lib/surface/widgets/code_editor_field.dart': '代码高亮配色（语法着色，属数据）',
    'lib/surface/app/boot_splash.dart': '首帧占位屏 —— 渲染时主题尚未编译，只能用字面色',
    'lib/surface/pages/settings_page.dart': '设置页含代码字体 / 字号选择器（用户可调，非设计令牌）',
    'lib/surface/pages/code_editor_page.dart': '代码编辑器 —— 字号由设置驱动且为等宽字体',
    'lib/surface/pages/file_preview_page.dart': '代码预览 —— 字号由设置驱动',
    'lib/surface/pages/about_page.dart': '关于页含版本号等宽文本',
    'lib/surface/pages/repo_page.dart': '仓库页含代码片段等宽文本',
    'lib/surface/pages/commit_page.dart': '提交页含 diff 等宽文本',
    'lib/surface/pages/gist_detail_page.dart': 'Gist 页含代码等宽文本',
    'lib/surface/pages/new_gist_page.dart': '新建 Gist 页含代码等宽文本',
    'lib/surface/pages/drafts_page.dart': '草稿页含代码等宽文本',
    'lib/surface/pages/pull_page.dart': 'PR 页含代码等宽文本',
    'lib/surface/util/og_l_log_file*.dart': '日志格式定义',
    'lib/surface/app/motion.dart': '动效档位表 —— 时长的唯一来源',
    'lib/main.dart': '全局 ErrorWidget 兜底 —— 主题尚未存在时的字面色',
    'lib/base/disk/disk_cache.dart': '读回延迟（缓存策略，非动画）',
    'lib/base/net/net_retry.dart': '重试退避（网络策略，非动画）',
}

# 间距 / 圆角刻度（出现这些值以外的一律算漂移）
SPACE_SCALE = {'4', '8', '12', '16', '24', '32', '48', '64'}
RADIUS_SCALE = {'4', '8', '12', '16', '24', '999'}

NUM = r'(\d+(?:\.\d+)?)'

RULES = [
    ('裸 EdgeInsets', re.compile(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^)]*)\)')),
    ('裸 SizedBox', re.compile(r'SizedBox\((?:height|width): ' + NUM + r'\)')),
    ('裸 BorderRadius', re.compile(r'BorderRadius\.circular\(' + NUM + r'\)')),
    ('裸 fontSize', re.compile(r'fontSize: ' + NUM)),
    ('字面色', re.compile(r'(?:Colors\.[a-z]+|Color\(0x[0-9A-Fa-f]{6,8}\))')),
    ('裸动画时长', re.compile(r'Duration\(milliseconds: ' + NUM + r'\)')),
    ('裸曲线', re.compile(r'Curves\.([a-zA-Z]+)')),
]

# 曲线允许清单（档位表内定义的曲线族）
CURVES_ALLOWED = {
    'easeOut', 'easeOutCubic', 'easeOutQuart', 'easeOutQuint', 'easeOutBack',
    'linear', 'easeInOut', 'easeInOutCubic', 'fastOutSlowIn', 'decelerate',
}

# 颜色允许清单（中性值，不属于设计漂移）
COLOR_NEUTRAL = {'Colors.transparent'}


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT)).replace('\\', '/')


def is_allowed(relpath: str) -> str | None:
    for k, v in ALLOW.items():
        if k.endswith('*'):
            if relpath.startswith(k[:-1]):
                return v
        elif relpath == k:
            return v
    return None


def scan() -> list[tuple[str, str, int, str]]:
    hits: list[tuple[str, str, int, str]] = []
    for p in sorted(LIB.rglob('*.dart')):
        r = rel(p)
        reason = is_allowed(r)
        if reason:
            continue
        lines = p.read_text(encoding='utf-8').split('\n')
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('///'):
                continue

            # 1) EdgeInsets：参数里出现"刻度外"的数字
            for m in RULES[0][1].finditer(line):
                for num in re.findall(NUM, m.group(1)):
                    if num in ('0', '0.0'):
                        continue
                    if num not in SPACE_SCALE:
                        hits.append(('裸 EdgeInsets', r, i, stripped[:110]))
                        break

            # 2) SizedBox 数字
            m = RULES[1][1].search(line)
            if m and m.group(1) not in ('0', '0.0'):
                hits.append(('裸 SizedBox', r, i, stripped[:110]))

            # 3) BorderRadius 数字
            m = RULES[2][1].search(line)
            if m and m.group(1) not in RADIUS_SCALE:
                hits.append(('裸 BorderRadius', r, i, stripped[:110]))

            # 4) fontSize 字面量（等宽字体上下文放行）
            m = RULES[3][1].search(line)
            if m:
                ctx = '\n'.join(lines[max(0, i - 3):i + 2])
                if 'monospace' not in ctx:
                    hits.append(('裸 fontSize', r, i, stripped[:110]))

            # 5) 字面色
            for m in RULES[4][1].finditer(line):
                tok = m.group(0)
                if tok in COLOR_NEUTRAL:
                    continue
                if tok == 'Colors.entries':
                    continue
                hits.append(('字面色', r, i, stripped[:110]))
                break

            # 6) 动画时长（motion.dart 是令牌来源，已白名单外）
            if RULES[5][1].search(line):
                hits.append(('裸动画时长', r, i, stripped[:110]))

            # 7) 曲线
            m = RULES[6][1].search(line)
            if m and m.group(1) not in CURVES_ALLOWED:
                hits.append(('裸曲线', r, i, stripped[:110]))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    args = ap.parse_args()

    hits = scan()
    print('UI 细节度扫描（lib/）：%d 处' % len(hits))
    by_rule: dict[str, list] = {}
    for label, r, i, text in hits:
        by_rule.setdefault(label, []).append((r, i, text))

    for label in sorted(by_rule):
        rows = by_rule[label]
        print('\n## %s（%d）' % (label, len(rows)))
        for r, i, text in rows[:40]:
            print('  %s:%d  %s' % (r, i, text))
        if len(rows) > 40:
            print('  … 其余 %d 处' % (len(rows) - 40))

    if args.fatal and hits:
        print('\n[fatal] UI 细节度不合规：%d 处' % len(hits))
        return 1
    print('\nUI 细节度审计通过：0 处令牌外字面值' if not hits else '')
    return 0


if __name__ == '__main__':
    sys.exit(main())
