#!/usr/bin/env python3
"""Generate the launcher icons used by the Android renderer example.

The mark is drawn from a formula rather than copied from anywhere: a bright X on
a deep blue field inside an amber frame, which is the same motif the example
library generates for the texture it puts on screen. Regenerating the icons is
therefore always possible, and the example carries no third-party artwork.

usage:
  python tests/format/make_demo_icon.py
  python tests/format/make_demo_icon.py --out <directory>
"""

from __future__ import annotations

import argparse
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "tests" / "format" / "android_gl_demo" / "res"

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def pixel(x: int, y: int, size: int) -> tuple[int, int, int, int]:
    """One RGBA texel: an amber frame, a diagonal cross, a shaded blue field."""
    edge = max(size // 16, 1)
    if x < edge or y < edge or x >= size - edge or y >= size - edge:
        return (255, 150, 40, 255)
    thickness = max(size // 10, 2)
    if abs(x - y) <= thickness or abs(x + y - (size - 1)) <= thickness:
        return (90, 220, 255, 255)
    middle = size / 2.0
    distance = ((x - middle) ** 2 + (y - middle) ** 2) ** 0.5 / middle
    dim = max(0.0, 1.0 - distance)
    return (int(12 + 20 * dim), int(20 + 30 * dim), int(70 + 60 * dim), 255)


def chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def png(size: int) -> bytes:
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type: none
        for x in range(size):
            raw += bytes(pixel(x, y, size))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    for density, size in DENSITIES.items():
        target = args.out / f"mipmap-{density}" / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        data = png(size)
        target.write_bytes(data)
        print(f"{target.relative_to(ROOT)}: {size}x{size}, {len(data)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
