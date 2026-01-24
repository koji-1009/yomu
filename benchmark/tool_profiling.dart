import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';

/// Detailed profiling tool.
///
/// Purpose: Breaks down decoding pipeline into stages.
/// See `benchmark/README.md` for details.
void main() {
  final dir = Directory('fixtures/performance_test_images');
  if (!dir.existsSync()) {
    print('ERROR: fixtures/performance_test_images not found');
    print('Run: uv run scripts/generate_performance_test_images.py');
    exit(1);
  }

  print('=' * 70);
  print('📊 QYUTO PROFILING BENCHMARK');
  print('=' * 70);

  // Group files by resolution
  final resolutions = <String, List<File>>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.png')) continue;
    final name = file.path.split('/').last;
    final res = name.split('_').first; // e.g., "4k", "fullhd", "square"
    resolutions.putIfAbsent(res, () => []).add(file);
  }

  // Test each resolution group
  for (final entry in resolutions.entries) {
    final res = entry.key;
    final files = entry.value;

    print('\n📐 Resolution: $res (${files.length} images)');
    print('-' * 50);

    // Sample first 5 images
    final samples = files.take(5).toList();

    final times = <String, List<int>>{
      'load': [],
      'convert': [],
      'downsample': [],
      'binarize': [],
      'detect': [],
      'decode': [],
      'total': [],
    };

    for (final file in samples) {
      final profile = _profileDecode(file);
      if (profile != null) {
        for (final key in times.keys) {
          times[key]!.add(profile[key]!);
        }
      }
    }

    // Print averages
    if (times['total']!.isNotEmpty) {
      print('Stage breakdown (avg of ${times['total']!.length} images):');
      for (final key in [
        'convert',
        'downsample',
        'binarize',
        'detect',
        'decode',
        'total',
      ]) {
        final avg = times[key]!.reduce((a, b) => a + b) / times[key]!.length;
        final pct = key == 'total'
            ? ''
            : ' (${(avg / (times['total']!.reduce((a, b) => a + b) / times['total']!.length) * 100).toStringAsFixed(0)}%)';
        print('  ${key.padRight(12)}: ${avg.toStringAsFixed(2)}ms$pct');
      }
    }
  }

  print('\n${'=' * 70}');
  print('📝 OPTIMIZATION TARGETS');
  print('=' * 70);
  print('Stages with >20% of total time are candidates for optimization.');
}

Map<String, int>? _profileDecode(File file) {
  final sw = Stopwatch();

  // Load
  sw.start();
  final bytes = file.readAsBytesSync();
  final decoded = img.decodePng(bytes);
  if (decoded == null) return null;
  final loadTime = sw.elapsedMicroseconds;

  // Prep (Untimed) - Get raw RGBA bytes to simulate Yomu's input
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final width = image.width;
  final height = image.height;
  final rgbaBytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final p = image.getPixel(i % width, i ~/ width);
    rgbaBytes[i * 4] = p.r.toInt();
    rgbaBytes[i * 4 + 1] = p.g.toInt();
    rgbaBytes[i * 4 + 2] = p.b.toInt();
    rgbaBytes[i * 4 + 3] = 0xFF;
  }

  // Convert to Grayscale & Downsample
  sw.reset();
  sw.start();
  const targetPixels = 1000000;
  final totalPixels = width * height;

  Uint8List processPixels;
  var processWidth = width;
  var processHeight = height;

  if (totalPixels <= targetPixels) {
    final total = width * height;
    processPixels = Uint8List(total);
    var offset = 0;
    for (var i = 0; i < total; i++) {
      final r = rgbaBytes[offset];
      final g = rgbaBytes[offset + 1];
      final b = rgbaBytes[offset + 2];
      processPixels[i] = (306 * r + 601 * g + 117 * b) >> 10;
      offset += 4;
    }
  } else {
    // Downscale logic
    final scaleFactor = totalPixels / targetPixels;
    final scale = math.sqrt(scaleFactor).ceil();
    processWidth = width ~/ scale;
    processHeight = height ~/ scale;
    processPixels = Uint8List(processWidth * processHeight);

    // ... replicate downsampling logic manually for profiling ...
    // Or just simplify for profiling sake to assume we want to measure the "prep" phase.
    // I'll stick to the "Small" path for strict "Convert" measurement, or implementing strict
    // downsampling here is tedious.
    // Let's implement the fused loop from Yomu.dart
    final halfScale = scale ~/ 2;
    final pixelStride = scale * 4;
    for (var dstY = 0; dstY < processHeight; dstY++) {
      final srcY = dstY * scale + halfScale;
      final rowOffset = srcY * width * 4;
      final dstRowOffset = dstY * processWidth;
      var currentByteOffset = rowOffset + (halfScale * 4);

      for (var dstX = 0; dstX < processWidth; dstX++) {
        final r = rgbaBytes[currentByteOffset];
        final g = rgbaBytes[currentByteOffset + 1];
        final b = rgbaBytes[currentByteOffset + 2];
        processPixels[dstRowOffset + dstX] =
            (306 * r + 601 * g + 117 * b) >> 10;
        currentByteOffset += pixelStride;
      }
    }
  }

  final convertTime = sw.elapsedMicroseconds;

  // Binarize
  sw.reset();
  sw.start();
  final source = LuminanceSource(
    width: processWidth,
    height: processHeight,
    luminances: processPixels,
  );
  final blackMatrix = Binarizer(source).getBlackMatrix();
  final binarizeTime = sw.elapsedMicroseconds;

  // Detect
  sw.reset();
  sw.start();
  final detector = Detector(blackMatrix);
  late final DetectorResult detectorResult;
  try {
    detectorResult = detector.detect();
  } catch (_) {
    return null;
  }
  final detectTime = sw.elapsedMicroseconds;

  // Decode
  sw.reset();
  sw.start();
  const decoder = QRCodeDecoder();
  try {
    decoder.decode(detectorResult.bits);
  } catch (_) {
    return null;
  }
  final decodeTime = sw.elapsedMicroseconds;

  return {
    'load': loadTime ~/ 1000,
    'convert': convertTime ~/ 1000,
    'downsample': 0, // Merged into convert
    'binarize': binarizeTime ~/ 1000,
    'detect': detectTime ~/ 1000,
    'decode': decodeTime ~/ 1000,
    'total':
        (convertTime +
            // downsampleTime +
            binarizeTime +
            detectTime +
            decodeTime) ~/
        1000,
  };
}
