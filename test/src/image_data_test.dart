import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('YomuImage', () {
    test('grayscale factory creates correct instance', () {
      final bytes = Uint8List(100);
      final image = YomuImage.grayscale(bytes: bytes, width: 10, height: 10);

      expect(image.bytes, equals(bytes));
      expect(image.width, equals(10));
      expect(image.height, equals(10));
      expect(image.format, equals(YomuImageFormat.grayscale));
      expect(image.rowStride, equals(10)); // Default stride for grayscale
    });

    test('grayscale factory uses provided rowStride', () {
      final bytes = Uint8List(200);
      final image = YomuImage.grayscale(
        bytes: bytes,
        width: 10,
        height: 10,
        rowStride: 20,
      );

      expect(image.rowStride, equals(20));
    });

    test('rgba factory creates correct instance', () {
      final bytes = Uint8List(400);
      final image = YomuImage.rgba(bytes: bytes, width: 10, height: 10);

      expect(image.bytes, equals(bytes));
      expect(image.width, equals(10));
      expect(image.height, equals(10));
      expect(image.format, equals(YomuImageFormat.rgba));
      expect(image.rowStride, equals(40)); // Default stride for rgba (10 * 4)
    });

    test('rgba factory uses provided rowStride', () {
      final bytes = Uint8List(800);
      final image = YomuImage.rgba(
        bytes: bytes,
        width: 10,
        height: 10,
        rowStride: 80,
      );

      expect(image.rowStride, equals(80));
    });

    test('bgra factory creates correct instance', () {
      final bytes = Uint8List(400);
      final image = YomuImage.bgra(bytes: bytes, width: 10, height: 10);

      expect(image.bytes, equals(bytes));
      expect(image.width, equals(10));
      expect(image.height, equals(10));
      expect(image.format, equals(YomuImageFormat.bgra));
      expect(image.rowStride, equals(40)); // Default stride for bgra (10 * 4)
    });

    test('bgra factory uses provided rowStride', () {
      final bytes = Uint8List(800);
      final image = YomuImage.bgra(
        bytes: bytes,
        width: 10,
        height: 10,
        rowStride: 80,
      );

      expect(image.rowStride, equals(80));
    });

    test('yuv420 factory creates correct instance using grayscale format', () {
      final bytes = Uint8List(100);
      final image = YomuImage.yuv420(yBytes: bytes, width: 10, height: 10);

      expect(image.bytes, equals(bytes));
      expect(image.width, equals(10));
      expect(image.height, equals(10));
      expect(image.format, equals(YomuImageFormat.grayscale));
      expect(image.rowStride, equals(10));
    });

    test('yuv420 factory uses provided rowStride', () {
      final bytes = Uint8List(200);
      final image = YomuImage.yuv420(
        yBytes: bytes,
        width: 10,
        height: 10,
        yRowStride: 20,
      );

      expect(image.rowStride, equals(20));
    });

    test('constructor sets default rowStride correctly', () {
      final bytes = Uint8List(100);
      final grayscaleImage = YomuImage(
        bytes: bytes,
        width: 10,
        height: 10,
        format: YomuImageFormat.grayscale,
      );
      expect(grayscaleImage.rowStride, equals(10));

      final rgbaBytes = Uint8List(400);
      final rgbaImage = YomuImage(
        bytes: rgbaBytes,
        width: 10,
        height: 10,
        format: YomuImageFormat.rgba,
      );
      expect(rgbaImage.rowStride, equals(40));

      final bgraBytes = Uint8List(400);
      final bgraImage = YomuImage(
        bytes: bgraBytes,
        width: 10,
        height: 10,
        format: YomuImageFormat.bgra,
      );
      expect(bgraImage.rowStride, equals(40));
    });

    test('constructor uses provided rowStride', () {
      final bytes = Uint8List(150);
      final image = YomuImage(
        bytes: bytes,
        width: 10,
        height: 10,
        format: YomuImageFormat.grayscale,
        rowStride: 15,
      );
      expect(image.rowStride, equals(15));
    });
    group('validation', () {
      test('throws if width or height is not positive', () {
        final bytes = Uint8List(100);
        expect(
          () => YomuImage.grayscale(bytes: bytes, width: 0, height: 10),
          throwsA(isA<ArgumentException>()),
        );
        expect(
          () => YomuImage.grayscale(bytes: bytes, width: 10, height: -1),
          throwsA(isA<ArgumentException>()),
        );
      });

      test('throws if rowStride is too small', () {
        final bytes = Uint8List(100);
        expect(
          () => YomuImage.grayscale(
            bytes: bytes,
            width: 10,
            height: 10,
            rowStride: 9, // < width (10) * 1
          ),
          throwsA(isA<ArgumentException>()),
        );

        final rgbaBytes = Uint8List(400);
        expect(
          () => YomuImage.rgba(
            bytes: rgbaBytes,
            width: 10,
            height: 10,
            rowStride: 39, // < width (10) * 4
          ),
          throwsA(isA<ArgumentException>()),
        );
      });

      test('throws if bytes length is insufficient', () {
        final bytes = Uint8List(99); // Need 100 (10 * 10)
        expect(
          () => YomuImage.grayscale(bytes: bytes, width: 10, height: 10),
          throwsA(isA<ArgumentException>()),
        );

        final rgbaBytes = Uint8List(399); // Need 400 (10 * 40)
        expect(
          () => YomuImage.rgba(bytes: rgbaBytes, width: 10, height: 10),
          throwsA(isA<ArgumentException>()),
        );

        // Check with custom stride
        final paddedBytes = Uint8List(199); // Need 200 (stride 20 * height 10)
        expect(
          () => YomuImage.grayscale(
            bytes: paddedBytes,
            width: 10,
            height: 10,
            rowStride: 20,
          ),
          throwsA(isA<ArgumentException>()),
        );
      });
    });
  });
}
