import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pool/pool.dart';
import 'package:yomu/yomu.dart';

/// Comparative benchmark detector configurations.
///
/// Goal: Measure overhead of different configurations (e.g. qrOnly vs all).
/// See `benchmark/README.md` for details.
void main() async {
  print('================================================');
  print('📊 YOMU COMPARATIVE BENCHMARK');
  print('================================================\n');

  // 1. Run QR Standard (Pure)
  // Now strictly reads from fixtures/qr_images which contains only Standard files.
  print('--- QR Code Standard Performance (fixtures/qr_images) ---');
  final standardFiles = _getFiles('fixtures/qr_images');

  if (standardFiles.isNotEmpty) {
    await _runComparison(
      files: standardFiles,
      configA: ('Yomu.qrOnly', Yomu.qrOnly),
      configB: ('Yomu.all', Yomu.all),
    );
  } else {
    print('No Standard QR images found.');
  }
  print('');

  // 2. Run QR Stress (Complex, HiRes, Distorted, Edge, Noise)
  // Aggregates all other stress-test directories.
  print('--- QR Code Stress Performance (Complex, HiRes, Distorted) ---');
  final complexFiles = _getFiles('fixtures/qr_complex_images');
  final perfFiles = _getFiles('fixtures/performance_test_images');
  final distFiles = _getFiles('fixtures/distorted_images');

  final stressFiles = [...complexFiles, ...perfFiles, ...distFiles];

  if (stressFiles.isNotEmpty) {
    await _runComparison(
      files: stressFiles,
      configA: ('Yomu.qrOnly', Yomu.qrOnly),
      configB: ('Yomu.all', Yomu.all),
    );
  } else {
    print('No Stress images found.');
  }
  print('');

  // 3. Barcode Performance
  print('--- Barcode Performance (fixtures/barcode_images) ---');
  final barcodeFiles = _getFiles('fixtures/barcode_images');
  if (barcodeFiles.isNotEmpty) {
    await _runComparison(
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

Future<void> _runComparison({
  required List<File> files,
  required (String, Yomu) configA,
  required (String, Yomu) configB,
}) async {
  // Pre-load images
  final images = <String, (int, int, Uint8List)>{};
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final image = img.decodePng(bytes)!;
    final pixels = _imageToBytes(image);
    images[file.path] = (image.width, image.height, pixels);
  }

  // Run A
  final (metricsA, detailsA) = await _bench(configA.$2, images);
  // Run B
  final (metricsB, detailsB) = await _bench(configB.$2, images);

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
    'Complex',
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
  if (filename.contains('rotation') ||
      filename.contains('tilt') ||
      filename.contains('distorted') ||
      filename.contains('blur') ||
      filename.contains('curved') ||
      filename.contains('damaged')) {
    return 'Distorted';
  }
  if (filename.contains('noise')) {
    return 'Noise';
  }

  if (filename.contains('version_7') ||
      filename.contains('version_10') ||
      filename.contains('version_5') || // Assuming 5+ is complex
      filename.contains('qr_version_5') ||
      filename.contains('qr_version_6')) {
    return 'Complex';
  }
  if (filename.contains('edge_') || filename.contains('ec_level_h')) {
    return 'Edge';
  }
  return 'Standard';
}

const int _iterations = 250;

// Isolate worker parameters
typedef _BenchTask = ({
  int width,
  int height,
  Uint8List pixels,
  int iterations,
  bool enableQRCode,
  bool enableBarcode,
  String filename,
});

class _BenchResult {
  _BenchResult({required this.timesMs, required this.filename});
  final List<double> timesMs;
  final String filename;
}

// Top-level function for Isolate execution
Future<_BenchResult> _benchImageIsolate(_BenchTask task) async {
  final yomu = Yomu(
    enableQRCode: task.enableQRCode,
    barcodeScanner: task.enableBarcode
        ? BarcodeScanner.all
        : BarcodeScanner.none,
  );

  final times = <double>[];

  for (var i = 0; i < task.iterations; i++) {
    final sw = Stopwatch()..start();
    try {
      yomu.decode(
        YomuImage.rgba(
          bytes: task.pixels,
          width: task.width,
          height: task.height,
        ),
      );
    } catch (_) {}
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1000.0);
  }

  return _BenchResult(timesMs: times, filename: task.filename);
}

Future<(Map<String, Metric>, Map<String, double>)> _bench(
  Yomu yomu,
  Map<String, (int, int, Uint8List)> images,
) async {
  final details = <String, double>{};
  final categoryTimes = <String, List<double>>{
    'All': [],
    'Standard': [],
    'Complex': [],
    'HiRes': [],
    'Distorted': [],
    'Noise': [],
    'Edge': [],
  };

  // Get optimal parallelism based on CPU cores
  final cpuCount = Platform.numberOfProcessors;
  final maxConcurrent = cpuCount > 1 ? cpuCount - 1 : 1; // Leave 1 core free

  print('  Using $maxConcurrent concurrent workers (CPU cores: $cpuCount)');

  // Create pool to limit concurrent Isolate execution
  // This prevents OS scheduler overload and stabilizes measurements
  final pool = Pool(maxConcurrent);

  try {
    // Submit all tasks to pool
    final tasks = <Future<_BenchResult>>[];
    final entries = images.entries.toList();

    for (final entry in entries) {
      final task = (
        width: entry.value.$1,
        height: entry.value.$2,
        pixels: entry.value.$3,
        iterations: _iterations,
        enableQRCode: yomu.enableQRCode,
        enableBarcode: !yomu.barcodeScanner.isEmpty,
        filename: entry.key,
      );

      // Pool.withResource limits concurrent execution while Isolate.run handles isolation
      tasks.add(
        pool.withResource(() => Isolate.run(() => _benchImageIsolate(task))),
      );
    }

    // Wait for all tasks to complete
    final results = await Future.wait(tasks);

    // Aggregate results
    for (final result in results) {
      final cat = _categorize(result.filename.split('/').last);

      // Add all times to category
      categoryTimes[cat]!.addAll(result.timesMs);
      categoryTimes['All']!.addAll(result.timesMs);

      // Calculate average for this specific image
      final avg =
          result.timesMs.reduce((a, b) => a + b) / result.timesMs.length;
      details[result.filename] = avg;
    }
  } finally {
    await pool.close();
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
