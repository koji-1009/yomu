import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  group('Fallback Strategy', () {
    late Uint8List pixels;
    late int width;
    late int height;

    setUpAll(() {
      final file = File('fixtures/qr_images/qr_distorted_v4.png');
      if (!file.existsSync()) {
        fail('Test fixture qr_distorted_v4.png not found');
      }
      final bytes = file.readAsBytesSync();
      final image = img.decodePng(bytes)!;
      width = image.width;
      height = image.height;

      // Convert to RGBA
      final converted = image.convert(format: img.Format.uint8, numChannels: 4);
      pixels = converted.buffer.asUint8List();
    });

    test('Yomu.all should abort fallback on DecodeException', () {
      // This image is known to have a detectable QR finder pattern but fails Reed-Solomon decoding.
      //
      // Expected Behavior:
      // 1. QR Detection -> Success (Finder patterns found)
      // 2. QR Decoding -> Fail (DecodeException)
      // 3. Optimization -> Abort (Do NOT fall back to barcode scanning)
      //
      // If it falls back, it would try barcode scanning, find nothing, and throw DetectionException.
      // So we expect DecodeException to propagate.

      expect(
        () => Yomu.all.decode(bytes: pixels, width: width, height: height),
        throwsA(isA<DecodeException>()),
        reason:
            'Should throw DecodeException directly, ensuring no fallback occurred.',
      );
    });

    test('Yomu.qrOnly should throw DecodeException', () {
      // Logic check: Verify baseline behavior for this image
      expect(
        () => Yomu.qrOnly.decode(bytes: pixels, width: width, height: height),
        throwsA(isA<DecodeException>()),
      );
    });
  });
}
