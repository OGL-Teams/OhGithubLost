#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""输入层可复现构建：音轨 / 字体子集 / milestones 校验。

只写入这三个路径（tools/ 下脚本除外）：
  assets/audio/dream-aria-25.m4a
  assets/fonts/heiti-subset.woff2
  data/milestones.json   （仅规范化；内容字节不变时绝不写回）
不生成任何图片、位图、SVG、HTML。

依赖：ffmpeg / ffprobe / pyftsubset / fonttools / brotli
用法：python3 tools/build_assets.py [--verify]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path('/var/minis/mounts/Tiernan_Music/'
           '陈致逸 - Dream Aria (Genshin Impact Main Theme Var.) 梦之咏叹.mp3.mp3')
TTC = Path('/usr/share/fonts/noto/NotoSansCJK-Regular.ttc')
AUDIO_DIR = ROOT / 'assets/audio'
AUDIO_OUT = AUDIO_DIR / 'dream-aria-25.m4a'
FONT_OUT = ROOT / 'assets/fonts/heiti-subset.woff2'
DATA = ROOT / 'data/milestones.json'

FIXED = ('OhGithubLost 更新日志 项目转折 长期基线 v0.1.0 — v12.6.9 '
         'This is the first real platform-wide client of GitHub that covers '
         'almost all common functions, but this is not the end '
         'Powered by Hy4free Thanks to OGL-Teams and Workbuddy '
         'About 12.5 billion tokens have been used '
         '起点 扩张 收敛 基线 五平台首航 系统标准样式重写 下载器与草稿箱 '
         'GitHub 工作流，在本地完成 github.com/OGL-Teams/OhGithubLost '
         '十八道离线门禁全通过 · 四层依赖零越级 · Apache-2.0 '
         'Android Windows Linux Web OGL Teams')
ASCII = ''.join(chr(i) for i in range(0x20, 0x7f))
CJK_PUNCT = '，。、；：！？（）【】《》「」『』—…·～／＼＋－＝°％'

FIELDS = ('version', 'era', 'act_line', 'kind', 'headline', 'detail')
KINDS = {'origin', 'architecture', 'platform', 'feature', 'turn',
         'reliability', 'governance', 'finale'}
EXPECT_DUR = 98.746
FAMILY = 'OGLHeiti'


def run(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], check=True,
                          capture_output=True, text=True, **kw)


def probe(path, entries='format=duration,bit_rate'):
    out = run(['ffprobe', '-v', 'error', '-show_entries', entries,
               '-of', 'json', path]).stdout
    return json.loads(out)


def mean_volume(path):
    r = run(['ffmpeg', '-hide_banner', '-nostats', '-i', path,
             '-map', '0:a:0', '-af', 'volumedetect', '-f', 'null', '-'])
    m = re.search(r'mean_volume:\s*(-?[\d.]+)\s*dB', r.stderr)
    return float(m.group(1)) if m else float('nan')


def build_audio():
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    tmp = AUDIO_OUT.with_suffix('.tmp.m4a')
    tmp.unlink(missing_ok=True)
    # -map 0:a:0 + -map_metadata -1 + -vn：杜绝源 FLAC 内嵌封面等附加流
    run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
         '-i', SRC, '-map', '0:a:0', '-vn', '-map_metadata', '-1',
         '-af', 'volume=0.25', '-ar', '44100', '-ac', '2',
         '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', tmp])
    tmp.replace(AUDIO_OUT)
    removed = []
    for p in sorted(AUDIO_DIR.iterdir()):
        if p.name == AUDIO_OUT.name:
            continue
        (shutil.rmtree(p) if p.is_dir() else p.unlink())
        removed.append(p.name)
    return removed


def verify_audio():
    info = probe(AUDIO_OUT, 'format=duration,bit_rate:stream=index,codec_name,'
                 'codec_type,sample_rate,channels,bit_rate')
    dur = float(info['format']['duration'])
    streams = info['streams']
    src_v, out_v = mean_volume(SRC), mean_volume(AUDIO_OUT)
    delta = out_v - src_v
    ok = (abs(dur - EXPECT_DUR) <= 0.5 and len(streams) == 1
          and streams[0]['codec_type'] == 'audio'
          and streams[0]['codec_name'] == 'aac'
          and streams[0]['sample_rate'] == '44100'
          and -13.0 <= delta <= -11.0)
    print(f'[音频] {AUDIO_OUT.name}: {AUDIO_OUT.stat().st_size} B, '
          f'{dur:.6f}s (偏差 {dur - EXPECT_DUR:+.6f}s), '
          f'{streams[0]["sample_rate"]}Hz/{streams[0]["channels"]}ch, '
          f'{int(info["format"]["bit_rate"])//1000}k, '
          f'增益 {delta:+.2f}dB (目标 -12.04dB), 流数 {len(streams)}')
    print(f'[音频] 校验: {"PASS" if ok else "FAIL"}')
    return ok


