import 'package:test/test.dart';
import 'package:yomu/src/qr/mode.dart';
import 'package:yomu/src/qr/version.dart';

void main() {
  group('Mode', () {
    group('forBits', () {
      test('returns correct mode for valid bits', () {
        expect(Mode.forBits(0x00), Mode.terminator);
        expect(Mode.forBits(0x01), Mode.numeric);
        expect(Mode.forBits(0x02), Mode.alphanumeric);
        expect(Mode.forBits(0x03), Mode.structuredAppend);
        expect(Mode.forBits(0x04), Mode.byte);
        expect(Mode.forBits(0x05), Mode.fnc1FirstPosition);
        expect(Mode.forBits(0x07), Mode.eci);
        expect(Mode.forBits(0x08), Mode.kanji);
        expect(Mode.forBits(0x09), Mode.fnc1SecondPosition);
        expect(Mode.forBits(0x0D), Mode.hanzi);
      });

      test('throws for invalid bits', () {
        expect(() => Mode.forBits(0x06), throwsArgumentError);
        expect(() => Mode.forBits(0x0A), throwsArgumentError);
        expect(() => Mode.forBits(0xFF), throwsArgumentError);
      });
    });

    group('getCharacterCountBits', () {
      test('returns correct bits for Version 1-9', () {
        final v1 = Version.getVersionForNumber(1);
        final v9 = Version.getVersionForNumber(9);

        expect(Mode.numeric.getCharacterCountBits(v1), 10);
        expect(Mode.alphanumeric.getCharacterCountBits(v1), 9);
        expect(Mode.byte.getCharacterCountBits(v1), 8);
        expect(Mode.kanji.getCharacterCountBits(v1), 8);

        expect(Mode.numeric.getCharacterCountBits(v9), 10);
      });

      test('returns correct bits for Version 10-26', () {
        final v10 = Version.getVersionForNumber(10);
        final v26 = Version.getVersionForNumber(26);

        expect(Mode.numeric.getCharacterCountBits(v10), 12);
        expect(Mode.alphanumeric.getCharacterCountBits(v10), 11);
        expect(Mode.byte.getCharacterCountBits(v10), 16);
        expect(Mode.kanji.getCharacterCountBits(v10), 10);

        expect(Mode.numeric.getCharacterCountBits(v26), 12);
      });

      test('returns correct bits for Version 27-40', () {
        final v27 = Version.getVersionForNumber(27);
        final v40 = Version.getVersionForNumber(40);

        expect(Mode.numeric.getCharacterCountBits(v27), 14);
        expect(Mode.alphanumeric.getCharacterCountBits(v27), 13);
        expect(Mode.byte.getCharacterCountBits(v27), 16);
        expect(Mode.kanji.getCharacterCountBits(v27), 12);

        expect(Mode.numeric.getCharacterCountBits(v40), 14);
      });
    });

    test('toString returns name', () {
      expect(Mode.numeric.toString(), 'NUMERIC');
      expect(Mode.alphanumeric.toString(), 'ALPHANUMERIC');
      expect(Mode.byte.toString(), 'BYTE');
    });

    test('bits property returns correct value', () {
      expect(Mode.numeric.bits, 0x01);
      expect(Mode.alphanumeric.bits, 0x02);
      expect(Mode.byte.bits, 0x04);
      expect(Mode.kanji.bits, 0x08);
    });
  });
}
