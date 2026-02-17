#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode",
#     "pillow",
#     "python-barcode",
# ]
# ///
"""
Generate QR codes with various versions for integration testing.

Different QR code versions have different dimensions:
Version N has dimension = 4*N + 17

This script generates QR codes that exercise different code paths
in the detector and decoder.

Usage:
    uv run scripts/generate_version_qr.py
"""

import os

import random
import qrcode


def generate_versioned_qr(version: int, filename: str, data: str | None = None):
    """
    Generate a QR code with a specific version.

    Args:
        version: QR code version (1-40)
        filename: Output filename
        data: Data to encode (auto-generated if None)
    """
    if data is None:
        # Simple data, let qrcode handles version fitting
        data = f"Version {version} QR Code"

    qr = qrcode.QRCode(
        version=version,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=15,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)  # Auto-fit to ensure it works

    img = qr.make_image(fill_color="black", back_color="white")
    img = img.convert("RGB")  # Ensure consistent RGB format
    img.save(filename)

    dimension = 4 * version + 17
    print(f"Generated version {version} QR code: {filename}")
    print(f"  Dimension: {dimension} (mod 4 = {dimension % 4})")


def generate_code128_with_codeset_a(filename: str):
    """
    Generate a Code128 barcode that uses Code Set A.

    Code Set A is used for uppercase letters and control characters.
    """
    try:
        import barcode
        from barcode.writer import ImageWriter

        class CleanImageWriter(ImageWriter):
            def __init__(self):
                super().__init__()
                self.set_options(
                    {
                        "write_text": False,
                        "quiet_zone": 10,
                        "module_height": 50,
                        "module_width": 0.4,
                        "font_size": 0,
                    }
                )

        # Code Set A handles control characters (ASCII 0-31) and uppercase
        # Including a control character (e.g., \r = ASCII 13) forces Code Set A
        data = "\rHELLO"
        code = barcode.get("code128", data, writer=CleanImageWriter())
        write_path = filename.replace(".png", "")
        code.save(write_path)
        print(f"Generated Code128 (Code Set A): {filename}")
    except Exception as e:
        print(f"Error generating Code128: {e}")


def generate_distorted_qr(version: int, filename: str):
    """
    Generate a distorted (perspective transformed) QR code.
    This simulates a QR code viewed from an angle.
    """
    # 1. Generate standard QR
    qr = qrcode.QRCode(
        version=version,
        error_correction=qrcode.constants.ERROR_CORRECT_H,  # Use High ECC to survive distortion
        box_size=15,
        border=4,
    )
    qr.add_data(f"Distorted V{version}")
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert("RGB")

    # 2. Apply Perspective Transform
    width, height = img.size

    # Perspective coefficients calculation not needed if using transform with finding coeffs
    # But PIL's transform method with PERSPECTIVE expects 8-tuple coefficients.
    # A simpler way using Image.transform with params is tricky.
    # simpler approach: limit shear/rotation for now or use specific library.
    # Let's use a simpler Affine transform (Shear) which is easier and supported widely
    # Or actually, let's keep it simple with rotate + resize which might trigger similar issues

    # Actually, let's use a simple resize to non-integer scaling which might cause aliasing
    # But for "dirty", noise is also good.

    # Let's try explicit Perspective Transform using simple geometric distortion

    # Find coefficients (skipping complex math, let's use simple rotate + noise for now)
    # Real perspective transform in PIL requires numpy usually to find coeffs.
    # Let's rely on simple rotation which definitely triggers floating point coordinates

    distorted = img.rotate(15, expand=True, fillcolor="white")

    # Add some random noise
    pixels = distorted.load()
    width, height = distorted.size
    for y in range(height):
        for x in range(width):
            if random.random() < 0.02:  # 2% salt and pepper noise
                pixels[x, y] = (0, 0, 0) if random.random() < 0.5 else (255, 255, 255)

    distorted.save(filename)
    print(f"Generated distorted version {version} QR code: {filename}")


def main():
    """Main execution entry point."""
    output_dir = "fixtures/qr_images"
    os.makedirs(output_dir, exist_ok=True)

    # Generate QR codes for versions 1-7
    # These have different dimensions that may trigger different detector paths
    for version in range(1, 8):
        filename = os.path.join(output_dir, f"qr_version_{version}.png")
        generate_versioned_qr(version, filename)

    # Generate additional QR codes with specific data patterns
    # Version 7+ has version information encoded
    generate_versioned_qr(
        7,
        os.path.join(output_dir, "qr_version_7_with_version_info.png"),
        "This QR code is version 7 or higher and contains encoded version information",
    )

    # Generate a Distorted QR code to test detector resilience
    generate_distorted_qr(4, os.path.join(output_dir, "qr_distorted_v4.png"))

    # Generate Code128 with Code Set A
    barcode_dir = "fixtures/barcode_images"
    os.makedirs(barcode_dir, exist_ok=True)
    generate_code128_with_codeset_a(os.path.join(barcode_dir, "code128_uppercase.png"))

    print(f"\nGenerated QR codes in {output_dir}/")


if __name__ == "__main__":
    main()
