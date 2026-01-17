import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';

void main() {
  group('RGBLuminanceSource', () {
    test('converts RGB to luminance correctly', () {
      // 2x2 image
      // Red, Green
      // Blue, White
      // R: 255,0,0 -> Y = .299*255 ~ 76
      // G: 0,255,0 -> Y = .587*255 ~ 150
      // B: 0,0,255 -> Y = .114*255 ~ 29
      // W: 255,255,255 -> 255

      // Pixels setup...
      // 2 pixels wide, 2 pixels high. raw RGB.

      // Pixels setup...
      // Wait, RGBLuminanceSource usually takes int[] of 0xAARRGGBB or similar.
      // Let's assume we pass int array (ARGB).
      // If input is bytes, we need to convert.
      // Let's allow passing Uint8List (RGBA) or Int32List.
      // For simplicity in test, let's construct Int32List.

      // 0xFFFF0000 (Red), 0xFF00FF00 (Green)
      // 0xFF0000FF (Blue), 0xFFFFFFFF (White)
      final ints = Int32List.fromList([
        0xFFFF0000,
        0xFF00FF00,
        0xFF0000FF,
        0xFFFFFFFF,
      ]);

      final lum = RGBLuminanceSource(width: 2, height: 2, pixels: ints);
      final row0 = lum.getRow(0, null);

      // Allow some rounding differences
      expect(row0[0], closeTo(76, 1));
      expect(row0[1], closeTo(150, 1));
    });
  });

  group('GlobalHistogramBinarizer', () {
    test('binarizes based on histogram', () {
      // 50% dark gray, 50% light gray
      // Threshold should be middle.
      // 0xFF404040 (64)
      // 0xFFC0C0C0 (192)
      final ints = Int32List(4);
      ints[0] = 0xFF404040;
      ints[1] = 0xFF404040;
      ints[2] = 0xFFC0C0C0;
      ints[3] = 0xFFC0C0C0; // 2x2 image

      final source = RGBLuminanceSource(width: 2, height: 2, pixels: ints);
      final binarizer = GlobalHistogramBinarizer(source);
      final matrix = binarizer.getBlackMatrix();

      // Darker should be black (true)
      expect(matrix.get(x: 0, y: 0), isTrue);
      expect(matrix.get(x: 1, y: 0), isTrue);

      // Lighter should be white (false)
      expect(matrix.get(x: 0, y: 1), isFalse);
      expect(matrix.get(x: 1, y: 1), isFalse);
    });
  });
}
