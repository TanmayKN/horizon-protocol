#!/usr/bin/env python3
"""Offline sound design for The Horizon Protocol.

Synthesises every sound effect, ambience loop and music track at 44.1 kHz with numpy/scipy
(no samples, no licences) and writes 16-bit WAVs to assets/audio/.

  python3 tools/gen_audio.py            # everything
  python3 tools/gen_audio.py rifle music_combat   # just some

Names ending in _0.._N are variations: the game picks one at random each time.
"""
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- basic DSP helpers

def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.uniform(-1, 1, int(sec * SR))


def pink(sec):
    n = int(sec * SR)
    w = rng.standard_normal(n)
    f = np.fft.rfft(w)
    fr = np.fft.rfftfreq(n, 1 / SR)
    fr[0] = 1
    f /= np.sqrt(fr)
    x = np.fft.irfft(f, n)
    return x / (np.abs(x).max() + 1e-9)


def brown(sec):
    x = np.cumsum(rng.standard_normal(int(sec * SR)))
    x = signal.lfilter([1, -1], [1, -0.995], x)
    return x / (np.abs(x).max() + 1e-9)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x, axis=0)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x, axis=0)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x, axis=0)


def env_exp(sec, decay, attack=0.0005):
    t = t_axis(sec)
    e = np.exp(-t * decay)
    if attack > 0:
        e *= np.minimum(1, t / attack)
    return e


def adsr(n, a, d, s, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    e = np.full(n, s)
    a = min(a, n)
    e[:a] = np.linspace(0, 1, a, endpoint=False)
    d2 = min(d, n - a)
    e[a:a + d2] = np.linspace(1, s, d2, endpoint=False)
    if r > 0 and r < n:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def sweep(sec, f0, f1, curve=4.0):
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-t * curve)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def modal(sec, freqs, decays, gains):
    t = t_axis(sec)
    out = np.zeros_like(t)
    for f, d, g in zip(freqs, decays, gains):
        out += g * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t * d)
    return out


def place(buf, x, at):
    i = int(at * SR)
    if i >= len(buf):
        return buf
    n = min(len(x), len(buf) - i)
    buf[i:i + n] += x[:n]
    return buf


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=0.95):
    m = np.abs(x).max()
    return x / m * peak if m > 0 else x


def fade(x, fin=0.002, fout=0.01):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


def ir(sec, decay, bright=6000, stereo=True, predelay=0.0, density=1.0):
    """Synthetic room / space impulse response (exponentially decaying filtered noise)."""
    n = int(sec * SR)
    chans = []
    for _ in range(2 if stereo else 1):
        x = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * decay)
        if density < 1.0:
            x *= rng.random(n) < density
        x = lp(x, bright)
        pd = np.zeros(int(predelay * SR))
        chans.append(np.concatenate([pd, x]))
    out = np.stack(chans, 1) if stereo else chans[0]
    return out / np.sqrt((out ** 2).sum() / (2 if stereo else 1))


def reverb(x, sec=1.5, decay=4.0, wet=0.3, bright=6000, predelay=0.012):
    """Convolve (mono or stereo input) -> stereo output with a dry/wet mix."""
    h = ir(sec, decay, bright, True, predelay)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    n = len(x) + len(h) - 1
    y = np.stack([signal.fftconvolve(x[:, c], h[:, c])[:n] for c in range(2)], 1)
    dry = np.zeros_like(y)
    dry[:len(x)] = x
    return dry * (1 - wet) + y * wet * 0.35


def to_stereo(x, width=0.0):
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], 1)
    d = int(width * 0.0008 * SR) + 1
    r = np.concatenate([np.zeros(d), x[:-d]])
    return np.stack([x, r * 0.95 + x * 0.05], 1)


