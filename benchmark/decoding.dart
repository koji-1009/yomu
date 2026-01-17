import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/yomu.dart';

/// **Comparative Benchmark**
///
/// **Purpose**:
/// Compares performance overhead between different detector configurations.
///
/// **Modes**:
/// 1. **QR Images**: Compare `Yomu.qrOnly` vs `Yomu.all`
/// 2. **Barcode Images**: Compare `Yomu.barcodeOnly` vs `Yomu.all`
void main() {
  print('================================================');
  print('📊 YOMU COMPARATIVE BENCHMARK');
  print('================================================\n');

  // 1. QR Performance
  print('--- QR Code Performance (fixtures/qr_images) ---');
  final qrFiles = _getFiles('fixtures/qr_images');
  if (qrFiles.isNotEmpty) {
    _runComparison(
      files: qrFiles,
      configA: ('Yomu.qrOnly', Yomu.qrOnly),
      configB: ('Yomu.all', Yomu.all),
    );
  } else {
    print('No QR images found.');
  }
  print('');

  // 2. Barcode Performance
  print('--- Barcode Performance (fixtures/barcode_images) ---');
  final barcodeFiles = _getFiles('fixtures/barcode_images');
  if (barcodeFiles.isNotEmpty) {
    _runComparison(
      files: barcodeFiles,
      configA: ('Yomu.barcodeOnly', Yomu.barcodeOnly),
      configB: ('Yomu.all', Yomu.all),
    );
  } else {
    print('No Barcode images found.');
  }
}

List<File> _getFiles(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .where((f) => !f.path.contains('multi_qr'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void _runComparison({
  required List<File> files,
  required (String, Yomu) configA,
  required (String, Yomu) configB,
}) {
  // Pre-load images
  final images = <String, (int, int, Uint8List)>{};
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final image = img.decodePng(bytes)!;
    final pixels = _imageToBytes(image);
    images[file.path] = (image.width, image.height, pixels);
  }

  // Warmup both
  for (var i = 0; i < 5; i++) {
    for (final entry in images.values) {
      try {
        configA.$2.decode(bytes: entry.$3, width: entry.$1, height: entry.$2);
        configB.$2.decode(bytes: entry.$3, width: entry.$1, height: entry.$2);
      } catch (_) {}
    }
  }

  // Run A
  final resultA = _bench(configA.$2, images);
  // Run B
  final resultB = _bench(configB.$2, images);

  // Report
  print(
    '${configA.$1.padRight(20)} | Avg: ${resultA.toStringAsFixed(3)}ms | Total: ${(resultA * files.length).toStringAsFixed(1)}ms',
  );
  print(
    '${configB.$1.padRight(20)} | Avg: ${resultB.toStringAsFixed(3)}ms | Total: ${(resultB * files.length).toStringAsFixed(1)}ms',
  );

  final diff = resultB - resultA;
  final pct = (diff / resultA) * 100;
  final sign = diff > 0 ? '+' : '';
  print(
    'Overhead: $sign${diff.toStringAsFixed(3)}ms ($sign${pct.toStringAsFixed(1)}%)',
  );
}

double _bench(Yomu yomu, Map<String, (int, int, Uint8List)> images) {
  var totalUs = 0;
  for (final entry in images.values) {
    final sw = Stopwatch()..start();
    try {
      yomu.decode(bytes: entry.$3, width: entry.$1, height: entry.$2);
    } catch (_) {}
    sw.stop();
    totalUs += sw.elapsedMicroseconds;
  }
  return (totalUs / images.length) / 1000.0;
}

Uint8List _imageToBytes(img.Image image) {
  final p = image.convert(format: img.Format.uint8, numChannels: 4);
  return p.buffer.asUint8List();
}
