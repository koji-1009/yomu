import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/yomu.dart';

/// Comparative benchmark detector configurations.
///
/// Goal: Measure overhead of different configurations (e.g. qrOnly vs all).
/// See `benchmark/README.md` for details.
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

  // 3. Performance & Distortion
  print(
    '--- Extended Performance (fixtures/performance_test_images, distorted_images) ---',
  );
  final perfFiles = _getFiles('fixtures/performance_test_images');
  final distFiles = _getFiles('fixtures/distorted_images');
  final extendedFiles = [...perfFiles, ...distFiles];

  if (extendedFiles.isNotEmpty) {
    _runComparison(
      files: extendedFiles,
      configA: ('Yomu.qrOnly', Yomu.qrOnly), // Compare QR mode for these
      configB: ('Yomu.all', Yomu.all),
    );
  } else {
    print('No Extended images found.');
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
  final (metricsA, detailsA) = _bench(configA.$2, images);
  // Run B
  final (metricsB, detailsB) = _bench(configB.$2, images);

  _printCategoryReport(configA.$1, metricsA);
  _printCategoryReport(configB.$1, metricsB);

  // Report Summary
  print(
    '${configA.$1.padRight(20)} | Avg: ${metricsA['All']!.avg.toStringAsFixed(3)}ms | p95: ${metricsA['All']!.p95.toStringAsFixed(3)}ms',
  );
  print(
    '${configB.$1.padRight(20)} | Avg: ${metricsB['All']!.avg.toStringAsFixed(3)}ms | p95: ${metricsB['All']!.p95.toStringAsFixed(3)}ms',
  );

  final diff = metricsB['All']!.avg - metricsA['All']!.avg;
  final pct = (diff / metricsA['All']!.avg) * 100;
  final sign = diff > 0 ? '+' : '';
  print(
    'Overhead: $sign${diff.toStringAsFixed(3)}ms ($sign${pct.toStringAsFixed(1)}%)',
  );

  // Report Details
  print('\nDetailed Performance (ms):');
  print(
    '${'Image'.padRight(40)} | ${configA.$1.padRight(12)} | ${configB.$1.padRight(12)} | Diff',
  );
  print('-' * 90);

  for (final path in images.keys) {
    final name = path.split('/').last;
    final timeA = detailsA[path] ?? 0.0;
    final timeB = detailsB[path] ?? 0.0;
    final d = timeB - timeA;

    print(
      'DETAILS:${name.padRight(32)} | ${timeA.toStringAsFixed(3).padRight(12)} | ${timeB.toStringAsFixed(3).padRight(12)} | ${d > 0 ? '+' : ''}${d.toStringAsFixed(3)}',
    );
  }
}

class Metric {
  Metric(this.avg, this.p95);
  final double avg;
  final double p95;
}

void _printCategoryReport(String name, Map<String, Metric> metrics) {
  print('--- $name Metrics ---');
  for (final category in [
    'Standard',
    'Heavy',
    'HiRes',
    'Distorted',
    'Noise',
    'Edge',
  ]) {
    if (metrics.containsKey(category)) {
      final m = metrics[category]!;
      print(
        '  ${category.padRight(10)}: Avg ${m.avg.toStringAsFixed(3)}ms, p95 ${m.p95.toStringAsFixed(3)}ms',
      );
    }
  }
  print('');
}

String _categorize(String filename) {
  if (filename.contains('4k_')) {
    return 'HiRes';
  }
  if (filename.contains('rotation') || filename.contains('tilt')) {
    return 'Distorted';
  }
  if (filename.contains('noise')) {
    return 'Noise';
  }

  if (filename.contains('distorted') ||
      filename.contains('version_7') ||
      filename.contains('version_10') ||
      filename.contains('version_5') || // Assuming 5+ is heavy
      filename.contains('qr_version_5') ||
      filename.contains('qr_version_6')) {
    return 'Heavy';
  }
  if (filename.contains('edge_') || filename.contains('ec_level_h')) {
    return 'Edge';
  }
  return 'Standard';
}

const int _iterations =
    50; // Reduced iterations for extended tests to save time

(Map<String, Metric>, Map<String, double>) _bench(
  Yomu yomu,
  Map<String, (int, int, Uint8List)> images,
) {
  final details = <String, double>{};
  final categoryTimes = <String, List<double>>{
    'All': [],
    'Standard': [],
    'Heavy': [],
    'HiRes': [],
    'Distorted': [],
    'Noise': [],
    'Edge': [],
  };

  for (final entry in images.entries) {
    var imageTotalUs = 0;

    // Run iterations
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      try {
        yomu.decode(
          bytes: entry.value.$3,
          width: entry.value.$1,
          height: entry.value.$2,
        );
      } catch (_) {}
      sw.stop();

      final ms = sw.elapsedMicroseconds / 1000.0;
      imageTotalUs += sw.elapsedMicroseconds;

      final cat = _categorize(entry.key.split('/').last);
      categoryTimes[cat]!.add(ms);
      categoryTimes['All']!.add(ms);
    }

    // Calculate average for this specific image
    details[entry.key] = (imageTotalUs / _iterations) / 1000.0;
  }

  final metrics = <String, Metric>{};
  for (final entry in categoryTimes.entries) {
    if (entry.value.isEmpty) continue;
    final times = entry.value..sort();
    final avg = times.reduce((a, b) => a + b) / times.length;
    final p95Index = (times.length * 0.95).floor();
    final p95 = times[p95Index < times.length ? p95Index : times.length - 1];
    metrics[entry.key] = Metric(avg, p95);
  }

  return (metrics, details);
}

Uint8List _imageToBytes(img.Image image) {
  final p = image.convert(format: img.Format.uint8, numChannels: 4);
  return p.buffer.asUint8List();
}
