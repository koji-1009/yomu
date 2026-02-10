import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('Yomu Input Validation', () {
    test('decode throws ArgumentException on empty bytes', () {
      expect(
        () => Yomu.all.decode(
          YomuImage.rgba(width: 10, height: 10, bytes: Uint8List(0)),
        ),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('decode throws ArgumentException on size mismatch', () {
      expect(
        () => Yomu.all.decode(
          YomuImage.rgba(
            width: 10,
            height: 10,
            bytes: Uint8List(10), // 100 needed for grayscale, 400 for RGBA
          ),
        ),
        throwsA(isA<ArgumentException>()),
      );
    });
  });

  group('Yomu Image Processing Coverage', () {
    // 1000 * 1001 = 1,001,000 pixels > 1,000,000 threshold
    const largeWidth = 1000;
    const largeHeight = 1001;

    test('processes BGRA images (small)', () {
      const width = 100;
      const height = 100;
      final bytes = Uint8List(width * height * 4);
      // Fill with some data
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 255;
      }

      final image = YomuImage.bgra(width: width, height: height, bytes: bytes);

      // Should run conversion logic and fail at detection
      expect(() => Yomu.all.decode(image), throwsA(isA<DetectionException>()));
    });

    test('processes BGRA images (large, downsampled)', () {
      final bytes = Uint8List(largeWidth * largeHeight * 4);
      final image = YomuImage.bgra(
        width: largeWidth,
        height: largeHeight,
        bytes: bytes,
      );

      expect(() => Yomu.all.decode(image), throwsA(isA<DetectionException>()));
    });

    test('processes RGBA images (large, downsampled)', () {
      final bytes = Uint8List(largeWidth * largeHeight * 4);
      final image = YomuImage.rgba(
        width: largeWidth,
        height: largeHeight,
        bytes: bytes,
      );

      expect(() => Yomu.all.decode(image), throwsA(isA<DetectionException>()));
    });

    test('processes Grayscale images with stride', () {
      const width = 100;
      const height = 100;
      const stride = 120; // Stride > Width
      final bytes = Uint8List(stride * height);

      final image = YomuImage.grayscale(
        width: width,
        height: height,
        bytes: bytes,
        rowStride: stride,
      );

      expect(() => Yomu.all.decode(image), throwsA(isA<DetectionException>()));
    });

    test('processes Grayscale images (large, downsampled)', () {
      final bytes = Uint8List(largeWidth * largeHeight);
      final image = YomuImage.grayscale(
        width: largeWidth,
        height: largeHeight,
        bytes: bytes,
      );

      expect(() => Yomu.all.decode(image), throwsA(isA<DetectionException>()));
    });

    test('decodeAll processes Grayscale images', () {
      const width = 100;
      const height = 100;
      final bytes = Uint8List(width * height);
      final image = YomuImage.grayscale(
        width: width,
        height: height,
        bytes: bytes,
      );

      // detectMulti returns empty list if no patterns found.
      final results = Yomu.all.decodeAll(image);
      expect(results, isEmpty);
    });
  });

  group('Yomu Configuration', () {
    test('Yomu accepts custom parameters', () {
      const yomu = Yomu(
        enableQRCode: true,
        barcodeScanner: BarcodeScanner.none,
        binarizerThreshold: 0.5,
        alignmentAreaAllowance: 20,
      );

      expect(yomu.binarizerThreshold, 0.5);
      expect(yomu.alignmentAreaAllowance, 20);
    });
  });

  group('Error Handling', () {
    test('wraps unexpected exceptions in ImageProcessingException', () {
      final brokenImage = BrokenYomuImage();
      expect(
        () => Yomu.all.decode(brokenImage),
        throwsA(isA<ImageProcessingException>()),
      );
    });
  });
}

class BrokenYomuImage implements YomuImage {
  @override
  Uint8List get bytes => Uint8List(0); // Dummy

  @override
  int get width => 100;

  @override
  int get height => 100;

  @override
  int get rowStride => 100;

  @override
  YomuImageFormat get format =>
      throw Exception('Unexpected error accessing format');
}
