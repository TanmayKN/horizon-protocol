#!/usr/bin/env python3
"""Voice acting for The Horizon Protocol, generated offline with the Piper neural TTS.

Every radio line, cutscene line and shout in the scripts gets a voice file:
  assets/voice/<md5("speaker|text")[:12]>.ogg
The game computes the same key at runtime (see scripts/voice.gd).

Voices: LibriTTS "high" model for Piper (CC BY 4.0), one speaker per character.
  pip install piper-tts ; voice from github.com/rhasspy/piper/releases (voice-en-us-libritts-high)
  python3 tools/gen_voice.py [--force]
"""
import hashlib
import io
import os
import re
import sys
import wave

import numpy as np
from scipy import signal

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "voice")
MODEL = os.environ.get("PIPER_MODEL", "/tmp/voices/en-us-libritts-high/en-us-libritts-high.onnx")

# character -> (libritts speaker id, length_scale (slower > 1), pitch shift in semitones)
CAST = {
    "vance": (553, 0.98, 0.0),
    "reyes": (462, 0.95, 0.0),
    "hale": (805, 0.97, 0.0),
    "raskov": (49, 1.0, -1.5),
    "command": (868, 1.0, 0.0),
    "pilot": (217, 0.95, 0.0),
    "guard1": (399, 0.95, 0.0),
    "guard2": (686, 0.95, 0.0),
    "merc": (105, 0.9, 0.0),
}


def who(speaker: str) -> str:
    s = speaker.lower()
    if "vance" in s:
        return "vance"
    if "reyes" in s or "overwatch" in s:
        return "reyes"
    if "hale" in s:
        return "hale"
    if "raskov" in s:
        return "raskov"
    if "command" in s:
        return "command"
    if "nightingale" in s:
        return "pilot"
    if "guard 2" in s:
        return "guard2"
    if "guard" in s or "shout" in s:
        return "guard1"
    return "merc"


def key(speaker: str, text: str) -> str:
    return hashlib.md5(f"{speaker}|{text}".encode("utf-8")).hexdigest()[:12]


LIT = r'"((?:[^"\\]|\\.)*)"'


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\'", "'").replace("\\n", "\n").replace("\\\\", "\\")


def collect():
    lines = set()
    consts = {}
    files = ["scripts/mission.gd", "scripts/story.gd", "scripts/enemy.gd"]
    srcs = {f: open(os.path.join(ROOT, f)).read() for f in files}
    for f, src in srcs.items():
        for m in re.finditer(r'const\s+([A-Z_0-9]+)\s*:?=\s*' + LIT, src):
            consts[m.group(1)] = unescape(m.group(2))

    def spk(tok):
        tok = tok.strip()
        if tok.startswith('"'):
            return unescape(tok[1:-1])
        return consts.get(tok)

    for f, src in srcs.items():
        # say(SPEAKER, "text", ...)
        for m in re.finditer(r'say\(\s*([A-Z_0-9]+|' + LIT + r')\s*,\s*' + LIT, src):
            s = spk(m.group(1))
            if s:
                lines.add((s, unescape(m.group(3))))
        # say(_handler(), "text") lines are spoken by Reyes or by Command
        for m in re.finditer(r'say\(\s*_handler\(\)\s*,\s*' + LIT, src):
            for who_c in ("OVERWATCH", "COMMAND"):
                lines.add((consts.get(who_c, who_c), unescape(m.group(1))))
        # [time, SPEAKER, "text" (or a conditional with two texts)]
        for m in re.finditer(r'\[\s*[\d.]+\s*,\s*([A-Z_0-9]+|' + LIT + r')\s*,\s*(.+?)\]', src):
            s = spk(m.group(1))
            if s:
                for t in re.findall(LIT, m.group(3)):
                    lines.add((s, unescape(t)))
        # overheard: [GUARD, "text"]
        for m in re.finditer(r'\[\s*([A-Z_0-9]+)\s*,\s*' + LIT + r'\s*\]', src):
            s = spk(m.group(1))
            if s:
                lines.add((s, unescape(m.group(2))))
        # Reyes' kill confirmations are picked from a list
        for ln in src.splitlines():
            if "var lines := [" in ln:
                for t in re.findall(LIT, ln):
                    for who_c in ("OVERWATCH", "COMMAND"):
                        lines.add((consts.get(who_c, who_c), unescape(t)))
        # shouts: every literal on a line that shouts / lists commands
        for ln in src.splitlines():
            if "shout(" in ln or "commands :=" in ln or "pick_random()" in ln and "shout" in ln:
                for t in re.findall(LIT, ln):
                    if t.isupper() or t.endswith("!"):
                        lines.add(("Shout", unescape(t)))
    return sorted(lines)


def pitch_shift(x, sr, semis):
    if abs(semis) < 0.01:
        return x
    f = 2 ** (semis / 12)
    y = signal.resample(x, int(len(x) * f))      # lower pitch = longer, then speed back up
    return y


def main():
    from piper import PiperVoice, SynthesisConfig
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    voice = PiperVoice.load(MODEL)
    todo = collect()
    keep = set()
    made = 0
    for speaker, text in todo:
        k = key(speaker, text)
        keep.add(k)
        path = os.path.join(OUT, k + ".ogg")
        if os.path.exists(path) and not force:
            continue
        who_ = who(speaker)
        sid, ls, semis = CAST[who_]
        spoken = text.replace("'H'", "H").replace("-", ", ").replace("...", ", ")
        if speaker == "Shout":
            spoken = text.capitalize()
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            voice.synthesize_wav(spoken, w, syn_config=SynthesisConfig(speaker_id=sid, length_scale=ls, noise_scale=0.6, noise_w_scale=0.7))
        buf.seek(0)
        with wave.open(buf) as w:
            sr = w.getframerate()
            x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float32) / 32768
        if semis:
            x = pitch_shift(x, sr, semis).astype(np.float32)
        # trim silence, gentle compression, normalise
        a = np.nonzero(np.abs(x) > 0.01)[0]
        if len(a):
            x = x[max(0, a[0] - int(0.03 * sr)): a[-1] + int(0.12 * sr)]
        x = np.tanh(x * 1.6) / np.tanh(1.6)
        x = x / (np.abs(x).max() + 1e-6) * 0.92
        tmp = "/tmp/_voice.wav"
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes((x * 32767).astype("<i2").tobytes())
        os.system(f'ffmpeg -loglevel error -y -i {tmp} -c:a libvorbis -q:a 4 "{path}"')
        made += 1
        print(f"[{who_}] {text[:70]}")
    # remove files for lines that no longer exist
    for fn in os.listdir(OUT):
        if fn.endswith(".ogg") and fn[:-4] not in keep:
            os.remove(os.path.join(OUT, fn))
            imp = os.path.join(OUT, fn + ".import")
            if os.path.exists(imp):
                os.remove(imp)
    print(f"{len(todo)} lines, {made} synthesised")


if __name__ == "__main__":
    main()
