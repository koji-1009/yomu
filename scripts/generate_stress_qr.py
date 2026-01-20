#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode[pil]",
#     "pillow",
#     "numpy",
# ]
# ///
"""
QR Code Stress Test Generator

Generates highly distorted QR codes to test robustness limits:
1. Blur (Gaussian)
2. Curvature (Cylindrical projection)
3. Damage (Occlusion, Spots)
4. Noise (Salt & Pepper)

Target Directory: fixtures/distorted_images
Content: "Hello World"
"""

import math
from pathlib import Path
from typing import Tuple

import numpy as np
import qrcode
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_ROOT / "fixtures" / "distorted_images"


def ensure_dir():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def generate_base_qr(content: str = "Hello World") -> Image.Image:
    """Generates a clean base QR code."""
    qr = qrcode.QRCode(
        version=4,
        error_correction=qrcode.constants.ERROR_CORRECT_H,  # High EC for robustness tests
        box_size=10,
        border=4,
    )
    qr.add_data(content)
    qr.make(fit=True)
    return qr.make_image(fill_color="black", back_color="white").convert("RGBA")


def apply_blur(img: Image.Image, radius: float) -> Tuple[Image.Image, str]:
    """Applies Gaussian Blur."""
    blurred = img.filter(ImageFilter.GaussianBlur(radius))
    return blurred, f"blur_radius_{radius:.1f}.png"


def apply_curvature(
    img: Image.Image, strength: float = 10.0
) -> Tuple[Image.Image, str]:
    """Simulates cylindrical curvature (Wavy)."""
    w, h = img.size
    out = Image.new("RGBA", (w, h), (255, 255, 255, 255))

    for x in range(w):
        # Sine wave offset for y
        offset_y = int(strength * math.sin(x / 30.0))
        # Paste column
        col = img.crop((x, 0, x + 1, h))
        out.paste(col, (x, offset_y))

    return out, f"curved_wavy_{strength}.png"


def apply_damage(img: Image.Image, coverage: float) -> Tuple[Image.Image, str]:
    """
    Applies random spots/dirt (occlusion).
    Excludes Finder Patterns (corners) to test error correction, not detection failure.
    coverage: 0.0 to 1.0
    """
    w, h = img.size
    damaged = img.copy()
    draw = ImageDraw.Draw(damaged)

    # QR dimensions (Version 4 + 4 module border)
    # Box size = 10 (hardcoded in generate_base_qr)
    box = 10
    # Finders are 7x7 modules. Border is 4 modules.
    # Exclude roughly 9x9 area at corners to be safe (includes separators)
    safe_margin = (4 + 8) * box

    def is_critical(x, y):
        # Top-Left
        if x < safe_margin and y < safe_margin:
            return True
        # Top-Right
        if x > (w - safe_margin) and y < safe_margin:
            return True
        # Bottom-Left
        if x < safe_margin and y > (h - safe_margin):
            return True
        return False

    # Draw random 'dirt' blobs
    num_spots = int(coverage * 100)
    for _ in range(num_spots):
        # Retry loop to find safe spot
        for _retry in range(10):
            x = np.random.randint(0, w)
            y = np.random.randint(0, h)
            if not is_critical(x, y):
                break

        r = np.random.randint(5, 20)
        # Random gray/black color for dirt
        color = np.random.randint(0, 100)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(color, color, color))

    return damaged, f"damaged_dirt_{coverage:.2f}.png"


def apply_noise(img: Image.Image, intensity: float) -> Tuple[Image.Image, str]:
    """Applies Salt and Pepper noise."""
    w, h = img.size
    pixels = np.array(img)

    # Generate random noise mask
    noise = np.random.rand(h, w)

    # Salt (White)
    pixels[noise < (intensity / 2)] = [255, 255, 255, 255]
    # Pepper (Black)
    pixels[noise > (1 - (intensity / 2))] = [0, 0, 0, 255]

    return Image.fromarray(pixels), f"damaged_noise_{intensity:.2f}.png"


def main():
    np.random.seed(42)  # Ensure reproducible results
    ensure_dir()
    base = generate_base_qr()
    print(f"Base Image Size: {base.size}")

    # 1. Blur Series (Find max limit)
    for r in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0]:
        img, name = apply_blur(base, r)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # 2. Curvature (Mild to Moderate)
    # 6.0 is known failure, so generate up to 6.0 to confirm boundary
    for s in [1, 2, 3, 4, 5, 6]:
        img, name = apply_curvature(base, float(s))
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # 3. Damage/Dirt (Robustness)
    # Extend to find limit (0.20 passed)
    for c in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4]:
        img, name = apply_damage(base, c)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # 4. Noise (Robustness)
    # 0.05 failed, so try very mild noise to see if ANY is supported
    for i in [0.01, 0.02, 0.03, 0.04, 0.05, 0.08, 0.1]:
        img, name = apply_noise(base, i)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # 5. Rotation (Standardized)
    # Replacing legacy rotation files
    for ang in [-20, -15, -10, -5, 5, 10, 15, 20]:
        img = base.rotate(
            ang, resample=Image.BICUBIC, expand=True, fillcolor=(255, 255, 255)
        )
        name = f"rotation_{ang}deg.png"
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # 6. Perspective (Tilt)
    # Replacing legacy tilt files. Simulating X/Y axis tilt.
    for p in [0.1, 0.2, 0.3, 0.4]:
        # Tilt X
        img, name = apply_perspective(base, p, axis="x")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")
        # Tilt Y
        img, name = apply_perspective(base, p, axis="y")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")


def _find_coeffs(pa, pb):
    matrix = []
    for p1, p2 in zip(pa, pb):
        matrix.append([p1[0], p1[1], 1, 0, 0, 0, -p2[0] * p1[0], -p2[0] * p1[1]])
        matrix.append([0, 0, 0, p1[0], p1[1], 1, -p2[1] * p1[0], -p2[1] * p1[1]])
    A = np.matrix(matrix, dtype=float)
    B = np.array(pb).reshape(8)
    res = np.linalg.solve(A, B)
    return np.array(res).reshape(8)


def apply_perspective(img, strength, axis="x"):
    w, h = img.size
    # Shrink one side to create trapezoid
    delta = int(w * strength * 0.5)

    if axis == "x":
        # Tilt along X axis (top/bottom width changes)
        # Squeeze top
        pts = [(delta, 0), (w - delta, 0), (w, h), (0, h)]
    else:
        # Tilt along Y axis (left/right height changes)
        # Squeeze left
        pts = [(0, delta), (w, delta), (w, h), (0, h - delta)]

    coeffs = _find_coeffs([(0, 0), (w, 0), (w, h), (0, h)], pts)

    transformed = img.transform(
        (w, h), Image.PERSPECTIVE, coeffs, Image.BICUBIC, fillcolor=(255, 255, 255)
    )
    return transformed, f"perspective_{axis}_{strength}.png"

    print(f"Done. Check {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
