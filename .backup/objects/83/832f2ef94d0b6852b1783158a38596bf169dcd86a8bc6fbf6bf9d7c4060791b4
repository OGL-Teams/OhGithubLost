#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 平台私有文件注入器（读 `tool/platform_spec.yaml`，按需注入）。

## 定位
`platform_spec.yaml` 声明**物理上写不了 Dart** 的平台私有文件（安装期权限、
编译期宏、编译期属性、图标资源）。本脚本把它翻译成**当下那一版**脚手架里的
具体改动 —— 因为平台工程由 `flutter create` 在构建时现场生成，不能入库。

凡是 spec 里没写的，能力都必须在 `lib/platform/` 里用 Dart 实现。
**这里不是逃生舱**：新增注入项必须同时在 spec 里写清 `why`。

## 幂等
每个 step 都有 `marker`；文件里已有该标记即跳过，重跑安全。

## 用法
    python3 tool/inject_platform_spec.py --target android
    python3 tool/inject_platform_spec.py --target android --job android-icon
    python3 tool/inject_platform_spec.py --target windows --python python
    python3 tool/inject_platform_spec.py --list
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, 'tool', 'platform_spec.yaml')

DESUGAR_DEP = 'com.android.tools:desugar_jdk_libs:2.1.4'

# Android 自适应图标（几何源 assets/icon/ogl_icon.svg，见 inject_android_icon.py）。
ADAPTIVE_ICON = """<?xml version="1.0" encoding="utf-8"?>
<!-- OGL_PLATFORM_SPEC icon -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""

FOREGROUND_ICON = """<?xml version="1.0" encoding="utf-8"?>
<!-- OGL_PLATFORM_SPEC icon -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M54,26 L78,36 L78,56 C78,70 68,80 54,86 C40,80 30,70 30,56 L30,36 Z" />
    <path
        android:fillColor="#FF3A7AFE"
        android:pathData="M46,48 L46,68 L64,58 Z" />
