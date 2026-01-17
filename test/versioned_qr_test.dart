/// Integration tests for versioned QR code detection.
///
/// Tests QR codes of versions 1-7 to exercise detector/decoder paths.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  final fixturesDir = Directory('fixtures/qr_images');

  group('Versioned QR Code Detection', () {
    test('detects version 1 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_1.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_1.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 2 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_2.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_2.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 3 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_3.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_3.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 4 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_4.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_4.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 5 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_5.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_5.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 6 QR code', () {
      final file = File('${fixturesDir.path}/qr_version_6.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_6.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects version 7 QR code (has version info)', () {
      final file = File('${fixturesDir.path}/qr_version_7.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_version_7.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty);
    });

    test('detects distorted version 4 QR code (rotation + noise)', () {
      final file = File('${fixturesDir.path}/qr_distorted_v4.png');
      if (!file.existsSync()) {
        markTestSkipped('Fixture qr_distorted_v4.png not found');
        return;
      }

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);

      final pixels = _imageToRgba(image!);
      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );

      expect(results, isNotEmpty, reason: 'Failed to detect distorted QR code');
      expect(results.first.text, contains('Distorted V4'));
    });
  });
}

/// Converts an image to RGBA bytes.
Uint8List _imageToRgba(img.Image image) {
  final pixels = Uint8List(image.width * image.height * 4);
  var i = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      pixels[i++] = pixel.r.toInt();
      pixels[i++] = pixel.g.toInt();
      pixels[i++] = pixel.b.toInt();
      pixels[i++] = 255;
    }
  }
  return pixels;
}
