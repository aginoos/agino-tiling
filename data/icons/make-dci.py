#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds the DCI icons in this directory from src/*.svg (needs rsvg-convert and python3-pil).

DCI (DTK's icon container): b"DCI\\0", version 1, a 3-byte entry count, then entries of
type (1 file, 2 directory, 3 link), a 63-byte name, an 8-byte size and the content.
Layout as in deepin's own icons (deepin-multitasking-view.dci, dcc-multitasking-view.dci):
<size>/normal.light/<scale>/<layer>.webp, with normal.dark linking to the light layer.
  - dock button: 256, scale 3, layer "1" (full colour)
  - Control Center (dock settings): 16, scale 3, layer "1.0" (palette 0: tinted with the
    foreground colour, so one black mask serves light and dark themes)
Run it after changing an SVG and commit the .dci files with the sources.
"""
import io
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ICONS = {
    "agino-tiling-on": (256, "1"),
    "agino-tiling-off": (256, "1"),
    "dcc-agino-tiling": (16, "1.0"),
}
SCALE = 3


def entry(kind, name, content):
    raw = name.encode()
    if len(raw) > 62:
        sys.exit(f"DCI entry name too long: {name}")
    return struct.pack("<B63sQ", kind, raw, len(content)) + content


def webp(svg, pixels):
    png = subprocess.run(["rsvg-convert", "-w", str(pixels), "-h", str(pixels), str(svg)],
                         check=True, capture_output=True).stdout
    out = io.BytesIO()
    Image.open(io.BytesIO(png)).save(out, "WEBP", lossless=True, quality=100, method=6)
    return out.getvalue()


def dci(svg, size, layer):
    image = f"{layer}.webp"
    light = entry(2, str(SCALE), entry(1, image, webp(svg, size * SCALE)))
    dark = entry(2, str(SCALE), entry(3, image, f"../../normal.light/{SCALE}/{image}".encode()))
    tree = entry(2, "normal.dark", dark) + entry(2, "normal.light", light)
    return b"DCI\0" + bytes([1]) + (1).to_bytes(3, "little") + entry(2, str(size), tree)


def main():
    for name, (size, layer) in ICONS.items():
        (HERE / f"{name}.dci").write_bytes(dci(HERE / "src" / f"{name}.svg", size, layer))


if __name__ == "__main__":
    main()
