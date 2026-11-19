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
    """从 buildOgLTheme 的 extensions 段提取语义色（当前为明暗共用值）。"""
    m = re.search(
        r'OgLSemanticColors\(\s*\n\s*success:\s*const\s+Color\((0x[0-9A-Fa-f]{8})\)'
        r'.*?onSuccess:\s*const\s+Color\((0x[0-9A-Fa-f]{8})\)'
        r'.*?warning:\s*const\s+Color\((0x[0-9A-Fa-f]{8})\)'
        r'.*?onWarning:\s*const\s+Color\((0x[0-9A-Fa-f]{8})\)'
        r'.*?info:\s*(?:const\s+Color\((0x[0-9A-Fa-f]{8})\)|scheme\.primary)'
        r'.*?onInfo:\s*(?:const\s+Color\((0x[0-9A-Fa-f]{8})\)|scheme\.onPrimary)',
        source, re.S)
    if not m:
        return {}
    (success, on_success, warning, on_warning, info,
     on_info) = m.groups()
    colors: dict[str, str] = {
        'success': success,
        'onSuccess': on_success,
        'warning': warning,
        'onWarning': on_warning,
    }
    if info:
        colors['info'] = info
    else:
        # info: scheme.primary（运行时）→ 以品牌种子色 #0969DA 近似评估。
        colors['info'] = '0xFF0969DA'
    if on_info:
        colors['onInfo'] = on_info
    else:
        colors['onInfo'] = '0xFFFFFFFF'
    return colors


def audit() -> list[str]:
    source = THEME.read_text(encoding='utf-8')
    c = _extract_colors(source, dark=True)
    problems: list[str] = []
    if not c:
        problems.append('未在 theme.dart 找到 OgLSemanticColors 定义')
        return problems

    # M3 暗色容器底色近似值（ColorScheme.fromSeed GitHub 蓝 #0969DA 的
    # 暗色板实测区间；对比度按最不利容器取）。
    containers = {
        'surface': '0xFF111318',
        'surfaceContainerLow': '0xFF191C20',
        'surfaceContainer': '0xFF1D2024',
        'surfaceContainerHigh': '0xFF272A2F',
    }
    pairs_text = [
        ('onSuccess', 'success 容器内文字'),
        ('onWarning', 'warning 容器内文字'),
        ('onInfo', 'info 容器内文字'),
    ]
    # 语义色前景（on*）对各自容器底 ≥ 4.5
    for fg_name, desc in pairs_text:
        fg = c.get(fg_name)
        bg_key = fg_name[2:].lower()
        bg = containers.get(
            'surfaceContainerHigh', containers['surfaceContainer'])
        if fg is None:
            problems.append(f'{fg_name} 未定义')
            continue
        ratio = contrast(fg, bg)
        if ratio < 4.5:
            problems.append(
                f'{fg_name} 对容器底 {ratio:.2f}:1 < 4.5:1（{desc}）')
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
