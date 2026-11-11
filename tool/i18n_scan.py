#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · i18n 抽取与校验工具（5.0 多语言工程的基础设施）。

## 它做什么
1. **抽取**：扫描 `lib/` 下所有 Dart 源码里的**中文字符串字面量**（跳过注释），
   按"文件 → 页面分片"映射，输出待翻译清单（JSON + CSV）。
2. **拆分**：按 `assets/i18n/<locale>/<page>.json` 的既有结构归类，
   并给出每个 page 的 key 计数（对照现有分片，指出缺哪些）。
3. **校验（--check）**：发现**新增的中文字面量**即有非零退出，供 CI 卡住回退；
   同时校验各语言分片的 key 集合是否与 zh 对齐（缺 key / 多 key）。

## 用法
    python3 tool/i18n_scan.py                    # 打印报告
    python3 tool/i18n_scan.py --json out.json    # 导出 JSON 清单
    python3 tool/i18n_scan.py --check            # CI 模式（有问题退出 1）
    python3 tool/i18n_scan.py --allowlist tool/i18n_allow.txt  # 允许的中文（如日志/注释）

## 设计取舍（与用户要求一致）
- 中文/英文**按语境人工翻译**，专有名词（GitHub / Release / Actions / PR / Token…）
  **不过度翻译**，描述不加额外语句 —— 因此工具只做"找出来、归类、对齐"，
  不自动机器翻译 zh/en；
- 其余语言由**机翻**产出，键集合以 zh 为基准（见 `--check`）。
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

# ★ 批 9 · X-01：与 layer_audit 同因，禁止依赖 CWD。
REPO_ROOT = Path(__file__).resolve().parent.parent

CJK = re.compile(r'[\u4e00-\u9fff]')
# 单/双引号字符串（含转义），以及 raw 字符串前缀。
STRING = re.compile(r"(?<![\w])(r?)('(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\")")
LINE_COMMENT = re.compile(r'//[^\n]*')
# 「日志上下文」：这些行里的中文按**开发者日志**处理（不本地化，按设计保留）。
#
# ★ 这里**只列精确的日志入口**，不用 `log\w*(` 这类模糊式。教训：`log\w*(`
#   会命中 `AlertDialog(`（子串 `log(`）、`showDialog(`、`catalog(`，甚至
#   `login(`（`\w*` 吞掉 "in"）—— 于是对话框附近的**用户可见文案**被判成
#   开发者日志，`--check` 依然通过。曾经就是这样漏掉了
#   「第三方服务，需自行确认可信…」这类界面文案。
#   新增日志入口时请显式加在这里，不要放宽成通配。
LOG_CONTEXT = re.compile(
    r'(debugPrint\(|print\(|Logger\.|OgLAppLog|OgLLogFile|OgLTrace|'
    r'OgLNoticeSeverity|diagnostics\.|assert\(|throw\b|UnsupportedError|'
    r'StateError|ArgumentError|FormatException|tag:|tag ?=|'
    r'announce\(|unavailableReason)')

# 有意保留中文的文件（不参与 --check 失败判定）：
# - i18n 内核里的语言自称（「简体中文」「繁體中文」在**任何**语言下都该显示原文）。
ALLOW_FILES = {
    'lib/surface/i18n/og_l_i18n.dart',
}

# 有意保留中文的**具体条目**（file, 文案）。
#
# - 模块描述（`ModuleDescriptor.description`）：开发者元数据，与其它模块的
#   写法一致（`base/net/net_bridge.dart` 等），不是界面文案。
ALLOW_ITEMS = {
    ('lib/surface/surface_bridge.dart', '展示·Material3 页面/主题/设置 的装配入口'),
}

# 文件 → 页面分片 的映射（新增页面时在这里补一条）。
PAGE_BY_PREFIX = [
    ('lib/surface/app/', 'shell'),
    ('lib/surface/pages/settings_page.dart', 'settings'),
    ('lib/surface/pages/login_page.dart', 'login'),
    ('lib/surface/pages/onboarding_page.dart', 'onboarding'),
    ('lib/surface/pages/repo_page.dart', 'repo'),
    ('lib/surface/pages/', None),          # 其余页面：按文件名定
    ('lib/surface/widgets/', 'common'),
    ('lib/surface/util/', 'common'),
]


def page_of(rel):
    for prefix, page in PAGE_BY_PREFIX:
        if rel.startswith(prefix):
            if page is not None:
                return page
            base = os.path.basename(rel)[:-5]
            return base
    return 'common'


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return LINE_COMMENT.sub('', text)


