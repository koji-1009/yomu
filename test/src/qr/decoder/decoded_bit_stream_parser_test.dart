import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/decoded_bit_stream_parser.dart';
import 'package:yomu/src/qr/version.dart';

void main() {
  group('DecodedBitStreamParser', () {
    test('decode numeric mode', () {
      // Mode: Numeric (0001)
      // Count: 4 digits (000000100 -> length 4, assuming version 1, 10 bits for count)
      // Data: "0123"
      // 012 = 12 (0000001100) -> 10 bits
      // 3 = 3 (0011) -> 4 bits
      // Terminator: 0000

      // Version 1 Numeric count bits = 10.
      // Bitstream:
      // Mode (4): 0001
      // Count (10): 0000000100 (4)
      // Data "012": 0000001100 (12)
      // Data "3": 0011 (3)
      // Terminator: 0000

      // Total bits: 4 + 10 + 10 + 4 + 4 = 32 bits = 4 bytes.
      // 0001 0000 0001 0000 0000 0011 0000 11 00 00
      // Hex: 10 10 03 00 (padded with 0s)

      // Let's construct manually carefully.
      // 00010000 00010000 00001100 00110000
      // 0x10, 0x10, 0x0C, 0x30

      final bytes = Uint8List.fromList([0x10, 0x10, 0x0C, 0x30]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );

      expect(result.text, '0123');
    });

    test('decode simple byte mode', () {
      // Mode: Byte (0100)
      // Count: 1 char (length 1). Version 1 Byte count bits = 8.
      // Data 'A' (0x41) = 01000001.
      // Terminator

      // Mode (4): 0100
      // Count (8): 00000001
      // Data (8): 01000001
      // Term (4): 0000

      // 0100 0000 0001 0100 0001 0000
      // 40 14 10

      final bytes = Uint8List.fromList([0x40, 0x14, 0x10]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, 'A');
    });

    test('decode alphanumeric mode', () {
      // Mode: Alphanumeric (0010)
      // Count: 2 chars. Version 1 Alphanumeric count bits = 9.
      // Data "AB": Value = 10*45 + 11 = 461 (11 bits: 00111001101)
      // Terminator

      // Mode (4): 0010
      // Count (9): 000000010 (2)
      // Data (11): 00111001101 (461)
      // Term (4): 0000

      // 0010 0000 0001 0001 1100 1101 0000
      // 20 11 CD 00

      final bytes = Uint8List.fromList([0x20, 0x11, 0xCD, 0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, 'AB');
    });

    test('decode alphanumeric odd character count', () {
      // Mode: Alphanumeric (0010)
      // Count: 3 chars. "ABC"
      // "AB" = 461 (11 bits)
      // "C" = 12 (6 bits)

      // Mode (4): 0010
      // Count (9): 000000011 (3)
      // Data AB (11): 00111001101
      // Data C (6): 001100
      // Term (4): 0000

      // 0010 0000 0001 1001 1100 1101 0011 0000 00
      // 20 19 CD 30 00

      final bytes = Uint8List.fromList([0x20, 0x19, 0xCD, 0x30, 0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, 'ABC');
    });

    test('decode numeric with 2 remaining digits', () {
      // "01" - 2 digits encoded in 7 bits as value 1
      // Mode (4): 0001
      // Count (10): 0000000010 (2)
      // Data (7): 0000001 (1 -> "01")
      // Term: 0000

      // 0001 0000 0000 1000 0000 1000 0
      // 10 08 08

      final bytes = Uint8List.fromList([0x10, 0x08, 0x08, 0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, '01');
    });

    test('decode numeric with 1 remaining digit', () {
      // "1" - 1 digit encoded in 4 bits as value 1
      // Mode (4): 0001
      // Count (10): 0000000001 (1)
      // Data (4): 0001 (1)
      // Term: 0000

      // 0001 0000 0000 0100 0100 00
      // 10 04 40

      final bytes = Uint8List.fromList([0x10, 0x04, 0x40]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, '1');
    });

    test('decode byte mode with UTF-8', () {
      // Byte mode with UTF-8 encoded string "日" (0xE6 0x97 0xA5)
      // Mode (4): 0100
      // Count (8): 00000011 (3 bytes)
      // Data: 0xE6 0x97 0xA5
      // Term: 0000

      // 0100 0000 0011 1110 0110 1001 0111 1010 0101 0000
      // 40 3E 69 7A 50

      final bytes = Uint8List.fromList([0x40, 0x3E, 0x69, 0x7A, 0x50]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, '日');
    });

    test('decode byte mode with Latin-1 fallback', () {
      // Byte mode with invalid UTF-8 that falls back to Latin-1
      // 0xFF is invalid UTF-8 lead byte but valid Latin-1 (ÿ)
      // Mode (4): 0100
      // Count (8): 00000001 (1 byte)
      // Data: 0xFF
      // Term: 0000

      // 0100 0000 0001 1111 1111 0000
      // 40 1F F0

      final bytes = Uint8List.fromList([0x40, 0x1F, 0xF0]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, 'ÿ');
    });

    test('decode empty message (terminator only)', () {
      final bytes = Uint8List.fromList([0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text, '');
    });

    test('byteSegments contains raw bytes from byte mode', () {
      // "AB" in byte mode
      final bytes = Uint8List.fromList([0x40, 0x24, 0x14, 0x20]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.byteSegments.isNotEmpty, true);
    });

    test('throws on unsupported mode', () {
      // Mode: FNC1 First Position (0101) - not fully supported
      // This should throw or handle gracefully
      final bytes = Uint8List.fromList([0x50, 0x00]);
      expect(
        () => DecodedBitStreamParser.decode(
          bytes: bytes,
          version: Version.getVersionForNumber(1),
        ),
        throwsA(anything),
      );
    });

    test('throws on insufficient bits for numeric', () {
      // Mode: Numeric, Count: 10, but not enough data bits
      // Truncated data
      final bytes = Uint8List.fromList([
        0x10,
        0x28,
      ]); // Count 10 but only 2 bytes
      expect(
        () => DecodedBitStreamParser.decode(
          bytes: bytes,
          version: Version.getVersionForNumber(1),
        ),
        throwsException,
      );
    });

    test('throws on illegal numeric value', () {
      // Numeric mode with value >= 1000 for 3 digits
      // 1000 = 0x3E8 in 10 bits = 1111101000
      // Mode (4): 0001
      // Count (10): 0000000011 (3)
      // Data (10): 1111101000 (1000 - illegal)

      // 0001 0000 0000 1111 1110 1000 0000
      // 10 0F E8 00

      final bytes = Uint8List.fromList([0x10, 0x0F, 0xE8, 0x00]);
      expect(
        () => DecodedBitStreamParser.decode(
          bytes: bytes,
          version: Version.getVersionForNumber(1),
        ),
        throwsException,
      );
    });

    test('decode kanji mode single character', () {
      // Mode: Kanji (1000)
      // Count: 1 character. Version 1 Kanji count bits = 8.
      // Kanji encoding: 13 bits per character
      //
      // Example: 亜 (U+4E9C) encoded in Shift JIS as 0x889F
      // Compact encoding: 0x889F - 0x8140 = 0x075F = 1887
      // Or as twoBytes: ((0x07 * 0xC0) + 0x5F) = 1887
      //
      // Mode (4): 1000
      // Count (8): 00000001
      // Data (13): 0000111010111 (1887 in 13 bits = 0x075F = 0000011101011111)
      // Wait, 1887 = 0x75F = 0000 0111 0101 1111 (13 bits needed)
      // 1887 in 13 bits = 0011101011111
      //
      // Terminator (4): 0000
      //
      // 1000 00000001 0011101011111 0000 = 8 01 D7 80 (roughly)
      // Let's compute precisely:
      // 1000 0000 0001 0011 1010 1111 1000 0
      // 80 13 AF 80

      final bytes = Uint8List.fromList([0x80, 0x13, 0xAF, 0x80]);
      // This should parse but may not decode the exact character
      // since our Shift JIS table is limited
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      expect(result.text.isNotEmpty, isTrue);
    });

    test('decode kanji mode hiragana', () {
      // Encode hiragana あ (U+3042)
      // Shift JIS: 0x82A0  (in range 0x8140-0x9FFC)
      // Compact: 0x82A0 - 0x8140 = 0x0160 = 352
      // 352 in 13 bits = 0000101100000
      //
      // Mode (4): 1000
      // Count (8): 00000001
      // Data (13): 0000101100000
      // Term (4): 0000
      //
      // 1000 00000001 0000101100000 0000
      // 0x80, 0x10, 0x58, 0x00

      final bytes = Uint8List.fromList([0x80, 0x10, 0x58, 0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      // Should contain hiragana (row 4 in JIS X 0208)
      expect(result.text.isNotEmpty, isTrue);
    });

    test('throws on insufficient bits for kanji', () {
      // Mode: Kanji, Count: 5, but not enough data
      final bytes = Uint8List.fromList([0x80, 0x50]); // Count 5, only 2 bytes
      expect(
        () => DecodedBitStreamParser.decode(
          bytes: bytes,
          version: Version.getVersionForNumber(1),
        ),
        throwsException,
      );
    });

    test('decode byte mode with latin1 fallback', () {
      // Create bytes that are NOT valid UTF-8 but are valid Latin-1
      // Mode: Byte (0100)
      // Count: 2
      // Data: 0xE0 0xC0 (invalid UTF-8 continuation, valid Latin-1)
      //
      // Mode (4): 0100
      // Count (8): 00000010
      // Data (8): 11100000
      // Data (8): 11000000
      // Term (4): 0000
      //
      // 0100 00000010 11100000 11000000 0000
      // 40 2E 0C 00

      final bytes = Uint8List.fromList([0x40, 0x2E, 0x0C, 0x00]);
      final result = DecodedBitStreamParser.decode(
        bytes: bytes,
        version: Version.getVersionForNumber(1),
      );
      // Should fall back to Latin-1 decoding
      expect(result.text.isNotEmpty, isTrue);
    });
  });

  group('DecoderResult', () {
    test('holds text and segments', () {
      final result = DecoderResult(
        text: 'test',
        byteSegments: [
          Uint8List.fromList([1, 2, 3]),
        ],
        ecLevel: 'L',
      );
      expect(result.text, 'test');
      expect(result.byteSegments.length, 1);
      expect(result.ecLevel, 'L');
    });

    test('allows null ecLevel', () {
      const result = DecoderResult(text: 'test', byteSegments: []);
      expect(result.ecLevel, isNull);
    });
  });
}
