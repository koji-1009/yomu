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

    # NOTE: The value lists of the random-consuming generators (damage,
    # noise) below must stay EXACTLY as they are: changing them shifts the
    # global random sequence and silently regenerates different bytes for
    # the existing committed fixtures. Boundary-extension images are
    # generated in `generate_boundary_extension()` with an independent
    # seed instead.

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
    # Values above 0.2 are NOT generated here: this legacy transform crops
    # the finder patterns out of the canvas at higher strengths, producing
    # invalid test images (not decodable by any reader). Stronger values
    # use the padded transform in `generate_boundary_extension()`.
    # The committed perspective_y_0.3.png is a kept legacy artifact (its
    # cropping is mild enough to remain decodable) and is intentionally
    # not regenerated.
    for p in [0.1, 0.2]:
        # Tilt X
        img, name = apply_perspective(base, p, axis="x")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")
        # Tilt Y
        img, name = apply_perspective(base, p, axis="y")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    generate_boundary_extension(base)
    generate_modern_extension(base)


def generate_boundary_extension(base: Image.Image):
    """
    Generates images that bracket the CURRENT detection boundary.

    The original ladders were calibrated against the pre-try-harder
    implementation; after the retry strategies landed, every noise value up
    to 0.20 decodes, so the ladders no longer demonstrate where detection
    stops. This batch extends each distortion axis past the new boundary.

    Each axis keeps one value at or near the current capability boundary
    plus the first failing value, so the fixtures bracket the boundary
    from both sides (failing values are sorted into
    fixtures/unsupported_images by the maintainer, as usual).

    Boundary as of the try-harder implementation:
    - noise:  0.25 decodes / 0.30 does not
    - dirt:   0.30 decodes / 0.35 does not
    - blur:   5.0 decodes  / 6.0 does not
    - perspective x: 0.3 decodes / 0.4 does not
    - perspective y: decodes through 0.6; stronger values are not
      generated because the padding required to keep the code visible
      grows faster than the distortion across the code itself, so the
      nominal strength no longer reflects the effective distortion.

    Uses an independent seed so the values can be tuned without disturbing
    the byte-identical reproduction of the original fixtures above.
    """
    np.random.seed(43)

    # Noise: 0.20 decodes via the despeckle retry; bracket the ceiling.
    for i in [0.25, 0.30]:
        img, name = apply_noise(base, i)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Dirt: 0.30 decodes, 0.40 does not; tighten the bracket.
    for c in [0.35]:
        img, name = apply_damage(base, c)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Blur: every original value (up to 5.0) decodes; bracket the ceiling.
    for r in [6.0]:
        img, name = apply_blur(base, r)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Perspective with a padded canvas: the code stays fully visible, so
    # these test the reader's actual perspective limit instead of the
    # legacy transform's cropping artifact.
    for p in [0.3, 0.4]:
        img, name = apply_perspective_padded(base, p, axis="x")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")
    for p in [0.4, 0.6]:
        img, name = apply_perspective_padded(base, p, axis="y")
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")


