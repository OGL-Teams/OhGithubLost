#!/usr/bin/env python3
"""OGL 宣传片 · 180s 配乐编排（BGM 贯穿、分段推进）

结构与画面同步：
  00–40   静默（片头与第一批功能演示，只留文案与界面声画）
  40–52   BGM 从 0 淡入到 0.5
  52–100  0.5 铺底（功能演示密集段，不抢注意力）
  100–120 推到 1.0
  120–172 满音量（高潮段：代码编辑、Issue 评论、PR 差异、下载）
  172–180 淡出到静默（片尾 CTA）

素材：HOYO-MiX《子不语 Wordless》全曲 132.19s（版权归原权利人，仅内部样片）。
用法：40s 静默 + 132s 原曲 + 8s 尾部淡出 = 180s。
CI 不重算此文件（源曲不在仓库），只校验时长与可解码性。

用法: python3 promo/scripts/make_score.py
"""
import os
import subprocess
import sys

SRC = "/var/minis/mounts/Tiernan_Music/HOYO-MiX - 子不语 Wordless.mp3.mp3"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "audio", "score-180s.mp3"))
TMP = "/tmp/ogl-score-base.mp3"

DUR = 180
LEAD = 40
MUSIC_LEN = 132

# 分段推进的音量包络（0 → 0.5 → 1.0 → 0）
ENVELOPE = (
    "volume=eval=frame:volume='"
    "if(lt(t,40),0,"
    "if(lt(t,52),(t-40)/24,"
    "if(lt(t,100),0.5,"
    "if(lt(t,120),0.5+(t-100)/40,"
    "if(lt(t,172),1,"
    "if(lt(t,180),1-(t-172)/8,0))))))"
    "'"
)


def main():
    if not os.path.exists(SRC):
        sys.exit(f"缺源曲：{SRC}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    # 1) 40s 静音 + 132s 原曲 + 补足到 180s
    concat_graph = (
        f"[0:a]atrim=0:{LEAD}[sil];"
        f"[1:a]atrim=0:{MUSIC_LEN},"
        f"afade=t=in:st=0:d=0.8,afade=t=out:st={MUSIC_LEN-8}:d=8[mus];"
        f"[sil][mus]concat=n=2:v=0:a=1,"
        f"apad=whole_dur={DUR},atrim=0:{DUR}[out]"
    )
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", f"anullsrc=r=44100:cl=stereo:d={LEAD}",
        "-i", SRC,
        "-filter_complex", concat_graph, "-map", "[out]",
        "-c:a", "libmp3lame", "-b:a", "256k", "-ar", "44100",
        TMP,
    ], check=True)

    # 2) 施加分段音量包络
    subprocess.run([
        "ffmpeg", "-y", "-v", "error", "-i", TMP, "-af", ENVELOPE,
        "-c:a", "libmp3lame", "-b:a", "192k", "-ar", "44100", OUT,
    ], check=True)

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", OUT],
        capture_output=True, text=True, check=True)
    d = float(probe.stdout.strip())
    print(f"wrote {OUT}")
    print(f"  {d:.2f}s · {os.path.getsize(OUT)/1048576:.2f} MB")
    if abs(d - DUR) > 1.0:
        sys.exit(f"时长异常：{d}")


if __name__ == "__main__":
    main()
