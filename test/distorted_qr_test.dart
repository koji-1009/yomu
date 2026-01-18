import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  final fixtureDir = Directory('fixtures/distorted_images');

  setUpAll(() {
    if (!fixtureDir.existsSync()) {
      fail('Fixtures directory not found: ${fixtureDir.path}');
    }
  });

  group('Distorted QR Codes', () {
    test('detects rotated QR codes (Z-axis)', () {
      final files = fixtureDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('rotation_') && f.path.endsWith('.png'))
          .toList();

      expect(files, isNotEmpty);

      for (final file in files) {
        final decoded = img.decodePng(file.readAsBytesSync());
        if (decoded == null) fail('Failed to decode image');

        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final bytes = Uint8List(image.width * image.height * 4);
        for (var i = 0; i < image.width * image.height; i++) {
          final p = image.getPixel(i % image.width, i ~/ image.width);
          bytes[i * 4] = p.r.toInt();
          bytes[i * 4 + 1] = p.g.toInt();
          bytes[i * 4 + 2] = p.b.toInt();
          bytes[i * 4 + 3] = 0xFF;
        }

        final result = Yomu.qrOnly.decode(
          bytes: bytes,
          width: image.width,
          height: image.height,
        );
        expect(result.text, contains('DISTORTION_TEST_DATA'));
      }
    });

    test('detects tilted QR codes (Perspective)', () {
      final files = fixtureDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('tilt_') && f.path.endsWith('.png'))
          .toList();

      expect(files, isNotEmpty);

      for (final file in files) {
        final decoded = img.decodePng(file.readAsBytesSync());
        if (decoded == null) fail('Failed to decode image');

        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final bytes = Uint8List(image.width * image.height * 4);
        for (var i = 0; i < image.width * image.height; i++) {
          final p = image.getPixel(i % image.width, i ~/ image.width);
          bytes[i * 4] = p.r.toInt();
          bytes[i * 4 + 1] = p.g.toInt();
          bytes[i * 4 + 2] = p.b.toInt();
          bytes[i * 4 + 3] = 0xFF;
        }

        final result = Yomu.qrOnly.decode(
          bytes: bytes,
          width: image.width,
          height: image.height,
        );
        expect(result.text, contains('DISTORTION_TEST_DATA'));
        // User policy: 0, 3, 6 degrees matrix check.
        // These are within the guaranteed reliable range.
      }
    });
  });
}
