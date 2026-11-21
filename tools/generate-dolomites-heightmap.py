#!/usr/bin/env python3
"""Build the original 16-bit heightmap for the Dolomites Drive template."""

from array import array
from math import exp, sin, cos
from pathlib import Path
import sys

WIDTH = 11674.9258
LENGTH = 10768.3579
ELEVATION = 1320.0
SAMPLES = 1025


def height(x: float, z: float) -> float:
    valley_axis = 300.0 + 180.0 * sin(x / 2100.0)
    valley = z - valley_axis
    plain = exp(-((x + 1000.0) / 2200.0) ** 2 - (valley / 800.0) ** 2)
    foothills = 1.0 - exp(-(valley / 1550.0) ** 2)
    bed = 50.0 + 32.0 * (x / 6000.0) ** 2 + 9.0 * sin(x / 1300.0)
    bed += (1.0 - 0.88 * plain) * (12.0 + 7.0 * cos(x / 415.0 + z / 650.0))
    north = exp(-((z + 3460.0 + 310.0 * sin(x / 950.0)) / 1210.0) ** 2)
    south = exp(-((z - 3860.0 - 520.0 * cos(x / 1700.0)) / 1370.0) ** 2)
    broken_ridge = (0.53 + 0.47 * abs(sin(x / 690.0 + z / 1240.0))) ** 1.8
    peak = 570.0 * north * broken_ridge + 520.0 * south * (0.52 + 0.48 * sin(x / 990.0) ** 2)
    peak += 480.0 * exp(-((x - 3770.0) / 1190.0) ** 2 - ((z + 3740.0) / 800.0) ** 2)
    peak += 410.0 * exp(-((x + 3130.0) / 1050.0) ** 2 - ((z - 3470.0) / 940.0) ** 2)
    peak += 280.0 * exp(-((x + 4140.0) / 920.0) ** 2 - ((z + 2780.0) / 1150.0) ** 2)
    ravines = 1.0 - 0.32 * exp(-((z + 0.47 * x + 1750.0) / 285.0) ** 2)
    detail = sin(x / 210.0 + z / 325.0) * cos(z / 274.0 - x / 450.0) * 19.0
    detail += sin(x / 73.0 - z / 120.0) * sin(z / 97.0) * 4.5
    detail += cos(x / 29.0 + z / 57.0) * sin(z / 43.0 - x / 53.0) * 1.8
    tributary = x + 560.0 - 64.0 * sin((z - 470.0) / 510.0)
    riverbed = 34.0 * exp(-(tributary / 49.0) ** 2 - ((z - 460.0) / 1500.0) ** 4)
    gorge_axis = z + 1360.0 + 0.12 * (x - 700.0)
    gorge = 54.0 * exp(-(gorge_axis / 73.0) ** 2 - ((x - 700.0) / 570.0) ** 4)
    return bed + foothills * (peak * ravines + 27.0 * (1.0 + cos(x / 530.0 - z / 810.0)) + detail) - riverbed - gorge


def main() -> None:
    target = Path(__file__).resolve().parents[1] / "templates/dolomites-drive/Terrain/alpine-valley.pgm"
    pixels = array("H")
    for row in range(SAMPLES):
        z = LENGTH * (row / (SAMPLES - 1) - 0.5)
        for column in range(SAMPLES):
            x = WIDTH * (column / (SAMPLES - 1) - 0.5)
            pixels.append(round(65535.0 * min(1.0, max(0.0, height(x, z) / ELEVATION))))
    if sys.byteorder == "little":
        pixels.byteswap()
    with target.open("wb") as stream:
        stream.write(f"P5\n# Azora Dolomites Drive, metres sampled in world X and Z\n{SAMPLES} {SAMPLES}\n65535\n".encode())
        pixels.tofile(stream)


if __name__ == "__main__":
    main()
