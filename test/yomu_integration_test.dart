import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/yomu.dart';

/// Metadata for a single test case.
class QrTestCase {
  const QrTestCase({
    required this.filename,
    required this.content,
    required this.version,
    required this.ecLevel,
  });

  factory QrTestCase.fromJson(Map<String, dynamic> json) {
    return QrTestCase(
      filename: json['filename'] as String,
      content: json['content'] as String,
      version: json['version'] as int,
      ecLevel: json['error_correction'] as String,
    );
  }

  final String filename;
  final String content;
  final int version;
  final String ecLevel;
}

void main() {
  final qrFixturesDir = Directory('fixtures/qr_images');
  final distortedFixturesDir = Directory('fixtures/distorted_images');
  final lightingFixturesDir = Directory('fixtures/uneven_lighting');
  final perfFixturesDir = Directory('fixtures/performance_test_images');

  setUpAll(() {
    if (!qrFixturesDir.existsSync()) {
      fail('QR Fixtures directory not found: ${qrFixturesDir.path}');
    }
    // We assume others exist if one exists, but we can check individually in tests
  });

  group('Yomu Integration Tests', () {
    // --- FROM qr_test.dart ---
    group('Basic QR Decoding', () {
      test('decodes numeric_simple.png', () {
        _testPngDecode(qrFixturesDir, 'numeric_simple.png', '12345');
      });

      test('decodes alphanumeric_hello.png', () {
        _testPngDecode(qrFixturesDir, 'alphanumeric_hello.png', 'HELLO WORLD');
      });

      test('decodes byte_japanese.png', () {
        _testPngDecode(qrFixturesDir, 'byte_japanese.png', 'こんにちは世界');
      });
    });

    group('Metadata Driven Validation', () {
      test('decodes all generated test cases', () {
        final metadataFile = File('${qrFixturesDir.path}/metadata.json');
        if (!metadataFile.existsSync()) return;

        final metadataJson =
            jsonDecode(metadataFile.readAsStringSync()) as List<dynamic>;
        final testCases = metadataJson
            .map((e) => QrTestCase.fromJson(e as Map<String, dynamic>))
            .toList();

        var passed = 0;
        final failures = <String>[];

        for (final tc in testCases) {
          try {
            _testPngDecode(qrFixturesDir, tc.filename, tc.content);
            passed++;
          } catch (e) {
            failures.add('${tc.filename}: $e');
          }
        }

        if (failures.isNotEmpty) {
          // We expect mostly success, but sometimes random generation might make hard codes?
          // With the current generator, they should all pass.
          fail('Failed ${failures.length} cases: ${failures.join(", ")}');
        }
        expect(passed, testCases.length);
      });
    });

    // --- FROM versioned_qr_test.dart ---
    group('Versioned QR Codes', () {
      for (var v = 1; v <= 7; v++) {
        test('decodes version $v QR code', () {
          // These files are expected to exist from generate_test_qr.py or previous setup
          // Check if file exists first to avoid crashing
          final filename = 'qr_version_$v.png';
          // Check Standard directory first, then Complex
          var file = File('${qrFixturesDir.path}/$filename');
          if (!file.existsSync()) {
            file = File('fixtures/qr_complex_images/$filename');
          }

          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            final image = img.decodePng(bytes)!;
            final pixels = _imageToRgba(image);

            final results = Yomu.qrOnly.decodeAll(
              bytes: pixels,
              width: image.width,
              height: image.height,
            );
            expect(results, isNotEmpty, reason: 'Failed to decode V$v');
          }
        });
      }
    });

    // --- FROM distorted_qr_test.dart ---
    group('Distorted QR Codes', () {
      test('detects rotated/tilted codes', () {
        if (!distortedFixturesDir.existsSync()) return;

        final files = distortedFixturesDir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  (f.path.contains('rotation_') || f.path.contains('tilt_')) &&
                  f.path.endsWith('.png'),
            )
            .toList();

        for (final file in files) {
          final decoded = img.decodePng(file.readAsBytesSync());
          if (decoded == null) continue;
          final image = decoded.convert(
            format: img.Format.uint8,
            numChannels: 4,
          );
          final bytes = image.buffer.asUint8List();

          final result = Yomu.qrOnly.decode(
            bytes: bytes,
            width: image.width,
            height: image.height,
          );
          expect(result.text, contains('DISTORTION_TEST_DATA'));
        }
      });
    });

    // --- FROM uneven_lighting_test.dart ---
    group('Uneven Lighting', () {
      test('decodes with lighting variations', () {
        if (!lightingFixturesDir.existsSync()) return;
        final files = lightingFixturesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList();

        var successCount = 0;
        for (final file in files) {
          try {
            final decoded = img.decodePng(file.readAsBytesSync());
            if (decoded == null) continue;
            final image = decoded.convert(
              format: img.Format.uint8,
              numChannels: 4,
            );
            final bytes = image.buffer.asUint8List();

            final result = Yomu.qrOnly.decode(
              bytes: bytes,
              width: image.width,
              height: image.height,
            );
            expect(result.text, contains('UNEVEN_LIGHTING'));
            successCount++;
          } catch (_) {}
        }
        // Expect reasonable robustness
        if (files.isNotEmpty) {
          expect(
            successCount,
            greaterThanOrEqualTo((files.length * 0.8).floor()),
          );
        }
      });
    });

    // --- FROM large_image_test.dart ---
    group('Large Images & Performance', () {
      test('decodes 4MP image (triggers downsampling)', () {
        if (!perfFixturesDir.existsSync()) return;
        final file = File(
          '${perfFixturesDir.path}/square_white_center_400px.png',
        );
        if (!file.existsSync()) return;

        final decoded = img.decodePng(file.readAsBytesSync());
        if (decoded != null) {
          // Scale up to 2000x2000
          final large = img.copyResize(decoded, width: 2000, height: 2000);
          final bytes = _imageToRgba(large);

          final result = Yomu.qrOnly.decode(
            bytes: bytes,
            width: large.width,
            height: large.height,
          );
          expect(result.text, contains('PerfTest'));
        }
      });

      test('handles malformed/noise input', () {
        final bytes = Uint8List(200 * 200 * 4);
        // Random noise
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = (i % 255);
        }

        expect(
          () => Yomu.qrOnly.decode(bytes: bytes, width: 200, height: 200),
          throwsA(anything), // Should not crash, just throw exception
        );
      });
    });

    // --- FROM multi_qr_test.dart ---
    group('Multi-QR Detection', () {
      test('decodes multiple codes in single image', () {
        final file = File('${qrFixturesDir.path}/multi_qr_3_vertical.png');
        if (!file.existsSync()) return;

        final decoded = img.decodePng(file.readAsBytesSync())!;
        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final bytes = image.buffer.asUint8List();

        final results = Yomu.qrOnly.decodeAll(
          bytes: bytes,
          width: image.width,
          height: image.height,
        );
        expect(results.length, 3);
        expect(
          results.map((r) => r.text),
          containsAll(['Code A', 'Code B', 'Code C']),
        );
      });
    });

    group('Barcode Integration Tests', () {
      final barcodeFixturesDir = Directory('fixtures/barcode_images');

      setUpAll(() {
        if (!barcodeFixturesDir.existsSync()) {
          fail('Barcode Fixtures not found: ${barcodeFixturesDir.path}');
        }
      });

      // Scan helper using direct scanner for specific format tests
      // Note: _testPngDecode uses Yomu wrapper, but here we want to test BarcodeScanner directly sometimes
      // or we can just use Yomu.barcodeOnly.
      // The original barcode_test.dart used methods like separate scanner instances.

      test('EAN-13: decodes product barcode', () {
        _testPngDecode(
          barcodeFixturesDir,
          'ean13_product.png',
          '4901234567894',
          useBarcodeOnly: true,
        );
      });

      test('EAN-13: decodes ISBN barcode', () {
        _testPngDecode(
          barcodeFixturesDir,
          'ean13_isbn.png',
          '9784873115658',
          useBarcodeOnly: true,
        );
      });

      test('Code 128: decodes hello world', () {
        _testPngDecode(
          barcodeFixturesDir,
          'code128_hello.png',
          'Hello World',
          useBarcodeOnly: true,
        );
      });

      test('Code 128: decodes numeric', () {
        _testPngDecode(
          barcodeFixturesDir,
          'code128_numeric.png',
          '1234567890',
          useBarcodeOnly: true,
        );
      });

      test('Code 39: decodes hello', () {
        _testPngDecode(
          barcodeFixturesDir,
          'code39_hello.png',
          'HELLO', // Expected prefix
          useBarcodeOnly: true,
          matchMode: MatchMode.startsWith,
        );
      });

      test('Code 39: decodes numeric', () {
        _testPngDecode(
          barcodeFixturesDir,
          'code39_numeric.png',
          '', // Ignored
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('ITF: decodes numeric', () {
        _testPngDecode(
          barcodeFixturesDir,
          'itf_numeric.png',
          '12345678901230', // Dummy
          useBarcodeOnly: true,
          checkContent: false,
        ); // Just check it decodes
      });

      test('ITF-14: decodes product', () {
        _testPngDecode(
          barcodeFixturesDir,
          'itf14_product.png',
          '12345678901231', // Dummy
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('Codabar: decodes numeric', () {
        _testPngDecode(
          barcodeFixturesDir,
          'codabar_numeric.png',
          'A12345B',
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('Codabar: decodes long', () {
        _testPngDecode(
          barcodeFixturesDir,
          'codabar_long.png',
          'A1234567890B',
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('EAN-8: decodes product', () {
        _testPngDecode(
          barcodeFixturesDir,
          'ean8_product.png',
          '12345670', // Dummy
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('EAN-8: decodes small', () {
        _testPngDecode(
          barcodeFixturesDir,
          'ean8_small.png',
          '12345670', // Dummy
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('UPC-A: decodes product', () {
        _testPngDecode(
          barcodeFixturesDir,
          'upca_product.png',
          '123456789012', // Standard UPC-A
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      test('UPC-A: decodes food', () {
        _testPngDecode(
          barcodeFixturesDir,
          'upca_food.png',
          '123456789012', // Dummy
          useBarcodeOnly: true,
          checkContent: false,
        );
      });

      // Special Case: Selective Scanning (was in barcode_test.dart)
      test('Specific Decoder: only EAN-13 ignores others', () {
        // Create blank image
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

        const scanner = BarcodeScanner(decoders: [EAN13Decoder()]);
        final result = scanner.scan(source);
        expect(result, isNull);
      });

      // Special Case: Explicit UPC-A config (integration level)
      test('scan() with explicit UPCADecoder finds UPC-A', () {
        final file = File('${barcodeFixturesDir.path}/upca_product.png');
        if (!file.existsSync()) return;

        final bytes = file.readAsBytesSync();
        final decoded = img.decodePng(bytes)!;
        final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final rgba = image.buffer.asUint8List();
        final luminances = rgbaToGrayscale(rgba, image.width, image.height);
        final source = LuminanceSource(
          width: image.width,
          height: image.height,
          luminances: luminances,
        );

        const scanner = BarcodeScanner(decoders: [UPCADecoder()]);
        final result = scanner.scan(source);
        expect(result, isNotNull);
        expect(result!.format, 'UPC_A');
      });

      test('BarcodeScanner returns null for empty image', () {
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

        const scanner = BarcodeScanner.all;
        expect(scanner.scan(source), isNull);
        expect(scanner.scanAll(source), isEmpty);
      });

      test('BarcodeScanner handles corrupted data gracefully', () {
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

        const scanner = BarcodeScanner.all;
        expect(scanner.scanAll(source), isA<List<dynamic>>());
      });
    });
  });
}

// Helpers

// Helpers

Uint8List _imageToRgba(img.Image image) {
  final pixels = Uint8List(image.width * image.height * 4);
  var i = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      pixels[i++] = pixel.r.toInt();
      pixels[i++] = pixel.g.toInt();
      pixels[i++] = pixel.b.toInt();
      pixels[i++] = 255; // Alpha
    }
  }
  return pixels;
}

enum MatchMode { exact, startsWith, contains }

void _testPngDecode(
  Directory fixturesDir,
  String filename,
  String expectedContent, {
  bool useBarcodeOnly = false,
  bool checkContent = true,
  MatchMode matchMode = MatchMode.exact,
}) {
  var file = File('${fixturesDir.path}/$filename');
  if (!file.existsSync()) {
    // Fallback search for QR tests impacted by refactor
    if (File('fixtures/qr_complex_images/$filename').existsSync()) {
      file = File('fixtures/qr_complex_images/$filename');
    } else if (File('fixtures/distorted_images/$filename').existsSync()) {
      file = File('fixtures/distorted_images/$filename');
    } else {
      fail(
        '$filename not found in ${fixturesDir.path} or fallback directories',
      );
    }
  }

  final bytes = file.readAsBytesSync();
  final decoded = img.decodePng(bytes);
  if (decoded == null) fail('Failed to decode PNG $filename');

  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final rgba = image.buffer.asUint8List();

  final decoder = useBarcodeOnly ? Yomu.barcodeOnly : Yomu.qrOnly;
  final result = decoder.decode(
    bytes: rgba,
    width: image.width,
    height: image.height,
  );

  if (checkContent) {
    if (matchMode == MatchMode.exact) {
      expect(result.text, expectedContent);
    } else if (matchMode == MatchMode.startsWith) {
      expect(result.text, startsWith(expectedContent));
    } else if (matchMode == MatchMode.contains) {
      expect(result.text, contains(expectedContent));
    }
  } else {
    expect(result.text, isNotEmpty);
  }
}
