#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "python-barcode",
#     "pillow",
# ]
# ///
"""
Generate test barcode images for testing 1D barcode decoders.

Usage:
    uv run scripts/generate_barcodes.py
"""

import json
import os
from typing import Optional

import barcode
from barcode.writer import ImageWriter


class CleanImageWriter(ImageWriter):
    """Custom writer that generates clean barcodes without text."""

    def __init__(self):
        super().__init__()
        self.set_options(
            {
                "write_text": False,  # No text below barcode
                "quiet_zone": 10,  # Minimal quiet zone
                "module_height": 50,  # Shorter bars
                "module_width": 0.4,  # Thicker bars for better detection
                "font_size": 0,  # No font
            }
        )


def generate_barcode(barcode_type: str, data: str, filename: str) -> Optional[str]:
    """Generate a barcode image."""
    try:
        code = barcode.get(barcode_type, data, writer=CleanImageWriter())
        # clean filename extension because save() appends it
        write_path = filename.replace(".png", "")
        full_path = code.save(write_path)
        print(f"Generated {barcode_type.upper()}: {full_path}")
        return full_path
    except Exception as e:
        print(f"Error generating {barcode_type.upper()} ({filename}): {e}")
        return None


def get_barcode_metadata_filename(output_dir):
    return os.path.join(output_dir, "metadata.json")


def main():
    """Main execution entry point."""
    output_dir = "fixtures/barcode_images"
    os.makedirs(output_dir, exist_ok=True)

    metadata = []

    # Helper to generate and record metadata
    def gen(barcode_type, data, filename, expected=None):
        full_path = generate_barcode(
            barcode_type, data, os.path.join(output_dir, filename)
        )
        if full_path:
            # Record relative filename
            rel_name = os.path.basename(full_path)
            metadata.append(
                {
                    "filename": rel_name,
                    "content": expected if expected is not None else data,
                    "format": barcode_type,
                }
            )

    # EAN-13 test cases
    # Qyuto (and python-barcode) handles checksums.
    # Mismatch was 4901234567890 -> 4901234567894. (0 was wrong checksum for 490123456789)
    # We should provide correct data or expect the corrected one.
    ean13_cases = [
        # 490123456789 -> Checksum is 4. Input was 4901234567890.
        # python-barcode replaces check digit?
        ("4901234567890", "ean13_product.png", "4901234567894"),
        ("9784873115658", "ean13_isbn.png", None),  # 8 is correct for 978487311565
        ("0012345678905", "ean13_upc.png", None),  # 5 is correct for 001234567890
    ]

    for data, filename, expected in ean13_cases:
        gen("ean13", data, filename, expected)

    # EAN-8 test cases
    ean8_cases = [
        ("12345670", "ean8_product.png", None),
        ("55123457", "ean8_small.png", None),
    ]

    for data, filename, expected in ean8_cases:
        gen("ean8", data, filename, expected)

    # UPC-A test cases
    # Qyuto reads UPC-A as EAN-13 by prepending 0.
    upca_cases = [
        ("012345678905", "upca_product.png", "0012345678905"),
        ("725272730706", "upca_food.png", "0725272730706"),
    ]

    for data, filename, expected in upca_cases:
        gen("upca", data, filename, expected)

    # Code 128 test cases
    code128_cases = [
        ("Hello World", "code128_hello.png", None),
        ("ABC-12345", "code128_mixed.png", None),
        ("1234567890", "code128_numeric.png", None),
    ]

    for data, filename, expected in code128_cases:
        gen("code128", data, filename, expected)

    # Code 39 test cases
    # python-barcode adds check digit by default? Qyuto reads it.
    code39_cases = [
        ("HELLO", "code39_hello.png", "HELLOB"),
        ("ABC123", "code39_mixed.png", "ABC123$"),
        ("12345", "code39_numeric.png", "12345F"),
    ]

    for data, filename, expected in code39_cases:
        gen("code39", data, filename, expected)

    # ITF test cases (requires even number of digits)
    itf_cases = [
        ("1234567890", "itf_numeric.png", None),
        ("00012345678905", "itf14_product.png", None),  # ITF-14 format
    ]

    for data, filename, expected in itf_cases:
        # python-barcode uses 'itf' for ITF-14 (Interleaved 2 of 5)
        gen("itf", data, filename, expected)

    # Codabar test cases (A-D are start/stop characters)
    # Qyuto strips start/stop characters.
    codabar_cases = [
        ("A12345B", "codabar_numeric.png", "12345"),
        ("A9876543210B", "codabar_long.png", "9876543210"),
        ("C12-34-56D", "codabar_dashes.png", "12-34-56"),
    ]

    for data, filename, expected in codabar_cases:
        # Try 'codabar' first, fall back to 'nw-7' if not available
        path = generate_barcode("codabar", data, os.path.join(output_dir, filename))

        if path is None:
            path = generate_barcode("nw-7", data, os.path.join(output_dir, filename))

        if path:
            rel_name = os.path.basename(path)
            metadata.append(
                {"filename": rel_name, "content": expected, "format": "codabar"}
            )

    total = len(metadata)

    # Write metadata
    with open(get_barcode_metadata_filename(output_dir), "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"\nGenerated {total} barcode images and metadata.json in {output_dir}/")


if __name__ == "__main__":
    main()
