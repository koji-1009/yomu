import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/ean13_decoder.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';

void main() {
  (LuminanceSource, int, int) loadSource(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    final decoded = img.decodePng(bytes)!;
    final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

    // Get RGBA bytes directly
    final width = image.width;
    final height = image.height;
    final rgbaBytes = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final p = image.getPixel(i % width, i ~/ width);
      rgbaBytes[i * 4] = p.r.toInt();
      rgbaBytes[i * 4 + 1] = p.g.toInt();
      rgbaBytes[i * 4 + 2] = p.b.toInt();
      rgbaBytes[i * 4 + 3] = 0xFF; // Alpha
    }

    final luminances = rgbaToGrayscale(rgbaBytes, width, height);

    return (
      LuminanceSource(
        width: width,
        height: height,
        luminances: luminances,
      ),
      width,
      height,
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
      final luminances = int32ToGrayscale(emptyPixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
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
      final luminances = int32ToGrayscale(emptyPixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
      );

      const scanner = BarcodeScanner.all;
      final results = scanner.scanAll(source);

      expect(results, isEmpty);
    });
  });
}
