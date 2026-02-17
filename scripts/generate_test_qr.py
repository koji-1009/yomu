#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "qrcode[pil]",
#     "pillow",
# ]
# ///
"""
QR Code Test Image Generator

Generates QR code images for integration testing of the yomu library.

Usage:
    uv run scripts/generate_test_qr.py
"""

import json
from pathlib import Path
from typing import Optional

import qrcode
from qrcode.constants import (
    ERROR_CORRECT_H,
    ERROR_CORRECT_L,
    ERROR_CORRECT_M,
    ERROR_CORRECT_Q,
)


# Output directory
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_ROOT / "fixtures" / "qr_images"

# Test cases: (filename, content, error_correction, version)
TEST_CASES = [
    # Numeric mode
    ("numeric_simple.png", "12345", ERROR_CORRECT_L, None),
    ("numeric_large.png", "0123456789012345678901234567890", ERROR_CORRECT_M, None),
    ("numeric_zeros.png", "000000", ERROR_CORRECT_L, None),
    # Alphanumeric mode
    ("alphanumeric_hello.png", "HELLO WORLD", ERROR_CORRECT_L, None),
    ("alphanumeric_special.png", "TEST123$%*+-./:", ERROR_CORRECT_M, None),
    ("alphanumeric_url.png", "HTTPS://EXAMPLE.COM/PATH", ERROR_CORRECT_Q, None),
    # Byte mode
    ("byte_lowercase.png", "Hello, World!", ERROR_CORRECT_L, None),
    ("byte_url.png", "https://example.com/path?query=1", ERROR_CORRECT_M, None),
    ("byte_japanese.png", "こんにちは世界", ERROR_CORRECT_H, None),
    ("byte_emoji.png", "Hello 👋🌍!", ERROR_CORRECT_H, None),
    ("byte_mixed.png", "Test 123 テスト ABC", ERROR_CORRECT_Q, None),
    # Error correction levels
    ("ec_level_l.png", "EC Level L Test", ERROR_CORRECT_L, None),
    ("ec_level_m.png", "EC Level M Test", ERROR_CORRECT_M, None),
    ("ec_level_q.png", "EC Level Q Test", ERROR_CORRECT_Q, None),
    ("ec_level_h.png", "EC Level H Test", ERROR_CORRECT_H, None),
    # Versions
    ("version_1.png", "Hi", ERROR_CORRECT_L, 1),
    ("version_2.png", "Version 2 QR", ERROR_CORRECT_L, 2),
    (
        "version_5.png",
        "This is Version 5 QR code with more content",
        ERROR_CORRECT_L,
        5,
    ),
    ("version_10.png", "A" * 150, ERROR_CORRECT_L, 10),
    # Edge cases
    ("edge_single_char.png", "A", ERROR_CORRECT_L, None),
    ("edge_single_digit.png", "0", ERROR_CORRECT_L, None),
    ("edge_special.png", "!@#$%^&*()[]{}", ERROR_CORRECT_M, None),
    ("edge_whitespace.png", "Line1\nLine2\tTabbed", ERROR_CORRECT_L, None),
]


def generate_qr(
    content: str, error_correction: int, version: Optional[int], output_path: Path
):
    """Generate a single QR code image."""
    qr = qrcode.QRCode(
        version=version,
        error_correction=error_correction,
        box_size=10,
        border=4,
    )
    qr.add_data(content)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_path)


def get_ec_label(ec_int: int) -> str:
    if ec_int == ERROR_CORRECT_L:
        return "L"
    if ec_int == ERROR_CORRECT_M:
        return "M"
    if ec_int == ERROR_CORRECT_Q:
        return "Q"
    if ec_int == ERROR_CORRECT_H:
        return "H"
    return "M"


def main():
    """Generate all test QR codes."""
    print(f"Generating QR codes to: {OUTPUT_DIR}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    metadata = []

    for filename, content, ec, version in TEST_CASES:
        output_path = OUTPUT_DIR / filename
        try:
            generate_qr(content, ec, version, output_path)
            print(f"  ✓ {filename}")

            # Add to metadata
            metadata.append(
                {
                    "filename": filename,
                    "content": content,
                    "version": version
                    if version is not None
                    else 0,  # Default to 0/auto if None? Dart expects int?
                    # Actually Dart expects 'version' as int. If python has None, we should probably output 0 or maybe the actual version generated?
                    # The python qrcode lib chooses version automatically if None.
                    # For now let's dump None or 0. The test likely just checks if it exists or uses it for logging.
                    # Let's check the Dart side QrTestCase again. It says 'version' is int.
                    "error_correction": get_ec_label(ec),
                }
            )

        except Exception as e:
            print(f"  ✗ {filename}: {e}")

    # Fix version: Dart expects int, but some are None (auto).
    # For generated JSON, if version is None, we should probably use 0 (implied auto) or not include it?
    # qyuto_test.dart factory: version: json['version'] as int
    # So it must be an int.
    for item in metadata:
        if item["version"] is None:
            item["version"] = 0

    metadata_path = OUTPUT_DIR / "metadata.json"
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Generated {len(TEST_CASES)} QR codes and metadata.json.")


if __name__ == "__main__":
    main()