def generate_modern_extension(base: Image.Image):
    """
    Distortions derived from the MODERN imaging pipeline, complementing the
    legacy axes above (salt & pepper noise models dead pixels of older
    sensors; modern smartphone noise is Gaussian, and modern sources add
    JPEG quantization, screen moire, glossy-print glare and composite
    casual-scan degradations).

    Random-consuming axes seed per value (`seed(44 + value)`), so editing
    one ladder never changes the bytes of another fixture.

    Boundary as of the try-harder implementation:
    - gaussian noise: sigma 110 decodes / 120 does not
    - jpeg: decodes at quality 1 (no practical boundary)
    - glare: decodes at full saturation of the highlighted region (error
      correction absorbs it while the finder patterns stay outside the
      highlight; a highlight covering a finder pattern is the cropped-
      pattern class, which is out of scope by definition)
    - moire: amplitude 0.7 decodes / 0.8 does not
    - composite scan: blur 5.0 decodes / 5.5 does not (the single-axis
      blur boundary is 6.0; the composition lowers it)
    """
    # Low-light sensor noise (Gaussian luminance noise).
    for sigma in [110, 120]:
        img, name = apply_gaussian_noise(base, sigma)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # JPEG quantization artifacts (camera output is JPEG; fixtures store
    # the decoded result as PNG). No boundary: quality 1 still decodes,
    # kept as the extreme anchor.
    for q in [1]:
        img, name = apply_jpeg_artifacts(base, q)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Specular glare on glossy print (radial highlight washing out
    # contrast). No boundary within this geometry: full saturation still
    # decodes, kept as the extreme anchor.
    for s in [1.0]:
        img, name = apply_glare(base, s)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Screen moire: sinusoidal interference beating against the module
    # grid (display pixel pitch vs camera sampling).
    for a in [0.7, 0.8]:
        img, name = apply_moire(base, a)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")

    # Composite casual scan: mild perspective + lighting gradient with an
    # increasing blur. Each component is well inside its single-axis
    # boundary; the composition is what creates the failure.
    for r in [5.0, 5.5]:
        img, name = apply_composite_scan(base, r)
        img.save(OUTPUT_DIR / name)
        print(f"Generated: {name}")


def apply_gaussian_noise(img: Image.Image, sigma: int):
    """Adds Gaussian luminance noise (modern low-light sensor model)."""
    np.random.seed(44 + sigma)
    pixels = np.array(img.convert("RGB"), dtype=np.float64)
    noise = np.random.normal(0.0, sigma, pixels.shape[:2])
    pixels += noise[:, :, np.newaxis]
    out = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    return out, f"gaussian_noise_{sigma}.png"


def apply_jpeg_artifacts(img: Image.Image, quality: int):
    """Encodes to JPEG at the given quality and decodes back."""
    import io

    buffer = io.BytesIO()
    img.convert("RGB").save(buffer, format="JPEG", quality=quality)
    buffer.seek(0)
    return Image.open(buffer).convert("RGBA"), f"jpeg_q{quality}.png"


def apply_glare(img: Image.Image, strength: float):
    """
    Simulates a specular highlight: a radial bright spot centered over the
    top-right quadrant (covering data modules and part of a finder ring).
    """
    pixels = np.array(img.convert("RGB"), dtype=np.float64)
    h, w = pixels.shape[:2]
    cy, cx = h * 0.35, w * 0.6
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    radius = w * 0.45
    falloff = np.clip(1.0 - dist / radius, 0.0, 1.0) ** 2
    pixels += (255.0 - pixels) * (strength * falloff)[:, :, np.newaxis]
    out = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    return out, f"glare_{strength:.1f}.png"


def apply_moire(img: Image.Image, amplitude: float):
    """
    Simulates screen-capture moire: a diagonal sinusoidal interference
    pattern with a spatial frequency close to the module frequency, so the
    beat pattern sweeps across the modules.
    """
    pixels = np.array(img.convert("RGB"), dtype=np.float64)
    h, w = pixels.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    # Module size is 10px (frequency 0.1/px); beat against it.
    pattern = 0.5 + 0.5 * np.sin(2.0 * math.pi * (0.11 * xx + 0.013 * yy))
    factor = 1.0 - amplitude * pattern
    pixels *= factor[:, :, np.newaxis]
    out = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    return out, f"moire_{amplitude:.1f}.png"


def apply_composite_scan(img: Image.Image, blur_radius: float):
    """
    A casual handheld scan: mild perspective (0.2), a horizontal lighting
    gradient (1.0 -> 0.55) and Gaussian blur. Each component alone is well
    inside the single-axis boundary.
    """
    tilted, _ = apply_perspective_padded(img, 0.2, axis="x")
    pixels = np.array(tilted.convert("RGB"), dtype=np.float64)
    h, w = pixels.shape[:2]
    gradient = np.linspace(1.0, 0.55, w)
    pixels *= gradient[np.newaxis, :, np.newaxis]
    shaded = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    blurred = shaded.filter(ImageFilter.GaussianBlur(blur_radius))
    return blurred, f"composite_scan_blur_{blur_radius:.1f}.png"


def apply_perspective_padded(img, strength, axis="x"):
    """
    Like `apply_perspective`, but pastes the code onto a padded white
    canvas first so the keystone transform never pushes the finder
    patterns outside the image.
    """
    w, h = img.size
    # The transform crops up to `delta = canvas * strength / 2` from the
    # squeezed side; pad so the code always stays inside:
    # pad >= (w + 2*pad) * strength / 2  =>  pad >= w*s / (2*(1-s))
    pad = int(w * strength / (2.0 * (1.0 - strength))) + 20
    canvas = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (255, 255, 255, 255))
    canvas.paste(img, (pad, pad))

    cw, ch = canvas.size
    delta = int(cw * strength * 0.5)

    if axis == "x":
        pts = [(delta, 0), (cw - delta, 0), (cw, ch), (0, ch)]
    else:
        pts = [(0, delta), (cw, delta), (cw, ch), (0, ch - delta)]

    coeffs = _find_coeffs([(0, 0), (cw, 0), (cw, ch), (0, ch)], pts)

    transformed = canvas.transform(
        (cw, ch), Image.PERSPECTIVE, coeffs, Image.BICUBIC, fillcolor=(255, 255, 255)
    )
    return transformed, f"perspective_{axis}_{strength}.png"


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
