#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode",
#     "pillow",
# ]
# ///
"""
Generate test images with multiple QR codes for testing multi-QR detection.

Usage:
    uv run scripts/generate_multi_qr.py
"""

import qrcode
from PIL import Image


def generate_multi_qr_image(
    qr_data: list[str], filename: str, layout: str = "horizontal"
):
    """
    Generate an image containing multiple QR codes.

    Args:
        qr_data: List of strings to encode in each QR code
        filename: Output filename
        layout: "horizontal", "vertical", or "grid"
    """
    qr_codes = []

    # Generate QR codes (force RGB mode for easier manipulation)
    for data in qr_data:
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        # Convert to RGB for consistent paste operations
        img_rgb = img.convert("RGB")
        qr_codes.append(img_rgb)

    if not qr_codes:
        print("No QR data provided")
        return

    # Calculate canvas size
    qr_size = qr_codes[0].size[0]  # Assuming all QR codes are same size

    if layout == "horizontal":
        canvas_width = qr_size * len(qr_codes)
        canvas_height = qr_size
    elif layout == "vertical":
        canvas_width = qr_size
        canvas_height = qr_size * len(qr_codes)
    elif layout == "grid":
        # 2x2 grid
        canvas_width = qr_size * 2
        canvas_height = qr_size * 2
    else:
        raise ValueError(f"Unknown layout: {layout}")

    # Create canvas (RGB mode)
    canvas = Image.new("RGB", (canvas_width, canvas_height), (255, 255, 255))

    # Paste QR codes
    if layout == "horizontal":
        for i, qr_img in enumerate(qr_codes):
            canvas.paste(qr_img, (i * qr_size, 0))
    elif layout == "vertical":
        for i, qr_img in enumerate(qr_codes):
            canvas.paste(qr_img, (0, i * qr_size))
    elif layout == "grid":
        positions = [(0, 0), (qr_size, 0), (0, qr_size), (qr_size, qr_size)]
        for i, qr_img in enumerate(qr_codes[:4]):  # Max 4 for 2x2 grid
            canvas.paste(qr_img, positions[i])

    canvas.save(filename)
    print(f"Generated {filename} with {len(qr_codes)} QR codes ({layout} layout)")


def main():
    """Main execution entry point."""
    # Two QR codes horizontally
    generate_multi_qr_image(
        ["QR Code 1", "QR Code 2"],
        "fixtures/qr_images/multi_qr_2_horizontal.png",
        "horizontal",
    )

    # Three QR codes vertically
    generate_multi_qr_image(
        ["Code A", "Code B", "Code C"],
        "fixtures/qr_images/multi_qr_3_vertical.png",
        "vertical",
    )

    # Four QR codes in 2x2 grid
    generate_multi_qr_image(
        ["Top Left", "Top Right", "Bottom Left", "Bottom Right"],
        "fixtures/qr_images/multi_qr_4_grid.png",
        "grid",
    )


if __name__ == "__main__":
    main()
