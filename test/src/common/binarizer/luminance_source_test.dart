import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';

void main() {
  group('LuminanceSource', () {
    test('creates source with correct dimensions', () {
      final luminances = Uint8List(100);
      final source = LuminanceSource(
        width: 10,
        height: 10,
        luminances: luminances,
      );
      expect(source.width, 10);
      expect(source.height, 10);
    });

    test('getRow returns raw luminance values', () {
      // Create a 3x1 image
      final luminances = Uint8List.fromList([
        128, // Gray
        255, // White
        0, // Black
      ]);
      final source = LuminanceSource(
        width: 3,
        height: 1,
        luminances: luminances,
      );
      final row = source.getRow(0, null);

      expect(row[0], 128);
      expect(row[1], 255);
      expect(row[2], 0);
    });

    test('getRow reuses provided buffer if large enough', () {
      final luminances = Uint8List.fromList([255, 0]);
      final source = LuminanceSource(
        width: 2,
        height: 1,
        luminances: luminances,
      );
      final buffer = Uint8List(10);
      final result = source.getRow(0, buffer);

      expect(result, same(buffer));
      expect(result[0], 255);
      expect(result[1], 0);
    });

    test('getRow throws for invalid row', () {
      final luminances = Uint8List(9);
      final source = LuminanceSource(
        width: 3,
        height: 3,
        luminances: luminances,
      );

      expect(() => source.getRow(-1, null), throwsRangeError);
      expect(() => source.getRow(3, null), throwsRangeError);
    });

    test('matrix returns full copy of luminance data', () {
      final luminances = Uint8List.fromList([
        128, 255, // Row 0
        0, 64, // Row 1
      ]);
      final source = LuminanceSource(
        width: 2,
        height: 2,
        luminances: luminances,
      );
      final matrix = source.luminances;

      expect(matrix.length, 4);
      expect(matrix[0], 128);
      expect(matrix[1], 255);
      expect(matrix[2], 0);
      expect(matrix[3], 64);

      // Ensure it's a reference (performance optimization)
      expect(matrix, same(luminances));
    });
  });

  group('Image Conversion Helpers', () {
    test('int32ToGrayscale converts colors correctly', () {
      final pixels = Int32List.fromList([
        0xFFFF0000, // Red
        0xFF00FF00, // Green
        0xFF0000FF, // Blue
        0xFFFFFFFF, // White
        0xFF000000, // Black
      ]);
      final luminances = int32ToGrayscale(pixels, 5, 1);

      // Calculations:
      // R: 0.299 * 255 = 76
      // G: 0.587 * 255 = 149
      // B: 0.114 * 255 = 29

      expect(luminances[0], closeTo(76, 1));
      expect(luminances[1], closeTo(149, 1));
      expect(luminances[2], closeTo(29, 1));
      expect(luminances[3], 255);
      expect(luminances[4], 0);
    });

    test('rgbaToGrayscale converts bytes correctly', () {
      // RGBA bytes
      final bytes = Uint8List.fromList([
        255, 0, 0, 255, // Red
        0, 255, 0, 255, // Green
        0, 0, 255, 255, // Blue
      ]);
      final luminances = rgbaToGrayscale(bytes, 3, 1);

      expect(luminances[0], closeTo(76, 1));
      expect(luminances[1], closeTo(149, 1));
      expect(luminances[2], closeTo(29, 1));
    });
  });
}
