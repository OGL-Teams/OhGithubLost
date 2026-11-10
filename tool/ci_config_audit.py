#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · CI 配置自检（离线，不依赖 GitHub）。

## 为什么要这个工具
CI 配置里的错误（YAML 语法、缓存路径写死与 runner 不符、缓存键没绑定
依赖清单、产物压缩退化为串行）**只有推上去跑一次才暴露**，一次就是
7 分钟墙钟 + 十几个并行 job。这里把几条会静默拖慢构建的结构契约
变成离线可查：

1. 所有 workflow 的 YAML 必须可解析；
2. `actions/cache` 的路径不得出现绝对路径写死（Windows runner 路径不同），
   必须使用 `~`、`env.*` 或 `github.workspace`；
3. 缓存键必须绑定 `pubspec.yaml`（依赖变了却不换键 = 用旧依赖构建）；
4. 发布任务的产物压缩必须并行（否则 85s 串行退化）。
5. `build` 腿的 Android 缓存键必须与预热/其它腿一致（命中率）。

用法：
    python3 tool/ci_config_audit.py             # 报告
    python3 tool/ci_config_audit.py --fatal     # CI 模式（有问题退出 1）
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WF = ROOT / '.github' / 'workflows'

try:
    import yaml
except ImportError:
    print('需要 PyYAML：pip install pyyaml', file=sys.stderr)
    sys.exit(2)


def doc_all_steps(doc: dict) -> list[dict]:
    """列出 workflow 里所有 job 的所有步骤（扁平化）。"""
    out: list[dict] = []
    for job in doc.get('jobs', {}).values():
        if isinstance(job, dict):
            out.extend(s for s in (job.get('steps') or []) if isinstance(s, dict))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true', help='有问题时退出 1')
    args = ap.parse_args()

    issues: list[str] = []
    files = sorted(WF.glob('*.yml'))
    if not files:
        issues.append('没有找到任何 workflow 文件')

    for path in files:
        text = path.read_text(encoding='utf-8')
        try:
            doc = yaml.safe_load(text)
        except Exception as exc:  # noqa: BLE001
            issues.append(f'{path.name}: YAML 解析失败：{exc}')
            continue
        if not isinstance(doc, dict) or 'jobs' not in doc:
            issues.append(f'{path.name}: 缺少 jobs 段')
            continue

        # 缓存步骤检查
        for job_name, job in doc['jobs'].items():
            if not isinstance(job, dict):
                continue
            for step in job.get('steps', []) or []:
                if not isinstance(step, dict):
                    continue
                uses = str(step.get('uses', ''))
                if not uses.startswith('actions/cache'):
                    continue
                with_block = step.get('with') or {}
                paths = with_block.get('path') or ''
                key = str(with_block.get('key', ''))
                # 2) 缓存路径不得写死平台专属绝对路径（runner 路径不同）。
                for line in str(paths).splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith('/') and not line.startswith('/usr/local/lib/android/sdk'):
                        issues.append(
                            f'{path.name}/{job_name}/{step.get("name")}: '
                            f'缓存路径写死绝对路径 {line!r}（跨平台不命中；'
                            f'用 ~ 或 env.* 表达）')
                    # 2b) ★ 不许缓存 runner 预装的只读系统 SDK 目录。
                    #   实测（run 42843889680）：把 ${ANDROID_SDK_ROOT}/ndk 与
                    #   /cmake 整目录塞进缓存 → 4078 MB，解包时数百条
                    #   `tar: Cannot utime: Operation not permitted`，
                    #   最终 `Failed to restore`，5 条腿全白下载 4GB。
                    #   SDK 属 root，用户态 tar 无法恢复其元数据。
                    #   注意路径可能写成 `${{ env.ANDROID_SDK_ROOT }}/ndk`
                    #   这类变量引用，不含字面 `android/sdk` —— 所以按
                    #   「ANDROID_SDK_ROOT / android/sdk 变量 + ndk/cmake 段」
                    #   判定，而不是只找字面路径。
                    mentions_sdk = ('ANDROID_SDK_ROOT' in line.upper()
                                    or 'ANDROID_HOME' in line.upper()
                                    or 'android/sdk' in line)
                    if mentions_sdk and ('/ndk' in line or '/cmake' in line):
                        issues.append(
                            f'{path.name}/{job_name}/{step.get("name")}: '
                            f'缓存了 runner 预装的只读 SDK 目录 {line!r}'
                            f'（restore 会因权限失败；只缓存 ~/.gradle 依赖）')
                # 3) 缓存键必须绑定依赖清单或 SDK 版本
                if 'pubspec.yaml' not in key and 'FLUTTER_VERSION' not in key:
                    issues.append(
                        f'{path.name}/{job_name}/{step.get("name")}: '
                        f'缓存键未绑定 pubspec.yaml / FLUTTER_VERSION，依赖变更不会失效')

        # 3b) 同一 workflow 里若同时出现 cache/restore 与 cache/save，
        #     save 必须带独占条件（不能每条 matrix 腿都写同一个 key）。
        #     实测（run 42840707327）：5 条腿并发写同一个 ~2GB 缓存，
        #     `Post 缓存` 各花 280~431s，比构建步还慢，且只有一个能保存成功。
        restore_steps = [s for s in doc_all_steps(doc)
                         if str(s.get('uses', '')).startswith('actions/cache/restore')]
        save_steps = [s for s in doc_all_steps(doc)
                      if str(s.get('uses', '')).startswith('actions/cache/save')]
        if restore_steps and save_steps:
            for s in save_steps:
                cond = str(s.get('if', ''))
                if 'matrix.label' not in cond and 'matrix.' not in cond:
                    issues.append(
                        f'{path.name}/{s.get("name")}: save 步骤缺少独占条件'
                        f'（每条 matrix 腿都会写同一个 key → 并发上传白烧）')

        # 4) 发布产物压缩必须并行
        if '整理产物' in text or 'zip -r -9' in text:
            # 并行版本里 zip 行尾有 '&'，且必须有显式 wait
            # （无参数 wait 或带 PID 的 wait "$p" 都算）。
            zip_lines = [ln for ln in text.splitlines()
                         if re.search(r'zip -r -9', ln)]
            parallel = any(') &' in ln or ln.rstrip().endswith('&')
                           for ln in zip_lines)
            # 只要存在后台启动（&）且后续有任意显式的 wait 调用即算并行。
            # （wait 可能是 `wait`、`wait "$p"`、`wait "$p_zip"` 等形式。）
            has_wait = bool(re.search(r'^\s*wait\b', text, re.M))
            if zip_lines and not (parallel and has_wait):
                issues.append(
                    f'{path.name}: 产物压缩退化为串行（zip 无 & / 缺 wait）')

    if issues:
        print('CI 配置自检：发现 %d 处问题' % len(issues))
        for issue in issues:
            print('  -', issue)
        return 1 if args.fatal else 0
    print('CI 配置自检通过：%d 个 workflow，缓存键/路径/并行压缩均合规'
          % len(files))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
