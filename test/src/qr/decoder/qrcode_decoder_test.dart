import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/src/qr/decoder/format_information.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
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

    test('readVersion throws for a size no version has', () {
      // Every symbol is 17 + 4v modules wide.
      for (final dimension in [18, 20, 22, 23, 24, 46]) {
        expect(
          () => BitMatrixParser(BitMatrix(width: dimension)).readVersion(),
          throwsA(isA<DecodeException>()),
          reason: '$dimension',
        );
      }
    });

    test('readVersion ignores version information for another size', () {
      // Both version blocks of a 45-module (version 7) grid read as
      // version 8, which is 49 modules wide.
      const version8 = 0x085BC;
      final matrix = BitMatrix(width: 45);
      var bit = 17;
      for (var y = 5; y >= 0; y--) {
        for (var x = 45 - 9; x >= 45 - 11; x--) {
          if ((version8 >> bit) & 1 == 1) matrix.set(x, y);
          bit--;
        }
      }
      bit = 17;
      for (var x = 5; x >= 0; x--) {
        for (var y = 45 - 9; y >= 45 - 11; y--) {
          if ((version8 >> bit) & 1 == 1) matrix.set(x, y);
          bit--;
        }
      }
      expect(Version.decodeVersionInformation(version8)!.versionNumber, 8);

      expect(BitMatrixParser(matrix).readVersion().versionNumber, 7);
    });

    test('readCodewords extracts bytes', () {
      // Minimal test, all zeros
      final matrix = BitMatrix(width: 21);
      final parser = BitMatrixParser(matrix);
      final version = Version.getVersionForNumber(1);
      // Unmasked shouldn't matter for pure extraction if we just want to see it run
      // But wait, it uses isFunctionPattern which calls version.
      final codewords = parser.readCodewords(version: version);
      // V1 has 26 codewords
      expect(codewords.length, 26);
    });
  });

  group('QRCodeDecoder', () {
    test('decode throws DecodeException on invalid format info', () {
      final matrix = BitMatrix(width: 21);
      // Empty matrix has invalid format info usually
      expect(
        () => const QRCodeDecoder().decode(matrix),
        throwsA(isA<DecodeException>()),
      );
    });

    test('decode covers V7+ version reading logic', () {
      const decoder = QRCodeDecoder();
      // Version 7 is 45x45
      final matrix = BitMatrix(width: 45, height: 45);
      expect(() => decoder.decode(matrix), throwsA(isA<DecodeException>()));
    });

    test('decode decodes valid V1 QR code (Happy Path)', () {
      const decoder = QRCodeDecoder();
      final imageMatrix = _loadBitMatrix('version_1.png');

      // Use Detector to extract the QR code bits from the simulated camera image
      final detector = Detector(imageMatrix);
      final validBits = detector.detect().bits;

      final result = decoder.decode(validBits);
      expect(result.text, 'Hi');
    });

    test('decode decodes valid V5 QR code (Multi-block/Interleaved)', () {
      const decoder = QRCodeDecoder();
      // Version 5 (37x37) has multiple EC blocks, triggering interleaving logic
      final imageMatrix = _loadBitMatrix('version_5.png');

      final detector = Detector(imageMatrix);
      final validBits = detector.detect().bits;

      final result = decoder.decode(validBits);
      // Content from generate_test_qr.py: "This is Version 5 QR code with more content"
      expect(result.text, contains('Version 5'));
    });

    test('decode decodes valid V10 QR code (Complex)', () {
      const decoder = QRCodeDecoder();
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
      const decoder = QRCodeDecoder();
      final matrix = BitMatrix(width: 10); // Too small
      expect(() => decoder.decode(matrix), throwsA(isA<DecodeException>()));
    });

    test('decode rethrows YomuException', () {
      // Setup a condition that throws a specific YomuException
      // e.g. detection error if we were detecting.
      // But decode takes a BitMatrix.
      // If we pass too small matrix, it throws DecodeException (which is YomuException).
      const decoder = QRCodeDecoder();
      final matrix = BitMatrix(width: 10);
      expect(() => decoder.decode(matrix), throwsA(isA<YomuException>()));
    });

    // We need to test the "catch (e)" path that wraps non-Yomu exceptions.
    // How to trigger a non-Yomu exception inside decode?
    // Maybe mock RS decoder to throw StateError?

    test('decode throws a DecodeException for a size no version has', () {
      // 18 modules: past the 17 readVersion checks for, short of version 1.
      expect(
        () => const QRCodeDecoder().decode(BitMatrix(width: 18)),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            isNot(startsWith('Decoding failed')),
          ),
        ),
      );
    });

    test('decode lets a Reed-Solomon failure through as it is', () {
      final bits = Detector(_loadBitMatrix('version_1.png')).detect().bits;
      // Flip the data region: far more errors than version 1 corrects.
      for (var y = 9; y < bits.height; y++) {
        for (var x = 9; x < bits.width; x++) {
          bits.flip(x, y);
        }
      }

      expect(
        () => const QRCodeDecoder().decode(bits),
        throwsA(isA<ReedSolomonException>()),
      );
    });

    test('decode rejects a grid whose data is not a bit stream', () {
      // Sampled by the bottom-right grid search from a mirror image of
      // fixtures/qr_images/multi_qr_3_vertical.png: its format information
      // reads as L with mask 0 and its codewords pass Reed-Solomon, but the
      // data opens with the mode indicator 1110, which no mode has. This
      // used to decode to an empty text.
      const rows = [
        '########.#.....###...',
        '......##.#..##.....#.',
        '..###.##..###.#.###..',
        '..###.##.####.#.###..',
        '..###.##...#..#.####.',
        '......##..##..#....#.',
        '#######..#.#..###....',
        '.........#..#.#..#.#.',
        '###.#####.##.##.###..',
        '....##.......######..',
        '###.###..####.#...#..',
        '..#.#....#....#.##.#.',
        '##.##.#...####..##...',
        '.........#.#####.##..',
        '#######.########..##.',
        '#.....#.#.##..#..#...',
        '..###.#...##..#..#.#.',
        '..###.#.##....####...',
        '..###.#.###.#.......#',
        '......#..#.......####',
        '#####........#######.',
      ];
      final bits = BitMatrix(width: 21);
      for (var y = 0; y < rows.length; y++) {
        for (var x = 0; x < rows[y].length; x++) {
          if (rows[y][x] == '#') bits.set(x, y);
        }
      }

      expect(
        () => const QRCodeDecoder().decode(bits),
        throwsA(isA<DecodeException>()),
      );
    });
  });

  group('Mirror imaging', () {
    // ISO/IEC 18004:2015, 6.2: mirror imaging interchanges the row and
    // column positions of the modules, so a mirror-image symbol samples as
    // the transpose of its normal grid.
    BitMatrix sampled(String filename) =>
        Detector(_loadBitMatrix(filename)).detect().bits;

    const fixtures = ['version_1.png', 'version_5.png', 'version_10.png'];

    test('readFormatWords reads what readFormatInformation reads', () {
      final random = Random(18004);
      for (var i = 0; i < 500; i++) {
        final dim = 21 + 4 * random.nextInt(40);
        final bits = BitMatrix(width: dim);
        for (var y = 0; y < dim; y++) {
          for (var x = 0; x < dim; x++) {
            if (random.nextBool()) bits.set(x, y);
          }
        }
        final parser = BitMatrixParser(bits);
        final (word1, word2) = parser.readFormatWords();
        final expected = parser.readFormatInformation();
        final actual = FormatInformation.decodeFormatInformation(word1, word2);

        expect(actual?.errorCorrectionLevel, expected?.errorCorrectionLevel);
        expect(actual?.dataMask, expected?.dataMask);
        // And the transposed reading is the normal reading of the
        // transpose.
        expect(
          parser.readFormatWords(transposed: true),
          BitMatrixParser(bits.transposed()).readFormatWords(),
        );
      }
    });

    test('readsAsMirrorImage holds for a transposed grid', () {
      for (final filename in fixtures) {
        expect(
          BitMatrixParser(sampled(filename).transposed()).readsAsMirrorImage(),
          isTrue,
          reason: filename,
        );
      }
    });

    test('readsAsMirrorImage does not hold for a normal grid', () {
      // Read backwards, most format information codewords still lie within
      // three bits of another one, so a normal grid would pass a check of
      // the mirrored reading alone.
      for (final filename in fixtures) {
        expect(
          BitMatrixParser(sampled(filename)).readsAsMirrorImage(),
          isFalse,
          reason: filename,
        );
      }
    });

    test('readsAsMirrorImage needs both mirrored copies to read', () {
      final bits = sampled('version_1.png');
      // Four errors in the second copy, beyond what it may correct.
      final dim = bits.height;
      for (var i = 1; i <= 4; i++) {
        bits.flip(8, dim - i);
      }

      // The normal reading still takes the intact first copy...
      expect(BitMatrixParser(bits).readFormatInformation(), isNotNull);
      // ...but the mirrored one does not settle for one.
      expect(BitMatrixParser(bits.transposed()).readsAsMirrorImage(), isFalse);
    });

    test('readsAsMirrorImage does not hold for a blank grid', () {
      // The lenient reading accepts this one (see above).
      expect(
        BitMatrixParser(BitMatrix(width: 21)).readsAsMirrorImage(),
        isFalse,
      );
    });

    for (final (filename, text) in [
      ('version_1.png', 'Hi'),
      ('version_5.png', null),
      ('version_10.png', null),
    ]) {
      test('decode reads a mirror-image $filename', () {
        const decoder = QRCodeDecoder();
        final bits = sampled(filename);
        final expected = text ?? decoder.decode(bits).text;
        final transposed = bits.transposed();
        final before = Uint32List.fromList(transposed.bits);

        expect(decoder.decode(transposed).text, expected);
        // Like the normal reading, the mirror reading leaves its input as
        // it found it.
        expect(transposed.bits, before);
      });
    }

    test('decode throws when the mirror reading fails too', () {
      const decoder = QRCodeDecoder();
      final transposed = sampled('version_5.png').transposed();
      // Clear the data region: the mirrored format information still reads,
      // so the mirror reading runs, and fails.
      for (var y = 9; y < transposed.height - 9; y++) {
        for (var x = 9; x < transposed.width - 9; x++) {
          if (transposed.get(x, y)) transposed.flip(x, y);
        }
      }
      expect(BitMatrixParser(transposed).readsAsMirrorImage(), isTrue);
      final before = Uint32List.fromList(transposed.bits);

      expect(() => decoder.decode(transposed), throwsA(isA<DecodeException>()));
      expect(transposed.bits, before);
    });
  });
}

BitMatrix _loadBitMatrix(String filename) {
  var path = 'fixtures/qr_images/$filename';
  var file = File(path);
  if (!file.existsSync()) {
    // Try complex images
    path = 'fixtures/qr_complex_images/$filename';
    file = File(path);
  }

  if (!file.existsSync()) {
    throw StateError(
      'Fixture not found in qr_images or qr_complex_images: $filename. Run scripts/generate_test_qr.py',
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