def loopify(x, xfade=1.5):
    """Make a seamless loop: crossfade the tail into the head."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n] if len(x) > 2 * n else x[n:], x[-n:]
    w = np.linspace(0, 1, n)
    if x.ndim == 2:
        w = w[:, None]
    blended = tail * (1 - w) + head * w
    return np.concatenate([blended, x[n:-n]]) if len(x) > 2 * n else x


TMP = "/tmp/hp_audio_wav"


def write(name, x, peak=0.95, normalize=True, trim=True):
    """Write a WAV to a temp dir, then encode it to OGG Vorbis in assets/audio (small + good)."""
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    if normalize:
        x = norm(x, peak)
    x = np.clip(x, -1, 1)
    if trim:   # drop the silent end of reverb tails
        a = np.abs(x) if x.ndim == 1 else np.abs(x).max(1)
        idx = np.nonzero(a > 0.0006)[0]
        if len(idx):
            end = min(len(x), idx[-1] + int(0.05 * SR))
            x = fade(x[:end], 0, min(0.04, end / SR / 4))
    ch = 2 if x.ndim == 2 else 1
    data = (x * 32767).astype("<i2").tobytes()
    wav = os.path.join(TMP, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    ogg = os.path.join(OUT, name + ".ogg")
    q = "4" if name.startswith("step_") or name.startswith("impact") else "5"
    os.system(f'ffmpeg -loglevel error -y -i "{wav}" -c:a libvorbis -q:a {q} "{ogg}"')


# ---------------------------------------------------------------- guns

def gun_core(sec, body_f=(140, 48), body_decay=18, crack=1.0, boom=1.0, mid=1.0, mid_decay=35,
             mid_band=(250, 3000), drive=3.0):
    """The shot itself: transient click + supersonic crack + chest-thump + mid blast."""
    n = int(sec * SR)
    out = np.zeros(n)
    # 1) transient: a couple of ms of full-band impulse
    click = noise(0.004) * env_exp(0.004, 900)
    place(out, click * 1.6, 0)
    # 2) crack: bright N-wave-ish burst
    if crack > 0:
        c = hp(noise(0.03), 2500) * env_exp(0.03, 220)
        place(out, c * crack * 1.2, 0)
    # 3) boom: pitched low thump sweeping down
    b = sweep(min(sec, 0.5), body_f[0], body_f[1], 18) * env_exp(min(sec, 0.5), body_decay, 0.001)
    place(out, b * boom * 1.3, 0)
    # 4) mid blast: band-passed noise, this is most of the "bang"
    m = bp(noise(0.4), *mid_band) * env_exp(0.4, mid_decay, 0.0007)
    place(out, m * mid * 1.5, 0)
    return sat(out, drive)


def outdoor_tail(sec, strength=1.0, echoes=((0.11, 0.35), (0.27, 0.22), (0.52, 0.14), (0.86, 0.08))):
    """Rolling rumble + slap echoes off hills / buildings."""
    n = int(sec * SR)
    out = np.zeros(n)
    rum = lp(noise(sec), 700) * env_exp(sec, 3.2, 0.02)
    out += rum * 0.55 * strength
    for d, g in echoes:
        e = lp(bp(noise(0.25), 150, 2200) * env_exp(0.25, 16, 0.004), 1800)
        place(out, e * g * strength * rng.uniform(0.8, 1.2), d + rng.uniform(-0.02, 0.02))
    return out


def mech(sec, at, freqs=(2300, 3700, 5200), dec=(90, 110, 140), gain=0.3):
    """Metal-on-metal action click."""
    n = int(sec * SR)
    out = np.zeros(n)
    m = modal(0.08, freqs, dec, [1, 0.7, 0.5]) + hp(noise(0.08), 3000) * env_exp(0.08, 160)
    place(out, m * gain, at)
    return out


def gunshot(kind, var):
    rng.bit_generator.advance(var * 1000)
    j = lambda a: a * rng.uniform(0.93, 1.07)
    if kind == "rifle":       # player's suppressed M4: thwump + loud action, short tail
        sec = 0.9
        x = gun_core(sec, (j(170), 60), 26, crack=0.18, boom=0.9, mid=0.55, mid_decay=55,
                     mid_band=(180, 1600), drive=1.8)
        x += bp(noise(sec), 700, 2800) * env_exp(sec, 60, 0.002) * 0.35          # gas "pfft"
        x += mech(sec, j(0.045), (j(2100), j(3300), j(4800)), gain=0.55)          # bolt carrier
        x += mech(sec, j(0.085), (j(1700), j(2900), j(4100)), gain=0.35)
        x += outdoor_tail(sec, 0.28, ((0.1, 0.2), (0.24, 0.12)))
        return reverb(x, 0.9, 6, 0.18)
    if kind == "enemy_rifle":  # AK-47: big crack, heavy mid, rolling echoes
        sec = 1.6
        x = gun_core(sec, (j(130), 45), 16, crack=1.0, boom=1.1, mid=1.2, mid_decay=24,
                     mid_band=(220, 3400), drive=2.4)
        x += mech(sec, j(0.05), (j(1900), j(3100), j(4400)), gain=0.25)
        x += outdoor_tail(sec, 1.0)
        return reverb(x, 1.4, 4, 0.22)
    if kind == "sniper":     # .308 DMR: huge boom, long rolling thunder
        sec = 3.0
        x = gun_core(sec, (j(110), 38), 10, crack=1.3, boom=1.6, mid=1.3, mid_decay=16,
                     mid_band=(160, 3200), drive=2.8)
        x += lp(noise(sec), 250) * env_exp(sec, 1.6, 0.03) * 0.6
        x += outdoor_tail(sec, 1.5, ((0.16, 0.4), (0.42, 0.28), (0.8, 0.18), (1.3, 0.1), (1.9, 0.06)))
        x += mech(sec, j(0.06), (j(1500), j(2600), j(3900)), gain=0.2)
        return reverb(x, 2.2, 2.5, 0.25)
    if kind == "pistol":     # 9mm: sharp snappy bang, slide cycle
        sec = 1.0
        x = gun_core(sec, (j(200), 70), 30, crack=0.8, boom=0.7, mid=1.1, mid_decay=40,
                     mid_band=(400, 4200), drive=2.2)
        x += mech(sec, j(0.035), (j(2600), j(4000), j(5600)), gain=0.4)
        x += outdoor_tail(sec, 0.6, ((0.1, 0.3), (0.25, 0.18), (0.48, 0.1)))
        return reverb(x, 1.0, 5, 0.2)
    if kind == "mg":         # technical's machine gun (heavier AK)
        sec = 1.4
        x = gun_core(sec, (j(100), 40), 14, crack=1.1, boom=1.4, mid=1.3, mid_decay=22,
                     mid_band=(180, 3000), drive=2.8)
        x += outdoor_tail(sec, 1.1)
        return reverb(x, 1.4, 4, 0.2)
    raise ValueError(kind)


def distant(x, cut=900, gain=0.7):
    """Filtered copy for far-away gunfire."""
    y = lp(x, cut, 2)
    return y * gain


# ---------------------------------------------------------------- foley

def casing(var):
    """Brass shell casing bouncing on the ground."""
    rng.bit_generator.advance(var * 999)
    sec = 0.7
    out = np.zeros(int(sec * SR))
    f0 = rng.uniform(3800, 5200)
    tt = 0.0
    g = 0.5
    for k in range(rng.integers(3, 6)):
        m = modal(0.18, [f0, f0 * 1.47, f0 * 2.13, f0 * 0.61], [40, 55, 70, 50], [1, 0.6, 0.35, 0.3])
        place(out, m * g, tt)
        tt += rng.uniform(0.06, 0.14) * (0.8 ** k)
        g *= 0.55
    return to_stereo(hp(out, 1500), 0.3)


def reload_snd():
    sec = 1.8
    out = np.zeros(int(sec * SR))
    # mag release click + mag sliding out
    place(out, mech(0.2, 0, (1800, 2900, 4400), gain=0.8), 0.05)
    place(out, bp(noise(0.18), 900, 4000) * env_exp(0.18, 18, 0.02) * 0.25, 0.1)
    # mag in: slide then seat (heavy)
    place(out, bp(noise(0.22), 700, 3500) * env_exp(0.22, 12, 0.08) * 0.3, 0.7)
    seat = mech(0.2, 0, (1300, 2200, 3500), (60, 80, 100), gain=1.0)
    place(seat, sweep(0.1, 300, 120, 30) * env_exp(0.1, 50) * 0.5, 0)
    place(out, seat, 0.92)
    # charging handle back ... and forward
    place(out, bp(noise(0.12), 1200, 5000) * env_exp(0.12, 25, 0.03) * 0.3, 1.3)
    place(out, mech(0.2, 0, (2000, 3400, 5000), gain=0.7), 1.4)
    place(out, mech(0.2, 0, (1600, 2700, 3900), (70, 90, 120), gain=1.0), 1.55)
    return reverb(out, 0.5, 10, 0.12)


def empty_click():
    x = mech(0.25, 0.0, (2500, 3900, 5400), (120, 150, 180), gain=1.0)
    return reverb(x, 0.4, 12, 0.1)


def swap_snd():
    sec = 0.6
    out = bp(noise(sec), 600, 3500) * env_exp(sec, 9, 0.05) * 0.3     # cloth / sling
    place(out, mech(0.2, 0, (1800, 3000, 4300), gain=0.8), 0.18)
    place(out, mech(0.2, 0, (2200, 3500, 5000), gain=0.6), 0.32)
    return reverb(out, 0.4, 12, 0.1)


def swish():
    sec = 0.35
    t = t_axis(sec)
    e = np.sin(np.pi * np.clip(t / 0.28, 0, 1)) ** 2
    x = bp(noise(sec), 1500, 7000) * e
    x += bp(noise(sec), 400, 1500) * e * 0.4
    return to_stereo(x, 0.5)


def stab():
    sec = 0.4
    x = lp(noise(sec), 900) * env_exp(sec, 30, 0.002)
    x += sweep(sec, 180, 70, 20) * env_exp(sec, 25) * 0.8
    x += bp(noise(sec), 300, 1200) * env_exp(sec, 14, 0.02) * 0.3          # wet
    return sat(x, 2)


def cut_snd():
    sec = 0.6
    out = np.zeros(int(sec * SR))
    place(out, modal(0.3, [3200, 4700, 6100], [60, 80, 100], [1, 0.6, 0.4]) * 0.6, 0)
    place(out, hp(noise(0.02), 2000) * env_exp(0.02, 300), 0)
    # wire twang
    t = t_axis(0.5)
    f = 220 * (1 + 0.03 * np.exp(-t * 8))
    tw = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    tw += 0.5 * np.sin(2 * 2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    place(out, tw * 0.5, 0.01)
    return reverb(out, 0.8, 6, 0.15)


def impact(surface, var):
    rng.bit_generator.advance(var * 777)
    sec = 0.5
    out = np.zeros(int(sec * SR))
    if surface == "dirt":
        place(out, lp(noise(0.3), 1500) * env_exp(0.3, 22, 0.001), 0)
        for _ in range(12):
            place(out, bp(noise(0.02), 800, 3000) * env_exp(0.02, 200) * rng.uniform(0.1, 0.3), rng.uniform(0.02, 0.3))
    elif surface == "metal":
        f = rng.uniform(900, 1400)
        place(out, modal(0.5, [f, f * 1.6, f * 2.7, f * 3.9], [12, 15, 20, 26], [0.6, 0.5, 0.35, 0.2]), 0)
        place(out, hp(noise(0.01), 2000) * env_exp(0.01, 400) * 1.2, 0)
        if var % 2 == 0:   # ricochet whine
            t = t_axis(0.4)
            fr = rng.uniform(2500, 3600) * (1 - 0.4 * t / 0.4)
            place(out, np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 6) * 0.25, 0.02)
    elif surface == "concrete":
        place(out, bp(noise(0.25), 400, 5000) * env_exp(0.25, 35, 0.0005), 0)
        place(out, hp(noise(0.006), 3000) * env_exp(0.006, 500) * 1.3, 0)
        for _ in range(8):
            place(out, hp(noise(0.015), 2500) * env_exp(0.015, 250) * rng.uniform(0.1, 0.35), rng.uniform(0.03, 0.25))
    elif surface == "wood":
        place(out, modal(0.2, [rng.uniform(300, 450), 780, 1300], [40, 55, 70], [0.8, 0.5, 0.3]), 0)
        place(out, bp(noise(0.12), 600, 3500) * env_exp(0.12, 45), 0)
    elif surface == "flesh":
        place(out, lp(noise(0.25), 700) * env_exp(0.25, 30, 0.001), 0)
        place(out, sweep(0.2, 150, 60, 25) * env_exp(0.2, 30) * 0.9, 0)
        place(out, bp(noise(0.15), 300, 1500) * env_exp(0.15, 20, 0.01) * 0.3, 0.01)
    return reverb(sat(out, 1.5), 0.6, 8, 0.15)


def whiz(var):
    """Supersonic bullet cracking past + little whistle with doppler."""
    rng.bit_generator.advance(var * 555)
    sec = 0.45
    out = np.zeros(int(sec * SR))
    place(out, hp(noise(0.006), 3000) * env_exp(0.006, 500) * 1.4, 0.0)
    t = t_axis(0.35)
    f = rng.uniform(1800, 2600) * (1.25 - 0.5 * t / 0.35)
    wh = bp(noise(0.35), 1500, 6000) * np.exp(-((t - 0.08) / 0.07) ** 2) * 0.6
    wh += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-((t - 0.07) / 0.06) ** 2) * 0.15
    place(out, wh, 0.0)
    x = to_stereo(out)
    pan = rng.uniform(-1, 1)
    x[:, 0] *= 1 - max(0, pan) * 0.6
    x[:, 1] *= 1 + min(0, pan) * 0.6
    return x


def glass():
    sec = 1.4
    out = np.zeros(int(sec * SR))
    place(out, hp(noise(0.05), 1500) * env_exp(0.05, 60) * 1.2, 0)
    for k in range(40):
        f = rng.uniform(2500, 8000)
        place(out, modal(0.3, [f, f * 1.37], [30, 45], [1, 0.5]) * rng.uniform(0.05, 0.25), rng.uniform(0, 0.9) ** 1.5)
    place(out, lp(noise(0.3), 800) * env_exp(0.3, 20) * 0.5, 0)
    return reverb(out, 1.0, 5, 0.2)


def explosion(var=0, big=1.0):
    rng.bit_generator.advance(var * 333)
    sec = 4.5
    out = np.zeros(int(sec * SR))
    place(out, noise(0.01) * env_exp(0.01, 300) * 2, 0)
    place(out, sweep(1.2, 90, 28, 3) * env_exp(1.2, 3.5, 0.005) * 1.8 * big, 0)
    body = noise(sec)
    # filter sweep: bright blast darkening into rumble
    b1 = lp(body, 3500) * env_exp(sec, 9, 0.002)
    b2 = lp(body, 400) * env_exp(sec, 1.1, 0.03)
    out += b1 * 1.2 + b2 * 1.4 * big
    for _ in range(60):     # debris
        place(out, bp(noise(0.03), 600, 4000) * env_exp(0.03, 120) * rng.uniform(0.05, 0.3), rng.uniform(0.15, 2.2) ** 1.2)
    out = sat(out, 3.0)
    out += outdoor_tail(sec, 1.2, ((0.25, 0.4), (0.6, 0.3), (1.1, 0.2), (1.8, 0.12)))
    return reverb(out, 3.0, 1.8, 0.3, 4000)


def grenade_bounce():
    sec = 0.9
    out = np.zeros(int(sec * SR))
    tt, g = 0.0, 1.0
    for k in range(4):
        place(out, modal(0.15, [620, 1450, 2380], [40, 55, 70], [1, 0.5, 0.3]) * g, tt)
        place(out, lp(noise(0.05), 1200) * env_exp(0.05, 60) * g * 0.5, tt)
        tt += 0.22 * (0.7 ** k)
        g *= 0.6
    return reverb(out, 0.6, 8, 0.15)


def pin_pull():
    out = mech(0.4, 0.0, (3000, 4500, 6200), gain=0.8)
    place(out, modal(0.3, [5200, 7100], [20, 30], [0.4, 0.2]), 0.12)   # spoon ping
    return reverb(out, 0.4, 12, 0.1)


def hit_marker():
    t = t_axis(0.12)
    x = np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 60) * 0.5 + hp(noise(0.12), 3000) * np.exp(-t * 90) * 0.3
    return to_stereo(x)


def hurt(var):
    """Player getting hit: body thump, muffled + a little cloth."""
    rng.bit_generator.advance(var * 211)
    sec = 0.5
    out = np.zeros(int(sec * SR))
    place(out, sweep(0.3, 120, 45, 15) * env_exp(0.3, 16, 0.002), 0)
    place(out, lp(noise(0.2), 500) * env_exp(0.2, 25) * 0.8, 0)
    place(out, bp(noise(0.3), 600, 3000) * env_exp(0.3, 14, 0.02) * 0.15, 0.02)
    return to_stereo(sat(out, 2))


def heartbeat():
    sec = 1.0
    out = np.zeros(int(sec * SR))
    for at, g in [(0.0, 1.0), (0.24, 0.7)]:
        place(out, sweep(0.18, 70, 38, 20) * env_exp(0.18, 20, 0.008) * g, at)
    return to_stereo(lp(out, 200))


def beep():
    t = t_axis(0.18)
    x = (np.sin(2 * np.pi * 1320 * t) + 0.3 * np.sin(2 * np.pi * 2640 * t)) * adsr(len(t), 0.003, 0.05, 0.5, 0.06)
    return to_stereo(x * 0.6)


def ui_click():
    t = t_axis(0.06)
    return to_stereo(np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 90) * 0.5)


def radio_in():
    """Squelch + static burst + chirp: plays when someone talks on the radio."""
    sec = 0.5
    out = np.zeros(int(sec * SR))
    place(out, bp(noise(0.12), 1200, 5000) * env_exp(0.12, 12, 0.003) * 0.5, 0)
    t = t_axis(0.09)
    place(out, np.sign(np.sin(2 * np.pi * 1850 * t)) * 0.18 * np.exp(-t * 8) * (t < 0.07), 0.13)
    place(out, bp(noise(0.25), 800, 3500) * env_exp(0.25, 10, 0.01) * 0.12, 0.22)
    return to_stereo(out)


def radio_out():
    sec = 0.3
    out = np.zeros(int(sec * SR))
    t = t_axis(0.06)
    place(out, np.sign(np.sin(2 * np.pi * 1450 * t)) * 0.18, 0)
    place(out, bp(noise(0.2), 1000, 5000) * env_exp(0.2, 18, 0.002) * 0.4, 0.06)
    return to_stereo(out)


def door():
    """Heavy steel shutter slamming down: rattle then clang."""
    sec = 2.2
    out = np.zeros(int(sec * SR))
    rat = np.zeros(int(1.0 * SR))
    for k in range(70):
        place(rat, modal(0.05, [rng.uniform(700, 1800), rng.uniform(1900, 3000)], [80, 110], [1, 0.5]) * rng.uniform(0.05, 0.2), k / 70)
    rat += bp(noise(1.0), 200, 1500) * 0.15
    place(out, rat * np.linspace(0.4, 1, len(rat)), 0)
    clang = modal(1.2, [180, 297, 431, 612, 890, 1210], [5, 6, 8, 10, 13, 17], [1, 0.8, 0.6, 0.45, 0.3, 0.2])
    clang += lp(noise(1.2), 400) * env_exp(1.2, 8) * 0.6
    place(out, sat(clang, 2) * 1.2, 0.98)
    return reverb(out, 2.0, 3, 0.3)


def alarm():
    """Klaxon: two-tone warble, with reverb baked in, 2 s loop."""
    sec = 2.0
    t = t_axis(sec)
    f = np.where((t % 1.0) < 0.5, 740, 555)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = signal.sawtooth(ph) * 0.6 + np.sin(ph * 2) * 0.2
    x = lp(x, 2500)
    x = reverb(x, 1.6, 3, 0.35)
    return loopify(x, 0.3)


# ---------------------------------------------------------------- footsteps

def step(surface, var):
    rng.bit_generator.advance(var * 97 + hash(surface) % 1000)
    sec = 0.55
    out = np.zeros(int(sec * SR))
    toe = rng.uniform(0.075, 0.11)
    w = rng.uniform(0.8, 1.1)

    def grains(start, length, count, lo, hi, g):
        for _ in range(count):
            place(out, bp(noise(0.015), lo, hi) * env_exp(0.015, rng.uniform(200, 400)) * g * rng.uniform(0.3, 1.0),
                  start + rng.random() ** 1.6 * length)

    if surface == "grass":
        place(out, lp(noise(0.14), 500) * env_exp(0.14, 35, 0.004) * w, 0)
        place(out, sweep(0.1, 90, 55, 30) * env_exp(0.1, 40) * 0.3 * w, 0)
        grains(0.005, 0.22, 26, 900, 4200, 0.16)
        place(out, bp(noise(0.12), 150, 1800) * env_exp(0.12, 40) * 0.35, toe)
        grains(toe, 0.14, 12, 1000, 4500, 0.12)
        place(out, bp(noise(0.35), 1800, 6000) * env_exp(0.35, 12, 0.02) * 0.04, 0.02)
        cut = 3200
    elif surface == "gravel":
        place(out, lp(noise(0.1), 800) * env_exp(0.1, 40, 0.003) * 0.7 * w, 0)
        grains(0.0, 0.25, 90, 700, 4200, 0.26)
        grains(toe, 0.18, 55, 800, 4500, 0.2)
        place(out, bp(noise(0.3), 600, 3500) * env_exp(0.3, 11) * 0.1, 0)
        cut = 4500
    elif surface == "mud":
        place(out, lp(noise(0.16), 420) * env_exp(0.16, 24, 0.006) * w, 0)
        place(out, sweep(0.14, 110, 55, 22) * env_exp(0.14, 22) * 0.5 * w, 0)
        t = t_axis(0.22)
        suck = lp(noise(0.22), 900) * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(22 - 13 * t / 0.22) / SR)) * np.exp(-t * 11)
        place(out, suck * 0.8, toe + 0.04)
        place(out, sweep(0.05, 380, 900, -20) * env_exp(0.05, 55) * 0.15, toe + 0.22)
        grains(0.02, 0.15, 10, 400, 1600, 0.25)
        cut = 2200
    elif surface == "hard":
        place(out, bp(noise(0.05), 200, 5000) * env_exp(0.05, 90, 0.0008) * w, 0)
        place(out, sweep(0.05, 150, 90, 40) * env_exp(0.05, 70) * 0.35 * w, 0)
        place(out, bp(noise(0.08), 500, 4000) * env_exp(0.08, 55) * 0.45, toe)
        place(out, bp(noise(0.1), 800, 5000) * env_exp(0.1, 30, 0.01) * 0.06, toe + 0.04)   # scuff
        cut = 5000
    elif surface == "metal":
        place(out, bp(noise(0.05), 200, 5000) * env_exp(0.05, 80, 0.0008) * 0.8 * w, 0)
        fs = [f * rng.uniform(0.96, 1.04) for f in (410, 687, 1123, 1590, 2210, 2950)]
        place(out, modal(0.5, fs, [9, 11, 13, 15, 18, 22], [0.5, 0.4, 0.3, 0.2, 0.14, 0.1]), 0)
        grains(0.01, 0.12, 14, 1500, 5000, 0.15)
        place(out, bp(noise(0.05), 300, 4000) * env_exp(0.05, 80) * 0.4, toe)
        place(out, modal(0.3, [520, 980, 1400], [16, 20, 24], [0.12, 0.08, 0.05]), toe)
        cut = 6500
    else:
        raise ValueError(surface)
    out = lp(out, cut)
    # tiny bit of room / space so steps don't sound pasted on
    return reverb(out, 0.35, 14, 0.12 if surface in ("hard", "metal") else 0.06)


def land(surface):
    x = step(surface, 9) * 1.4
    thud = np.zeros(len(x))
    place(thud, sweep(0.2, 90, 45, 15) * env_exp(0.2, 18, 0.003), 0)
    return x + to_stereo(thud) * 0.6


def cloth(var):
    rng.bit_generator.advance(var * 123)
    sec = 0.4
    t = t_axis(sec)
    e = np.sin(np.pi * t / sec) ** 2
    x = bp(noise(sec), 600, 3500) * e * 0.4 + bp(noise(sec), 2500, 7000) * e * 0.1
    return to_stereo(x, 0.4)


# ---------------------------------------------------------------- ambience (stereo loops)

def amb_rain(sec=16):
    L = []
    for c in range(2):
        hiss = lp(hp(pink(sec), 400), 9000) * 0.35
        roar = lp(brown(sec), 600) * 0.25
        drops = np.zeros(int(sec * SR))
        for _ in range(int(sec * 110)):
            f = rng.uniform(1500, 6000)
            place(drops, modal(0.04, [f], [rng.uniform(60, 120)], [1]) * rng.uniform(0.02, 0.12), rng.uniform(0, sec))
        slow = 0.85 + 0.15 * np.sin(2 * np.pi * np.arange(int(sec * SR)) / SR / sec * 2 + c)
        L.append((hiss + roar + drops) * slow)
    return loopify(np.stack(L, 1), 2.0)


def amb_rain_roof(sec=12):
    """Rain heard from inside: muffled roar + drumming on sheet metal."""
    L = []
    for c in range(2):
        roar = lp(pink(sec), 900) * 0.4
        drum = np.zeros(int(sec * SR))
        for _ in range(int(sec * 70)):
            f = rng.uniform(300, 1200)
            place(drum, modal(0.06, [f, f * 2.3], [50, 70], [1, 0.3]) * rng.uniform(0.03, 0.1), rng.uniform(0, sec))
        L.append(roar + lp(drum, 2500))
    return loopify(np.stack(L, 1), 2.0)


def amb_wind(sec=20):
    L = []
    for c in range(2):
        t = t_axis(sec)
        gust = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 7.0 + c * 0.7)) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 3.1 + c))
        body = lp(brown(sec), 500) * 0.6
        whistle = bp(pink(sec), 600, 1400) * 0.15 * gust ** 2
        L.append(body * gust + whistle)
    return loopify(np.stack(L, 1), 3.0)


def amb_forest(sec=16):
    """Night forest: crickets + distant owl + leaves."""
    n = int(sec * SR)
    out = np.zeros((n, 2))
    t = t_axis(sec)
    for k in range(6):
        f = rng.uniform(3800, 5200)
        rate = rng.uniform(14, 22)
        chirp = np.sin(2 * np.pi * f * t) * (np.sin(2 * np.pi * rate * t) > 0.3) * (0.5 + 0.5 * np.sin(2 * np.pi * t / rng.uniform(1.5, 3) + k))
        g = rng.uniform(0.01, 0.03)
        pan = rng.uniform(0, 1)
        out[:, 0] += chirp * g * (1 - pan)
        out[:, 1] += chirp * g * pan
    leaves = bp(pink(sec), 1500, 6000) * 0.05
    out += np.stack([leaves, np.roll(leaves, 5000)], 1)
    # owl hoots
    for at in (3.2, 11.5):
        tt = t_axis(0.5)
        hoot = np.sin(2 * np.pi * (380 - 40 * tt) * tt) * np.sin(np.pi * tt / 0.5) ** 2 * 0.05
        place(out[:, 0], hoot * 0.6, at)
        place(out[:, 1], hoot, at + 0.01)
    return loopify(reverb(out, 2.5, 2.5, 0.35)[:n], 2.0)


def amb_indoor(sec=10):
    """Admin block: fluorescent buzz + mains hum + air handling."""
    t = t_axis(sec)
    hum = sum(np.sin(2 * np.pi * 50 * h * t) * g for h, g in [(1, 0.25), (2, 0.18), (3, 0.08), (4, 0.05)])
    buzz = bp(noise(sec), 2000, 6000) * 0.02 * (0.7 + 0.3 * np.sin(2 * np.pi * 100 * t))
    air = lp(pink(sec), 350) * 0.35
    L = np.stack([hum * 0.6 + buzz + air, hum * 0.6 + buzz + np.roll(air, 3000)], 1)
    return loopify(L, 1.0)


def amb_bunker(sec=14):
    """Deep underground: low drone, distant machinery, water drips."""
    t = t_axis(sec)
    n = len(t)
    drone = lp(brown(sec), 120) * 0.6 + np.sin(2 * np.pi * 38 * t) * 0.08
    mach = lp(noise(sec), 300) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.8 * t)) * 0.08
    out = np.stack([drone + mach, drone + np.roll(mach, 7000)], 1)
    for _ in range(9):
        f = rng.uniform(900, 1800)
        d = modal(0.25, [f, f * 1.8], [25, 35], [1, 0.3]) * 0.05
        c = rng.integers(0, 2)
        place(out[:, c], d, rng.uniform(0, sec - 0.3))
    return loopify(reverb(out, 3.0, 1.5, 0.4, 3000)[:n], 2.0)


def amb_vent(sec=8):
    air = lp(pink(sec), 1200) * 0.5 + np.sin(2 * np.pi * 60 * t_axis(sec)) * 0.05
    return loopify(to_stereo(air, 0.8), 1.0)


def engine(sec=4.0):
    """Diesel truck idle/drive loop: firing pulses + gear whine + rumble."""
    t = t_axis(sec)
    f0 = 33.0
    x = np.zeros_like(t)
    for h in range(1, 14):
        x += np.sin(2 * np.pi * f0 * h * t + rng.uniform(0, 6)) * (1 / h) * (1.3 if h in (2, 4, 6) else 1)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * f0 * 0.5 * t)
    x += lp(noise(sec), 300) * 0.5
    x += np.sin(2 * np.pi * 820 * t) * 0.02
    x = lp(sat(x * 0.6, 2), 1800)
    return loopify(to_stereo(x, 0.5), 0.5)


def helicopter(sec=6.0):
    t = t_axis(sec)
    rate = 5.2
    blade = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) ** 6
    thump = lp(noise(sec), 500) * blade * 1.2 + np.sin(2 * np.pi * 42 * t) * blade * 0.6
    turb = bp(pink(sec), 1500, 5000) * 0.12 + np.sin(2 * np.pi * 1900 * t) * 0.01
    x = thump + turb
    return loopify(to_stereo(x, 0.6), 0.5)


def thunder(var):
    rng.bit_generator.advance(var * 444)
    sec = 6.0
    out = np.zeros(int(sec * SR))
    place(out, hp(noise(0.15), 800) * env_exp(0.15, 20) * (0.6 if var else 0.2), 0)
    rum = lp(brown(sec), 180) * env_exp(sec, 0.9, 0.3)
    for _ in range(8):
        place(rum, lp(noise(0.8), 300) * env_exp(0.8, 4, 0.05) * rng.uniform(0.3, 1), rng.uniform(0.1, 3))
    out += rum
    return reverb(out, 3, 1.5, 0.3, 2000)


# ---------------------------------------------------------------- music
# Key: D minor. Everything is synthesised: strings = detuned saws through a low-pass, brass = saws
# with a filter envelope, taiko = pitched sine drop + noise, pulses = gated saw, pads = chorus.

BPM = 96
BEAT = 60 / BPM
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name):
    """'D3' -> frequency"""
    n, o = name[:-1], int(name[-1])
    return 440 * 2 ** ((NOTE[n] + 12 * (o + 1) - 69) / 12)


def saw_voice(f, sec, detune=0.12, voices=5, cut=1800, a=0.3, d=0.4, s=0.8, r=0.6, cut_env=0.0):
    t = t_axis(sec)
    x = np.zeros_like(t)
    for v in range(voices):
        dt = (v - (voices - 1) / 2) / max(1, voices - 1) * detune
        ff = f * 2 ** (dt / 12)
        x += signal.sawtooth(2 * np.pi * ff * t + rng.uniform(0, 6.28))
    x /= voices
    e = adsr(len(t), a, d, s, r)
    if cut_env > 0:   # brass-like filter opening
        seg = 256
        y = np.zeros_like(x)
        zi = None
        for i in range(0, len(x), seg):
            fc = cut * (1 + cut_env * e[i])
            b, aa = signal.butter(2, min(fc, SR * 0.45) / (SR / 2), "low")
            if zi is None:
                zi = signal.lfilter_zi(b, aa) * 0
            y[i:i + seg], zi = signal.lfilter(b, aa, x[i:i + seg], zi=zi)
        x = y
    else:
        x = lp(x, cut)
    return x * e


def taiko(big=1.0, pitch=1.0):
    sec = 1.2
    x = sweep(sec, 95 * pitch, 42 * pitch, 12) * env_exp(sec, 5.5 / big, 0.002)
    x += lp(noise(sec), 900) * env_exp(sec, 28, 0.001) * 0.5
    return sat(x * big, 1.5)


def snare_hit():
    x = bp(noise(0.3), 1500, 7000) * env_exp(0.3, 22) + sweep(0.3, 220, 160, 20) * env_exp(0.3, 30) * 0.5
    return x


def hat():
    return hp(noise(0.08), 7000) * env_exp(0.08, 70)


def mix_to(buf, x, at, pan=0.0, gain=1.0):
    if x.ndim == 1:
        x = np.stack([x * (1 - max(0, pan)), x * (1 + min(0, pan))], 1)
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(x), len(buf) - i)
    buf[i:i + n] += x[:n] * gain


def wrap_loop(buf, length):
    """Fold anything past the loop end back onto the start so the loop is seamless."""
    n = int(length * SR)
    out = buf[:n].copy()
    tail = buf[n:]
    k = min(len(tail), n)
    out[:k] += tail[:k]
    return out


CHORDS = [  # D minor progression: i - VI - III - VII  (Dm - Bb - F - C)
    ["D3", "F3", "A3"], ["A#2", "D3", "F3"], ["F2", "A2", "C3"], ["C3", "E3", "G3"],
]


def music_stealth():
    """Tense, sparse: low string drone, pulsing high harmonics, soft heartbeat drum."""
    bars = 8
    length = bars * 4 * BEAT
    buf = np.zeros((int((length + 4) * SR), 2))
    for b in range(bars):
        ch = CHORDS[(b // 2) % 4]
        t0 = b * 4 * BEAT
        if b % 2 == 0:
            for i, nm in enumerate(ch):
                v = saw_voice(hz(nm) / 2, 8 * BEAT + 1, 0.15, 5, 700, 1.5, 1.0, 0.7, 1.5)
                mix_to(buf, v, t0, (i - 1) * 0.5, 0.22)
        # heartbeat kick on 1 and the & of 1
        for beat in (0, 0.45):
            mix_to(buf, taiko(0.6, 0.9), t0 + beat * BEAT, 0, 0.35)
        # glassy pulses (8ths) on the fifth, very quiet
        for e in range(8):
            f = hz(ch[2]) * 4
            tt = t_axis(0.25)
            p = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 14) * 0.5
            mix_to(buf, p, t0 + e * BEAT / 2, 0.6 if e % 2 else -0.6, 0.05 + 0.03 * (b % 2))
    buf = reverb(buf, 3.5, 1.4, 0.45, 5000)
    return wrap_loop(buf, length)


def music_combat():
    """Driving: taiko + snare, staccato low string ostinato, brass stabs."""
    bars = 8
    length = bars * 4 * BEAT
    buf = np.zeros((int((length + 4) * SR), 2))
    ost = [0, 0, 12, 0, 7, 0, 10, 8]   # semitone offsets from chord root, 8ths... but 16ths below
    for b in range(bars):
        ch = CHORDS[(b // 2) % 4]
        root = hz(ch[0]) / 2
        t0 = b * 4 * BEAT
        # 16th-note string ostinato
        for s in range(16):
            f = root * 2 ** (ost[s % 8] / 12)
            v = saw_voice(f, BEAT / 4 + 0.08, 0.1, 3, 1400, 0.004, 0.06, 0.4, 0.06)
            mix_to(buf, v, t0 + s * BEAT / 4, 0.3 if s % 2 else -0.3, 0.22 if s % 4 == 0 else 0.15)
        # drums
        for beat, big in [(0, 1.3), (1.5, 0.8), (2, 1.1), (3, 0.9), (3.5, 0.7)]:
            mix_to(buf, taiko(big), t0 + beat * BEAT, 0, 0.55)
        for beat in (1, 3):
            mix_to(buf, snare_hit(), t0 + beat * BEAT, 0.1, 0.25)
        for e in range(8):
            mix_to(buf, hat(), t0 + e * BEAT / 2, 0.4, 0.06)
        # brass chord stabs on bars 2 and 4 of each phrase, long swell on 8
        if b % 2 == 1:
            for i, nm in enumerate(ch):
                v = saw_voice(hz(nm), 1.4 * BEAT, 0.08, 4, 500, 0.02, 0.3, 0.5, 0.25, cut_env=5)
                mix_to(buf, v, t0 + 2 * BEAT, (i - 1) * 0.4, 0.28)
        # low sustained strings underneath
        if b % 2 == 0:
            for i, nm in enumerate(ch):
                v = saw_voice(hz(nm) / 2, 8 * BEAT + 0.5, 0.15, 5, 900, 0.3, 1.0, 0.8, 0.8)
                mix_to(buf, v, t0, (i - 1) * 0.6, 0.12)
    buf = reverb(buf, 2.5, 2.2, 0.3, 7000)
    return wrap_loop(buf, length)


def music_menu():
    """Main theme: slow, big, emotional. Strings + a solo 'horn' melody."""
    bars = 16
    length = bars * 4 * BEAT * 1.25   # a bit slower
    beat = BEAT * 1.25
    buf = np.zeros((int((length + 5) * SR), 2))
    melody = [("A4", 2), ("D5", 2), ("C5", 1), ("A#4", 1), ("A4", 2), ("F4", 3), ("G4", 1), ("A4", 4),
              ("A4", 2), ("D5", 2), ("E5", 1), ("F5", 1), ("E5", 2), ("D5", 3), ("C5", 1), ("D5", 4),
              ("F5", 2), ("E5", 2), ("D5", 2), ("C5", 2), ("A#4", 2), ("A4", 2), ("G4", 4),
              ("A4", 3), ("C5", 1), ("D5", 8)]
    for b in range(bars):
        ch = CHORDS[b % 4]
        t0 = b * 4 * beat
        for i, nm in enumerate(ch + [ch[0][:-1] + str(int(ch[0][-1]) - 1)]):
            v = saw_voice(hz(nm), 4 * beat + 0.8, 0.18, 6, 1100, 0.8, 1.0, 0.8, 1.0)
            mix_to(buf, v, t0, (i - 1.5) * 0.4, 0.14)
        mix_to(buf, taiko(1.2, 0.8), t0, 0, 0.4)
        if b >= 8 and b % 2 == 0:
            mix_to(buf, taiko(0.8, 1.1), t0 + 2.5 * beat, 0, 0.25)
    tt = 0.0
    for nm, dur in melody:
        v = saw_voice(hz(nm) / 2, dur * beat + 0.3, 0.05, 3, 900, 0.08, 0.3, 0.8, 0.4, cut_env=2.5)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * t_axis(len(v) / SR))
        mix_to(buf, v * vib, 4 * 4 * beat + tt, 0.1, 0.3)
        tt += dur * beat
    buf = reverb(buf, 4.0, 1.2, 0.45, 6000)
    return wrap_loop(buf, length)


def stinger(kind):
    if kind == "alert":      # you've been spotted: brass swell + big hit
        buf = np.zeros((int(4 * SR), 2))
        for i, nm in enumerate(["D3", "A3", "D4", "F4"]):
            mix_to(buf, saw_voice(hz(nm), 1.4, 0.1, 4, 400, 0.4, 0.2, 0.9, 0.5, cut_env=6), 0, (i - 1.5) * 0.4, 0.3)
        mix_to(buf, taiko(1.8, 0.8), 0.9, 0, 0.9)
        return reverb(buf, 3, 1.5, 0.4)
    if kind == "title":      # segment title card: boom + low drone
        buf = np.zeros((int(6 * SR), 2))
        mix_to(buf, taiko(2.0, 0.6), 0, 0, 1.0)
        for i, nm in enumerate(["D2", "A2", "D3"]):
            mix_to(buf, saw_voice(hz(nm), 4.5, 0.2, 6, 500, 0.05, 2, 0.4, 2.0), 0, (i - 1) * 0.5, 0.3)
        return reverb(buf, 4, 1.2, 0.45)
    if kind == "victory":    # mission complete: major lift D -> Bb -> C -> D major
        buf = np.zeros((int(9 * SR), 2))
        prog = [["D3", "F3", "A3"], ["A#2", "D3", "F3"], ["C3", "E3", "G3"], ["D3", "F#3", "A3", "D4"]]
        for k, ch in enumerate(prog):
            for i, nm in enumerate(ch):
                d = 1.5 if k < 3 else 4.0
                mix_to(buf, saw_voice(hz(nm), d + 0.4, 0.12, 5, 1200, 0.15, 0.4, 0.8, 0.8, cut_env=2), k * 1.5, (i - 1.5) * 0.4, 0.2)
            mix_to(buf, taiko(1.2 if k == 3 else 0.8), k * 1.5, 0, 0.6)
        return reverb(buf, 4, 1.2, 0.4)
    if kind == "death":
        buf = np.zeros((int(5 * SR), 2))
        for i, nm in enumerate(["D3", "F3", "G#3"]):
            mix_to(buf, saw_voice(hz(nm), 3.5, 0.3, 5, 600, 0.02, 2, 0.3, 1.5), 0, (i - 1) * 0.5, 0.3)
        mix_to(buf, taiko(1.5, 0.5), 0, 0, 0.8)
        return reverb(buf, 4, 1.3, 0.5)
    if kind == "sting_reveal":  # story twist hit
        buf = np.zeros((int(6 * SR), 2))
        mix_to(buf, taiko(2.2, 0.55), 0, 0, 1.0)
        mix_to(buf, hp(noise(1.5), 3000) * np.linspace(0, 1, int(1.5 * SR)) ** 3 * 0.2, 0, 0, 1)   # riser before? (reverse feel)
        for i, nm in enumerate(["C#3", "D3", "G#3", "A3"]):
            mix_to(buf, saw_voice(hz(nm), 4.5, 0.25, 5, 900, 0.3, 1.5, 0.6, 1.8), 0.05, (i - 1.5) * 0.4, 0.2)
        return reverb(buf, 4, 1.2, 0.5)
    raise ValueError(kind)


def music_boss():
    """Final showdown: faster, heavier, choir-ish pad (formant-filtered saws)."""
    global BPM, BEAT
    old = BEAT
    BEAT = 60 / 118
    bars = 8
    length = bars * 4 * BEAT
    buf = np.zeros((int((length + 4) * SR), 2))
    prog = [["D3", "F3", "A3"], ["D#3", "G3", "A#3"], ["D3", "F3", "A3"], ["C#3", "E3", "A3"]]
    for b in range(bars):
        ch = prog[b % 4]
        t0 = b * 4 * BEAT
        root = hz(ch[0]) / 2
        for s in range(16):
            f = root * (2 if s % 4 == 2 else 1)
            v = saw_voice(f, BEAT / 4 + 0.05, 0.1, 3, 1000, 0.003, 0.05, 0.5, 0.05)
            mix_to(buf, v, t0 + s * BEAT / 4, 0, 0.25)
        for beat_i in range(4):
            mix_to(buf, taiko(1.3), t0 + beat_i * BEAT, 0, 0.5)
        mix_to(buf, taiko(1.0, 1.3), t0 + 3.5 * BEAT, 0, 0.35)
        for beat_i in (1, 3):
            mix_to(buf, snare_hit(), t0 + beat_i * BEAT, 0, 0.3)
        for i, nm in enumerate(ch):
            v = saw_voice(hz(nm), 4 * BEAT + 0.3, 0.2, 6, 3000, 0.2, 0.5, 0.8, 0.4)
            v = bp(v, 500, 1200) * 1.5 + bp(v, 2200, 3000) * 0.5   # "ah" formants
            mix_to(buf, v, t0, (i - 1) * 0.6, 0.35)
    buf = reverb(buf, 3.0, 1.8, 0.35, 7000)
    out = wrap_loop(buf, length)
    BEAT = old
    return out


# ---------------------------------------------------------------- registry

def build():
    R = {}
    for k in range(4):
        R[f"rifle_{k}"] = lambda k=k: gunshot("rifle", k)
        R[f"enemy_rifle_{k}"] = lambda k=k: gunshot("enemy_rifle", k)
        R[f"pistol_{k}"] = lambda k=k: gunshot("pistol", k)
        R[f"mg_{k}"] = lambda k=k: gunshot("mg", k)
        R[f"enemy_rifle_far_{k}"] = lambda k=k: distant(gunshot("enemy_rifle", k + 10), 700, 0.8)
    for k in range(3):
        R[f"sniper_{k}"] = lambda k=k: gunshot("sniper", k)
        R[f"casing_{k}"] = lambda k=k: casing(k)
        R[f"hurt_{k}"] = lambda k=k: hurt(k)
        R[f"explosion_{k}"] = lambda k=k: explosion(k)
        R[f"thunder_{k}"] = lambda k=k: thunder(k)
        R[f"cloth_{k}"] = lambda k=k: cloth(k)
    for k in range(4):
        R[f"whiz_{k}"] = lambda k=k: whiz(k)
        for s in ("dirt", "metal", "concrete", "wood", "flesh"):
            R[f"impact_{s}_{k}"] = lambda s=s, k=k: impact(s, k)
    for s in ("grass", "gravel", "mud", "hard", "metal"):
        for k in range(5):
            R[f"step_{s}_{k}"] = lambda s=s, k=k: step(s, k)
        R[f"land_{s}"] = lambda s=s: land(s)
    R.update({
        "reload": reload_snd, "empty": empty_click, "swap": swap_snd, "swish": swish, "stab": stab,
        "cut": cut_snd, "glass": glass, "grenade_bounce": grenade_bounce, "pin": pin_pull,
        "hitmarker": hit_marker, "heartbeat": heartbeat, "beep": beep, "click": ui_click,
        "radio": radio_in, "radio_out": radio_out, "door": door, "alarm": alarm,
        "rain": amb_rain, "rain_roof": amb_rain_roof, "wind": amb_wind, "forest": amb_forest,
        "hum": amb_indoor, "bunker": amb_bunker, "vent": amb_vent, "engine": engine, "helicopter": helicopter,
        "music_stealth": music_stealth, "music_combat": music_combat, "music_menu": music_menu,
        "music_boss": music_boss,
        "sting_alert": lambda: stinger("alert"), "sting_title": lambda: stinger("title"),
        "sting_victory": lambda: stinger("victory"), "sting_death": lambda: stinger("death"),
        "sting_reveal": lambda: stinger("sting_reveal"),
    })
    # aliases for older names used in code
    R["impact"] = lambda: impact("concrete", 0)
    R["hit"] = lambda: impact("flesh", 1)
    return R


LOOPS = {"rain", "rain_roof", "wind", "forest", "hum", "bunker", "vent", "engine", "helicopter", "alarm",
         "music_stealth", "music_combat", "music_menu", "music_boss"}
QUIET = {"rain": 0.7, "rain_roof": 0.7, "wind": 0.7, "forest": 0.6, "hum": 0.6, "bunker": 0.7, "vent": 0.6}


def main():
    R = build()
    names = sys.argv[1:] or list(R)
    sel = []
    for n in names:
        if n in R:
            sel.append(n)
        else:
            sel += [k for k in R if k.startswith(n)]
    for n in sel:
        x = R[n]()
        if n not in LOOPS:
            x = fade(x, 0.0005, 0.03)
        write(n, x, QUIET.get(n, 0.9 if n.startswith("music") else 0.95), trim=n not in LOOPS)
        print("wrote", n, f"{len(x) / SR:.2f}s")
    # loop list for the game
    with open(os.path.join(OUT, "loops.txt"), "w") as f:
        f.write("\n".join(sorted(LOOPS)) + "\n")


if __name__ == "__main__":
    main()
