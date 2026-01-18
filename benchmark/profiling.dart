import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';

/// **Detailed Profiling Tool**
///
/// **Purpose**:
/// Breaks down the decoding pipeline into stages (Load, Convert, Downsample, Binarize, Detect, Decode)
/// to identify bottlenecks.
///
/// **Usage**:
/// Run manually when `realworld.dart` or `decoding_benchmark.dart` shows regression.
/// `dart run benchmark/profiling.dart`
void main() {
  final dir = Directory('fixtures/realworld_images');
  if (!dir.existsSync()) {
    print('ERROR: fixtures/realworld_images not found');
    print('Run: uv run scripts/generate_realworld_qr.py');
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

  // Convert to pixels
  sw.reset();
  sw.start();
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final width = image.width;
  final height = image.height;

  final pixels = Int32List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      pixels[y * width + x] =
          (0xFF << 24) | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
  }
  final convertTime = sw.elapsedMicroseconds;

  // Downsample (if needed)
  sw.reset();
  sw.start();
  const targetPixels = 1000000;
  final totalPixels = width * height;

  var processPixels = pixels;
  var processWidth = width;
  var processHeight = height;

  if (totalPixels > targetPixels) {
    final scaleFactor = totalPixels / targetPixels;
    final scale = math.sqrt(scaleFactor).ceil();
    if (scale >= 2) {
      processWidth = width ~/ scale;
      processHeight = height ~/ scale;
      processPixels = _downsamplePixels(pixels, width, height, scale);
    }
  }
  final downsampleTime = sw.elapsedMicroseconds;

  // Binarize
  sw.reset();
  sw.start();
  final source = RGBLuminanceSource(
    width: processWidth,
    height: processHeight,
    pixels: processPixels,
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
  final decoder = QRCodeDecoder();
  try {
    decoder.decode(detectorResult.bits);
  } catch (_) {
    return null;
  }
  final decodeTime = sw.elapsedMicroseconds;

  return {
    'load': loadTime ~/ 1000,
    'convert': convertTime ~/ 1000,
    'downsample': downsampleTime ~/ 1000,
    'binarize': binarizeTime ~/ 1000,
    'detect': detectTime ~/ 1000,
    'decode': decodeTime ~/ 1000,
    'total':
        (convertTime +
            downsampleTime +
            binarizeTime +
            detectTime +
            decodeTime) ~/
        1000,
  };
}

Int32List _downsamplePixels(
  Int32List src,
  int srcWidth,
  int srcHeight,
  int scale,
) {
  final dstWidth = srcWidth ~/ scale;
  final dstHeight = srcHeight ~/ scale;
  final result = Int32List(dstWidth * dstHeight);
  final halfScale = scale ~/ 2;

  for (var dstY = 0; dstY < dstHeight; dstY++) {
    final srcY = dstY * scale + halfScale;
    final clampedSrcY = srcY >= srcHeight ? srcHeight - 1 : srcY;
    final srcOffset = clampedSrcY * srcWidth;
    final dstOffset = dstY * dstWidth;

    for (var dstX = 0; dstX < dstWidth; dstX++) {
      final srcX = dstX * scale + halfScale;
      final clampedSrcX = srcX >= srcWidth ? srcWidth - 1 : srcX;
      result[dstOffset + dstX] = src[srcOffset + clampedSrcX];
    }
  }
  return result;
}
