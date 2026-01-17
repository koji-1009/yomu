#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode",
#     "pillow",
# ]
# ///
"""
Generate real-world test images with embedded QR codes.

Creates large images (HD, 4K) with QR codes at various positions.

Usage:
    uv run scripts/generate_realworld_qr.py
"""

from pathlib import Path

import qrcode
from PIL import Image  # type: ignore


# Image configurations
CONFIGS = [
    # (width, height, name, qr_sizes, backgrounds)
    (1920, 1080, "fullhd", [200, 300], ["white", "gradient", "noise"]),
    (1600, 1600, "square", [250, 400], ["white", "gray"]),
    (3840, 2160, "4k", [300, 500], ["white"]),
]

# QR positions relative to image
POSITIONS = {
    "center": lambda w, h, qw, qh: ((w - qw) // 2, (h - qh) // 2),
    "top_left": lambda w, h, qw, qh: (50, 50),
    "top_right": lambda w, h, qw, qh: (w - qw - 50, 50),
    "bottom_left": lambda w, h, qw, qh: (50, h - qh - 50),
    "bottom_right": lambda w, h, qw, qh: (w - qw - 50, h - qh - 50),
}


def create_background(width: int, height: int, style: str) -> Image.Image:
    """Create a background image."""
    if style == "white":
        return Image.new("RGB", (width, height), "white")
    elif style == "gray":
        return Image.new("RGB", (width, height), (200, 200, 200))
    elif style == "gradient":
        img = Image.new("RGB", (width, height))
        for y in range(height):
            gray = int(255 * (1 - y / height * 0.3))  # Light gradient
            for x in range(width):
                img.putpixel((x, y), (gray, gray, gray))
        return img
    elif style == "noise":
        import random

        img = Image.new("RGB", (width, height))
        for y in range(height):
            for x in range(width):
                # Light noise
                v = random.randint(240, 255)
                img.putpixel((x, y), (v, v, v))
        return img
    return Image.new("RGB", (width, height), "white")


def generate_qr(data: str, size: int) -> Image.Image:
    """Generate a QR code image."""
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=2,
    )
    qr.add_data(data)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    return img.resize((size, size), Image.NEAREST)


def main():
    """Main execution entry point."""
    output_dir = Path("fixtures/realworld_images")
    output_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("🖼️ REAL-WORLD QR IMAGE GENERATOR")
    print("=" * 60)

    count = 0

    for width, height, name, qr_sizes, backgrounds in CONFIGS:
        for bg_style in backgrounds:
            for qr_size in qr_sizes:
                for pos_name, pos_fn in POSITIONS.items():
                    # Create background
                    bg = create_background(width, height, bg_style)

                    # Create QR code
                    qr_data = f"RealWorld_{name}_{pos_name}_{qr_size}"
                    qr_img = generate_qr(qr_data, qr_size)

                    # Calculate position
                    x, y = pos_fn(width, height, qr_size, qr_size)

                    # Paste QR onto background
                    bg.paste(qr_img, (x, y))

                    # Save
                    filename = f"{name}_{bg_style}_{pos_name}_{qr_size}px.png"
                    filepath = output_dir / filename
                    bg.save(filepath)

                    print(f"✓ {filename} ({width}x{height})")
                    count += 1

    print("-" * 60)
    print(f"Generated {count} real-world test images in {output_dir}/")

    # Generate a representative subset for quick benchmarking
    print("\n📌 Representative images for benchmark:")
    subset = [
        "fullhd_white_center_300px.png",
        "square_white_center_400px.png",
        "4k_white_center_500px.png",
    ]
    for name in subset:
        path = output_dir / name
        if path.exists():
            size = path.stat().st_size / 1024
            print(f"   • {name} ({size:.1f} KB)")


if __name__ == "__main__":
    main()
