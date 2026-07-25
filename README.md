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
* **🚀 High Performance**: Full HD in ~2.4ms, 4K in ~4.0ms on M4 MacBook Air (AOT). Fast enough for real-time scanning.
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

| Constructor / Static                   | Description                                  |
| -------------------------------------- | -------------------------------------------- |
| `Yomu.all`                             | QR codes + all barcode formats               |
| `Yomu.qrOnly`                          | QR codes only                                |
| `Yomu.barcodeOnly`                     | 1D barcodes only                             |
| `Yomu.responsive`                      | All formats, `DecodeEffort.balanced`         |
| `Yomu.realtime`                        | All formats, `DecodeEffort.fast` (per-frame) |
| `Yomu({enableQRCode, barcodeScanner})` | Custom configuration                         |

| Method        | Description                                     |
| ------------- | ----------------------------------------------- |
| `decode()`    | Decode the first QR code or barcode in an image |
| `decodeAll()` | Detect and decode all QR codes in an image      |

### Detection vs Latency (`DecodeEffort`)

Retries only run on images the fast path cannot decode, so **successful scans are never slowed down** by this setting. What it trades is detection on hard inputs against latency on inputs holding no code at all — which is every frame of a camera preview pointed at nothing.

The levels split where the cost actually jumps: between stages that **reuse** the binarized image already in hand and stages that **rebuild** it from the source pixels.

| `effort`                | Retries                                                    | Detection¹     | Blank frame² | Textured frame² |
| ----------------------- | ---------------------------------------------------------- | -------------- | ------------ | --------------- |
| `DecodeEffort.fast`     | none                                                       | 167/201, 83.1% | 1.41ms       | 2.58ms          |
| `DecodeEffort.balanced` | corner grid search, despeckle, tolerant finder             | 188/201, 93.5% | 1.36ms       | 17.98ms         |
| `DecodeEffort.thorough` | + full-resolution retry, alternate binarization thresholds | 192/201, 95.5% | 7.89ms       | 51.30ms         |

¹ Fixture corpus. ² Full HD frame containing no code, AOT. A textured frame costs more at every level because noise produces false finder patterns, so each stage has candidates to rule out rather than nothing to look at.

Pick by use case:

* **Single images** (photos, uploaded pictures): keep the default `thorough`. A slower failure is better than a missed code.
* **Camera streams that can spend ~18ms on a bad frame**: `Yomu.responsive` (`balanced`). It recovers 21 of the 25 codes `thorough` adds over `fast`, for a third of the cost on a textured frame.
* **Real-time preview**: `Yomu.realtime` (`fast`). Frames without a code fail as fast as possible; a code missed on one frame is caught on a later one.

The older `tryHarder: bool` parameter still works — `false` maps to `fast`, `true` to `thorough` — but it is deprecated in favour of `effort`.

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
| Low-light (Gaussian) noise | σ=120²          | σ=170²            |
| Gray dirt occlusion        | 30%             | 35%               |
| Gaussian blur              | radius 5.0      | radius 6.0        |
| Perspective (top squeeze)  | 0.3             | 0.4               |
| Perspective (side squeeze) | 0.6             | — (saturates)     |
| JPEG artifacts             | quality 1       | — (no boundary)   |
| Specular glare             | full saturation | — (EC absorbs it) |
| Screen moire               | amplitude 0.8   | amplitude 0.9     |
| Composite casual scan¹     | blur 5.5        | blur 6.0          |

¹ Mild perspective (0.2) + lighting gradient + blur. Each component alone is well inside its single-axis boundary.

² The only probabilistic axis. Each σ draws one noise field, so a fixture near the transition reports its own draw rather than the decoder's limit. Measured decode rate over 20 independent draws per σ: 110→100%, 120→100%, 130→75%, 140→70%, 150→50%, 160→40%, 170→5%, 180→5%. The rungs are taken from the flat ends so neither side depends on a lucky draw; the real transition is around σ=150.

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
| AOT  | ~0.55ms         |
| JIT  | ~0.72ms         |

### Large Images (Fused Downsampling)

Images >1MP are automatically processed with a fused conversion step for optimal performance.

| Resolution          | Avg Decode Time |
| ------------------- | --------------- |
| 4K (3840×2160)      | ~4.0ms          |
| Full HD (1920×1080) | ~2.4ms          |

## License

MIT License - see [LICENSE](LICENSE) for details.
