#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 minSdk 显式钉为 21（Android 5.0）→ 目标 5.1（API 22）可装可运行。

背景：
- Flutter 3.47.5 模板 `minSdk = flutter.minSdkVersion`（随引擎版本浮动，
  近年已抬到 21+）。为「兼容到 Android 5.1」提供**确定性**，显式钉 21。
- API 22/21：运行时权限机制（API 23+）不存在 → 安装即授予 manifest 声明的
  权限；`permission_handler` 对旧系统返回 granted 而非报错。
- desugaring 已注入（java.time 在低版本可用）。

运行期「自动回退」已由权限网关实现（lib/surface/app/permissions.dart 的
requestStorage()：请求结果驱动 + 真实写入探针），本项只保证**能装**。
"""
from __future__ import annotations

import argparse
import os
import re
import sys

MARKER = ' // OGL_PLATFORM_SPEC minSdk'


def patch_kotlin(path: str, min_sdk: int) -> bool:
    text = open(path, encoding='utf-8').read()
    if MARKER in text:
        print(f'  [已存在] minSdk（{path}）')
        return False
    # Kotlin DSL：`minSdk = flutter.minSdkVersion`（新模板）
    new, n1 = re.subn(
        r'minSdk\s*=\s*flutter\.minSdkVersion',
        f'minSdk = {min_sdk}{MARKER}',
        text, count=1)
    if n1:
        open(path, 'w', encoding='utf-8').write(new)
        print(f'  [注入] minSdk = {min_sdk}（Kotlin DSL）')
        return True
    # 数字直写的也覆盖（钉死，防模板漂移）
    new, n2 = re.subn(
        r'minSdk\s*=\s*\d+',
        f'minSdk = {min_sdk}{MARKER}',
        new if n1 else text, count=1)
    if n2:
        open(path, 'w', encoding='utf-8').write(new)
        print(f'  [替换] minSdk = {min_sdk}（原数字值）')
        return True
    # Groovy：`minSdkVersion flutter.minSdkVersion`
    new, n3 = re.subn(
        r'minSdkVersion\s+flutter\.minSdkVersion',
        f'minSdkVersion {min_sdk}{MARKER}',
        text, count=1)
    if n3:
        open(path, 'w', encoding='utf-8').write(new)
        print(f'  [注入] minSdkVersion {min_sdk}（Groovy）')
        return True
    print(f'  [未命中] {path}：找不到 minSdk 声明', file=sys.stderr)
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description='钉 minSdk 到目标 API')
    ap.add_argument('--gradle', default='android/app/build.gradle.kts')
    ap.add_argument('--min-sdk', type=int, default=21)
    args = ap.parse_args()
    if not os.path.isfile(args.gradle):
        print(f'[跳过] {args.gradle} 不存在（android/ 未生成）')
        return 0
    return 0 if patch_kotlin(args.gradle, args.min_sdk) else 0


if __name__ == '__main__':
    sys.exit(main())