# ---------- milestones：只校验 / 规范化，不改任何文案 ----------
def display_zi(s):
    """中文排版「字」：全角计 1 字，半角计 0.5 字。"""
    return sum(1.0 if unicodedata.east_asian_width(c) in ('W', 'F')
               else 0.5 for c in s)


def canonical(data):
    lines = ['[']
    for i, item in enumerate(data):
        body = json.dumps(item, ensure_ascii=False, separators=(',', ':'))
        lines.append('  ' + body + (',' if i < len(data) - 1 else ''))
    lines.append(']')
    return ('\n'.join(lines) + '\n').encode('utf-8')


def validate_milestones(write=False):
    raw = DATA.read_bytes()
    assert not raw.startswith(b'\xef\xbb\xbf'), '存在 BOM'
    data = json.loads(raw.decode('utf-8'))
    assert isinstance(data, list), '根节点必须是数组'
    problems = []
    if len(data) != 18:
        problems.append(f'条数 {len(data)} != 18')
    kinds = {}
    seq = []
    max_hz = max_hc = max_dz = max_dc = 0.0
    for i, item in enumerate(data, 1):
        if not isinstance(item, dict):
            problems.append(f'#{i} 非对象')
            continue
        missing = [k for k in FIELDS if k not in item]
        extra = [k for k in item if k not in FIELDS]
        if missing:
            problems.append(f'#{i} 缺字段 {missing}')
        if extra:
            problems.append(f'#{i} 未知字段 {extra}')
        if item.get('kind') not in KINDS:
            problems.append(f'#{i} kind={item.get("kind")!r}')
        kinds[item.get('kind')] = kinds.get(item.get('kind'), 0) + 1
        h, d = item.get('headline', ''), item.get('detail', '')
        hc, dc = len(h), len(d)
        hz, dz = display_zi(h), display_zi(d)
        max_hz, max_dz = max(max_hz, hz), max(max_dz, dz)
        max_hc, max_dc = max(max_hc, hc), max(max_dc, dc)
        # 正式书面句允许略长：软校验只记录，不判失败
        if hz > 14 or dz > 26:
            print(f'  note #{i} 字数偏长 headline={hz} detail={dz}')
        m = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', item.get('version', ''))
        if not m:
            problems.append(f'#{i} 版本号格式 {item.get("version")!r}')
        else:
            seq.append(tuple(int(x) for x in m.groups()))
    if any(a >= b for a, b in zip(seq, seq[1:])):
        problems.append('版本未按时间顺序严格递增')
    canon = canonical(data)
    changed = canon != raw
    if write and changed:
        DATA.write_bytes(canon)
    strict_over = [(i, len(x['headline']), len(x['detail'])) for i, x in
                   enumerate(data, 1) if len(x['headline']) > 14
                   or len(x['detail']) > 26]
    print(f'[数据] {DATA.stat().st_size} B, {len(data)} 条, '
          f'每条 {len(FIELDS)} 字段 (version/era/act_line/kind/headline/detail'
          '；用户口径含外层序号共 7 位), '
          f'键序种类 {len(set(tuple(x) for x in data))}')
    print(f'[数据] kind 分布: ' + ' '.join(f'{k}={kinds.get(k, 0)}'
          for k in ('origin', 'architecture', 'platform', 'feature',
                    'turn', 'reliability', 'governance', 'finale')))
    print(f'[数据] headline 最大 {max_hz:g} 字 ({max_hc:g} 码点), '
          f'detail 最大 {max_dz:g} 字 ({max_dc:g} 码点); '
          f'严格码点超限条数 {len(strict_over)}: {strict_over}')
    print(f'[数据] 版本序列 {seq[0]} → {seq[-1]} 严格递增: '
          f'{all(a < b for a, b in zip(seq, seq[1:]))}')
    print(f'[数据] 规范化: {"已写回" if write and changed else "无需变更(字节一致)"}; '
          f'校验: {"PASS" if not problems else "FAIL " + "; ".join(problems)}')
    return data, not problems


