import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  final fixturesDir = Directory('fixtures/qr_images');

  setUpAll(() {
    if (!fixturesDir.existsSync()) {
      fail('Fixtures directory not found: ${fixturesDir.path}');
    }
  });

  group('Multi QR Code Detection', () {
    test('decodes 2 QR codes in horizontal layout', () {
      final file = File('fixtures/qr_images/multi_qr_2_horizontal.png');
      final bytes = file.readAsBytesSync();
      final decoded = img.decodePng(bytes)!;
      final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: image.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );

      expect(results.length, 2);
      expect(results[0].text, 'QR Code 1');
      expect(results[1].text, 'QR Code 2');
    });

    test('decodes 3 QR codes in vertical layout', () {
      final file = File('fixtures/qr_images/multi_qr_3_vertical.png');
      final bytes = file.readAsBytesSync();
      final decoded = img.decodePng(bytes)!;
      final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: image.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );

      expect(results.length, 3);
      expect(
        results.map((r) => r.text),
        containsAll(['Code A', 'Code B', 'Code C']),
      );
    });

    test('decodes 4 QR codes in 2x2 grid layout', () {
      final file = File('fixtures/qr_images/multi_qr_4_grid.png');
      final bytes = file.readAsBytesSync();
      final decoded = img.decodePng(bytes)!;
      final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: image.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );

      expect(results.length, 4);
      expect(
        results.map((r) => r.text),
        containsAll(['Top Left', 'Top Right', 'Bottom Left', 'Bottom Right']),
      );
    });

    test('returns empty list for image with no QR codes', () {
      // Create a blank white 300x300 RGBA image
      final pixels = List<int>.filled(300 * 300 * 4, 255); // All white

      const yomu = Yomu.qrOnly;
      final results = yomu.decodeAll(
        bytes: Uint8List.fromList(pixels),
        width: 300,
        height: 300,
      );

      expect(results, isEmpty);
    });

    test(
      'decode() still works for single QR code (backward compatibility)',
      () {
        final file = File('fixtures/qr_images/numeric_simple.png');
        final bytes = file.readAsBytesSync();
        final decoded = img.decodePng(bytes)!;
        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

        const yomu = Yomu.qrOnly;
        final result = yomu.decode(
          bytes: image.buffer.asUint8List(),
          width: image.width,
          height: image.height,
        );

        expect(result.text, '12345');
      },
    );
  });
}
