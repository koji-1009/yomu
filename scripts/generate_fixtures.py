#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Fixture Generator Entrypoint

Runs all image generation scripts to populate fixtures/ directory.
This ensures a complete set of test images for benchmarks and tests.

Usage:
    uv run scripts/generate_fixtures.py
"""

import subprocess
import sys
import time
from pathlib import Path

SCRIPTS = [
    "scripts/generate_test_qr.py",  # Standard QR codes
    "scripts/generate_barcodes.py",  # 1D Barcodes
    "scripts/generate_version_qr.py",  # Various QR versions
    "scripts/generate_multi_qr.py",  # Multiple QRs in one image
    "scripts/generate_uneven_lighting.py",  # Lighting/Shadow robustness
    "scripts/generate_realworld_qr.py",  # "Real-world" simulated images
]


def run_script(script_path: str):
    print(f"🔄 Running {script_path}...")
    try:
        # Check if uv is available, otherwise try python3 directly
        # Assuming we are running within the project root
        cmd = ["uv", "run", script_path]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            print(f"❌ Failed: {script_path}")
            print(result.stderr)
            return False

        print(f"✅ Done: {script_path}")
        return True
    except FileNotFoundError:
        print(f"❌ Error: 'uv' command not found or script missing.")
        return False


def main():
    print("=" * 60)
    print("🎨 QYUTO FIXTURE GENERATOR")
    print("=" * 60)
    print(f"Generating fixtures using {len(SCRIPTS)} scripts...\n")

    start_time = time.time()
    success_count = 0

    for script in SCRIPTS:
        if run_script(script):
            success_count += 1

    elapsed = time.time() - start_time
    print("-" * 60)
    print(f"🎉 Completed {success_count}/{len(SCRIPTS)} scripts in {elapsed:.1f}s")

    if success_count == len(SCRIPTS):
        print("✅ Ready for benchmarking and testing.")
        sys.exit(0)
    else:
        print("⚠️ Some scripts failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
