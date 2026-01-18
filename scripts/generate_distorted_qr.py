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
Generate distorted QR codes (rotation, perspective transform).

Creates images with:
1. Rotation (Z-axis): 5, 10 degrees...
2. Perspective (Tilt): Simulates looking from an angle.

Standard Output: 600x600 PNG with 400x400 QR centered.
"""

import os
import math
import numpy as np
import qrcode
from PIL import Image

OUTPUT_DIR = "fixtures/distorted_images"
CANVAS_SIZE = 600
QR_SIZE = 400


def create_base_qr(data: str) -> Image.Image:
    """Create a standard QR code (400x400)."""
    qr = qrcode.QRCode(
        version=4,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    return img.resize((QR_SIZE, QR_SIZE), Image.Resampling.NEAREST)


def place_on_canvas(img: Image.Image) -> Image.Image:
    """Center image on 600x600 white canvas."""
    canvas = Image.new("RGB", (CANVAS_SIZE, CANVAS_SIZE), "white")
    offset = ((CANVAS_SIZE - img.width) // 2, (CANVAS_SIZE - img.height) // 2)
    canvas.paste(img, offset)
    return canvas


def apply_rotation(img: Image.Image, angle: float) -> Image.Image:
    """Rotate image by angle (degrees) on fixed canvas."""
    # Place on 600x600 canvas first
    canvas = place_on_canvas(img)
    # Rotate around center, keeping size fixed (expand=False)
    # 400x400 rotated 45deg fits inside 600x600 (approx 566px diagonal)
    return canvas.rotate(
        angle, resample=Image.Resampling.NEAREST, expand=False, fillcolor="white"
    )


def find_coeffs(source_coords, target_coords):
    """Calculate coefficients for perspective transform."""
    matrix = []
    for i, (s, t) in enumerate(zip(source_coords, target_coords)):
        matrix.append([t[0], t[1], 1, 0, 0, 0, -s[0] * t[0], -s[0] * t[1]])
        matrix.append([0, 0, 0, t[0], t[1], 1, -s[1] * t[0], -s[1] * t[1]])
    A = np.matrix(matrix, dtype=float)
    B = np.array(source_coords).reshape(8)
    res = np.linalg.solve(A, B)
    return np.array(res).reshape(8)


def apply_perspective_tilt(
    img: Image.Image, x_angle: float, y_angle: float
) -> Image.Image:
    """
    Apply perspective projection to simulate tilting.
    x_angle: Tilt around X-axis (degrees)
    y_angle: Tilt around Y-axis (degrees)
    """
    # 1. Place on canvas
    canvas = place_on_canvas(img)
    w, h = canvas.size  # 600, 600

    # 2. Define Source points (Corners of 600x600 canvas)
    s_points = [(0, 0), (w, 0), (w, h), (0, h)]

    # 3. Define Target points (Simulate keystone effect)
    # Amount to squeeze edge by
    shift_x = int(w * math.tan(math.radians(y_angle)) * 0.3)
    shift_y = int(h * math.tan(math.radians(x_angle)) * 0.3)

    # Start with original corners
    # TL, TR, BR, BL
    p = [[0.0, 0.0], [float(w), 0.0], [float(w), float(h)], [0.0, float(h)]]

    # Tilt Y (Rotation around vertical axis)
    if y_angle > 0:  # Right side moves away -> Right side shrinks
        p[1][1] += shift_x  # TR y goes down
        p[1][0] -= shift_x  # TR x goes left
        p[2][1] -= shift_x  # BR y goes up
        p[2][0] -= shift_x  # BR x goes left
    elif y_angle < 0:  # Left side moves away -> Left side shrinks
        p[0][1] += abs(shift_x)
        p[0][0] += abs(shift_x)
        p[3][1] -= abs(shift_x)
        p[3][0] += abs(shift_x)

    # Tilt X (Rotation around horizontal axis)
    if x_angle > 0:  # Bottom moves away -> Bottom shrinks
        p[3][0] += shift_y
        p[3][1] -= shift_y
        p[2][0] -= shift_y
        p[2][1] -= shift_y
    elif x_angle < 0:  # Top moves away -> Top shrinks
        p[0][0] += abs(shift_y)
        p[0][1] += abs(shift_y)
        p[1][0] -= abs(shift_y)
        p[1][1] += abs(shift_y)

    t_points = [(pt[0], pt[1]) for pt in p]

    coeffs = find_coeffs(s_points, t_points)

    # Create new image
    # Note: size should ideally adapt, but keeping simple for now
    return canvas.transform(
        (w, h), Image.PERSPECTIVE, coeffs, Image.Resampling.NEAREST, fillcolor="white"
    )


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Generating distorted QR codes to: {OUTPUT_DIR}")
    print(f"Canvas Size: {CANVAS_SIZE}x{CANVAS_SIZE}, QR Size: {QR_SIZE}x{QR_SIZE}")

    base_data = "DISTORTION_TEST_DATA_1234567890"
    base_img = create_base_qr(base_data)

    # 1. Rotations (Guaranteed Range)
    rotations = [5, 10, 15, -5, -10, -15]
    for angle in rotations:
        res = apply_rotation(base_img, angle)
        name = f"rotation_{angle}deg.png"
        res.save(f"{OUTPUT_DIR}/{name}")
        print(f"  ✓ {name}")

    # 2. Perspective Tilts (X, Y) - Matrix 0, 3, 6
    tilts = []
    for x in [0, 3, 6]:
        for y in [0, 3, 6]:
            if x == 0 and y == 0:
                continue  # Skip base (no tilt)
            tilts.append((x, y))

    for ax, ay in tilts:
        res = apply_perspective_tilt(base_img, ax, ay)
        name = f"tilt_x{ax}_y{ay}.png"
        res.save(f"{OUTPUT_DIR}/{name}")
        print(f"  ✓ {name}")

    print(f"Generated {len(rotations) + len(tilts)} images.")


if __name__ == "__main__":
    main()
