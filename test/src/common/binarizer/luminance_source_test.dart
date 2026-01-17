import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';

void main() {
  group('RGBLuminanceSource', () {
    test('creates source with correct dimensions', () {
      final pixels = Int32List(100);
      final source = RGBLuminanceSource(width: 10, height: 10, pixels: pixels);
      expect(source.width, 10);
      expect(source.height, 10);
    });

    test('getRow returns correct luminance for grayscale', () {
      // Create a 3x1 image with gray pixels (R=G=B)
      final pixels = Int32List.fromList([
        0xFF808080, // Gray 128
        0xFFFFFFFF, // White 255
        0xFF000000, // Black 0
      ]);
      final source = RGBLuminanceSource(width: 3, height: 1, pixels: pixels);
      final row = source.getRow(0, null);

      expect(row[0], 128);
      expect(row[1], 255);
      expect(row[2], 0);
    });

    test('getRow returns correct luminance for color', () {
      // Create a pixel with R=255, G=0, B=0 (pure red)
      final pixels = Int32List.fromList([0xFFFF0000]);
      final source = RGBLuminanceSource(width: 1, height: 1, pixels: pixels);
      final row = source.getRow(0, null);

      // Luminance = (306 * 255 + 601 * 0 + 117 * 0) >> 10 = 76
      expect(row[0], closeTo(76, 1));
    });

    test('getRow reuses provided buffer if large enough', () {
      final pixels = Int32List.fromList([0xFFFFFFFF, 0xFF000000]);
      final source = RGBLuminanceSource(width: 2, height: 1, pixels: pixels);
      final buffer = Uint8List(10);
      final result = source.getRow(0, buffer);

      expect(result, same(buffer));
      expect(result[0], 255);
      expect(result[1], 0);
    });

    test('getRow creates new buffer if provided is too small', () {
      final pixels = Int32List.fromList([0xFFFFFFFF, 0xFF000000]);
      final source = RGBLuminanceSource(width: 2, height: 1, pixels: pixels);
      final buffer = Uint8List(1);
      final result = source.getRow(0, buffer);

      expect(result, isNot(same(buffer)));
      expect(result.length, 2);
    });

    test('getRow throws for invalid row', () {
      final pixels = Int32List(9);
      final source = RGBLuminanceSource(width: 3, height: 3, pixels: pixels);

      expect(() => source.getRow(-1, null), throwsArgumentError);
      expect(() => source.getRow(3, null), throwsArgumentError);
    });

    test('matrix returns full luminance data', () {
      final pixels = Int32List.fromList([
        0xFF808080, 0xFFFFFFFF, // Row 0
        0xFF000000, 0xFF404040, // Row 1
      ]);
      final source = RGBLuminanceSource(width: 2, height: 2, pixels: pixels);
      final matrix = source.matrix;

      expect(matrix.length, 4);
      expect(matrix[0], 128); // Gray
      expect(matrix[1], 255); // White
      expect(matrix[2], 0); // Black
      expect(matrix[3], 64); // Dark gray
    });

    test('matrix handles color pixels correctly', () {
      // Pure green pixel
      final pixels = Int32List.fromList([0xFF00FF00]);
      final source = RGBLuminanceSource(width: 1, height: 1, pixels: pixels);
      final matrix = source.matrix;

      // Luminance = (306 * 0 + 601 * 255 + 117 * 0) >> 10 = 149
      expect(matrix[0], closeTo(149, 1));
    });

    test('handles large images', () {
      const width = 100;
      const height = 100;
      final pixels = Int32List(width * height);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = 0xFFFFFFFF; // All white
      }

      final source = RGBLuminanceSource(
        width: width,
        height: height,
        pixels: pixels,
      );
      final matrix = source.matrix;

      expect(matrix.length, width * height);
      expect(matrix[0], 255);
      expect(matrix[matrix.length - 1], 255);
    });
  });
}
