import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('Image Conversion', () {
    group('rgbaToGrayscale', () {
      test('converts basic colors correctly', () {
        // Red, Green, Blue, White in RGBA (4 bytes per pixel)
        final bytes = Uint8List.fromList([
          255, 0, 0, 255, // Red
          0, 255, 0, 255, // Green
          0, 0, 255, 255, // Blue
          255, 255, 255, 255, // White
        ]);

        // Formula: 0.299R + 0.587G + 0.114B
        // Red: ~76
        // Green: ~150
        // Blue: ~29
        // White: 255

        final luminance = rgbaToGrayscale(bytes, 4, 1);
        expect(luminance, hasLength(4));
        expect(luminance[0], closeTo(76, 1));
        expect(luminance[1], closeTo(150, 1));
        expect(luminance[2], closeTo(29, 1));
        expect(luminance[3], 255);
      });

      test('throws ArgumentException if bytes length is too small', () {
        final bytes = Uint8List(3); // 3 bytes, need 4 for 1 pixel
        expect(
          () => rgbaToGrayscale(bytes, 1, 1),
          throwsA(isA<ArgumentException>()),
        );
      });

      test(
        'throws ArgumentException if bytes length is too small for large image',
        () {
          final bytes = Uint8List(400); // Enough for 100 pixels
          // Request 10x11 = 110 pixels -> Needs 440 bytes
          expect(
            () => rgbaToGrayscale(bytes, 10, 11),
            throwsA(isA<ArgumentException>()),
          );
        },
      );
    });

    group('int32ToGrayscale', () {
      test('converts basic colors correctly', () {
        final pixels = Int32List.fromList([
          0xFFFF0000, // Red (AARRGGBB)
          0xFF00FF00, // Green
          0xFF0000FF, // Blue
          0xFFFFFFFF, // White
        ]);

        final luminance = int32ToGrayscale(pixels, 4, 1);
        expect(luminance, hasLength(4));
        expect(luminance[0], closeTo(76, 1));
        expect(luminance[1], closeTo(150, 1));
        expect(luminance[2], closeTo(29, 1));
        expect(luminance[3], 255);
      });

      test('uses fast path for grayscale pixels', () {
        // Grayscale pixels have R=G=B
        final pixels = Int32List.fromList([
          0xFF000000, // Black
          0xFF808080, // Gray
          0xFFFFFFFF, // White
        ]);

        final luminance = int32ToGrayscale(pixels, 3, 1);
        expect(luminance[0], 0);
        expect(luminance[1], 0x80); // 128
        expect(luminance[2], 0xFF); // 255
      });

      test('throws ArgumentException if pixels length is too small', () {
        final pixels = Int32List(0);
        expect(
          () => int32ToGrayscale(pixels, 1, 1),
          throwsA(isA<ArgumentException>()),
        );
      });
    });
  });
}
