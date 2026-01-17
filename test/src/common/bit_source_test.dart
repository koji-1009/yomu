import 'package:test/test.dart';
import 'package:yomu/src/common/bit_source.dart';

void main() {
  group('BitSource', () {
    test('reads single bits correctly', () {
      // 0b10110100 = 180
      final source = BitSource([180]);
      expect(source.readBits(1), 1); // 1
      expect(source.readBits(1), 0); // 0
      expect(source.readBits(1), 1); // 1
      expect(source.readBits(1), 1); // 1
      expect(source.readBits(1), 0); // 0
      expect(source.readBits(1), 1); // 1
      expect(source.readBits(1), 0); // 0
      expect(source.readBits(1), 0); // 0
    });

    test('reads multiple bits correctly', () {
      // 0b11001010 = 202
      final source = BitSource([202]);
      expect(source.readBits(4), 0xC); // 1100 = 12
      expect(source.readBits(4), 0xA); // 1010 = 10
    });

    test('reads across byte boundaries', () {
      // 0xFF 0x00 = 11111111 00000000
      final source = BitSource([0xFF, 0x00]);
      expect(source.readBits(4), 0xF); // 1111
      expect(source.readBits(8), 0xF0); // 1111 0000
      expect(source.readBits(4), 0x0); // 0000
    });

    test('available() returns correct count', () {
      final source = BitSource([0xFF, 0xFF, 0xFF]);
      expect(source.available(), 24);
      source.readBits(5);
      expect(source.available(), 19);
      source.readBits(8);
      expect(source.available(), 11);
    });

    test('throws on insufficient bits', () {
      final source = BitSource([0xFF]);
      expect(() => source.readBits(9), throwsArgumentError);
    });

    test('throws on invalid numBits', () {
      final source = BitSource([0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
      expect(() => source.readBits(0), throwsArgumentError);
      expect(() => source.readBits(33), throwsArgumentError);
    });

    test('reads 32 bits correctly', () {
      // 0x12345678
      final source = BitSource([0x12, 0x34, 0x56, 0x78]);
      expect(source.readBits(32), 0x12345678);
    });

    test('byteOffset and bitOffset are correct', () {
      final source = BitSource([0xFF, 0xFF]);
      expect(source.byteOffset, 0);
      expect(source.bitOffset, 0);

      source.readBits(5);
      expect(source.byteOffset, 0);
      expect(source.bitOffset, 5);

      source.readBits(4);
      expect(source.byteOffset, 1);
      expect(source.bitOffset, 1);
    });
  });
}