def scan_file(path):
    """返回 [(line_no, text, kind)]，kind ∈ {'ui', 'log'}。

    `kind` 判定：日志调用常常**跨多行**（函数名在前面、字符串在后面，或先拼
    成变量再落盘），因此判断上下文时**向前回看 6 行、向后看 4 行**，
    命中日志/异常关键字才算 log。宁可把日志判成 log（本地化清单只少不多）。
    """
    found = []
    with open(path, encoding='utf-8') as handle:
        raw = handle.read()
    raw_lines = raw.split('\n')
    lines = [strip_comments(line) for line in raw_lines]
    for index, code in enumerate(lines, start=1):
        span = ' '.join(lines[max(0, index - 7):index + 4])
        # 显式豁免：命中行上方 3 行内出现 `i18n-allow` 注释（用于「确定只是日志
        # 载荷、但日志调用离得很远」的少数情况，例如先拼字符串再落盘）。
        waive = 'i18n-allow' in '\n'.join(raw_lines[max(0, index - 4):index])
        for match in STRING.finditer(code):
            value = match.group(2)
            value = value[1:-1]
            if value.startswith("'") or value.startswith('"'):
                continue
            if CJK.search(value):
                kind = 'log' if waive or LOG_CONTEXT.search(span) else 'ui'
                found.append((index, value, kind))
    return found


# 非交互层（kernel / base / domain）没有面向用户的文案：全部按开发者日志处理。
def layer_kind(rel, kind):
    if not rel.startswith('lib/surface/'):
        return 'log'
    return kind


def collect(root):
    items = []
    for dirpath, _dirs, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, os.path.dirname(root))
            for line, text, kind in scan_file(full):
                items.append({
                    'file': rel,
                    'line': line,
                    'page': page_of(rel),
                    'text': text,
                    'kind': layer_kind(rel, kind),
                })
    return items


def load_shard(locale_dir, page):
    path = os.path.join(locale_dir, '%s.json' % page)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


CONSISTENCY = 'consistency'


def parse_dart_locales(lib_root):
    """从 og_l_i18n.dart 里读出 `OgLI18n.locales` 声明的语言代码集合。

    读不到文件返回 None（不因此误报失败）。
    """
    path = os.path.join(lib_root, 'surface', 'i18n', 'og_l_i18n.dart')
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as handle:
        text = handle.read()
    marker = 'static const List<OgLLocale> locales'
    idx = text.find(marker)
    if idx < 0:
        return None
    # 取到该列表结束的分号为止。
    end = text.find('];', idx)
    if end < 0:
        return None
    block = text[idx:end]
    return set(re.findall(r"OgLLocale\(\s*'([A-Za-z_0-9]+)'", block))


def find_pubspec(lib_root):
    """向上找 pubspec.yaml（lib 的兄弟）。"""
    parent = os.path.dirname(os.path.abspath(lib_root))
    candidate = os.path.join(parent, 'pubspec.yaml')
    return candidate if os.path.exists(candidate) else None


