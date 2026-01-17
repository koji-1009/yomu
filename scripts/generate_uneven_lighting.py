#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode[pil]",
#     "numpy",
#     "pillow",
# ]
# ///
"""
Generate QR codes with uneven lighting conditions to test robust detection.

Combines standard QR generation with various lighting effects like gradients,
shadows, and spotlights using numpy transformations.

Usage:
    uv run scripts/generate_uneven_lighting.py
"""

import os

import numpy as np
import qrcode
from PIL import Image


OUTPUT_DIR = "fixtures/uneven_lighting"


def create_qr(data: str, size: int = 400) -> np.ndarray:
    """Create a QR code image as numpy array."""
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.array(img.convert("L"))


def apply_horizontal_gradient(img: np.ndarray, strength: float = 0.5) -> np.ndarray:
    """Apply horizontal lighting gradient (left dark, right bright)."""
    h, w = img.shape
    gradient = np.linspace(1 - strength, 1, w).reshape(1, w)
    return np.clip(img * gradient, 0, 255).astype(np.uint8)


def apply_vertical_gradient(img: np.ndarray, strength: float = 0.5) -> np.ndarray:
    """Apply vertical lighting gradient (top dark, bottom bright)."""
    h, w = img.shape
    gradient = np.linspace(1 - strength, 1, h).reshape(h, 1)
    return np.clip(img * gradient, 0, 255).astype(np.uint8)


def apply_corner_shadow(img: np.ndarray, strength: float = 0.6) -> np.ndarray:
    """Apply vignette-like shadow from corner."""
    h, w = img.shape
    y, x = np.ogrid[:h, :w]
    # Distance from top-left corner
    dist = np.sqrt(x**2 + y**2)
    max_dist = np.sqrt(h**2 + w**2)
    # Create gradient: 1-strength at corner, 1 at far corner
    gradient = (1 - strength) + strength * (dist / max_dist)
    return np.clip(img * gradient, 0, 255).astype(np.uint8)


def apply_spotlight(
    img: np.ndarray, cx: float = 0.3, cy: float = 0.3, radius: float = 0.4
) -> np.ndarray:
    """Apply spotlight effect."""
    h, w = img.shape
    y, x = np.ogrid[:h, :w]
    center_x, center_y = w * cx, h * cy
    dist = np.sqrt((x - center_x) ** 2 + (y - center_y) ** 2)
    max_radius = min(h, w) * radius
    # Bright in center, dark outside
    gradient = np.clip(1 - (dist / max_radius) * 0.6, 0.4, 1)
    return np.clip(img * gradient, 0, 255).astype(np.uint8)


def main():
    """Main execution entry point."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    data = "UNEVEN_LIGHTING_TEST_12345"

    # Create base QR
    base_qr = create_qr(data, size=400)

    # Apply different lighting conditions
    conditions = [
        ("horizontal_gradient_mild", lambda img: apply_horizontal_gradient(img, 0.3)),
        ("horizontal_gradient_strong", lambda img: apply_horizontal_gradient(img, 0.6)),
        ("vertical_gradient_mild", lambda img: apply_vertical_gradient(img, 0.3)),
        ("vertical_gradient_strong", lambda img: apply_vertical_gradient(img, 0.6)),
        ("corner_shadow_mild", lambda img: apply_corner_shadow(img, 0.4)),
        ("corner_shadow_strong", lambda img: apply_corner_shadow(img, 0.7)),
        ("spotlight_center", lambda img: apply_spotlight(img, 0.5, 0.5, 0.5)),
        ("spotlight_corner", lambda img: apply_spotlight(img, 0.2, 0.2, 0.3)),
    ]

    for name, transform in conditions:
        result = transform(base_qr)
        path = os.path.join(OUTPUT_DIR, f"{name}.png")
        Image.fromarray(result).save(path)
        print(f"Created: {path}")

    # Also save a clean reference
    Image.fromarray(base_qr).save(os.path.join(OUTPUT_DIR, "reference_clean.png"))
    print(f"Created: {OUTPUT_DIR}/reference_clean.png")

    print(f"\nGenerated {len(conditions) + 1} test images in {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