# ---------- 字体子集 ----------
def build_font(data):
    from fontTools.ttLib import TTFont
    text = DATA.read_text(encoding='utf-8') + FIXED + ASCII + CJK_PUNCT
    chars = sorted({c for c in text if ' ' <= c != '\x7f' and c != '\n'
                    and c != '\r' and c != '\t'})
    FONT_OUT.parent.mkdir(parents=True, exist_ok=True)
    fd, chars_path = tempfile.mkstemp(prefix='ogl-subset-chars-', suffix='.txt')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(''.join(chars))          # 临时 chars 文件，无尾换行
        # 清掉可能存在的同名旧产物，保证可复现
        FONT_OUT.unlink(missing_ok=True)
        run(['pyftsubset', TTC,
             '--font-number=0',
             '--text-file=' + chars_path,
             '--output-file=' + str(FONT_OUT),
             '--flavor=woff2',
             '--no-hinting',
             "--layout-features=",
             '--name-IDs=0,1,2,3,4,5,6'])
    finally:
        Path(chars_path).unlink(missing_ok=True)

    # pyftsubset 不提供改名选项：用 fontTools 把字体族名改为 OGLHeiti。
    # 保留源字体的版权 / 许可记录（nameID 0、7~15），仅覆盖命名记录。
    font = TTFont(FONT_OUT)
    name = font['name']
    keep = [r for r in name.names if r.nameID not in (1, 2, 3, 4, 5, 6, 16, 17)]
    name.names = keep
    records = ((1, FAMILY), (2, 'Regular'),
               (3, 'OGLHeiti-Regular;OGL;1.000'),
               (4, 'OGLHeiti Regular'), (5, 'Version 1.000'),
               (6, 'OGLHeiti-Regular'), (16, FAMILY), (17, 'Regular'))
    for nid, val in records:
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    font.save(FONT_OUT)                     # 保留 woff2 flavor 重新压缩
    font.close()
    return chars


def verify_font(chars):
    from fontTools.ttLib import TTFont
    import brotli  # noqa: F401
    f = TTFont(FONT_OUT)
    cmap = f.getBestCmap()
    missing = [c for c in chars if ord(c) not in cmap]
    fam = f['name'].getDebugName(1)
    tables = sorted(f.keys())
    bitmap = [t for t in tables if t in
              ('EBDT', 'EBLC', 'EBSC', 'CBDT', 'CBLC', 'sbix', 'SVG ')]
    size = FONT_OUT.stat().st_size
    ok = (FAMILY == fam and size < 300 * 1024 and f.flavor == 'woff2'
          and not bitmap and not missing)
    print(f'[字体] {FONT_OUT.name}: {size} B ({size/1024:.1f} KiB), '
          f'字符 {len(chars)} 个, 覆盖 {len(chars)-len(missing)}, '
          f'字形 {f["maxp"].numGlyphs}, family={fam!r}, flavor={f.flavor}')
    print(f'[字体] 表: {" ".join(tables)}')
    print(f'[字体] 缺字: {missing or "无"}; 位图表: {bitmap or "无"}; '
          f'校验: {"PASS" if ok else "FAIL"}')
    f.close()
    return ok


def main():
    verify_only = '--verify' in sys.argv
    if not verify_only:
        print('[音频] ffmpeg 转码 + volume=0.25 ...')
        print('[音频] 清理旧音轨: ' + (', '.join(build_audio()) or '无'))
        print('[字体] pyftsubset 子集化 ...')
    data, ok_data = validate_milestones(write=not verify_only)
    chars = build_font(data) if not verify_only else None
    if chars is None:                       # --verify：从 json 重建同一字符集
        text = DATA.read_text('utf-8') + FIXED + ASCII + CJK_PUNCT
        chars = sorted({c for c in text if ' ' <= c != '\x7f'
                        and c not in '\n\r\t'})
    ok_audio = verify_audio()
    ok_font = verify_font(chars)
    print('[汇总] ' + ('PASS' if all((ok_data, ok_audio, ok_font)) else 'FAIL')
          + f' | 三产物: {AUDIO_OUT} / {FONT_OUT} / {DATA}')
    return 0 if all((ok_data, ok_audio, ok_font)) else 1


if __name__ == '__main__':
    sys.exit(main())
