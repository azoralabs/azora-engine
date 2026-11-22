#!/usr/bin/env python3
"""Build the engine's seamless terrain texture sets and Material Fusion graphs."""

import json
import math
from pathlib import Path
import random
import struct

SIZE = 512
ENGINE = Path(__file__).resolve().parents[1]
LIBRARY = ENGINE / "materials" / "standard"
DEMO = ENGINE / "templates" / "dolomites-drive" / "Textures"

# Slug, label, dark and light linear colors, surface profile, roughness, tile metres.
MATERIALS = (
    ("grass-meadow", "Meadow Grass", (21, 35, 7), (95, 123, 35), "grass", 0.89, 4.0),
    ("grass-dry", "Dry Grass", (47, 34, 12), (150, 122, 53), "grass", 0.91, 4.5),
    ("grass-mossy", "Mossy Grass", (14, 26, 9), (69, 99, 29), "moss", 0.86, 3.0),
    ("sand-beach", "Beach Sand", (106, 78, 44), (204, 167, 105), "sand", 0.83, 2.0),
    ("sand-dunes", "Dune Sand", (106, 51, 21), (211, 132, 66), "dunes", 0.88, 3.0),
    ("soil-forest", "Forest Soil", (19, 12, 6), (79, 52, 29), "moss", 0.94, 3.0),
    ("gravel", "Gravel", (29, 26, 24), (144, 132, 115), "gravel", 0.91, 2.0),
)

EXISTING = (
    ("grass", "Grass", "Alpine/grass", 5.6, 0.34),
    ("rock", "Rock", "Alpine/rock", 8.8, 0.51),
    ("snow", "Snow", "Alpine/snow", 6.5, 0.23),
    ("asphalt", "Asphalt", "Asphalt", 1.45, 0.44),
)


def periodic_noise(cells, rng):
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    samples = []
    for pixel in range(SIZE):
        coord = pixel * cells / SIZE
        cell = int(coord)
        fraction = coord - cell
        samples.append((cell, (cell + 1) % cells, fraction**2 * (3 - 2 * fraction)))
    values = []
    for y0, y1, ty in samples:
        top, bottom = grid[y0], grid[y1]
        for x0, x1, tx in samples:
            a = top[x0] + (top[x1] - top[x0]) * tx
            b = bottom[x0] + (bottom[x1] - bottom[x0]) * tx
            values.append(a + (b - a) * ty)
    return values


def channel(value):
    return min(255, max(0, round(value)))


def texture_set(seed, dark, light, profile, roughness):
    rng = random.Random(seed)
    broad = periodic_noise(8, rng)
    patches = periodic_noise(32, rng)
    detail = periodic_noise(112, rng)
    color = bytearray()
    height = []
    for i, (macro, patch, fine) in enumerate(zip(broad, patches, detail)):
        x, y = i % SIZE, i // SIZE
        grain = rng.random() - 0.5
        tone = 0.45 * macro + 0.35 * patch + 0.20 * fine
        relief = 0.25 * macro + 0.35 * patch + 0.4 * fine
        if profile == "grass":
            blades = math.sin(math.tau * (65 * x / SIZE + 17 * y / SIZE + 2 * fine))
            relief += 0.12 * blades * patch
            tone += 0.16 * blades * patch
        elif profile == "dunes":
            wave = math.sin(math.tau * (8 * y / SIZE + x / SIZE + 0.65 * macro))
            ripple = (0.5 + 0.5 * wave) ** 2.2
            relief = 0.18 + 0.60 * ripple + 0.10 * fine
            tone = 0.60 * tone + 0.40 * ripple
        elif profile == "sand":
            relief = 0.28 * macro + 0.12 * fine + 0.08 * grain + 0.25
            tone += 0.12 * grain
        elif profile == "gravel":
            stone = min(1.0, max(0.0, (fine - 0.32) * 2.7))
            relief = 0.18 * patch + 0.62 * stone
            tone = 0.28 * tone + 0.66 * stone + 0.06 * grain
        else:
            relief += 0.16 * patch * fine
            tone += 0.12 * grain
        height.append(relief)
        color.extend(channel(low + (high - low) * tone + 7 * grain) for low, high in zip(dark, light))
        color.append(255)

    normals = bytearray()
    surface = bytearray()
    for i, relief in enumerate(height):
        y, x = divmod(i, SIZE)
        dx = 2.5 * (height[y * SIZE + (x - 1) % SIZE] - height[y * SIZE + (x + 1) % SIZE])
        dy = 2.5 * (height[((y - 1) % SIZE) * SIZE + x] - height[((y + 1) % SIZE) * SIZE + x])
        scale = 127.5 / math.sqrt(1 + dx * dx + dy * dy)
        normals.extend((channel(127.5 + dx * scale), channel(127.5 + dy * scale), channel(127.5 + scale), 255))
        surface.extend((channel(255 * (roughness + 0.09 * (detail[i] - 0.5))),
                        channel(255 * (0.74 + 0.26 * relief)), channel(255 * relief), 0))
    return struct.pack("<4sII", b"AZTX", SIZE, SIZE) + color + normals + surface


def write_material(slug, label, texture, tile, strength, directional=False):
    texture_path = Path("Textures/Standard") / slug / "surface.aztexture"
    target = LIBRARY / texture_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(texture)
    graph = {
        "format": "azora-material-fusion",
        "version": 1,
        "nodes": [
            {"id": 1, "kind": "texture", "label": label, "x": 35, "y": 55,
             "texture": texture_path.as_posix(), "scale": tile, "value": strength,
             "offset": 0.0 if directional else 1.5, "contrast": 0.6,
             "macroScale": 45, "rotation": 0 if directional else 1},
            {"id": 2, "kind": "output", "x": 280, "y": 55, "a": 1},
        ],
    }
    path = LIBRARY / "Materials" / "Standard" / f"{slug}.azmaterial"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(graph, indent=2) + "\n", encoding="utf-8")


def main():
    for slug, label, source, tile, strength in EXISTING:
        write_material(slug, label, (DEMO / source / "surface.aztexture").read_bytes(), tile, strength)
    for seed, (slug, label, dark, light, profile, roughness, tile) in enumerate(MATERIALS, start=1):
        write_material(slug, label, texture_set(seed, dark, light, profile, roughness),
                       tile, 0.38, directional=profile == "dunes")


if __name__ == "__main__":
    main()
