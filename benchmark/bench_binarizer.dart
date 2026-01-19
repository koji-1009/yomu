import 'dart:typed_data';

import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';

/// Binarizer micro-benchmark.
///
/// Measures raw performance of the binarization step (LuminanceSource -> BitMatrix).
/// See `benchmark/README.md` for details.
void main() {
  // Simulate 4K image (3840 x 2160)
  const width = 3840;
  const height = 2160;
  final luminances = Uint8List(width * height);

  // Fill with dummy data
  for (var i = 0; i < luminances.length; i++) {
    luminances[i] = i & 0xFF;
  }

  print(
    'Benchmarking Binarizer on $width x$height (${width * height} pixels)...',
  );

  final stopwatch = Stopwatch()..start();
  const iterations = 10;

  for (var i = 0; i < iterations; i++) {
    final source = LuminanceSource(
      width: width,
      height: height,
      luminances: luminances,
    );
    final binarizer = Binarizer(source);
    binarizer.getBlackMatrix();
  }

  stopwatch.stop();
  final avg = stopwatch.elapsedMilliseconds / iterations;
  print('Average time: ${avg.toStringAsFixed(2)} ms per image');
}
