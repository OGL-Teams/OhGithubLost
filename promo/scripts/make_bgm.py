#!/usr/bin/env python3
"""OGL 宣传片 BGM · 纯代码合成（无外部素材、无版权风险）

96 BPM 半拍律动科技 groove：
  - kick: 正弦扫频 120→45Hz
  - clap: 噪声 burst（拍 2/4）
  - hat: 高通噪声 8 分音
  - bass: 锯波跟随 Am-F-C-G 进行
  - pad: 失谐双锯和弦垫
  - arp: 32 分音符拨弦（后 1/3 段落进入，配合画面密度上升）
  - impact: 转场点的低频冲击 + 噪声上扬

输出: promo/assets/audio/bgm.wav（44.1kHz 立体声）+ beat 网格 JSON
用法: python3 promo/scripts/make_bgm.py
"""
import json
import os
import struct
import wave

import numpy as np

SR = 44100
BPM = 96.0
BEAT = 60.0 / BPM          # 0.625s
DUR = 56.0                 # 片长（秒）
N = int(SR * DUR)

OUT_WAV = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "bgm.wav")
OUT_JSON = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "bgm-beats.json")

rng = np.random.default_rng(20261114)


def env(n, attack, decay, sustain=0.0, release=0.0):
    """简单 ADSR 采样包络。"""
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    r = max(0, int(release * SR))
    s = max(0, n - a - d - r)
    return np.concatenate([
        np.linspace(0.0, 1.0, a),
        np.linspace(1.0, sustain, d),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r) if r else np.zeros(0),
    ])[:n]


def add(buf, start, sig):
    i = int(start * SR)
    if i >= len(buf):
        return
    seg = sig[: len(buf) - i]
    buf[i:i + len(seg)] += seg


def kick():
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 45.0 + 95.0 * np.exp(-t * 26.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7.0)
    click = rng.normal(0, 1, n) * np.exp(-t * 220.0) * 0.25
    return (body + click) * 0.9


def clap():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    # 三次短 burst 叠加 → 掌声感
    e = np.zeros(n)
    for off, amp in ((0.0, 1.0), (0.012, 0.7), (0.026, 0.45)):
        s = int(off * SR)
        e[s:] += np.exp(-(t[s:] - off) * 55.0) * amp
    sig = noise * e
    # 简易高通：一阶差分
    sig = np.concatenate([[0.0], np.diff(sig)])
    return sig * 0.45


def hat(open_=False):
    dur = 0.16 if open_ else 0.055
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    hp = np.concatenate([[0.0], np.diff(noise)])
    hp = np.concatenate([[0.0], np.diff(hp)])
    return hp * np.exp(-t * (28 if open_ else 85.0)) * 0.3


def bass(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    wave_ = np.sign(np.sin(2 * np.pi * freq * t)) * 0.6
    wave_ += 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    wave_ += 0.15 * np.sin(2 * np.pi * freq * 0.5 * t)
    e = np.exp(-t * 3.2) * 0.5 + np.exp(-t * 14.0) * 0.5
    lp = np.convolve(wave_ * e, np.ones(24) / 24, mode="same")
    return lp * 0.5


def pluck(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2 * t)
    sig += 0.2 * np.sin(2 * np.pi * freq * 3 * t)
    return sig * np.exp(-t * 16.0) * 0.22


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.16, 0.16):
            out += np.sin(2 * np.pi * (f + det) * t) * 0.09
    e = np.minimum(1.0, t / 0.9) * np.minimum(1.0, (dur - t) / 0.9)
    return out * np.clip(e, 0, 1) * 0.5


def impact():
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * (38.0 - 18.0 * t) * t) * np.exp(-t * 4.2)
    noise = rng.normal(0, 1, n) * np.exp(-t * 3.0) * 0.25
    return boom * 0.8 + noise


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    k = np.linspace(0, 1, n) ** 2
    sig = noise * k * 0.22
    sig = np.convolve(sig, np.ones(8) / 8, mode="same")
    sig += np.sin(2 * np.pi * (200 + 1800 * k) * t) * k * 0.08
    return sig


