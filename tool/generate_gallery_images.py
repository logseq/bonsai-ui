"""Generate deterministic raster fixtures used by Gallery and native image tests."""
import argparse
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "examples/gallery/resources"


def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def png():
    width, height = 96, 48
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            color = (35, 105, 170, 255) if x < 64 else (240, 135, 35, 255)
            if 8 <= x < 24 and 8 <= y < 24:
                color = (255, 255, 255, 255)
            row.extend(color)
        rows.append(row)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def gif():
    width, height = 24, 16
    data = bytearray(b"GIF89a" + struct.pack("<HHBBB", width, height, 0x80, 0, 0))
    data += bytes([35, 105, 170, 240, 135, 35])
    data += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"
    for color, delay in [(0, 10), (1, 20)]:
        data += b"\x21\xf9\x04\x04" + struct.pack("<H", delay) + b"\x00\x00"
        data += b"\x2c" + struct.pack("<HHHHB", 0, 0, width, height, 0) + b"\x02"
        codes = [item for _ in range(width * height) for item in (4, color)] + [5]
        packed = bytearray((len(codes) * 3 + 7) // 8)
        for index, code in enumerate(codes):
            for bit in range(3):
                packed[(index * 3 + bit) // 8] |= ((code >> bit) & 1) << ((index * 3 + bit) % 8)
        for offset in range(0, len(packed), 255):
            block = packed[offset:offset + 255]
            data += bytes([len(block)]) + block
        data += b"\x00"
    return bytes(data + b"\x3b")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, data in [("gallery-demo.png", png()), ("gallery-animation.gif", gif())]:
        path = ROOT / name
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f"Stale image fixture: {path}")
        else:
            ROOT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)


if __name__ == "__main__":
    main()
