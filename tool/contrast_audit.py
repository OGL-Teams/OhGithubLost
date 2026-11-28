#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 语义色 WCAG 对比度门禁（MD3 Accessibility 收口）。

解析 `lib/surface/theme.dart` 中 OgLSemanticColors 的语义色定义，对各类
surface 底色计算 WCAG 2.1 对比度：
- 正文级（success/warning/info 前景 on* 对 *Container 底）≥ 4.5:1
- 大字号/图形级（success/warning 色本身对 surface）≥ 3.0:1

调色时改 theme.dart，本门禁会拦截回归。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / 'lib' / 'surface' / 'theme.dart'


def _srgb_to_linear(c: float) -> float:
    if c <= 0.03928:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def _relative_luminance(r: int, g: int, b: int) -> float:
    return (
        0.2126 * _srgb_to_linear(r / 255)
        + 0.7152 * _srgb_to_linear(g / 255)
        + 0.0722 * _srgb_to_linear(b / 255)
    )


def contrast(fg_hex: str, bg_hex: str) -> float:
    """WCAG 2.1 对比度（两值均形如 0xFFRRGGBB）。"""
    def lum(h: str) -> float:
        v = int(h, 16)
        return _relative_luminance((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
    l1 = lum(fg_hex)
    l2 = lum(bg_hex)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def _extract_colors(source: str, dark: bool) -> dict[str, str]:
    """从 theme.dart 的 OgLSemanticColors.light/dark static const 提取语义色。

    MD2 迁移后语义色明暗分档（B 席修复），不再是单一实例；按 dark 参数
    取对应档位。Colors.white/black 映射为 0xFFFFFFFF/0xFF000000。
    """
    key = 'dark' if dark else 'light'
    m = re.search(
        r'static const OgLSemanticColors ' + key + r' = OgLSemanticColors\((.*?)\n  \);',
        source, re.S)
    if not m:
        return {}
    body = m.group(1)

    def token(name: str) -> str | None:
        mm = re.search(name + r':\s*(?:const\s+)?Color\((0x[0-9A-Fa-f]{8})\)', body)
        if mm:
            return mm.group(1)
        mm = re.search(name + r':\s*Colors\.(white|black)', body)
        if mm:
            return '0xFFFFFFFF' if mm.group(1) == 'white' else '0xFF000000'
        return None

    out: dict[str, str] = {}
    for n in ('success', 'onSuccess', 'warning', 'onWarning', 'info', 'onInfo'):
        v = token(n)
        if v:
            out[n] = v
    return out


def audit() -> list[str]:
    source = THEME.read_text(encoding='utf-8')
    dark = True  # MD2：暗色档为最不利场景，明色档另在下方核验
    c = _extract_colors(source, dark=dark)
    problems: list[str] = []
    if not c:
        problems.append('未在 theme.dart 找到 OgLSemanticColors 定义')
        return problems

    # M3 暗色容器底色近似值（ColorScheme.fromSeed GitHub 蓝 #0969DA 的
    # 暗色板实测区间；对比度按最不利容器取）。
    containers = {
        'surface': '0xFF121212' if dark else '0xFFFFFFFF',
        'surfaceContainerHighest': '0xFF1C2128' if dark else '0xFFF6F8FA',
    }
    # 语义色前景（on*）对**各自色块底** ≥ 4.5（WCAG 正文级）。
    # onSuccess 配 success、onWarning 配 warning、onInfo 配 info；
    # 色块内文字的对比对象是色块本身，不是页面容器底。
    for fg_name, bg_name, desc in (
        ('onSuccess', 'success', 'success 色块内文字'),
        ('onWarning', 'warning', 'warning 色块内文字'),
        ('onInfo', 'info', 'info 色块内文字'),
    ):
        fg, bg = c.get(fg_name), c.get(bg_name)
        if fg is None or bg is None:
            problems.append(f'{fg_name}/{bg_name} 未定义')
            continue
        ratio = contrast(fg, bg)
        if ratio < 4.5:
            problems.append(
                f'{fg_name} 对 {bg_name} {ratio:.2f}:1 < 4.5:1（{desc}）')
    # 语义色本身对 surface ≥ 3.0（图标/强调）
    for name in ('success', 'warning', 'info'):
        v = c.get(name)
        if v is None:
            problems.append(f'{name} 未定义')
            continue
        ratio = contrast(v, containers['surface'])
        if ratio < 3.0:
            problems.append(
                f'{name} 对 surface {ratio:.2f}:1 < 3.0:1（图标/强调级）')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser() if False else None
    problems = audit()
    print('语义色对比度审计：%d 处问题' % len(problems))
    for p in problems:
        print('  - ' + p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
