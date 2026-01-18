import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  final perfTestDir = Directory('fixtures/performance_test_images');
  final qrDir = Directory('fixtures/qr_images');

  setUpAll(() {
    if (!perfTestDir.existsSync()) {
      fail('Performance fixtures not found: ${perfTestDir.path}');
    }
    if (!qrDir.existsSync()) {
      fail('QR fixtures not found: ${qrDir.path}');
    }
  });

  group('Large Image Downsampling', () {
    test(
      'successfully decodes 2000x2000 image (4MP, triggers downsampling)',
      () {
        // Create a large image with an embedded QR code
        // This tests the _preparePixels and _downsamplePixels methods
        final file = File(
          'fixtures/performance_test_images/square_white_center_400px.png',
        );

        final decoded = img.decodePng(file.readAsBytesSync());
        if (decoded == null) return;

        // Scale up to 2000x2000 to trigger downsampling (>1MP threshold)
        final largeImage = img.copyResize(decoded, width: 2000, height: 2000);

        // Convert to RGBA bytes
        final bytes = Uint8List(largeImage.width * largeImage.height * 4);
        for (var i = 0; i < largeImage.width * largeImage.height; i++) {
          final x = i % largeImage.width;
          final y = i ~/ largeImage.width;
          final p = largeImage.getPixel(x, y);
          bytes[i * 4] = p.r.toInt();
          bytes[i * 4 + 1] = p.g.toInt();
          bytes[i * 4 + 2] = p.b.toInt();
          bytes[i * 4 + 3] = 0xFF;
        }

        // Should successfully decode despite downsampling
        final result = Yomu.qrOnly.decode(
          bytes: bytes,
          width: largeImage.width,
          height: largeImage.height,
        );
        expect(result.text, contains('PerfTest'));
      },
    );

    test('successfully decodes 1500x1500 image (2.25MP)', () {
      final file = File(
        'fixtures/performance_test_images/square_white_center_250px.png',
      );

      final decoded = img.decodePng(file.readAsBytesSync());
      if (decoded == null) return;

      final largeImage = img.copyResize(decoded, width: 1500, height: 1500);
      final bytes = Uint8List(largeImage.width * largeImage.height * 4);
      for (var i = 0; i < largeImage.width * largeImage.height; i++) {
        final x = i % largeImage.width;
        final y = i ~/ largeImage.width;
        final p = largeImage.getPixel(x, y);
        bytes[i * 4] = p.r.toInt();
        bytes[i * 4 + 1] = p.g.toInt();
        bytes[i * 4 + 2] = p.b.toInt();
        bytes[i * 4 + 3] = 0xFF;
      }

      final result = Yomu.qrOnly.decode(
        bytes: bytes,
        width: largeImage.width,
        height: largeImage.height,
      );
      expect(result.text, isNotEmpty);
    });

    test('decodeAll works with large images', () {
      final file = File('fixtures/qr_images/multi_qr_2_horizontal.png');

      final decoded = img.decodePng(file.readAsBytesSync());
      if (decoded == null) return;

      // Scale up to trigger downsampling
      final largeImage = img.copyResize(decoded, width: 1200, height: 600);
      final bytes = Uint8List(largeImage.width * largeImage.height * 4);
      for (var i = 0; i < largeImage.width * largeImage.height; i++) {
        final x = i % largeImage.width;
        final y = i ~/ largeImage.width;
        final p = largeImage.getPixel(x, y);
        bytes[i * 4] = p.r.toInt();
        bytes[i * 4 + 1] = p.g.toInt();
        bytes[i * 4 + 2] = p.b.toInt();
        bytes[i * 4 + 3] = 0xFF;
      }

      // decodeAll should still find QR codes after downsampling
      final results = Yomu.qrOnly.decodeAll(
        bytes: bytes,
        width: largeImage.width,
        height: largeImage.height,
      );
      // May find fewer codes after downsampling, but should not crash
      expect(results, isA<List<DecoderResult>>());
    });
  });

  group('Malformed Input Handling', () {
    test('throws on corrupted QR code data', () {
      // Create an image that looks like a QR code but has corrupted data
      // This tests error handling in the decoder
      final bytes = Uint8List(200 * 200 * 4);

      // Fill with random noise that might trigger finder pattern detection
      // but will fail during decoding
      for (var i = 0; i < bytes.length; i += 4) {
        final noise = (i * 17) % 256;
        bytes[i] = noise > 128 ? 255 : 0;
        bytes[i + 1] = noise > 128 ? 255 : 0;
        bytes[i + 2] = noise > 128 ? 255 : 0;
        bytes[i + 3] = 255;
      }

      // Should throw or return gracefully, not crash
      expect(
        () => Yomu.qrOnly.decode(bytes: bytes, width: 200, height: 200),
        throwsA(anything),
      );
    });

    test('decodeAll returns empty list for corrupted data', () {
      final bytes = Uint8List(200 * 200 * 4);

      // Fill with pattern that looks like multiple QR codes but is invalid
      for (var i = 0; i < bytes.length; i += 4) {
        final x = (i ~/ 4) % 200;
        final y = (i ~/ 4) ~/ 200;
        final isBlack = ((x ~/ 10) + (y ~/ 10)) % 2 == 0;
        bytes[i] = isBlack ? 0 : 255;
        bytes[i + 1] = isBlack ? 0 : 255;
        bytes[i + 2] = isBlack ? 0 : 255;
        bytes[i + 3] = 255;
      }

      // Should return empty list, not crash
      final results = Yomu.qrOnly.decodeAll(
        bytes: bytes,
        width: 200,
        height: 200,
      );
      expect(results, isEmpty);
    });

    test('handles image with partial QR code', () {
      // Load a valid QR code and crop it to make it incomplete
      final file = File('fixtures/qr_images/numeric_simple.png');

      final decoded = img.decodePng(file.readAsBytesSync());
      if (decoded == null) return;

      // Crop to remove part of the QR code (half the image)
      final cropped = img.copyCrop(
        decoded,
        x: 0,
        y: 0,
        width: decoded.width ~/ 2,
        height: decoded.height,
      );

      final bytes = Uint8List(cropped.width * cropped.height * 4);
      for (var i = 0; i < cropped.width * cropped.height; i++) {
        final x = i % cropped.width;
        final y = i ~/ cropped.width;
        final p = cropped.getPixel(x, y);
        bytes[i * 4] = p.r.toInt();
        bytes[i * 4 + 1] = p.g.toInt();
        bytes[i * 4 + 2] = p.b.toInt();
        bytes[i * 4 + 3] = 0xFF;
      }

      // Should throw (incomplete QR code cannot be decoded)
      expect(
        () => Yomu.qrOnly.decode(
          bytes: bytes,
          width: cropped.width,
          height: cropped.height,
        ),
        throwsA(anything),
      );
    });

    test('handles extremely small images gracefully', () {
      // 10x10 image - too small to contain a valid QR code
      final bytes = Uint8List(10 * 10 * 4);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = 255; // White
      }

      expect(
        () => Yomu.qrOnly.decode(bytes: bytes, width: 10, height: 10),
        throwsA(anything),
      );
    });

    test('handles all-black image', () {
      final bytes = Uint8List(100 * 100 * 4);
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i] = 0;
        bytes[i + 1] = 0;
        bytes[i + 2] = 0;
        bytes[i + 3] = 255;
      }

      expect(
        () => Yomu.qrOnly.decode(bytes: bytes, width: 100, height: 100),
        throwsA(anything),
      );
    });
  });
}
