import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/decoder/reed_solomon_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';
import 'package:yomu/src/qr/version.dart';
import 'package:yomu/src/yomu_exception.dart';

// Helper to access BitMatrixParser if it's not exported.
// Note: In yomu/lib/src/qr/decoder/qrcode_decoder.dart, BitMatrixParser is public class.
// But it is in 'qrcode_decoder.dart'.
// If 'bit_matrix_parser.dart' does not exist as separate file (as seen in my previous ls),
// then it is defined inside 'qrcode_decoder.dart'.
// I need to import 'package:yomu/src/qr/decoder/qrcode_decoder.dart'.

void main() {
  group('BitMatrixParser', () {
    test(
      'readFormatInformation returns non-null for empty matrix (0s may map to valid)',
      () {
        // Empty matrix (all 0s) apparently maps to a valid format info with error correction
        final matrix = BitMatrix(width: 21);
        final parser = BitMatrixParser(matrix);
        expect(parser.readFormatInformation(), isNotNull);
      },
    );

    test('readVersion returns version from dimension (V1-V6)', () {
      // Dimension 21 -> Version 1
      final matrix = BitMatrix(width: 21);
      final parser = BitMatrixParser(matrix);
      final version = parser.readVersion();
      expect(version.versionNumber, 1);
    });

    test('readVersion throws if dimension is too small', () {
      final matrix = BitMatrix(width: 10);
      final parser = BitMatrixParser(matrix);
      expect(() => parser.readVersion(), throwsA(isA<DecodeException>()));
    });

    test('readVersion falls back to second block or provisional', () {
      // Create a BitMatrix with dimension 45 (Version 7)
      // Dimension 45 -> (45-17)/4 = 7.
      final matrix = BitMatrix(width: 45, height: 45);

      // We need to verify that readVersion attempts to read version info.
      // Since the matrix is empty (all zeros), version decoding will fail for both blocks
      // (BCH check fails for 0x00000).
      // So it should fall back to provisional version 7.
      final parser = BitMatrixParser(matrix);
      final version = parser.readVersion();
      expect(version.versionNumber, 7);
    });

    test('readCodewords extracts bytes', () {
      // Minimal test, all zeros
      final matrix = BitMatrix(width: 21);
      final parser = BitMatrixParser(matrix);
      final version = Version.getVersionForNumber(1);
      // Unmasked shouldn't matter for pure extraction if we just want to see it run
      // But wait, it uses isFunctionPattern which calls version.
      final codewords = parser.readCodewords(
        unmasked: matrix,
        version: version,
      );
      // V1 has 26 codewords
      expect(codewords.length, 26);
    });
  });

  group('QRCodeDecoder', () {
    test('decode throws DecodeException on invalid format info', () {
      final matrix = BitMatrix(width: 21);
      // Empty matrix has invalid format info usually
      expect(
        () => QRCodeDecoder().decode(matrix),
        throwsA(isA<DecodeException>()),
      );
    });

    test('decode covers V7+ version reading logic', () {
      final decoder = QRCodeDecoder();
      // Version 7 is 45x45
      final matrix = BitMatrix(width: 45, height: 45);
      expect(() => decoder.decode(matrix), throwsA(isA<DecodeException>()));
    });

    test('decode decodes valid V1 QR code (Happy Path)', () {
      final decoder = QRCodeDecoder();
      final imageMatrix = _loadBitMatrix('version_1.png');

      // Use Detector to extract the QR code bits from the simulated camera image
      final detector = Detector(imageMatrix);
      final validBits = detector.detect().bits;

      final result = decoder.decode(validBits);
      expect(result.text, 'Hi');
    });

    test('decode decodes valid V5 QR code (Multi-block/Interleaved)', () {
      final decoder = QRCodeDecoder();
      // Version 5 (37x37) has multiple EC blocks, triggering interleaving logic
      final imageMatrix = _loadBitMatrix('version_5.png');

      final detector = Detector(imageMatrix);
      final validBits = detector.detect().bits;

      final result = decoder.decode(validBits);
      // Content from generate_test_qr.py: "This is Version 5 QR code with more content"
      expect(result.text, contains('Version 5'));
    });

    test('decode decodes valid V10 QR code (Complex)', () {
      final decoder = QRCodeDecoder();
      final imageMatrix = _loadBitMatrix('version_10.png');

      final detector = Detector(imageMatrix);
      final validBits = detector.detect().bits;

      final result = decoder.decode(validBits);
      // Content: "A" * 150
      expect(result.text, contains('AAAA'));
      expect(result.text.length, 150);
    });

    test('decode throws DecodeException on invalid version', () {
      // Need valid format info but invalid version?
      // Version is inferred from dimension for small versions (1-6).
      // So hard to have "invalid version" for V1 unless dimension is wrong.
      // But BitMatrixParser.readVersion throws if dimension < 17.
      final decoder = QRCodeDecoder();
      final matrix = BitMatrix(width: 10); // Too small
      expect(() => decoder.decode(matrix), throwsA(isA<DecodeException>()));
    });

    test('decode rethrows YomuException', () {
      // Setup a condition that throws a specific YomuException
      // e.g. detection error if we were detecting.
      // But decode takes a BitMatrix.
      // If we pass too small matrix, it throws DecodeException (which is YomuException).
      final decoder = QRCodeDecoder();
      final matrix = BitMatrix(width: 10);
      expect(() => decoder.decode(matrix), throwsA(isA<YomuException>()));
    });

    // We need to test the "catch (e)" path that wraps non-Yomu exceptions.
    // How to trigger a non-Yomu exception inside decode?
    // Maybe mock RS decoder to throw StateError?

    test('decode wraps unknown exceptions', () {
      // We need it to reach RS decode phase.
      // This requires valid format info, version, etc.
      // Constructing a valid QR matrix manually is hard.
      // Maybe we can test `rsDecode` static method directly if accessible?
      // `QRCodeDecoder.rsDecode` is visible for testing.

      expect(
        () => QRCodeDecoder.rsDecode(
          codewords: [1, 2, 3],
          ecCount: 2,
          rsDecoder: _MockThrowingRSDecoder(),
        ),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('RS error'),
          ),
        ),
      );
    });

    test('rsDecode throws DecodeException on real RS failure', () {
      // RS(4, 2) -> 2 data, 2 ec
      // Codewords: [1, 2, 3, 4]
      // Corrupt them heavily
      final codewords = [100, 200, 3, 4];
      final rsDecoder = ReedSolomonDecoder(GenericGF.qrCodeField256);

      expect(
        () => QRCodeDecoder.rsDecode(
          codewords: codewords,
          ecCount: 2,
          rsDecoder: rsDecoder,
        ),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('RS error'),
          ),
        ),
      );
    });
  });
}

