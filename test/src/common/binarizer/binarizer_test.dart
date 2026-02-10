import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/src/yomu_exception.dart'; // import

void main() {
  group('Binarizer', () {
    test('getBlackMatrix returns correct matrix dimensions', () {
      final luminances = Uint8List(100);
      final source = LuminanceSource(
        width: 10,
        height: 10,
        luminances: luminances,
      );
      final binarizer = Binarizer(source);
      final matrix = binarizer.getBlackMatrix();
      expect(matrix.width, 10);
      expect(matrix.height, 10);
    });

    test('getBlackMatrix handles invalid dimensions', () {
      final luminances = Uint8List(0);
      final source = LuminanceSource(
        width: 0,
        height: 0,
        luminances: luminances,
      );
      expect(
        () => Binarizer(source).getBlackMatrix(),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('thresholds correctly for simple contrast', () {
      // Create a 2x2 image
      // White | Black
      // Black | White
      final pixels = Int32List.fromList([
        0xFFFFFFFF,
        0xFF000000,
        0xFF000000,
        0xFFFFFFFF,
      ]);
      // Convert to luminance
      final luminances = int32ToGrayscale(pixels, 2, 2);

      final source = LuminanceSource(
        width: 2,
        height: 2,
        luminances: luminances,
      );
      final binarizer = Binarizer(source);
      final matrix = binarizer.getBlackMatrix();

      // For 2x2 image, adaptive thresholding with large minWindowSize (40)
      // implies the window covers the whole image.
      // Mean = 127. Threshold ~127.
      // White(255) -> Black (false, strictly speaking 'getBlackMatrix' means true=black?)
      // Wait, getBlackMatrix: true for black, false for white.
      // pixel <= threshold => true (black)
      // 255 <= 127 is False (White). OK.
      // 0 <= 127 is True (Black). OK.

      // (0,0) is White -> False
      expect(matrix.get(0, 0), isFalse);
      // (1,0) is Black -> True
      expect(matrix.get(1, 0), isTrue);
    });

    test('Binarizer respects thresholdFactor', () {
      // Create an image with a uniform background and one slightly darker pixel
      const width = 10;
      const height = 10;
      final pixels = Int32List(width * height);

      // Background: 100 (0xFF646464)
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = 0xFF646464;
      }

      // Target pixel at (5, 5): 88 (0xFF585858)
      // With background 100, threshold is 100 * factor.
      // If factor 0.875 (default): Threshold = 87.5. 88 > 87.5 -> White (False).
      // If factor 0.90: Threshold = 90. 88 <= 90 -> Black (True).
      pixels[5 * width + 5] = 0xFF585858;

      final luminances = int32ToGrayscale(pixels, width, height);
      final source = LuminanceSource(
        width: width,
        height: height,
        luminances: luminances,
      );

      // Test default (0.875)
      final binarizerDefault = Binarizer(source); // Default factor
      final matrixDefault = binarizerDefault.getBlackMatrix();
      expect(
        matrixDefault.get(5, 5),
        isFalse,
        reason: 'Should be white with default factor',
      );

      // Test custom (0.90)
      final binarizerCustom = Binarizer(source, thresholdFactor: 0.90);
      final matrixCustom = binarizerCustom.getBlackMatrix();
      expect(
        matrixCustom.get(5, 5),
        isTrue,
        reason: 'Should be black with coarser factor',
      );
    });
  });
}
