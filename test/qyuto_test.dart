/// Integration tests that decode QR codes from generated PNG images.
///
/// Before running these tests, generate test images with:
///   python3 scripts/generate_test_qr.py
///
/// Test images are stored in test/fixtures/qr_images/
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
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
  final fixturesDir = Directory('fixtures/qr_images');
  // Check fixtures exist
  if (!fixturesDir.existsSync()) {
    fail('Test fixtures not found. Run: python3 scripts/generate_test_qr.py');
  }

  // Load metadata
  final metadataFile = File('${fixturesDir.path}/metadata.json');
  if (!metadataFile.existsSync()) {
    fail('metadata.json not found. Regenerate fixtures.');
  }

  final metadataJson =
      jsonDecode(metadataFile.readAsStringSync()) as List<dynamic>;
  final testCases = metadataJson
      .map((e) => QrTestCase.fromJson(e as Map<String, dynamic>))
      .toList();

  group('PNG Image Integration Tests', () {
    test('fixtures are available', () {
      expect(testCases, isNotEmpty);
    });

    group('Numeric Mode', () {
      test('decodes numeric_simple.png', () {
        _testPngDecode(fixturesDir, 'numeric_simple.png', '12345');
      });

      test('decodes numeric_zeros.png', () {
        _testPngDecode(fixturesDir, 'numeric_zeros.png', '000000');
      });
    });

    group('Alphanumeric Mode', () {
      test('decodes alphanumeric_hello.png', () {
        _testPngDecode(fixturesDir, 'alphanumeric_hello.png', 'HELLO WORLD');
      });
    });

    group('Byte Mode', () {
      test('decodes byte_lowercase.png', () {
        _testPngDecode(fixturesDir, 'byte_lowercase.png', 'Hello, World!');
      });

      test('decodes byte_japanese.png', () {
        _testPngDecode(fixturesDir, 'byte_japanese.png', 'こんにちは世界');
      });
    });

    group('Version Tests', () {
      test('decodes version_1.png (21x21)', () {
        _testPngDecode(fixturesDir, 'version_1.png', 'Hi');
      });

      test('decodes version_2.png (25x25)', () {
        _testPngDecode(fixturesDir, 'version_2.png', 'Version 2 QR');
      });
    });

    group('All Generated Test Cases', () {
      test('decode all test cases from metadata', () {
        var passed = 0;
        var failed = 0;
        final failures = <String>[];

        for (final tc in testCases) {
          try {
            _testPngDecode(fixturesDir, tc.filename, tc.content);
            passed++;
          } catch (e) {
            failed++;
            failures.add('${tc.filename}: $e');
          }
        }

        if (failed > 0) {
          fail('Failed to decode $failed QR codes: ${failures.join(", ")}');
        }

        expect(passed, testCases.length);
      });
    });

    group('Barcode Integration Tests', () {
      final barcodeFixturesDir = Directory('fixtures/barcode_images');
      if (!barcodeFixturesDir.existsSync()) {
        fail(
          'Barcode fixtures not found. Run: python3 scripts/generate_barcodes.py',
        );
      }

      final barcodeMetadataFile = File(
        '${barcodeFixturesDir.path}/metadata.json',
      );
      if (!barcodeMetadataFile.existsSync()) {
        fail('barcode metadata.json not found. Regenerate fixtures.');
      }

      final barcodeMetadata =
          jsonDecode(barcodeMetadataFile.readAsStringSync()) as List<dynamic>;

      for (final element in barcodeMetadata) {
        final item = element as Map<String, dynamic>;
        final filename = item['filename'] as String;
        final content = item['content'] as String;
        final format = item['format'] as String;

        test('decodes $format ($filename)', () {
          _testPngDecode(
            barcodeFixturesDir,
            filename,
            content,
            useBarcodeOnly: true,
          );
        });
      }
    });
  });
}

/// Loads a PNG image and decodes it with yomu.
void _testPngDecode(
  Directory fixturesDir,
  String filename,
  String expectedContent, {
  bool useBarcodeOnly = false,
}) {
  final imageFile = File('${fixturesDir.path}/$filename');
  if (!imageFile.existsSync()) {
    fail('Image not found: $filename');
  }

  // Read PNG using image package
  final pngBytes = imageFile.readAsBytesSync();
  final decoded = img.decodePng(pngBytes);
  if (decoded == null) {
    fail('Failed to decode PNG: $filename');
  }

  // Convert to RGBA 8-bit to handle palettes/1-bit depth automatically
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

  // Convert to RGBA byte array
  final width = image.width;
  final height = image.height;
  final pixels = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      final offset = (y * width + x) * 4;

      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();

      pixels[offset] = r;
      pixels[offset + 1] = g;
      pixels[offset + 2] = b;
      pixels[offset + 3] = a;
    }
  }

  // Decode with yomu
  final decoder = useBarcodeOnly ? Yomu.barcodeOnly : Yomu.qrOnly;
  final result = decoder.decode(bytes: pixels, width: width, height: height);

  expect(result.text, expectedContent);
}
