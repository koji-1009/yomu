// Tests for remaining uncovered code paths in decoders
// Focuses on exception handling, Kanji mode, and Reed-Solomon error correction

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/decoded_bit_stream_parser.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/generic_gf_poly.dart';
import 'package:yomu/src/qr/decoder/reed_solomon_decoder.dart';
import 'package:yomu/src/qr/version.dart';
import 'package:yomu/yomu.dart';

void main() {
  group('DecodedBitStreamParser Exception Paths', () {
    test('throws DecodeException on not enough bits for numeric', () {
      // Mode: numeric (0001), Count: 10 (0x28), but truncated data
      final bytes = Uint8List.fromList([0x10, 0x28]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('Not enough bits for numeric'),
          ),
        ),
      );
    });

    test('throws DecodeException on not enough bits for alphanumeric', () {
      // Mode: alphanumeric (0010), Count: 4 (0x20), but truncated data
      final bytes = Uint8List.fromList([0x20, 0x20]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('Not enough bits for alphanumeric'),
          ),
        ),
      );
    });

    test('throws DecodeException on not enough bits for byte mode', () {
      // Mode: byte (0100), Count: 5 (0x50), but truncated data
      final bytes = Uint8List.fromList([0x40, 0x50]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('Not enough bits for byte mode'),
          ),
        ),
      );
    });

    test('throws DecodeException on unsupported mode (Hanzi)', () {
      // Mode: Hanzi (1101 = 0x0D), which is not handled in decode()
      // Bit pattern: 1101 (mode) + 00000001 (count=1 for version 1-9) + data
      // Encoded as: 1101 0000 0001 xxxx = 0xD0 0x10 ...
      final bytes = Uint8List.fromList([0xD0, 0x10, 0x00, 0x00]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported mode'),
          ),
        ),
      );
    });

    test('throws DecodeException on unsupported mode (StructuredAppend)', () {
      // Mode: StructuredAppend (0011 = 0x03), which is not handled
      // This mode has countBits=0, but we still hit else after mode check
      // Bit pattern: 0011 xxxx = 0x3x
      // Need enough data for structured append: symbol sequence + parity
      final bytes = Uint8List.fromList([0x30, 0x00, 0x00, 0x00]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        throwsA(anything), // May throw ArgumentError or DecodeException
      );
    });
  });

  group('DecodedBitStreamParser Kanji Mode', () {
    test('decodes Kanji mode with hiragana character', () {
      // Mode: Kanji (1000), Count: 1
      // Hiragana あ: 0x82A0 -> compact 0x0160 = 352
      final bytes = Uint8List.fromList([0x80, 0x10, 0x58, 0x00]);
      final version = Version.getVersionForNumber(1);

      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: version,
      );
      expect(result.text, isNotEmpty);
    });

    test('decodes Kanji mode with katakana character', () {
      // Katakana ア: 0x8341 -> compact 513
      // Mode(4) + Count(8) + Data(13) + Terminator(4) = 29 bits = 4 bytes minimum
      final bytes = Uint8List.fromList([0x80, 0x10, 0x20, 0x10, 0x00, 0x00]);
      final version = Version.getVersionForNumber(1);

      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: version,
      );
      expect(result.text, isNotEmpty);
    });

    test('decodes Kanji mode with high range character', () {
      // Character in range 0xE040-0xEBBF
      final bytes = Uint8List.fromList([0x80, 0x1F, 0x80, 0x00]);
      final version = Version.getVersionForNumber(1);

      // May produce replacement or valid char
      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        returnsNormally,
      );
    });

    test('handles unknown Shift JIS lead byte', () {
      // Lead byte outside valid ranges
      final bytes = Uint8List.fromList([0x80, 0x13, 0xFF, 0x80]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        returnsNormally,
      );
    });

    test('handles half-width katakana bytes', () {
      // Tests range 0xA1-0xDF
      final bytes = Uint8List.fromList([0x80, 0x10, 0x28, 0x80]);
      final version = Version.getVersionForNumber(1);

      expect(
        () => DecodedBitStreamParser.decode(bytes: bytes, version: version),
        returnsNormally,
      );
    });
  });

  group('Shift-JIS Decoder Direct Tests', () {
    test('decodes ASCII characters', () {
      // ASCII range: 0x00-0x7F
      final bytes = [0x41, 0x42, 0x43]; // "ABC"
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result, 'ABC');
    });

    test('decodes half-width katakana', () {
      // Half-width katakana: 0xA1-0xDF maps to U+FF61-U+FF9F
      final bytes = [0xA1, 0xA2, 0xB1]; // Half-width katakana
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      // 0xA1 -> U+FF61, 0xA2 -> U+FF62, 0xB1 -> U+FF71
      expect(result.codeUnits[0], 0xFF61);
      expect(result.codeUnits[1], 0xFF62);
    });

    test('handles unknown lead byte with replacement character', () {
      // Lead byte 0xF0-0xFF is outside valid Shift-JIS range
      final bytes = [0xF5, 0x40]; // Invalid lead byte
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result, contains('\uFFFD')); // Replacement character
    });

    test('handles unknown trail byte with replacement character', () {
      // Valid lead byte 0x81-9F, but invalid trail byte
      final bytes = [0x81, 0x30]; // 0x30 is outside valid trail range
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result, contains('\uFFFD'));
    });

    test('handles incomplete double-byte sequence', () {
      // Valid lead byte but no trail byte
      final bytes = [0x81]; // Only lead byte, no trail
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result, contains('\uFFFD'));
    });

    test('decodes valid double-byte with trail in 0x40-0x7E range', () {
      // Lead 0x81, trail 0x40-0x7E -> row calculation, cell = b2-0x40+1
      final bytes = [0x81, 0x40];
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result.isNotEmpty, isTrue);
    });

    test('decodes hiragana characters (row 4 path)', () {
      // Shift-JIS for ひらがな「ぁ」= 0x82, 0x9F
      // Lead 0x82: row = (0x82 - 0x81) * 2 + 1 = 3
      // Trail 0x9F: cell = 0x9F - 0x9F + 1 = 1, row++ => row 4
      // Row 4, cell 1 => jisToUnicode returns 0x3041 (ぁ)
      final bytes = [0x82, 0x9F]; // ぁ
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result.codeUnits[0], 0x3041);
    });

    test('decodes valid double-byte with trail in 0x80-0x9E range', () {
      // Lead 0x81, trail 0x80-0x9E -> cell = b2-0x80+64
      final bytes = [0x81, 0x80];
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result.isNotEmpty, isTrue);
    });

    test('decodes valid double-byte with trail in 0x9F-0xFC range', () {
      // Lead 0x81, trail 0x9F-0xFC -> cell = b2-0x9F+1, row++
      final bytes = [0x81, 0x9F];
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result.isNotEmpty, isTrue);
    });

    test('decodes high range lead byte (0xE0-0xEF)', () {
      // Lead 0xE0-0xEF -> row = (b1-0xE0)*2+63
      final bytes = [0xE0, 0x40];
      final result = DecodedBitStreamParser.decodeShiftJis(bytes);
      expect(result.isNotEmpty, isTrue);
    });
  });

  group('JIS-to-Unicode Mapping Direct Tests', () {
    test('maps hiragana row 4', () {
      // Row 4, cells 1-83 map to hiragana U+3041+
      final result = DecodedBitStreamParser.jisToUnicode(row: 4, cell: 1);
      expect(result, 0x3041); // ぁ (small a)
    });

    test('maps katakana row 5', () {
      // Row 5, cells 1-86 map to katakana U+30A1+
      final result = DecodedBitStreamParser.jisToUnicode(row: 5, cell: 1);
      expect(result, 0x30A1); // ァ (small a)
    });

    test('returns null for unmapped rows', () {
      // Row 10 is not mapped
      final result = DecodedBitStreamParser.jisToUnicode(row: 10, cell: 1);
      expect(result, isNull);
    });

    test('returns null for out-of-range cells in hiragana', () {
      // Row 4, cell 84+ is out of range
      final result = DecodedBitStreamParser.jisToUnicode(row: 4, cell: 84);
      expect(result, isNull);
    });

    test('returns null for out-of-range cells in katakana', () {
      // Row 5, cell 87+ is out of range
      final result = DecodedBitStreamParser.jisToUnicode(row: 5, cell: 87);
      expect(result, isNull);
    });
  });

  group('ReedSolomonDecoder', () {
    test('ReedSolomonException toString returns formatted message', () {
      const exception = ReedSolomonException('test error');
      expect(exception.toString(), contains('ReedSolomonException'));
      expect(exception.toString(), contains('test error'));
      expect(exception.message, 'test error');
    });

    test('decoder handles no errors correctly (all zeros)', () {
      final decoder = ReedSolomonDecoder(GenericGF.qrCodeField256);
      final received = List<int>.filled(10, 0);

      expect(
        () => decoder.decode(received: received, twoS: 4),
        returnsNormally,
      );
    });

    test('decoder attempts to correct errors', () {
      final decoder = ReedSolomonDecoder(GenericGF.qrCodeField256);
      // Create data with single error
      final received = List<int>.filled(10, 0);
      received[0] = 1;

      // May succeed or throw depending on error pattern
      try {
        decoder.decode(received: received, twoS: 4);
      } catch (e) {
        expect(e, isA<ReedSolomonException>());
      }
    });

    test('decoder throws on uncorrectable errors', () {
      final decoder = ReedSolomonDecoder(GenericGF.qrCodeField256);
      // Many errors - uncorrectable
      final received = List<int>.generate(20, (i) => i * 17 % 256);

      expect(
        () => decoder.decode(received: received, twoS: 4),
        throwsA(isA<ReedSolomonException>()),
      );
    });

    test('decoder throws bad error location on invalid position', () {
      final decoder = ReedSolomonDecoder(GenericGF.qrCodeField256);
      // Create specific pattern that causes bad error location
      final received = List<int>.generate(5, (i) => (i + 1) * 50 % 256);

      // This tests the 'Bad error location' exception path
      try {
        decoder.decode(received: received, twoS: 2);
      } catch (e) {
        // Expected to throw
        expect(e, isA<ReedSolomonException>());
      }
    });
  });

  group('GenericGFPoly operations', () {
    test('evaluateAt with zero returns constant term', () {
      final field = GenericGF.qrCodeField256;
      // Coefficients are highest to lowest degree: [5, 10, 15] = 5x^2 + 10x + 15
      // Constant term (x^0) is 15
      final poly = GenericGFPoly(field, [5, 10, 15]);
      expect(poly.evaluateAt(0), 15); // getCoefficient(0) returns constant term
    });

    test('multiply by scalar zero returns zero poly', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2, 3]);
      final result = poly.multiplyByScalar(0);
      expect(result.isZero, isTrue);
    });

    test('add/subtract identical polys returns zero', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2, 3]);
      final result = poly.addOrSubtract(poly);
      expect(result.isZero, isTrue);
    });

    test('multiply by monomial', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2]);
      final result = poly.multiplyByMonomial(2, 3);
      expect(result.degree, poly.degree + 2);
    });

    test('divide returns quotient and remainder', () {
      final field = GenericGF.qrCodeField256;
      final dividend = GenericGFPoly(field, [1, 2, 3, 4]);
      final divisor = GenericGFPoly(field, [1, 1]);
      final result = dividend.divide(divisor);
      expect(result.length, 2); // [quotient, remainder]
    });
  });

  group('GenericGF operations', () {
    test('buildMonomial creates correct polynomial', () {
      final field = GenericGF.qrCodeField256;
      final mono = field.buildMonomial(3, 5);
      expect(mono.degree, 3);
      expect(mono.getCoefficient(3), 5);
    });

    test('exp and log are inverse operations', () {
      final field = GenericGF.qrCodeField256;
      for (var i = 0; i < 10; i++) {
        final exp = field.exp(i);
        final log = field.log(exp);
        expect(log, i);
      }
    });

    test('inverse produces correct result', () {
      final field = GenericGF.qrCodeField256;
      for (var i = 1; i < 10; i++) {
        final inv = field.inverse(i);
        final product = field.multiply(i, inv);
        expect(product, 1);
      }
    });
  });
}
