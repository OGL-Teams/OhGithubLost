#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""版本一致性校验：`lib/main.dart` 的 `kOgLAppVersion` 必须与 `pubspec.yaml` 一致。

## 为什么需要它
历史上 `kOgLAppVersion` 长期停留在 `7.4.0`，而 pubspec 已推进到 9.x：
「关于」页、诊断日志、引导清单校验全部**谎报版本**，而构建与发布流程浑然不知。
本脚本把"两处版本必须一致"变成 CI 门禁，杜绝这类漂移。

## 用法
    python3 tool/version_sync.py            # 检查，不一致则退出 1
    python3 tool/version_sync.py --fix      # 用 pubspec 的版本改写 main.dart

## 退出码
    0 一致 / 1 不一致 / 2 读不到版本
"""

import argparse
import re
import sys
from pathlib import Path

PUBSPEC = Path('pubspec.yaml')
MAIN_DART = Path('lib/main.dart')

# pubspec: version: 9.1.0+90100
PUBSPEC_RE = re.compile(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$', re.M)
# main.dart: const String kOgLAppVersion = '9.1.0';
MAIN_RE = re.compile(r"^const String kOgLAppVersion = '([^']+)';", re.M)


def read_pubspec_version() -> str | None:
    if not PUBSPEC.exists():
        return None
    match = PUBSPEC_RE.search(PUBSPEC.read_text(encoding='utf-8'))
    return match.group(1) if match else None


def read_main_version() -> str | None:
    if not MAIN_DART.exists():
        return None
    match = MAIN_RE.search(MAIN_DART.read_text(encoding='utf-8'))
    return match.group(1) if match else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--fix', action='store_true',
                        help='用 pubspec 的版本改写 main.dart')
    args = parser.parse_args()

    pub = read_pubspec_version()
    src = read_main_version()
    if pub is None:
        print('[version_sync] 读不到 pubspec.yaml 的 version', file=sys.stderr)
        return 2
    if src is None:
        print('[version_sync] 读不到 lib/main.dart 的 kOgLAppVersion', file=sys.stderr)
        return 2

    if pub == src:
        print('[version_sync] 一致：%s' % pub)
        return 0

    if args.fix:
        text = MAIN_DART.read_text(encoding='utf-8')
        fixed = MAIN_RE.sub("const String kOgLAppVersion = '%s';" % pub, text, count=1)
        MAIN_DART.write_text(fixed, encoding='utf-8')
        print('[version_sync] 已修正：%s -> %s' % (src, pub))
        return 0

    print('[version_sync] 版本不一致：pubspec=%s，main.dart=%s' % (pub, src),
          file=sys.stderr)
    print('             运行 `python3 tool/version_sync.py --fix` 修正',
          file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
