"""
Throwaway spatial-sanity-check plotter for T3.1's replay corpus.

CLAUDE.md's data-handling contract: "For any new source, plot it over Chennai and look at it
before declaring it ingested." No plotting library (matplotlib/PIL) is installed in this
venv and scripts/requirements.txt intentionally stays minimal (ijson, requests, yaml already
declared), so this writes a real PNG using only the standard library (zlib for the DEFLATE
stream PNG requires) -- not a new dependency, just stdlib. This is a manual QA aid, not a
pipeline artifact; it is not wired into t31_build_replay_corpus.py.

Usage: .venv/Scripts/python.exe scripts/t31_plot_check.py
"""

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OBS_PATH = ROOT / "data" / "corpus" / "2026-09-17" / "observations.ndjson"
OUT_PATH = ROOT / "data" / "results" / "2026-09-17-t31-corpus" / "spatial_check.png"

W, H = 900, 900
# Chennai metro bbox, same as the build script.
MIN_LAT, MAX_LAT = 12.75, 13.25
MIN_LON, MAX_LON = 79.95, 80.35

COLORS = {
    "waterlogging": (230, 160, 20),  # amber
    "flood": (30, 90, 220),  # blue
}
SOURCE_MARK = {
    "official_feed": 2,  # slightly larger squares
    "crowd": 1,
}


def write_png(path: Path, width: int, height: int, pixels: bytearray) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)  # filter type 0 (none) per scanline
        raw.extend(pixels[y * stride : (y + 1) * stride])
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main() -> None:
    pixels = bytearray([245, 245, 240] * (W * H))  # light background

    def set_px(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 3
            pixels[i : i + 3] = bytes(color)

    n = 0
    counts = {}
    with open(OBS_PATH, encoding="utf-8") as f:
        for line in f:
            obs = json.loads(line)
            lon, lat = obs["geometry"]["coordinates"]
            hc = obs["hazard_class"]
            sc = obs["source_class"]
            counts[hc] = counts.get(hc, 0) + 1
            x = int((lon - MIN_LON) / (MAX_LON - MIN_LON) * (W - 1))
            y = int((MAX_LAT - lat) / (MAX_LAT - MIN_LAT) * (H - 1))  # north-up
            color = COLORS.get(hc, (120, 120, 120))
            r = SOURCE_MARK.get(sc, 1)
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    set_px(x + dx, y + dy, color)
            n += 1

    # Draw a light bbox border for scale reference.
    for x in range(W):
        set_px(x, 0, (0, 0, 0))
        set_px(x, H - 1, (0, 0, 0))
    for y in range(H):
        set_px(0, y, (0, 0, 0))
        set_px(W - 1, y, (0, 0, 0))

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    write_png(OUT_PATH, W, H, pixels)
    print(f"Plotted {n} observations {counts} -> {OUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
