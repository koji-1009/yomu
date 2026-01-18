import 'dart:typed_data';

import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';

void main() {
  // Simulate 4K image (3840 x 2160)
  const width = 3840;
  const height = 2160;
  final pixels = Int32List(width * height);

  // Fill with random/dummy data to prevent optimization (though unlikely in Dart JIT for this)
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = i & 0xFFFFFFFF;
  }

  print(
    'Benchmarking Binarizer on $width x$height (${width * height} pixels)...',
  );

  final stopwatch = Stopwatch()..start();
  const iterations = 10;

  for (var i = 0; i < iterations; i++) {
    final source = RGBLuminanceSource(
      width: width,
      height: height,
      pixels: pixels,
    );
    final binarizer = Binarizer(source);
    binarizer.getBlackMatrix();
  }

  stopwatch.stop();
  final avg = stopwatch.elapsedMilliseconds / iterations;
  print('Average time: ${avg.toStringAsFixed(2)} ms per image');
}
