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
  });
}
