# Yomu

**Pure Dart QR Code & Barcode Reader Library**

Yomu is a **zero-dependency** pure Dart implementation of a QR code and barcode reader library. It works in any Dart environment including Flutter, Dart CLI applications, and server-side Dart.

## ✨ Features

* **🎯 Pure Dart** - No native code required, platform-independent
* **📦 Zero Dependencies** - No external package dependencies
* **🚀 High Performance** - 4K in < 5.2ms, Full HD in < 3ms, 120fps capable
* **📐 Full QR Support** - QR code versions 1-40, Multi-QR detection
* **📊 7 Barcode Formats** - EAN-13/8, UPC-A, Code 128/39, ITF, Codabar
* **🛡️ Robust Error Correction** - Complete Reed-Solomon implementation

## 🚀 Quick Start

### QR Code + All Barcodes

```dart
import 'package:yomu/yomu.dart';

void main() {
  // Decode QR codes and all barcode formats
  final result = Yomu.all.decode(
    bytes: imageBytes,
    width: 300,
    height: 300,
  );
  print('Decoded: ${result.text}');
}
```

### QR Code Only

```dart
// For QR code only scanning
final result = Yomu.qrOnly.decode(
  bytes: imageBytes,
  width: width,
  height: height,
);
```

### Barcodes Only

```dart
// For 1D barcode only scanning
final result = Yomu.barcodeOnly.decode(
  bytes: imageBytes,
  width: width,
  height: height,
);
```

### Custom Configuration

```dart
// Custom configuration: QR + retail barcodes only
const yomu = Yomu(
  enableQRCode: true,
  barcodeScanner: BarcodeScanner.retail,
);

// Or specific barcode formats
const yomu = Yomu(
  enableQRCode: false,
  barcodeScanner: BarcodeScanner(decoders: [
    EAN13Decoder(),
    Code128Decoder(),
  ]),
);
```

### Flutter Usage

```dart
import 'dart:ui' as ui;
import 'package:yomu/yomu.dart';

Future<String?> decodeFromImage(ui.Image image) async {
  final byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) return null;

  try {
    final result = Yomu.all.decode(
      bytes: byteData.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
    return result.text;
  } catch (e) {
    return null;
  }
}
```

## 📖 API Reference

### `Yomu` Class

The main entry point class.

| Constructor / Static                   | Description                    |
| -------------------------------------- | ------------------------------ |
| `Yomu.all`                             | QR codes + all barcode formats |
| `Yomu.qrOnly`                          | QR codes only                  |
| `Yomu.barcodeOnly`                     | 1D barcodes only               |
| `Yomu({enableQRCode, barcodeScanner})` | Custom configuration           |

| Method                              | Description              |
| ----------------------------------- | ------------------------ |
| `decode({bytes, width, height})`    | Decode single QR/barcode |
| `decodeAll({bytes, width, height})` | Decode all QR codes      |

### `BarcodeScanner` Class

Configuration for 1D barcode scanning.

| Constructor / Static         | Description                     |
| ---------------------------- | ------------------------------- |
| `BarcodeScanner.all`         | All 7 barcode formats           |
| `BarcodeScanner.retail`      | EAN-13, EAN-8, UPC-A            |
| `BarcodeScanner.industrial`  | Code 128, Code 39, ITF, Codabar |
| `BarcodeScanner({decoders})` | Custom decoder list             |

### `DecoderResult` Class

Holds the decoded result.

| Property       | Type              | Description            |
| -------------- | ----------------- | ---------------------- |
| `text`         | `String`          | Decoded text content   |
| `byteSegments` | `List<Uint8List>` | Raw byte segments      |
| `ecLevel`      | `String?`         | Error correction level |

### Exception Hierarchy

| Exception              | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `YomuException`        | Abstract base class for all library exceptions     |
| `DetectionException`   | QR/barcode detection failure                       |
| `DecodeException`      | Data decoding/parsing error                        |
| `ReedSolomonException` | Error correction failure (extends DecodeException) |

## 🔧 Support Status

### Encoding Modes

| Mode                 | Support         |
| -------------------- | --------------- |
| Numeric              | ✅               |
| Alphanumeric         | ✅               |
| Byte (Latin-1/UTF-8) | ✅               |
| Kanji                | ✅               |
| ECI                  | ❌ Not Supported |

### Error Correction Levels (QR)

| Level        | Support | Correction Capability |
| ------------ | ------- | --------------------- |
| L (Low)      | ✅       | ~7%                   |
| M (Medium)   | ✅       | ~15%                  |
| Q (Quartile) | ✅       | ~25%                  |
| H (High)     | ✅       | ~30%                  |

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

## 🏗️ Architecture

```
yomu/
├── lib/
│   ├── yomu.dart           # Public API exports
│   └── src/
│       ├── yomu.dart       # Main entry point
│       ├── common/         # Generic utilities (Binarizer, BitMatrix)
│       ├── qr/             # QR-specific logic (Decoder, Detector)
│       └── barcode/        # 1D barcode decoders (EAN-13, Code128)
├── web/                    # Browser demo
└── benchmark/              # Performance tests
```

## 🎯 Performance

Run the benchmark comparison (JIT vs AOT):

```bash
uv run scripts/benchmark_runner.py
```

Benchmarks are automatically run on CI (GitHub Actions) for every usage. We enforce strict performance thresholds to prevent regressions.

### Standard Images (≤1000px)

* **Environment**: M4 MacBook Air (2024), AOT Compiled

| Mode | Avg Decode Time |
| ---- | --------------- |
| AOT  | ~1.29ms         |
| JIT  | ~2.15ms         |

> **Note**: `Yomu.all` adds negligible overhead (~4%) for QR codes, but significant overhead (~92%) for 1D barcodes due to QR detection checks. Use `Yomu.barcodeOnly` if you only need 1D scanning performance.

### Large Images (Fused Downsampling)

Images >1MP are automatically processed with a fused conversion step for optimal performance.

| Resolution          | Avg Decode Time |
| ------------------- | --------------- |
| 4K (3840×2160)      | ~5.16ms         |
| Full HD (1920×1080) | ~2.93ms         |
| 1600×1600           | ~3.65ms         |

## ⚠️ Limitations

* **Micro QR**: Not supported.
* **ECI Mode**: Not supported. To maintain **zero dependencies** and keep the library lightweight, we do not include the massive character encoding tables required for full ECI support (standard UTF-8 and Shift_JIS/Kanji modes are supported).

## 📄 License

MIT License