def parse_pubspec_i18n(pubspec_path):
    """读出 pubspec.yaml 里 `- assets/i18n/<code>/` 形式的语言目录集合。"""
    with open(pubspec_path, encoding='utf-8') as handle:
        text = handle.read()
    return set(re.findall(r'-?\s*assets/i18n/([A-Za-z_0-9]+)/\s*$',
                          text, re.M))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lib', default=str(REPO_ROOT / 'lib'))
    parser.add_argument('--i18n', default=str(REPO_ROOT / 'assets' / 'i18n'))
    parser.add_argument('--json', dest='json_out')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()

    items = collect(args.lib)
    ui_items = [item for item in items if item['kind'] == 'ui'
                and item['file'] not in ALLOW_FILES
                and (item['file'], item['text']) not in ALLOW_ITEMS]
    log_items = [item for item in items if item not in ui_items]
    by_page = {}
    for item in ui_items:
        by_page.setdefault(item['page'], []).append(item)

    print('中文字面量：共 %d 处（待本地化 **%d** 处 / 开发者日志·有意保留 %d 处）'
          % (len(items), len(ui_items), len(log_items)))
    for page in sorted(by_page):
        print('  %-14s %d 处' % (page, len(by_page[page])))

    shard_problems = []
    value_problems = []
    # 与现有分片对齐：列出各语言缺哪些 page。
    if os.path.isdir(args.i18n):
        locales = sorted(
            d for d in os.listdir(args.i18n)
            if os.path.isdir(os.path.join(args.i18n, d)))
        print('\n语言目录（%d）：%s' % (len(locales), '、'.join(locales)))
        # 键集合对齐以 zh 全量为基准（不只扫描到的页面）。
        zh_dir = os.path.join(args.i18n, 'zh')
        all_pages = sorted(name[:-5] for name in os.listdir(zh_dir)
                           if name.endswith('.json'))
        zh_all = {page: set((load_shard(zh_dir, page) or {}).keys())
                  for page in all_pages}
        for locale in locales:
            for page in all_pages:
                shard = load_shard(os.path.join(args.i18n, locale), page)
                if shard is None:
                    shard_problems.append('%s/%s 缺失' % (locale, page))
                    continue
                # ★ 批 9 · X-02：值必须是字符串。批 8 曾实测
                #   zh_Hant/de/fr/ru 的 tokenExit* 共 32 个值是
                #   「全语种字典」，运行时被 '${e.value}' 字符串化后
                #   把整张字典显示给用户（令牌出本机安全警告变乱码），
                #   而只比 key 集合的 --check 全绿放行。
                for key, value in shard.items():
                    if not isinstance(value, str):
                        value_problems.append(
                            '%s/%s 键 %s 的值类型是 %s（应为字符串）'
                            % (locale, page, key, type(value).__name__))
                keys = set(shard.keys())
                missing = zh_all[page] - keys
                extra = keys - zh_all[page]
                if missing:
                    shard_problems.append('%s/%s 缺 key：%s'
                                          % (locale, page,
                                             '、'.join(sorted(missing)[:6])))
                if extra:
                    shard_problems.append('%s/%s 多出 key：%s'
                                          % (locale, page,
                                             '、'.join(sorted(extra)[:6])))
        if value_problems:
            print('\n分片值类型错误（%d）：' % len(value_problems))
            for row in value_problems[:20]:
                print('  ' + row)
        if shard_problems:
            print('\n分片差异（%d）：' % len(shard_problems))
            for row in shard_problems[:40]:
                print('  ' + row)
        else:
            print('分片校验：%d 语言 × %d 页面，键集合与 zh 完全一致'
                  % (len(locales), len(all_pages)))

    # ── 三处语言清单必须一致 ──────────────────────────────────────────
    # OgLI18n.locales（Dart 运行时清单）× assets/i18n/ 下的目录
    #                                  × pubspec.yaml 的 assets 声明
    # 三者任一不同步都会出问题，而且两种故障方向相反、都很难在排查时想到是这里：
    #   · pubspec 多声明了目录   → 构建期「资源不存在」直接失败
    #   · pubspec 少声明了目录   → 构建通过，运行时该语言全是裸键名
    # v6.4.0 删了 9 个语言目录却忘了改 pubspec，踩的正是第一种。
    consistency = []
    i18n_dirs = set()
    if os.path.isdir(args.i18n):
        i18n_dirs = set(d for d in os.listdir(args.i18n)
                        if os.path.isdir(os.path.join(args.i18n, d)))
    dart_locales = parse_dart_locales(args.lib)
    if dart_locales is not None:
        only_dart = sorted(dart_locales - i18n_dirs)
        only_dir = sorted(i18n_dirs - dart_locales)
        if only_dart:
            consistency.append(
                'OgLI18n.locales 声明但没有语言包目录：%s' % '、'.join(only_dart))
        if only_dir:
            consistency.append(
                '有语言包目录但 OgLI18n.locales 未声明：%s' % '、'.join(only_dir))
    pubspec = find_pubspec(args.lib)
    if pubspec:
        declared = parse_pubspec_i18n(pubspec)
        only_pub = sorted(declared - i18n_dirs)
        missing_in_pub = sorted(i18n_dirs - declared)
        if only_pub:
            consistency.append(
                'pubspec.yaml 声明但目录不存在（构建必失败）：%s'
                % '、'.join(only_pub))
        if missing_in_pub:
            consistency.append(
                'pubspec.yaml 漏声明（运行时该语言全是键名）：%s'
                % '、'.join(missing_in_pub))
    if consistency:
        print('\n语言清单不一致（%d）：' % len(consistency))
        for row in consistency:
            print('  ' + row)
    elif dart_locales is not None and pubspec:
        print('语言清单一致：locales / 目录 / pubspec 三处均为 %d 种'
              % len(i18n_dirs))

    if args.json_out:
        with open(args.json_out, 'w', encoding='utf-8') as handle:
            json.dump(items, handle, ensure_ascii=False, indent=2)
        print('\n已导出：%s' % args.json_out)

    if args.check:
        failed = False
        if ui_items:
            failed = True
            print('\n[check] 仍有 %d 处 **界面文案** 未本地化：' % len(ui_items),
                  file=sys.stderr)
            for item in ui_items[:40]:
                print('  %s:%d %s' % (item['file'], item['line'], item['text']),
                      file=sys.stderr)
        if shard_problems:
            failed = True
            print('\n[check] 分片键集合不一致：%d 处' % len(shard_problems),
                  file=sys.stderr)
        if value_problems:
            failed = True
            print('\n[check] 分片值类型错误：%d 处' % len(value_problems),
                  file=sys.stderr)
        if consistency:
            failed = True
            print('\n[check] 语言清单三处不一致：%d 处' % len(consistency),
                  file=sys.stderr)
            for row in consistency:
                print('  ' + row, file=sys.stderr)
        if failed:
            return 1
        print('\n[check] 通过：界面文案 0 处未本地化；分片键集合一致；'
              '语言清单三处一致；（日志/有意保留 %d 处不计）' % len(log_items))
    return 0


if __name__ == '__main__':
    sys.exit(main())