class _MockThrowingRSDecoder implements ReedSolomonDecoder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void decode({required List<int> received, required int twoS}) {
    throw StateError('Unexpected error');
  }
}

BitMatrix _loadBitMatrix(String filename) {
  final path = 'fixtures/qr_images/$filename';
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Fixture not found: $path. Run scripts/generate_test_qr.py',
    );
  }

  final bytes = file.readAsBytesSync();
  final decoded = img.decodePng(bytes)!;
  // Convert to RGBA 8-bit
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);

  final width = image.width;
  final height = image.height;

  // Extract bytes (RGBA)
  // image.buffer is ByteBuffer. image.toUint8List() gives the flat list.
  // Note: 'image' package v4 logic.
  final pixels = Uint8List(width * height * 4);

  // Manually copy to be safe, or use image.getBytes() if reliable.
  // qyuto_test.dart does manual copy loop. Let's replicate for safety/consistency.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      final offset = (y * width + x) * 4;
      pixels[offset] = pixel.r.toInt();
      pixels[offset + 1] = pixel.g.toInt();
      pixels[offset + 2] = pixel.b.toInt();
      pixels[offset + 3] = pixel.a.toInt();
    }
  }

  // Convert to grayscale
  final luminances = rgbaToGrayscale(pixels, width, height);

  // Binarize
  final source = LuminanceSource(
    width: width,
    height: height,
    luminances: luminances,
  );
  final binarizer = Binarizer(source);
  return binarizer.getBlackMatrix();
}
