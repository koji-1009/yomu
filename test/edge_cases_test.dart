// Edge case tests for Yomu library
// Tests malformed inputs, extreme sizes, and error handling

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/yomu.dart';

Uint8List _pixelsToBytes(int width, int height, int color) {
  final bytes = Uint8List(width * height * 4);
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = 0xFF;
  }
  return bytes;
}

void main() {
  group('Edge Cases', () {
    group('Yomu input validation', () {
      late Yomu yomu;

      setUp(() {
        yomu = Yomu.qrOnly;
      });

      test('throws on empty byte array', () {
        expect(
          () => yomu.decode(bytes: Uint8List(0), width: 0, height: 0),
          throwsA(anything),
        );
      });

      test('throws on insufficient bytes', () {
        // 100 bytes but claim 20x20 = 1600 bytes needed
        final bytes = Uint8List(100);
        expect(
          () => yomu.decode(bytes: bytes, width: 20, height: 20),
          throwsA(anything),
        );
      });

      test('throws when no QR code present', () {
        // All white image
        final bytes = _pixelsToBytes(100, 100, 0xFFFFFF);
        expect(
          () => yomu.decode(bytes: bytes, width: 100, height: 100),
          throwsException,
        );
      });

      test('decodeAll returns empty list for no QR codes', () {
        final bytes = _pixelsToBytes(100, 100, 0xFFFFFF);
        final results = yomu.decodeAll(bytes: bytes, width: 100, height: 100);
        expect(results, isEmpty);
      });
    });

    group('BitMatrix edge cases', () {
      test('handles 1x1 matrix', () {
        final matrix = BitMatrix(width: 1, height: 1);
        expect(matrix.get(x: 0, y: 0), isFalse);
        matrix.set(x: 0, y: 0);
        expect(matrix.get(x: 0, y: 0), isTrue);
        matrix.flip(x: 0, y: 0);
        expect(matrix.get(x: 0, y: 0), isFalse);
      });

      test('handles large matrix', () {
        final matrix = BitMatrix(width: 1000, height: 1000);
        matrix.set(x: 999, y: 999);
        expect(matrix.get(x: 999, y: 999), isTrue);
        expect(matrix.get(x: 0, y: 0), isFalse);
      });
    });

    group('LuminanceSource edge cases', () {
      test('handles very small image', () {
        final pixels = Int32List(4);
        pixels[0] = 0xFF000000; // Black
        pixels[1] = 0xFFFFFFFF; // White
        pixels[2] = 0xFFFFFFFF; // White
        pixels[3] = 0xFF000000; // Black

        final source = RGBLuminanceSource(width: 2, height: 2, pixels: pixels);
        expect(source.width, 2);
        expect(source.height, 2);
        // Black pixel should have low luminance
        expect(source.getRow(0, null)[0], lessThan(50));
        // White pixel should have high luminance
        expect(source.getRow(0, null)[1], greaterThan(200));
      });

      test('handles grayscale values correctly', () {
        final pixels = Int32List(3);
        // Pure red, green, blue
        pixels[0] = 0xFFFF0000; // Red
        pixels[1] = 0xFF00FF00; // Green
        pixels[2] = 0xFF0000FF; // Blue

        final source = RGBLuminanceSource(width: 3, height: 1, pixels: pixels);
        final row = source.getRow(0, null);

        // Green contributes most to luminance
        expect(row[1], greaterThan(row[0]));
        expect(row[1], greaterThan(row[2]));
      });
    });

    group('Binarizer edge cases', () {
      test('GlobalHistogramBinarizer handles uniform image', () {
        // All same color
        final pixels = Int32List(100);
        for (var i = 0; i < 100; i++) {
          pixels[i] = 0xFF808080; // Gray
        }
        final source = RGBLuminanceSource(
          width: 10,
          height: 10,
          pixels: pixels,
        );
        final binarizer = GlobalHistogramBinarizer(source);

        // Should not throw
        final matrix = binarizer.getBlackMatrix();
        expect(matrix.width, 10);
        expect(matrix.height, 10);
      });
    });
  });
}