def main():
    os.makedirs(os.path.dirname(OUT_WAV), exist_ok=True)
    L = np.zeros(N)
    R = np.zeros(N)

    # 进行：Am - F - C - G（每 4 拍一小节）
    root_seq = [55.0, 43.65, 65.41 / 2, 49.0]          # A1, F1, C2, G1
    chord_seq = [
        (220.0, 261.63, 329.63),   # Am
        (174.61, 220.0, 261.63),   # F
        (196.0, 246.94, 329.63),   # C
        (196.0, 246.94, 293.66),   # G
    ]
    arp_seq = [440.0, 523.25, 659.25, 523.25, 440.0, 392.0, 523.25, 392.0]

    total_beats = int(DUR / BEAT)
    beat_times = []

    for b in range(total_beats):
        t0 = b * BEAT
        beat_times.append(round(t0, 4))
        bar = (b // 4) % 4
        beat_in_bar = b % 4

        # kick：四踩
        if beat_in_bar in (0, 2):
            add(L, t0, kick()); add(R, t0, kick())
        if beat_in_bar == 2 and b % 16 >= 8:
            add(L, t0 + BEAT * 0.5, kick() * 0.7)
            add(R, t0 + BEAT * 0.5, kick() * 0.7)

        # clap：2、4 拍
        if beat_in_bar in (1, 3):
            s = clap()
            add(L, t0, s); add(R, t0 + 0.004, s)

        # hat：8 分
        for k in (0, 1):
            ht = t0 + k * BEAT * 0.5
            s = hat(open_=(beat_in_bar == 3 and k == 1))
            amp = 0.55 if k == 0 else 0.38
            add(L, ht, s * amp); add(R, ht, s * amp * 0.95)

        # bass：8 分律动
        root = root_seq[bar]
        for k in (0, 1):
            bt = t0 + k * BEAT * 0.5
            s = bass(root * (1.0 if k == 0 else 1.5), BEAT * 0.45)
            add(L, bt, s); add(R, bt, s)

        # pad：每小节
        if beat_in_bar == 0:
            s = pad(chord_seq[bar], BEAT * 4)
            add(L, t0, s); add(R, t0, s * 0.92)

        # arp：后 1/3 段落
        if t0 > DUR * 0.42:
            for k in range(4):
                at = t0 + k * BEAT * 0.25
                f = arp_seq[(b * 4 + k) % len(arp_seq)]
                s = pluck(f, BEAT * 0.3)
                add(L, at, s * 0.8); add(R, at, s)

    # 转场冲击点（对应分镜段落切换）
    for t_impact in (6.0, 14.0, 23.0, 32.0, 40.0, 46.0):
        s = impact()
        add(L, t_impact, s); add(R, t_impact, s)

    # 段落前的上扬
    for t_rise in (4.6, 12.6, 21.6, 30.6, 38.6, 44.6):
        s = riser(1.4)
        add(L, t_rise, s); add(R, t_rise, s * 0.9)

    # 整体淡入淡出
    fade_in = int(0.6 * SR)
    fade_out = int(1.8 * SR)
    L[:fade_in] *= np.linspace(0, 1, fade_in)
    R[:fade_in] *= np.linspace(0, 1, fade_in)
    L[-fade_out:] *= np.linspace(1, 0, fade_out)
    R[-fade_out:] *= np.linspace(1, 0, fade_out)

    # 限幅 + 归一
    peak = max(np.abs(L).max(), np.abs(R).max(), 1e-6)
    g = 0.89 / peak
    L *= g; R *= g

    stereo = np.stack([L, R], axis=1)
    pcm = np.clip(stereo, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype(np.int16)

    with wave.open(OUT_WAV, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm16.tobytes())

    beats = {
        "bpm": BPM,
        "duration": DUR,
        "beat_times": beat_times,
        "transitions": [6.0, 14.0, 23.0, 32.0, 40.0, 46.0],
    }
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(beats, f, indent=2)

    print("wrote", os.path.abspath(OUT_WAV), "%.1fs" % DUR)
    print("wrote", os.path.abspath(OUT_JSON), "beats:", len(beat_times))


if __name__ == "__main__":
    main()
