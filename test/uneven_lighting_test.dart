import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/yomu.dart';

void main() {
  group('Uneven Lighting QR Codes', () {
    late Yomu yomu;

    setUp(() {
      yomu = Yomu.qrOnly;
    });

    test('decodes QR codes with uneven lighting conditions', () {
      final dir = Directory('fixtures/uneven_lighting');
      if (!dir.existsSync()) {
        // Skip if fixtures don't exist
        return;
      }

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();

      expect(files.length, greaterThan(0));

      var successCount = 0;
      for (final file in files) {
        final decoded = img.decodePng(file.readAsBytesSync());
        if (decoded == null) continue;

        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final bytes = Uint8List(image.width * image.height * 4);
        for (var i = 0; i < image.width * image.height; i++) {
          final p = image.getPixel(i % image.width, i ~/ image.width);
          bytes[i * 4] = p.r.toInt();
          bytes[i * 4 + 1] = p.g.toInt();
          bytes[i * 4 + 2] = p.b.toInt();
          bytes[i * 4 + 3] = 0xFF;
        }

        try {
          final result = yomu.decode(
            bytes: bytes,
            width: image.width,
            height: image.height,
          );
          expect(result.text, contains('UNEVEN_LIGHTING'));
          successCount++;
        } catch (_) {
          // Some extreme conditions may fail
        }
      }

      // At least 80% should succeed
      expect(successCount, greaterThanOrEqualTo((files.length * 0.8).floor()));
    });
  });
}
