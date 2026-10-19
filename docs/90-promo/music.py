"""Deterministic ambient soundtrack for the CardFlow promo (numpy only).

make_music(total_s, scene_starts_s, out_path) writes a 16-bit stereo WAV:
  - warm pad chords (slow attack), soft sub bass, sparse plucked arpeggio
  - a quiet bell at every scene start
  - 1 s fade in, 4 s fade out
"""
from __future__ import annotations

import wave

import numpy as np

SR = 44100


def note(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


# F major / D minor pad progression (midi numbers), 5 s per chord, loops.
CHORDS = [
    [53, 57, 60, 64],  # Fmaj7
    [57, 60, 64, 67],  # Am7
    [50, 53, 57, 60],  # Dm7
    [46, 50, 53, 57],  # Bbmaj7
    [55, 58, 62, 65],  # Gm7
    [48, 52, 55, 59],  # Cmaj7
]
CHORD_S = 5.0


def _env(n: int, attack: float, release: float) -> np.ndarray:
    t = np.arange(n) / SR
    dur = n / SR
    a = np.clip(t / max(attack, 1e-3), 0, 1)
    r = np.clip((dur - t) / max(release, 1e-3), 0, 1)
    return np.minimum(a, r)


def _pad_tone(freq: float, n: int, detune: float) -> np.ndarray:
    t = np.arange(n) / SR
    f = freq * (1 + detune)
    tone = (
        np.sin(2 * np.pi * f * t)
        + 0.35 * np.sin(2 * np.pi * 2 * f * t + 0.3)
        + 0.12 * np.sin(2 * np.pi * 3 * f * t + 0.9)
    )
    lfo = 1 + 0.08 * np.sin(2 * np.pi * 0.18 * t + freq % 1.7)
    return tone * lfo


def _pluck(freq: float, n: int) -> np.ndarray:
    t = np.arange(n) / SR
    env = np.exp(-t * 5.5)
    return env * (np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * 3 * freq * t)) * (1 - np.exp(-t * 400))


def _bell(freq: float, n: int) -> np.ndarray:
    t = np.arange(n) / SR
    return (
        np.exp(-t * 2.2) * np.sin(2 * np.pi * freq * t)
        + 0.5 * np.exp(-t * 3.5) * np.sin(2 * np.pi * freq * 2.76 * t)
        + 0.25 * np.exp(-t * 5) * np.sin(2 * np.pi * freq * 5.4 * t)
    ) * (1 - np.exp(-t * 600))


def make_music(total_s: float, scene_starts_s: list[float], out_path: str, seed: int = 7) -> None:
    rng = np.random.default_rng(seed)
    n_total = int(total_s * SR)
    left = np.zeros(n_total)
    right = np.zeros(n_total)

    # Pads + bass
    k = 0
    pos = 0.0
    while pos < total_s:
        chord = CHORDS[k % len(CHORDS)]
        start = int(pos * SR)
        n = min(int((CHORD_S + 1.5) * SR), n_total - start)  # overlap 1.5 s into next chord
        if n <= 0:
            break
        env = _env(n, attack=1.6, release=1.8)
        for i, m in enumerate(chord):
            f = note(m)
            amp = 0.11 / (1 + 0.25 * i)
            left[start : start + n] += amp * env * _pad_tone(f, n, +0.0009)
            right[start : start + n] += amp * env * _pad_tone(f, n, -0.0009)
        bass = note(chord[0] - 12)
        t = np.arange(n) / SR
        b = 0.16 * env * np.sin(2 * np.pi * bass * t) * (1 + 0.15 * np.sin(2 * np.pi * bass * 2 * t))
        left[start : start + n] += b
        right[start : start + n] += b
        pos += CHORD_S
        k += 1

    # Sparse arpeggio: eighth notes at 72 bpm, ~45% density, chord tones one octave up.
    beat = 60 / 72
    step = beat / 2
    i = 0
    while i * step < total_s:
        tpos = i * step
        chord = CHORDS[int(tpos // CHORD_S) % len(CHORDS)]
        if rng.random() < 0.45 and tpos > 2.0 and tpos < total_s - 5:
            m = chord[rng.integers(0, len(chord))] + 12
            start = int(tpos * SR)
            n = min(int(1.6 * SR), n_total - start)
            if n > 0:
                tone = 0.05 * _pluck(note(m), n)
                pan = rng.uniform(0.3, 0.7)
                left[start : start + n] += tone * (1 - pan) * 2
                right[start : start + n] += tone * pan * 2
        i += 1

    # Bells at scene starts (skip t=0).
    for s in scene_starts_s:
        if s <= 0.01 or s >= total_s - 1:
            continue
        start = int(s * SR)
        n = min(int(3.0 * SR), n_total - start)
        tone = 0.07 * _bell(note(77), n)  # F5
        left[start : start + n] += tone * 0.9
        right[start : start + n] += tone * 1.1

    # Master: fades, soft clip, normalise.
    t = np.arange(n_total) / SR
    fade = np.minimum(np.clip(t / 1.0, 0, 1), np.clip((total_s - t) / 4.0, 0, 1))
    left *= fade
    right *= fade
    mix = np.stack([left, right], axis=1)
    mix = np.tanh(mix * 1.4) / np.tanh(1.4)
    peak = np.max(np.abs(mix)) or 1.0
    mix = mix / peak * 0.5  # about -6 dBFS peak; background level
    pcm = (mix * 32767).astype("<i2")
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    make_music(12.0, [0, 4, 8], "/tmp/promo/music_test.wav")
    print("ok")