</vector>
"""

PERMISSION_BLOCK = """    <!-- OGL_PLATFORM_SPEC permissions -->
{perms}"""


def _load_spec(path):
    """极简 YAML 读取：只支持本文件用到的子集（列表 + 缩进映射 + `>` 折叠）。

    刻意不引入 PyYAML：CI 里 `pip install` 不保证成功，而门禁脚本必须
    零依赖可跑。
    """
    try:
        import yaml  # noqa: PLC0415 - 可用就用，缺失走下面的兜底
    except ImportError:
        return _parse_minimal_yaml(path)

    with open(path, encoding='utf-8') as handle:
        return yaml.safe_load(handle)


def _strip_comment(line: str) -> str:
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            continue
        if ch == '#':
            break
        out.append(ch)
    return ''.join(out).rstrip()


def _scalar(text: str):
    text = text.strip()
    if not text:
        return None
    if text[0] in ('"', "'") and text[-1] == text[0] and len(text) >= 2:
        return text[1:-1]
    if text in ('true', 'True'):
        return True
    if text in ('false', 'False'):
        return False
    if re.fullmatch(r'-?\d+', text):
        return int(text)
    if text.startswith('>') or text.startswith('|'):
        return text[1:].strip()
    return text


def _parse_minimal_yaml(path: str):
    """兜底解析：够用即可（本文件的结构固定）。"""
    root: dict = {}
    items: list = []
    current_item: dict | None = None
    current_steps: list | None = None
    current_step: dict | None = None
    current_list_key: str | None = None
    pending_fold = False

    with open(path, encoding='utf-8') as handle:
        for raw in handle:
            line = _strip_comment(raw)
            if not line.strip():
                continue

            indent = len(line) - len(line.lstrip())
            body = line.strip()

            # `key: >` / `key: |` —— 折叠块，直接吞掉后续更深缩进
            m = re.match(r'^([A-Za-z_][\w]*):\s*([>|])\s*$', body)
            if m:
                pending_fold = True
                if current_step is not None:
                    current_step[m.group(1)] = ''
                elif current_item is not None:
                    current_item[m.group(1)] = ''
                else:
                    root[m.group(1)] = ''
                continue
            if pending_fold and indent > 0 and body.startswith(' '):
                continue
            pending_fold = False

            if body.startswith('- '):
                item_body = body[2:].strip()
                if current_steps is not None and current_step is None:
                    current_step = {}
                    current_steps.append(current_step)
                if current_item is None:
                    current_item = {}
                    items.append(current_item)
                    current_steps = None
                    current_step = None
                if ':' in item_body:
                    key, _, value = item_body.partition(':')
                    current_item[key.strip()] = _scalar(value)
                    if key.strip() == 'steps':
                        current_steps = current_item['steps'] = []
                        current_step = None
                    current_list_key = None
                else:
                    if current_list_key and current_item is not None:
                        current_item.setdefault(current_list_key, [])
                        current_item[current_list_key].append(_scalar(item_body))
                    elif current_step is not None:
                        current_step.setdefault('_values', []).append(_scalar(item_body))
                continue

            if current_step is not None:
                if indent >= 6:
                    if ':' in body:
                        key, _, value = body.partition(':')
                        if body.strip().endswith(':') or value.strip() == '':
                            current_step[key.strip()] = []
                            current_list_key = key.strip()
                        else:
                            current_step[key.strip()] = _scalar(value)
                            current_list_key = None
                    continue
                current_step = None
                current_steps = None
                current_list_key = None

            if current_item is not None:
                if indent >= 2:
                    key, _, value = body.partition(':')
                    if value.strip() == '':
                        current_item[key.strip()] = None
                    else:
                        current_item[key.strip()] = _scalar(value)
                    continue
                current_item = None

            key, _, value = body.partition(':')
            root[key.strip()] = _scalar(value) if value.strip() else None

    if items:
        root['specs'] = items
    return root


def _read(path: str) -> str:
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def _write(path: str, text: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


def _write_bytes(path: str, blob: bytes) -> None:
    """二进制资源（ICO / PNG）必须用 `wb`，否则文本编码会破坏字节流。"""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(blob)


def _resolve(root: str, relative: str) -> str:
    """把 spec 里的仓库相对路径解析成绝对路径。"""
    return relative if os.path.isabs(relative) else os.path.join(root, relative)


# ── 各 patch 实现 ────────────────────────────────────────────────────────

def patch_compile_sdk(root: str, step: dict) -> int:
    """把宿主 compileSdk 抬到插件要求的版本。

    必须覆盖 Flutter 模板的**全部**写法，否则会静默不生效：
      `compileSdkVersion flutter.compileSdkVersion`（Groovy 旧模板）
      `compileSdk = flutter.compileSdkVersion`（Kotlin DSL 新模板）
      `compileSdkVersion 35` / `compileSdk = 35`（直接写数字）
    """
    target = step.get('compile_sdk', 36)
    path = step['file']
    text = _read(path)
    if 'OGL_PLATFORM_SPEC compileSdk' in text:
        print('  [已存在] compileSdk（%s）' % path)
        return 0

    marker = ' // OGL_PLATFORM_SPEC compileSdk'
    updated = text
    # ① flutter.compileSdkVersion 引用式
    updated = re.sub(r'compileSdkVersion\s+flutter\.compileSdkVersion',
                     'compileSdkVersion %d%s' % (target, marker), updated)
    updated = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion',
                     'compileSdk = %d%s' % (target, marker), updated)
    # ② 直接写数字
    updated = re.sub(r'compileSdkVersion\s+\d+',
                     'compileSdkVersion %d%s' % (target, marker), updated)
    updated = re.sub(r'compileSdk\s*=\s*\d+',
                     'compileSdk = %d%s' % (target, marker), updated)

    if 'OGL_PLATFORM_SPEC compileSdk' not in updated:
        print('  [失败] %s 里找不到 compileSdk（模板写法可能又变了）' % path)
        return 1
    _write(path, updated)
    print('  [注入] %s → compileSdk %d' % (path, target))
    return 0


def patch_core_library_desugaring(root: str, step: dict) -> int:
    text = _read(step['file'])
    if 'OGL_PLATFORM_SPEC desugaring' in text:
        print('  [已存在] coreLibraryDesugaring')
        return 0
    if 'coreLibraryDesugaring' not in text:
        # 模板版本差异：没有 compileOptions 块就退化为"跳过 + 告警"，
        # 绝不让这一步把整条构建腿打红（真正的失败会在编译期暴露）。
        print('  [跳过] %s 里没有 coreLibraryDesugaring 位置（模板已变？）' % step['file'])
        return 0
    updated = text.replace(
        'coreLibraryDesugaring',
        'coreLibraryDesugaring // OGL_PLATFORM_SPEC desugaring', 1)
    updated = updated.replace(
        "'coreLibraryDesugaring'",
        "'coreLibraryDesugaring' // OGL_PLATFORM_SPEC desugaring", 1)
    if 'OGL_PLATFORM_SPEC desugaring' not in updated:
        print('  [跳过] desugaring 注入未命中')
        return 0
    _write(step['file'], updated)
    print('  [注入] %s → desugaring 标记' % step['file'])
    return 0


def patch_android_permissions(root: str, step: dict) -> int:
    perms = step.get('permissions') or []
    path = step['file']
    text = _read(path)
    if 'OGL_PLATFORM_SPEC permissions' in text:
        print('  [已存在] Android 权限块')
        return 0
    lines = []
    for perm in perms:
        if ':' in perm:  # 属性而非权限
            lines.append('    <meta-data android:name="%s" android:value="true" />'
                         % perm.split(':', 1)[1])
        else:
            lines.append('    <uses-permission android:name="%s" />' % perm)
    block = PERMISSION_BLOCK.format(perms='\n'.join(lines) + '\n')
    marker = '    <application'
    if marker not in text:
        print('  [失败] %s 里找不到 <application>' % path)
        return 1
    updated = text.replace(marker, block + marker, 1)
    _write(path, updated)
    print('  [注入] %s → %d 项权限' % (path, len(perms)))
    return 0


def patch_write_vector_xml(root: str, step: dict) -> int:
    _write(step['file'], FOREGROUND_ICON)
    print('  [写入] %s（矢量前景）' % step['file'])
    return 0


def patch_write_adaptive_icon_xml(root: str, step: dict) -> int:
    _write(step['file'], ADAPTIVE_ICON)
    print('  [写入] %s（自适应图标）' % step['file'])
    return 0


def patch_set_app_label(root: str, step: dict) -> int:
    path = step['file']
    value = step.get('value', 'OGL')
    text = _read(path)
    updated, count = re.subn(r'android:label="[^"]*"',
                             'android:label="%s"' % value, text, count=1)
    if not count:
        print('  [跳过] %s 里找不到 android:label' % path)
        return 0
    _write(path, updated)
    print('  [注入] %s → label=%s' % (path, value))
    return 0


def patch_add_compile_definitions(root: str, step: dict) -> int:
    path = step['file']
    defs = step.get('definitions') or []
    text = _read(path)
    if 'OGL_PLATFORM_SPEC' in text:
        print('  [已存在] 编译宏')
        return 0
    line = 'add_compile_definitions(%s)  # OGL_PLATFORM_SPEC coroutine\n' % ' '.join(defs)
    lines = text.splitlines(keepends=True)
    insert_at = next((i for i, l in enumerate(lines)
                      if l.strip() and not l.strip().startswith('#')), 0)
    lines.insert(insert_at, line)
    _write(path, ''.join(lines))
    if 'OGL_PLATFORM_SPEC' not in _read(path):
        print('  [失败] 宏注入后未生效：%s' % path)
        return 1
    print('  [注入] %s → %d 个编译宏' % (path, len(defs)))
    return 0


def patch_add_entitlement(root: str, step: dict) -> int:
    path = step['file']
    if not os.path.isfile(path):
        print('  [跳过] %s 不存在（非该平台构建）' % path)
        return 0
    key = step.get('key')
    text = _read(path)
    if key and key in text:
        print('  [已存在] %s' % key)
        return 0
    if '</dict>' not in text:
        print('  [跳过] %s 里没有 </dict>' % path)
        return 0
    _write(path, text.replace('</dict>', '\t<key>%s</key>\n\t<true/>\n</dict>' % key))
    print('  [注入] %s → %s' % (path, key))
    return 0


def patch_write_ico(root: str, step: dict) -> int:
    import desktop_icon  # noqa: PLC0415 - 同目录模块

    size = int(step.get('size', 256))
    rgba = desktop_icon.render_rgba(_resolve(root, step.get('source')), size)
    png = desktop_icon.encode_png(rgba, size)
    _write_bytes(step['file'], desktop_icon.encode_ico(png, size))
    print('  [写入] %s（ICO %d）' % (step['file'], size))
    return 0


def patch_write_png(root: str, step: dict) -> int:
    import desktop_icon  # noqa: PLC0415 - 同目录模块

    size = int(step.get('size', 2048))
    rgba = desktop_icon.render_rgba(_resolve(root, step.get('source')), size)
    _write_bytes(step['file'], desktop_icon.encode_png(rgba, size))
    print('  [写入] %s（PNG %d）' % (step['file'], size))
    return 0


PATCHES = {
    'compile_sdk': patch_compile_sdk,
    'core_library_desugaring': patch_core_library_desugaring,
    'android_permissions': patch_android_permissions,
    'write_vector_xml': patch_write_vector_xml,
    'write_adaptive_icon_xml': patch_write_adaptive_icon_xml,
    'set_app_label': patch_set_app_label,
    'add_compile_definitions': patch_add_compile_definitions,
    'add_entitlement': patch_add_entitlement,
    'write_ico': patch_write_ico,
    'write_png': patch_write_png,
}


def main() -> int:
    ap = argparse.ArgumentParser(description='按 platform_spec.yaml 注入平台私有文件')
    ap.add_argument('--target', help='目标平台（android / windows / linux / macos）')
    ap.add_argument('--job', help='只跑某个 job id')
    ap.add_argument('--root', default=ROOT)
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--list', action='store_true', help='只列规格')
    args = ap.parse_args()

    if not os.path.isfile(args.spec):
        sys.stderr.write('缺少平台规格：%s\n' % args.spec)
        return 1

    sys.path.insert(0, os.path.dirname(os.path.abspath(args.spec)))
    data = _load_spec(args.spec)
    specs = data.get('specs') or []
    if not specs:
        sys.stderr.write('规格为空或解析失败：%s\n' % args.spec)
        return 1

    if args.list or not args.target:
        for item in specs:
            print('%-10s %-28s %s' % (item.get('target'), item.get('id'),
                                      str(item.get('why', '')).strip()[:60]))
        return 0

    failed = 0
    ran = 0
    for item in specs:
        if item.get('target') != args.target:
            continue
        if args.job and item.get('id') != args.job and item.get('job') != args.job:
            continue
        ran += 1
        why = str(item.get('why', '')).strip()
        if not why:
            sys.stderr.write('[拒绝] %s 缺少 why —— 写不了 Dart 必须写清理由\n'
                             % item.get('id'))
            failed += 1
            continue
        print('== %s（%s）' % (item.get('id'), why.splitlines()[0][:70]))
        for step in (item.get('steps') or []):
            if 'file' not in step:
                continue
            handler = PATCHES.get(step.get('patch'))
            if handler is None:
                sys.stderr.write('  [跳过] 未知 patch：%s\n' % step.get('patch'))
                continue
            # handler 一律接收**绝对路径**（spec 里写的是相对仓库根的路径）。
            resolved = os.path.join(args.root, step['file'])
            if not os.path.exists(resolved) and step.get('patch') not in (
                    'write_vector_xml', 'write_adaptive_icon_xml',
                    'write_ico', 'write_png'):
                print('  [跳过] %s 不存在（非该平台构建）' % step['file'])
                continue
            step = dict(step, file=resolved)
            failed += handler(args.root, step)

    if not ran:
        print('规格中没有 %s 的条目（跳过）' % args.target)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())