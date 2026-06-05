import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/yomu.dart';

/// Measures the latency cost of try-harder mode on failure paths and the
/// rescue cost of previously-undecodable images.
///
/// Worst cases (no code present) pay the full retry ladder; this tool
/// quantifies that cost against tryHarder=false.
void main() {
  const iterations = 30;

  final cases = <(String, YomuImage)>[
    ('blank_640x480', _blank(640, 480)),
    ('blank_fullhd', _blank(1920, 1080)),
    ('blank_4k', _blank(3840, 2160)),
    ('noise_fullhd', _noise(1920, 1080)),
    ('gradient_fullhd', _gradient(1920, 1080)),
  ];

  final fixtureCases = <(String, String)>[
    ('barcode (Yomu.all)', 'fixtures/barcode_images/ean13_product.png'),
    (
      'rescued: noise_0.10',
      'fixtures/unsupported_images/damaged_noise_0.10.png',
    ),
    (
      'rescued: persp_y_0.2',
      'fixtures/unsupported_images/perspective_y_0.2.png',
    ),
    (
      'rescued: persp_y_0.3',
      'fixtures/unsupported_images/perspective_y_0.3.png',
    ),
    ('rescued: dirt_0.30', 'fixtures/unsupported_images/damaged_dirt_0.30.png'),
    (
      'rescued: fullhd_200px',
      'fixtures/performance_test_images/fullhd_white_center_200px.png',
    ),
    ('unrescued: wavy_6.0', 'fixtures/unsupported_images/curved_wavy_6.0.png'),
    (
      'unrescued: persp_x_0.4',
      'fixtures/unsupported_images/perspective_x_0.4.png',
    ),
  ];

  const fast = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.all,
    tryHarder: false,
  );
  const hard = Yomu(enableQRCode: true, barcodeScanner: BarcodeScanner.all);

  print('--- Failure-path latency (Yomu.all, avg of $iterations runs) ---');
  print(
    '${'case'.padRight(24)} | ${'fast-only'.padRight(12)} | ${'tryHarder'.padRight(12)} | overhead',
  );

  void report(String name, YomuImage image) {
    final fastMs = _bench(fast, image, iterations);
    final hardMs = _bench(hard, image, iterations);
    print(
      '${name.padRight(24)} | ${'${fastMs.toStringAsFixed(2)}ms'.padRight(12)} | '
      '${'${hardMs.toStringAsFixed(2)}ms'.padRight(12)} | '
      '+${(hardMs - fastMs).toStringAsFixed(2)}ms',
    );
  }

  for (final (name, image) in cases) {
    report(name, image);
  }
  for (final (name, path) in fixtureCases) {
    report(name, _load(path));
  }
}

double _bench(Yomu yomu, YomuImage image, int iterations) {
  // Warmup
  for (var i = 0; i < 3; i++) {
    try {
      yomu.decode(image);
    } catch (_) {}
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    try {
      yomu.decode(image);
    } catch (_) {}
  }
  sw.stop();
  return sw.elapsedMicroseconds / iterations / 1000.0;
}

YomuImage _blank(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = 255;
  }
  return YomuImage.rgba(bytes: bytes, width: width, height: height);
}

YomuImage _noise(int width, int height) {
  final random = Random(42);
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    final v = random.nextInt(256);
    bytes[i] = v;
    bytes[i + 1] = v;
    bytes[i + 2] = v;
    bytes[i + 3] = 255;
  }
  return YomuImage.rgba(bytes: bytes, width: width, height: height);
}

YomuImage _gradient(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final v = (x * 255) ~/ width;
      bytes[offset] = v;
      bytes[offset + 1] = v;
      bytes[offset + 2] = v;
      bytes[offset + 3] = 255;
    }
  }
  return YomuImage.rgba(bytes: bytes, width: width, height: height);
}

YomuImage _load(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final converted = image.convert(format: img.Format.uint8, numChannels: 4);
  return YomuImage.rgba(
    bytes: converted.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
}
