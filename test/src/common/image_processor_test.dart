import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/image_processor.dart';
import 'package:yomu/src/image_data.dart';

Uint8List _rgbaBytes(int width, int height, {int stridePixels = 0}) {
  final stride = (width + stridePixels) * 4;
  final bytes = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = y * stride + x * 4;
      // Distinct channel values so the grayscale formula is observable.
      bytes[offset] = 100; // R
      bytes[offset + 1] = 150; // G
      bytes[offset + 2] = 200; // B
      bytes[offset + 3] = 255; // A
    }
  }
  return bytes;
}

// (306 * 100 + 601 * 150 + 117 * 200) >> 10 = 140
const _expectedLuminance = 140;

void main() {
  group('ImageProcessor.process allowDownsample=false', () {
    test('keeps full resolution for large RGBA images', () {
      const width = 2000;
      const height = 1000; // 2MP > 800k target
      final image = YomuImage.rgba(
        bytes: _rgbaBytes(width, height),
        width: width,
        height: height,
      );

      final (defaultPixels, defaultW, defaultH) = ImageProcessor.process(image);
      expect(defaultW, lessThan(width), reason: 'default path downsamples');
      expect(defaultPixels.length, defaultW * defaultH);

      final (pixels, w, h) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
      expect(w, width);
      expect(h, height);
      expect(pixels.length, width * height);
      expect(pixels[0], _expectedLuminance);
      expect(pixels[width * height - 1], _expectedLuminance);
    });

    test('keeps full resolution for large strided RGBA images', () {
      const width = 1200;
      const height = 800;
      const extraPixels = 8;
      final image = YomuImage.rgba(
        bytes: _rgbaBytes(width, height, stridePixels: extraPixels),
        width: width,
        height: height,
        rowStride: (width + extraPixels) * 4,
      );

      final (pixels, w, h) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
      expect(w, width);
      expect(h, height);
      expect(pixels[0], _expectedLuminance);
      expect(pixels[width - 1], _expectedLuminance);
    });

    test('keeps full resolution for large BGRA images', () {
      const width = 1200;
      const height = 800;
      final bytes = _rgbaBytes(width, height);
      final image = YomuImage.bgra(bytes: bytes, width: width, height: height);

      final (pixels, w, h) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
      expect(w, width);
      expect(h, height);
      // Channels swap: R=200, G=150, B=100.
      // (306 * 200 + 601 * 150 + 117 * 100) >> 10 = 159
      expect(pixels[0], 159);
    });

    test('keeps full resolution for large grayscale images', () {
      const width = 1500;
      const height = 900;
      final bytes = Uint8List(width * height);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i & 0xFF;
      }
      final image = YomuImage.grayscale(
        bytes: bytes,
        width: width,
        height: height,
      );

      final (defaultPixels, defaultW, _) = ImageProcessor.process(image);
      expect(defaultW, lessThan(width));
      expect(defaultPixels, isNotEmpty);

      final (pixels, w, h) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
      expect(w, width);
      expect(h, height);
      // Zero-copy path: identical backing data.
      expect(pixels, same(bytes));
    });

    test('removes stride from large strided grayscale images', () {
      const width = 1500;
      const height = 900;
      const rowStride = width + 16;
      final bytes = Uint8List(rowStride * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          bytes[y * rowStride + x] = 42;
        }
      }
      final image = YomuImage.grayscale(
        bytes: bytes,
        width: width,
        height: height,
        rowStride: rowStride,
      );

      final (pixels, w, h) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
      expect(w, width);
      expect(h, height);
      expect(pixels.length, width * height);
      expect(pixels[0], 42);
      expect(pixels[width * height - 1], 42);
    });
  });
}
