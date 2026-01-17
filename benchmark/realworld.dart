import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/yomu.dart';

/// **Real-world Throughput Benchmark**
///
/// **Purpose**:
/// Measures performance on varied, realistic images (camera capture, noise, rotation).
/// This simulates the actual user experience in a scanning session.
///
/// **Goal**:
/// - Validate stability and robustness against noise.
/// - Ensure consistent frame rates under load.
///
/// **Target**:
/// - **< 8.33ms (120fps)** average.
/// - No single frame spiking above 16.6ms (60fps) to avoid jank.
void main() {
  final dir = Directory('fixtures/realworld_images');

  if (!dir.existsSync()) {
    print('Real-world images not found.');
    print('Run: python3 scripts/generate_realworld_qr.py');
    exit(1);
  }

  print('=' * 60);
  print('📊 QYUTO REAL-WORLD BENCHMARK');
  print('=' * 60);

  const yomu = Yomu.qrOnly;
  final results = <String, List<int>>{};
  var successCount = 0;

  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  print('Processing ${files.length} images...\n');

  for (final file in files) {
    final fileBytes = file.readAsBytesSync();
    final decoded = img.decodePng(fileBytes);
    if (decoded == null) continue;

    final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
    final width = image.width;
    final height = image.height;

    // Convert to RGBA Uint8List for decode()
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final p = image.getPixel(i % width, i ~/ width);
      bytes[i * 4] = p.r.toInt();
      bytes[i * 4 + 1] = p.g.toInt();
      bytes[i * 4 + 2] = p.b.toInt();
      bytes[i * 4 + 3] = 0xFF;
    }

    // Local stopwatch for pure processing time (downsampling + detection + decoding)
    final stopwatch = Stopwatch()..start();
    var success = false;
    try {
      yomu.decode(bytes: bytes, width: width, height: height);
      success = true;
    } catch (_) {}
    stopwatch.stop();

    if (success) successCount++;

    final elapsed = stopwatch.elapsedMicroseconds;
    final sizeStr = '${width}x$height';
    results.putIfAbsent(sizeStr, () => []);
    results[sizeStr]!.add(elapsed);
  }

  print('📈 RESULTS BY RESOLUTION:');
  print('-' * 50);

  for (final entry in results.entries) {
    final resolution = entry.key;
    final times = entry.value;
    final avgMs = (times.reduce((a, b) => a + b) / times.length) / 1000;
    final status = avgMs < 8 ? '✅' : '⚠️';
    print(
      '${resolution.padRight(15)} | ${avgMs.toStringAsFixed(2)}ms | $status',
    );
  }

  print('-' * 50);
  print('Detection rate: $successCount/${files.length}');

  // Calculate total stats for benchmark_runner compatibility
  final allTimes = results.values.expand((element) => element).toList();
  final totalUs = allTimes.reduce((a, b) => a + b);
  final totalAvgMs = (totalUs / allTimes.length) / 1000.0;

  print('Total processed: ${files.length} images ($successCount success)');
  print('Total decode time: $totalUsµs');
  print('Average decode time: ${totalAvgMs.toStringAsFixed(3)}ms');
  print('');
}
