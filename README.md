# Yomu

[![pub package](https://img.shields.io/pub/v/yomu.svg)](https://pub.dev/packages/yomu)
[![license](https://img.shields.io/github/license/koji-1009/yomu)](https://github.com/koji-1009/yomu/blob/main/LICENSE)
[![analyze](https://github.com/koji-1009/yomu/actions/workflows/analyze.yml/badge.svg)](https://github.com/koji-1009/yomu/actions/workflows/analyze.yml)
[![codecov](https://codecov.io/gh/koji-1009/yomu/branch/main/graph/badge.svg)](https://codecov.io/gh/koji-1009/yomu)

**Pure Dart QR Code & Barcode Reader Library**

Yomu is a **zero-dependency** pure Dart implementation of a QR code and barcode reader library. It works in any Dart environment including Flutter, Dart CLI applications, and server-side Dart.

## ✨ Why Yomu?

* **📦 Zero Dependencies**: No external package dependencies. Keep your app's dependency graph clean.
* **🎯 Pure Dart**: No C++/Native code. Works instantly on Web (Wasm/JS), Desktop, and Mobile without build issues.
* **🚀 High Performance**: Full HD in ~4.4ms, 4K in ~9ms on M4 MacBook Air (AOT). Fast enough for real-time scanning.
* **🛡️ Robust & Tested**: Comprehensive test coverage. Tested against hundreds of distorted, noisy, and unevenly lit images.

## 🚀 Quick Start

### QR Code + All Barcodes

```dart
import 'package:yomu/yomu.dart';

void main() {
  // Create a YomuImage container
  final image = YomuImage.rgba(
    bytes: imageBytes,
    width: 300,
    height: 300,
  );

  // Decode QR codes and all barcode formats
  final result = Yomu.all.decode(image);
  print('Decoded: ${result.text}');
}
```

### QR Code Only

```dart
// For QR code only scanning
final result = Yomu.qrOnly.decode(YomuImage.rgba(
  bytes: imageBytes,
  width: width,
  height: height,
));
```

## 📖 API Reference

### `Yomu` Class

The main entry point class.

| Constructor / Static                   | Description                                       |
| -------------------------------------- | ------------------------------------------------- |
| `Yomu.all`                             | QR codes + all barcode formats                    |
| `Yomu.qrOnly`                          | QR codes only                                     |
| `Yomu.barcodeOnly`                     | 1D barcodes only                                  |
| `Yomu.realtime`                        | All formats, `tryHarder` off (per-frame scanning) |
| `Yomu({enableQRCode, barcodeScanner})` | Custom configuration                              |

| Method        | Description                                     |
| ------------- | ----------------------------------------------- |
| `decode()`    | Decode the first QR code or barcode in an image |
| `decodeAll()` | Detect and decode all QR codes in an image      |

### Detection vs Latency (`tryHarder`)

`decode()` runs escalating retry strategies by default (`tryHarder: true`) when the fast path fails: corner grid search, despeckle, tolerant finder and a full-resolution retry. This significantly improves the detection rate for noisy, dirty, perspective-distorted and small codes, while successful scans pay nothing. `decodeAll()` applies the same strategy to multi-code sheets: detected-but-undecodable codes get the corner rescue, and a pass that finds nothing escalates to despeckle and full resolution.

The retries only cost time on images that fail the fast path (roughly +8ms on a Full HD frame without a code, AOT). Pick by use case:

* **Single images** (photos, uploaded pictures): keep the default. A slower failure is better than a missed code.
* **Real-time camera streams**: use `Yomu.realtime` (or `tryHarder: false`). Frames without a code fail as fast as possible; a code missed on one frame is caught on a later one.

### `YomuImage` Class

A platform-agnostic container for image data.

| Factory                 | Description                                |
| ----------------------- | ------------------------------------------ |
| `YomuImage.rgba()`      | Create from RGBA bytes (4 bytes/pixel)     |
| `YomuImage.bgra()`      | Create from BGRA bytes (4 bytes/pixel)     |
| `YomuImage.grayscale()` | Create from grayscale bytes (1 byte/pixel) |
| `YomuImage.yuv420()`    | Create from Y-plane of YUV420 camera image |

## 🔧 Support Status

### Supported Image Classes

Yomu targets modern capture sources: **printed codes, on-screen codes, and ordinary camera scans**. Instead of relying on era-specific photo corpora, the test fixtures are generated to bracket the capability boundary of each distortion axis from both sides (see `scripts/generate_stress_qr.py`):

| Distortion axis            | Decodes         | Does not decode   |
| -------------------------- | --------------- | ----------------- |
| Salt & pepper noise        | 25%             | 30%               |
| Low-light (Gaussian) noise | σ=110           | σ=120             |
| Gray dirt occlusion        | 30%             | 35%               |
| Gaussian blur              | radius 5.0      | radius 6.0        |
| Perspective (top squeeze)  | 0.3             | 0.4               |
| Perspective (side squeeze) | 0.6             | — (saturates)     |
| JPEG artifacts             | quality 1       | — (no boundary)   |
| Specular glare             | full saturation | — (EC absorbs it) |
| Screen moire               | amplitude 0.7   | amplitude 0.8     |
| Composite casual scan¹     | blur 5.0        | blur 5.5          |

¹ Mild perspective (0.2) + lighting gradient + blur. Each component alone is well inside its single-axis boundary.

Degradations outside these definable classes — arbitrary surface curvature, finder patterns cut out of the frame, damage beyond the error-correction capacity — are out of scope; that long tail is the domain of ML-based detectors.

### Encoding Modes (QR)

| Mode                 | Support         |
| -------------------- | --------------- |
| Numeric              | ✅               |
| Alphanumeric         | ✅               |
| Byte (Latin-1/UTF-8) | ✅               |
| Kanji                | ✅               |
| ECI                  | ❌ Not Supported |

### 1D Barcode Support

| Format   | Support | Description                         |
| -------- | ------- | ----------------------------------- |
| EAN-13   | ✅       | International retail (includes JAN) |
| EAN-8    | ✅       | Small products                      |
| UPC-A    | ✅       | North American retail               |
| Code 128 | ✅       | Logistics, high-density             |
| Code 39  | ✅       | Industrial, alphanumeric            |
| ITF      | ✅       | Interleaved 2 of 5, logistics       |
| Codabar  | ✅       | Libraries, blood banks              |

## 🎯 Performance

Run the benchmark suite:

```bash
uv run scripts/benchmark_runner.py
```

### Standard Images (≤1000px)

* **Environment**: M4 MacBook Air (2024), AOT Compiled

| Mode | Avg Decode Time |
| ---- | --------------- |
| AOT  | ~0.92ms         |
| JIT  | ~1.30ms         |

### Large Images (Fused Downsampling)

Images >1MP are automatically processed with a fused conversion step for optimal performance.

| Resolution          | Avg Decode Time |
| ------------------- | --------------- |
| 4K (3840×2160)      | ~9.0ms          |
| Full HD (1920×1080) | ~4.4ms          |

## License

MIT License - see [LICENSE](LICENSE) for details.
