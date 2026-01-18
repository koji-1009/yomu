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

  group('Binarizer', () {
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
      final binarizer = Binarizer(source);
      final matrix = binarizer.getBlackMatrix();

      // Darker should be black (true)
      expect(matrix.get(0, 0), isTrue);
      expect(matrix.get(1, 0), isTrue);

      // Lighter should be white (false)
      expect(matrix.get(0, 1), isFalse);
      expect(matrix.get(1, 1), isFalse);
    });

    test('handles larger images with rolling buffer', () {
      // Create a 100x100 image (larger than min window size 40)
      // Vertical gradient: Top is black, Bottom is white.
      const width = 100;
      const height = 100;
      final ints = Int32List(width * height);

      for (var y = 0; y < height; y++) {
        final val = (y * 255 ~/ height); // 0..255
        final pixel = (0xFF << 24) | (val << 16) | (val << 8) | val;
        for (var x = 0; x < width; x++) {
          ints[y * width + x] = pixel;
        }
      }

      final source = RGBLuminanceSource(
        width: width,
        height: height,
        pixels: ints,
      );
      final matrix = Binarizer(source).getBlackMatrix();

      // Top rows should be black (low value)
      expect(matrix.get(50, 10), isTrue);

      // Bottom rows should be white (high value)
      expect(matrix.get(50, 90), isFalse);
    });
  });
}
