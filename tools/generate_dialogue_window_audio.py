"""Original short menu tones, baked as samples for the native PS1 SPU path."""
import math
import pathlib
import struct
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
RATE = 22050


def tone(frequency, duration):
    frames = []
    for index in range(round(RATE * duration)):
        t = index / RATE
        # Soft attack/release; no runtime oscillator or added retro filter.
        attack = min(t / .003, 1)
        release = min((duration - t) / .012, 1)
        envelope = max(attack * release, 0) * math.exp(-t * 12)
        phase = math.tau * frequency * t
        triangle = math.sin(phase) - math.sin(phase * 3) / 9 + math.sin(phase * 5) / 25
        frames.append(round(triangle * envelope * .55 * 32767))
    return frames


for name, frequencies in [('open', (784, 1046.5)), ('close', (784, 523.25))]:
    frames = [0] * 16
    frames += tone(frequencies[0], .028)
    frames += [0] * round(RATE * .003)
    frames += tone(frequencies[1], .038)
    frames += [0] * 32
    path = ROOT / 'assets/audio/ui' / f'dialogue_{name}.wav'
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(struct.pack(f'<{len(frames)}h', *frames))
    print(f'DIALOGUE_WINDOW_SAMPLE: {path.name}, mono {RATE} Hz, {len(frames) / RATE:.3f} s')
