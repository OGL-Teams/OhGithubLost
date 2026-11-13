#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 引导清单（Boot Manifest）生成与签名。

CI 构建时执行（build.yml 的 `manifest` 任务）；本地可手工执行做演练：

    python3 tool/boot_manifest.py --build-id local-test

产出（勿入库，已进 .gitignore）：

- `boot_manifest.json`：清单原文（含 signature），供审计 / 归档；
- `dart_define.json`：`{"OGL_BOOT_MANIFEST": "<清单字符串>"}`，
  供 `flutter build --dart-define-from-file` 编译期注入。

与 Dart 侧的契约（**不可单方面改动**，否则误伤全部正常安装）：

- 签名覆盖 `canonicalJsonEncode(payload)` 的 UTF-8 字节，payload 不含 signature；
- 规范化规则：键按字典序、无空白、字符串 json 转义、数字 toString()；
- 本脚本与 `lib/kernel/boot/boot_manifest.dart` 的 `canonicalJsonEncode`
  必须逐字节一致；变更必须同步改两边，并跑
  `test/kernel/boot_release_chain_test.dart`。

模块条目说明：核心模块是 AOT 编译产物，运行时没有目录文件可指纹比对，
故 `modules` 为空列表；构建期源码指纹聚合进 `coreDigest`（签名覆盖）。
逐模块目录指纹机制保留给有真实文件落地的扩展包（Mod / 主题）。
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import sys


def canonical_json(obj: object) -> str:
    """确定性 JSON（与 Dart canonicalJsonEncode 对齐）。"""
    return json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def directory_fingerprint(root: str) -> str:
    """目录指纹：与 Dart directoryFingerprint 同算法。

    相对路径排序 → 每行 `路径 + \\x00 + 文件sha256 + \\n` → 整体 sha256。
    """
    rels = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in filenames:
            full = os.path.join(dirpath, name)
            rels.append(os.path.relpath(full, root).replace(os.sep, '/'))
    rels.sort()
    buffer = bytearray()
    for rel in rels:
        with open(os.path.join(root, rel), 'rb') as handle:
            digest = sha256_hex(handle.read())
        buffer += rel.encode('utf-8') + b'\x00' + digest.encode('ascii') + b'\n'
    return sha256_hex(bytes(buffer))


def read_pubspec_version(repo_root: str) -> str:
    with open(os.path.join(repo_root, 'pubspec.yaml'), encoding='utf-8') as handle:
        for line in handle:
            if line.startswith('version:'):
                return line.split(':', 1)[1].strip().split('+', 1)[0]
    raise SystemExit('无法从 pubspec.yaml 读取版本号')


def build_payload(repo_root: str, version: str, build_id: str) -> dict:
    layer_dirs = ['lib/kernel', 'lib/base', 'lib/domain', 'lib/surface']
    core = {d: directory_fingerprint(os.path.join(repo_root, d)) for d in layer_dirs}
    # ★ B8-B-01：平台门面与组合根也必须进签名覆盖范围——
    #   它们决定「哪个实现被装配进内核」，被篡改时若不在 coreDigest 里，
    #   引导清单仍会验签通过（信任链缺口）。
    core['lib/platform'] = directory_fingerprint(
        os.path.join(repo_root, 'lib/platform'))
    core['lib/main.dart'] = sha256_hex(
        open(os.path.join(repo_root, 'lib/main.dart'), 'rb').read())
    return {
        'schema': 1,
        'appVersion': version,
        'buildId': build_id,
        'generatedAt': datetime.datetime.now(
            datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'modules': [],
        'coreDigest': sha256_hex(canonical_json(core).encode('utf-8')),
    }


def sign_payload(payload: dict, key_path: str) -> str:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    seed = base64.b64decode(open(key_path, encoding='utf-8').read().strip())
    private = Ed25519PrivateKey.from_private_bytes(seed)
    message = canonical_json(payload).encode('utf-8')
    signature = private.sign(message)
    # 自检：签完立即验一遍，杜绝"签了个寂寞"。
    private.public_key().verify(signature, message)
    return base64.b64encode(signature).decode('ascii')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default='', help='应用版本（缺省读 pubspec.yaml）')
    parser.add_argument('--build-id', default='local-dev', help='构建标识（CI 传 git sha）')
    parser.add_argument('--key', default='.github/signing/ogl-boot-ed25519.key')
    parser.add_argument('--out', default='dart_define.json')
    parser.add_argument('--repo-root', default='.')
    args = parser.parse_args()

    if not os.path.exists(args.key):
        raise SystemExit(
            '私钥未找到：%s\n'
            '（私钥不随仓库保管：请用 --key 指向带外备份，'
            '或从 Actions Secret `OGL_BOOT_KEY` 还原，见 .github/signing/README.md）'
            % args.key)

    version = args.version.strip() or read_pubspec_version(args.repo_root)
    payload = build_payload(args.repo_root, version, args.build_id)
    signature = sign_payload(payload, args.key)

    manifest = dict(payload)
    manifest['signature'] = signature

    manifest_path = os.path.join(args.repo_root, 'boot_manifest.json')
    with open(manifest_path, 'w', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write('\n')

    define = {
        'OGL_BOOT_MANIFEST': json.dumps(
            manifest, separators=(',', ':'), ensure_ascii=False),
    }
    with open(os.path.join(args.repo_root, args.out), 'w', encoding='utf-8') as handle:
        json.dump(define, handle, ensure_ascii=False)
        handle.write('\n')

    print('OK appVersion=%s buildId=%s' % (version, args.build_id))
    print('signature=%s...' % signature[:24])
    print('canonical-bytes=%d' % len(canonical_json(payload).encode('utf-8')))
    return 0


if __name__ == '__main__':
    sys.exit(main())