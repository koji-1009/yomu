# CHANGELOG

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
