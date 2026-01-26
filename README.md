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

> **Note**: To run the development scripts and benchmarks, you need [uv](https://github.com/astral-sh/uv) installed.

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

### Barcodes Only

```dart
// For 1D barcode only scanning
final result = Yomu.barcodeOnly.decode(YomuImage.rgba(
  bytes: imageBytes,
  width: width,
  height: height,
));
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

To use Yomu with the `camera` package in Flutter:

```dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yomu/yomu.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ScannerScreen());
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  DecoderResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _error = 'Camera permission denied';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No cameras found';
        });
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() {});

      await controller.startImageStream(_processImage);
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Run decoding in a separate isolate to avoid blocking the UI thread
      final result = await compute(_decode, image);

      if (mounted && result != null) {
        setState(() {
          _result = result;
        });
      }
    } catch (e) {
      // Ignore decoding errors (no QR code found)
    } finally {
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('QR Scanner')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_result != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _result!.text,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Top-level function for isolate
DecoderResult? _decode(CameraImage image) {
  try {
    final width = image.width;
    final height = image.height;
    final yomuImage = switch (image.format.group) {
      ImageFormatGroup.yuv420 || ImageFormatGroup.nv21 => YomuImage.yuv420(
        yBytes: image.planes[0].bytes,
        width: width,
        height: height,
        yRowStride: image.planes[0].bytesPerRow,
      ),
      ImageFormatGroup.bgra8888 => YomuImage.bgra(
        bytes: image.planes[0].bytes,
        width: width,
        height: height,
        rowStride: image.planes[0].bytesPerRow,
      ),
      _ => null,
    };

    if (yomuImage == null) {
      return null;
    }

    final result = Yomu.all.decode(yomuImage);
    return result;
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

| Method             | Description                             |
| ------------------ | --------------------------------------- |
| `decode(image)`    | Decode single QR/barcode from YomuImage |
| `decodeAll(image)` | Decode all QR codes from YomuImage      |

### `YomuImage` Class

A platform-agnostic container for image data.

| Factory                 | Description                                |
| ----------------------- | ------------------------------------------ |
| `YomuImage.rgba()`      | Create from RGBA bytes (4 bytes/pixel)     |
| `YomuImage.bgra()`      | Create from BGRA bytes (4 bytes/pixel)     |
| `YomuImage.grayscale()` | Create from grayscale bytes (1 byte/pixel) |
| `YomuImage.yuv420()`    | Create from Y-plane of YUV420 camera image |

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
