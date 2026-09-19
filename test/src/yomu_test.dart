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

      // findMulti returns empty list if no patterns found.
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

  group('Out-of-range version estimate', () {
    // Three finder patterns spaced like a 245-module symbol, larger than
    // version 40's 177 modules.
    YomuImage oversizedSymbol() {
      const width = 1000;
      const module = 4;
      final px = Uint8List(width * width)..fillRange(0, width * width, 255);
      void finder(int x, int y) {
        for (var my = 0; my < 7; my++) {
          for (var mx = 0; mx < 7; mx++) {
            final ring = mx == 0 || mx == 6 || my == 0 || my == 6;
            final core = mx >= 2 && mx <= 4 && my >= 2 && my <= 4;
            if (!(ring || core)) continue;
            for (var dy = 0; dy < module; dy++) {
              for (var dx = 0; dx < module; dx++) {
                px[(y + my * module + dy) * width + x + mx * module + dx] = 0;
              }
            }
          }
        }
      }

      finder(10, 10);
      finder(10 + 238 * module, 10);
      finder(10, 10 + 238 * module);
      return YomuImage.grayscale(bytes: px, width: width, height: width);
    }

    for (final (name, yomu) in [
      ('realtime', Yomu.realtime),
      ('responsive', Yomu.responsive),
      ('qrOnly', Yomu.qrOnly),
    ]) {
      test('$name.decode throws DetectionException', () {
        expect(
          () => yomu.decode(oversizedSymbol()),
          throwsA(isA<DetectionException>()),
        );
      });
    }
  });

  group('Error Handling', () {
    test('rejects an implementation whose bytes do not fit its size', () {
      // Implementing YomuImage skips the checks of its constructor.
      final image = _UncheckedYomuImage();
      expect(() => Yomu.all.decode(image), throwsA(isA<ArgumentException>()));
      expect(
        () => Yomu.all.decodeAll(image),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('keeps ImageProcessingException a YomuException', () {
      // Deprecated and no longer thrown, but still caught by callers.
      // ignore: deprecated_member_use_from_same_package
      const exception = ImageProcessingException('message');
      expect(exception, isA<YomuException>());
      expect(exception.message, 'message');
    });

    test('lets an exception from the image itself through', () {
      // The library does not convert what the caller's own code throws.
      expect(
        () => Yomu.all.decode(_ThrowingYomuImage()),
        throwsA(isA<_ImageFailure>()),
      );
    });
  });
}

class _UncheckedYomuImage implements YomuImage {
  @override
  Uint8List get bytes => Uint8List(0);

  @override
  int get width => 100;

  @override
  int get height => 100;

  @override
  int get rowStride => 100;

  @override
  YomuImageFormat get format => YomuImageFormat.grayscale;
}

class _ImageFailure implements Exception {}

class _ThrowingYomuImage extends _UncheckedYomuImage {
  @override
  YomuImageFormat get format => throw _ImageFailure();
}
