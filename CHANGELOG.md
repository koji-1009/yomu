# CHANGELOG

## 1.1.0

### Features

* **Try-Harder Mode (default on)**: `Yomu.decode` now runs escalating retry strategies when the fast path fails, significantly improving the detection rate (fixture corpus: 84.3% -> 95.5%, 167/198 -> 189/198). Successful scans are unaffected; retries only run on images the fast path cannot decode.
  * **Corner grid search**: per-axis dimension candidates plus a grid search of the bottom-right corner rescue perspective-distorted codes.
  * **Despeckle retry**: a word-parallel 3x3 majority filter (`BitMatrix.majority3x3`) recovers codes under salt & pepper noise (validated up to 20% pixel noise).
  * **Tolerant finder**: clusters raw row-scan hits without the strict vertical cross-check, recovering slanted finder patterns under strong perspective.
  * **Full-resolution retry**: re-runs detection without downsampling when a downsampled pass fails, recovering small codes in high-resolution frames.
  * Retries are bounded by a deterministic work budget and grid-search deduplication, so undecodable inputs cannot make the failure path pathologically slow.
  * Set `tryHarder: false` for the previous fast-only behavior (latency-critical per-frame scanning).
* **`decodeAll` retry passes**: multi-code scanning applies the same strategy. Detected-but-undecodable codes get the corner-grid rescue, and a pass that finds nothing escalates to despeckle and a full-resolution pass (a noisy 3-code sheet and two 90px codes in a 4K frame go from 0 to fully decoded).
* **`Yomu.realtime` preset**: all formats with `tryHarder` disabled, tuned for per-frame camera scanning where a missed frame is cheaper than a slower failure path.
* With `tryHarder` enabled, a detected-but-undecodable QR code now falls through to barcode scanning instead of propagating a `DecodeException`.

### Test fixtures

* Fixture ladders now bracket the current capability boundary on both sides, with boundary-pinning tests on each side (see the Supported Image Classes table in the README).
* New distortion axes derived from the modern imaging pipeline: low-light Gaussian noise, JPEG quantization artifacts, specular glare, screen moire, and a composite casual-scan recipe (mild perspective + lighting gradient + blur) that demonstrates composition lowering the single-axis boundary.
* The legacy `perspective_{x,y}` fixtures above 0.2 cropped the finder patterns out of the canvas (invalid test images); they are replaced by a padded transform that keeps the code fully visible.
* `fixtures/unsupported_images` now contains only images beyond the capability boundary; everything rescued by the retry strategies moved to `fixtures/distorted_images`.

## 1.0.0

Initial stable release.

### Features

* **Pure Dart Implementation**: A zero-dependency QR code and barcode reader library. No native code required, making it highly portable across Flutter, Web, and Server-side Dart.
* **QR Code Support**:
  * Full support for QR Code versions 1 to 40.
  * Supports all error correction levels (L, M, Q, H).
  * Robust multi-QR detection and decoding in a single image.
  * High resilience against perspective distortion, rotation, and uneven lighting.
* **1D Barcode Support**:
  * Retail: EAN-13 (including JAN), EAN-8, UPC-A.
  * Industrial: Code 128, Code 39, ITF (Interleaved 2 of 5), Codabar.
* **High Performance**:
  * Specifically optimized for AOT compilation and performance.
  * Efficiently handles high-resolution images (> 1MP) using internal fused downsampling and conversion.
  * Capable of real-time decoding on mobile and desktop platforms.
* **Flexible Image API**: Platform-agnostic `YomuImage` container supporting various pixel formats including RGBA, BGRA, Grayscale, and YUV420 (camera stream Y-plane).
