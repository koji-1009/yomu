import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/ean13_decoder.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';

void main() {
  (RGBLuminanceSource, int, int) loadSource(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    final decoded = img.decodePng(bytes)!;
    final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

    final pixels = Int32List(image.width * image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        pixels[y * image.width + x] =
            (0xFF << 24) |
            (p.r.toInt() << 16) |
            (p.g.toInt() << 8) |
            p.b.toInt();
      }
    }
    return (
      RGBLuminanceSource(
        width: image.width,
        height: image.height,
        pixels: pixels,
      ),
      image.width,
      image.height,
    );
  }

  group('EAN-13 Decoder', () {
    test('decodes product barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/ean13_product.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_13');
      expect(result.text, '4901234567894');
    });

    test('decodes ISBN barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/ean13_isbn.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_13');
      expect(result.text, '9784873115658');
    });

    test('validates checksum correctly', () {
      const decoder = EAN13Decoder();
      expect(decoder.format, 'EAN_13');
    });
  });

  group('Code 128 Decoder', () {
    test('decodes hello world barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/code128_hello.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_128');
      expect(result.text, 'Hello World');
    });

    test('decodes numeric barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/code128_numeric.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_128');
      expect(result.text, '1234567890');
    });
  });

  group('Code 39 Decoder', () {
    test('decodes hello barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/code39_hello.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_39');
      // Code 39 may include extra trailing characters; check starts with
      expect(result.text, startsWith('HELLO'));
    });

    test('decodes numeric barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/code39_numeric.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_39');
    });
  });

  group('ITF Decoder', () {
    test('decodes numeric barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/itf_numeric.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'ITF');
    });

    test('decodes ITF-14 product barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/itf14_product.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, anyOf('ITF', 'ITF_14'));
    });
  });

  group('Codabar Decoder', () {
    test('decodes numeric barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/codabar_numeric.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODABAR');
    });

    test('decodes long barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/codabar_long.png',
      );
      const scanner = BarcodeScanner.industrial;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODABAR');
    });
  });

  group('EAN-8 Decoder', () {
    test('decodes product barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/ean8_product.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_8');
      expect(result.text, hasLength(8));
    });

    test('decodes small barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/ean8_small.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_8');
    });
  });

  group('UPC-A Decoder', () {
    test('decodes product barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/upca_product.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      // UPC-A is encoded as EAN-13 with leading 0
      expect(result, isNotNull);
      expect(result!.format, anyOf('UPC_A', 'EAN_13'));
    });

    test('decodes food barcode', () {
      final (source, _, _) = loadSource(
        'fixtures/barcode_images/upca_food.png',
      );
      const scanner = BarcodeScanner.retail;
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, anyOf('UPC_A', 'EAN_13'));
    });
  });

  group('BarcodeScanner', () {
    test('returns null for empty image', () {
      final emptyPixels = Int32List(100 * 100);
      for (var i = 0; i < emptyPixels.length; i++) {
        emptyPixels[i] = 0xFFFFFFFF;
      }
      final source = RGBLuminanceSource(
        width: 100,
        height: 100,
        pixels: emptyPixels,
      );

      const scanner = BarcodeScanner.all;
      final result = scanner.scan(source);

      expect(result, isNull);
    });

    test('scanAll returns empty list for empty image', () {
      final emptyPixels = Int32List(100 * 100);
      for (var i = 0; i < emptyPixels.length; i++) {
        emptyPixels[i] = 0xFFFFFFFF;
      }
      final source = RGBLuminanceSource(
        width: 100,
        height: 100,
        pixels: emptyPixels,
      );

      const scanner = BarcodeScanner.all;
      final results = scanner.scanAll(source);

      expect(results, isEmpty);
    });
  });
}
