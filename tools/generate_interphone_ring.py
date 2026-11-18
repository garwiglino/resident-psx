"""Original interphone ringback sample; played by the existing native SPU mixer."""
import math
import pathlib
import struct
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
RATE = 22050
PERIOD = 2.4
ON = .8
frames = []
for index in range(round(RATE * PERIOD)):
    t = index / RATE
    value = 0.0
    if t < ON:
        envelope = min(t / .012, 1.0) * min((ON - t) / .03, 1.0)
        modulation = .84 + .16 * math.cos(math.tau * 18 * t)
        value = (math.sin(math.tau * 420 * t) + .12 * math.sin(math.tau * 840 * t)) * envelope * modulation * .36
    frames.append(round(value * 32767))
path = ROOT / 'assets/audio/interactables/interphone_ring_loop.wav'
with wave.open(str(path), 'wb') as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes(struct.pack(f'<{len(frames)}h', *frames))
print(f'INTERPHONE_RING: mono {RATE} Hz, {PERIOD:.1f} s, silent loop boundary')
