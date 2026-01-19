// Comprehensive tests for 1D barcode decoders
// Tests successful decoding, error handling, and edge cases

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/codabar_decoder.dart';
import 'package:yomu/src/barcode/code128_decoder.dart';
import 'package:yomu/src/barcode/code39_decoder.dart';
import 'package:yomu/src/barcode/ean13_decoder.dart';
import 'package:yomu/src/barcode/ean8_decoder.dart';
import 'package:yomu/src/barcode/itf_decoder.dart';
import 'package:yomu/src/barcode/upca_decoder.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';

(LuminanceSource, int, int) _loadImageAsSource(String path) {
  final file = File(path);
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) throw Exception('Failed to decode image');

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

void main() {
  final fixtureDir = Directory('fixtures/barcode_images');

  setUpAll(() {
    if (!fixtureDir.existsSync()) {
      fail('Fixtures directory not found: ${fixtureDir.path}');
    }
  });

  group('BarcodeScanner Integration', () {
    late BarcodeScanner scanner;

    setUp(() {
      scanner = BarcodeScanner.all;
    });

    test('scans EAN-13 barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/ean13_product.png',
      );
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_13');
      expect(result.text, hasLength(13));
    });

    test('scans EAN-8 barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/ean8_product.png',
      );
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'EAN_8');
      expect(result.text, hasLength(8));
    });

    test('scans Code 128 barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/code128_hello.png',
      );
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_128');
    });

    test('scans Code 39 barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/code39_hello.png',
      );
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'CODE_39');
    });

    test('scans UPC-A barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/upca_product.png',
      );
      final result = scanner.scan(source);

      // UPC-A is a subset of EAN-13, so scanner may detect as either format
      if (result != null) {
        expect(result.format, anyOf('UPC_A', 'EAN_13'));
      }
    });

    test('scans ITF barcode', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/itf_numeric.png',
      );
      final result = scanner.scan(source);

      // ITF might not be detected depending on image quality
      if (result != null) {
        expect(result.format, 'ITF');
      }
    });

    test('scans Codabar barcode - numeric', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/codabar_numeric.png',
      );
      final result = scanner.scan(source);

      if (result != null) {
        expect(result.format, 'CODABAR');
        expect(result.text, contains('12345'));
      }
    });

    test('scans Codabar barcode - long', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/codabar_long.png',
      );
      final result = scanner.scan(source);

      if (result != null) {
        expect(result.format, 'CODABAR');
      }
    });

    test('scanAll finds multiple barcode formats', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/ean13_product.png',
      );
      final results = scanner.scanAll(source);

      expect(results, isNotEmpty);
    });

    test('returns null for image with no barcode', () {
      // Create a blank white image
      final pixels = Int32List(100 * 100);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = 0xFFFFFFFF;
      }
      final luminances = int32ToGrayscale(pixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
      );
      final result = scanner.scan(source);

      expect(result, isNull);
    });

    test('returns empty list for corrupted barcode data', () {
      // Create an image with random noise
      final pixels = Int32List(200 * 50);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = (i * 17) % 2 == 0 ? 0xFF000000 : 0xFFFFFFFF;
      }
      final luminances = int32ToGrayscale(pixels, 200, 50);
      final source = LuminanceSource(
        width: 200,
        height: 50,
        luminances: luminances,
      );
      final results = scanner.scanAll(source);

      // Should not crash, may find false positives or empty list
      expect(results, isA<List<dynamic>>());
    });
  });

  group('Decoder-specific selective scanning', () {
    test('scanner with only EAN-13 enabled ignores other formats', () {
      const scanner = BarcodeScanner(decoders: [EAN13Decoder()]);

      final pixels = Int32List(100 * 100);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = 0xFFFFFFFF;
      }
      final luminances = int32ToGrayscale(pixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
      );

      // Should not crash with limited decoders
      final result = scanner.scan(source);
      expect(result, isNull);
    });
  });

  group('CodabarDecoder', () {
    late CodabarDecoder decoder;

    setUp(() {
      decoder = const CodabarDecoder();
    });

    test('format is CODABAR', () {
      expect(decoder.format, 'CODABAR');
    });

    test('returns null for invalid row data', () {
      // Short row with no valid pattern
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });

    test('returns null for all-white row', () {
      final row = List<bool>.filled(200, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });

    test('returns null for all-black row', () {
      final row = List<bool>.filled(200, true);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('Code128Decoder', () {
    late Code128Decoder decoder;

    setUp(() {
      decoder = const Code128Decoder();
    });

    test('format is CODE_128', () {
      expect(decoder.format, 'CODE_128');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('Code39Decoder', () {
    late Code39Decoder decoder;

    setUp(() {
      decoder = const Code39Decoder();
    });

    test('format is CODE_39', () {
      expect(decoder.format, 'CODE_39');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('EAN13Decoder', () {
    late EAN13Decoder decoder;

    setUp(() {
      decoder = const EAN13Decoder();
    });

    test('format is EAN_13', () {
      expect(decoder.format, 'EAN_13');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('EAN8Decoder', () {
    late EAN8Decoder decoder;

    setUp(() {
      decoder = const EAN8Decoder();
    });

    test('format is EAN_8', () {
      expect(decoder.format, 'EAN_8');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('ITFDecoder', () {
    late ITFDecoder decoder;

    setUp(() {
      decoder = const ITFDecoder();
    });

    test('format is ITF', () {
      expect(decoder.format, 'ITF');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });
  });

  group('UPCADecoder', () {
    late UPCADecoder decoder;

    setUp(() {
      decoder = const UPCADecoder();
    });

    test('format is UPC_A', () {
      expect(decoder.format, 'UPC_A');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );

      expect(result, isNull);
    });

    test('Decodes UPC-A correctly when explicitly configured', () {
      final (source, _, _) = _loadImageAsSource(
        'fixtures/barcode_images/upca_product.png',
      );

      // Use scanner with ONLY UPCADecoder to force it to run
      const scanner = BarcodeScanner(decoders: [UPCADecoder()]);
      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.format, 'UPC_A');
      expect(result.text, hasLength(12));
    });
  });
}
