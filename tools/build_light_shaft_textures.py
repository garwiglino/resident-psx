"""Small RGB555 intensity masks for PSX additive geometry; no alpha gradient."""
import math
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'assets/effects/light_shafts'

def smooth(a, b, x):
    t = max(0., min(1., (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

def make(name, narrow):
    width, height = 64, 128
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        v = y / (height - 1)
        longitudinal = smooth(0, .055, v) * (1 - smooth(.18, 1., v))
        for x in range(width):
            u = x / (width - 1)
            transverse = math.sin(math.pi * u) ** (3.2 if narrow else 1.35)
            # A slight fixed variation across the sheet avoids a perfectly flat slab.
            variation = .9 + .1 * math.cos(u * math.pi * 6)
            value = int(max(0., min(1., transverse * longitudinal * variation)) * 31) << 3
            rows.extend((value, value, value, 255 if value else 0))
    payload = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    payload += chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + chunk(b'IEND', b'')
    (ROOT / name).write_bytes(payload)

if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    make('window_beam.png', False)
    make('narrow_ray.png', True)
    print('LIGHT_SHAFT_TEXTURES_OK 64x128 RGB555')
