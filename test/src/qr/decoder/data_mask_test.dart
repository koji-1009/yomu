import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/qr/decoder/data_mask.dart';

void main() {
  group('DataMask', () {
    group('isMasked patterns', () {
      test('binary000: (i + j) % 2 == 0', () {
        const mask = DataMask.binary000;
        // (0+0)=0 even -> masked
        expect(mask.isMasked(0, 0), isTrue);
        // (0+1)=1 odd -> not masked
        expect(mask.isMasked(0, 1), isFalse);
        // (1+0)=1 odd -> not masked
        expect(mask.isMasked(1, 0), isFalse);
        // (1+1)=2 even -> masked
        expect(mask.isMasked(1, 1), isTrue);
        // (2+3)=5 odd -> not masked
        expect(mask.isMasked(2, 3), isFalse);
        // (3+5)=8 even -> masked
        expect(mask.isMasked(3, 5), isTrue);
      });

      test('binary001: i % 2 == 0', () {
        const mask = DataMask.binary001;
        expect(mask.isMasked(0, 0), isTrue);
        expect(mask.isMasked(0, 5), isTrue);
        expect(mask.isMasked(1, 0), isFalse);
        expect(mask.isMasked(2, 0), isTrue);
        expect(mask.isMasked(3, 10), isFalse);
      });

      test('binary010: j % 3 == 0', () {
        const mask = DataMask.binary010;
        expect(mask.isMasked(0, 0), isTrue);
        expect(mask.isMasked(0, 1), isFalse);
        expect(mask.isMasked(0, 2), isFalse);
        expect(mask.isMasked(0, 3), isTrue);
        expect(mask.isMasked(5, 6), isTrue);
      });

      test('binary011: (i + j) % 3 == 0', () {
        const mask = DataMask.binary011;
        expect(mask.isMasked(0, 0), isTrue); // 0 % 3 == 0
        expect(mask.isMasked(0, 3), isTrue); // 3 % 3 == 0
        expect(mask.isMasked(1, 2), isTrue); // 3 % 3 == 0
        expect(mask.isMasked(1, 1), isFalse); // 2 % 3 != 0
        expect(mask.isMasked(2, 2), isFalse); // 4 % 3 != 0
      });

      test('binary100: ((i ~/ 2) + (j ~/ 3)) % 2 == 0', () {
        const mask = DataMask.binary100;
        expect(mask.isMasked(0, 0), isTrue); // (0+0)=0 even
        expect(mask.isMasked(0, 3), isFalse); // (0+1)=1 odd
        expect(mask.isMasked(2, 0), isFalse); // (1+0)=1 odd
        expect(mask.isMasked(2, 3), isTrue); // (1+1)=2 even
      });

      test('binary101: (i * j) % 2 + (i * j) % 3 == 0', () {
        const mask = DataMask.binary101;
        expect(mask.isMasked(0, 0), isTrue); // 0%2 + 0%3 = 0
        expect(mask.isMasked(0, 5), isTrue); // 0%2 + 0%3 = 0
        expect(mask.isMasked(6, 0), isTrue); // 0%2 + 0%3 = 0
        expect(mask.isMasked(2, 3), isTrue); // 6%2=0, 6%3=0 -> 0
        expect(mask.isMasked(1, 1), isFalse); // 1%2=1, 1%3=1 -> 2
      });

      test('binary110: ((i * j) % 2 + (i * j) % 3) % 2 == 0', () {
        const mask = DataMask.binary110;
        // i*j=0: 0%2+0%3=0, 0&1=0 -> true
        expect(mask.isMasked(0, 0), isTrue);
        expect(mask.isMasked(0, 5), isTrue);
        expect(mask.isMasked(5, 0), isTrue);
        // i*j=6: 0+0=0, 0&1=0 -> true
        expect(mask.isMasked(2, 3), isTrue);
        // i*j=1: 1+1=2, 2&1=0 -> true
        expect(mask.isMasked(1, 1), isTrue);
        // i*j=2: 0+2=2, 2&1=0 -> true
        expect(mask.isMasked(1, 2), isTrue);
        // i*j=5: 1+2=3, 3&1=1 -> false
        expect(mask.isMasked(1, 5), isFalse);
      });

      test('binary111: (((i + j) % 2) + ((i * j) % 3)) % 2 == 0', () {
        const mask = DataMask.binary111;
        expect(mask.isMasked(0, 0), isTrue); // (0+0)=0 even
        expect(mask.isMasked(0, 1), isFalse); // (1%2 + 0%3)=1 odd
        expect(mask.isMasked(1, 0), isFalse); // (1%2 + 0%3)=1 odd
        expect(mask.isMasked(1, 1), isFalse); // (0 + 1)=1 odd
      });
    });

    group('unmaskBitMatrix', () {
      test('flips correct bits for binary000', () {
        final bits = BitMatrix(width: 4, height: 4);
        // Set all bits
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            bits.set(x: j, y: i);
          }
        }

        DataMask.binary000.unmaskBitMatrix(bits, 4);

        // Checkerboard pattern: (i+j) even positions should be flipped (now false)
        expect(bits.get(x: 0, y: 0), isFalse); // flipped
        expect(bits.get(x: 1, y: 0), isTrue); // not flipped
        expect(bits.get(x: 0, y: 1), isTrue); // not flipped
        expect(bits.get(x: 1, y: 1), isFalse); // flipped
      });

      test('unmask is reversible', () {
        final bits = BitMatrix(width: 5, height: 5);
        // Set some bits
        bits.set(x: 1, y: 2);
        bits.set(x: 3, y: 4);
        bits.set(x: 0, y: 0);

        // Copy original state
        final originalState = <(int, int), bool>{};
        for (var i = 0; i < 5; i++) {
          for (var j = 0; j < 5; j++) {
            originalState[(i, j)] = bits.get(x: j, y: i);
          }
        }

        // Apply mask twice = should return to original
        DataMask.binary101.unmaskBitMatrix(bits, 5);
        DataMask.binary101.unmaskBitMatrix(bits, 5);

        for (var i = 0; i < 5; i++) {
          for (var j = 0; j < 5; j++) {
            expect(bits.get(x: j, y: i), originalState[(i, j)]);
          }
        }
      });
    });

    test('all mask patterns are unique', () {
      // Test that different masks produce different patterns for a sample grid
      final patterns = <int, Set<String>>{};

      for (final mask in DataMask.values) {
        final pattern = StringBuffer();
        for (var i = 0; i < 6; i++) {
          for (var j = 0; j < 6; j++) {
            pattern.write(mask.isMasked(i, j) ? '1' : '0');
          }
        }
        patterns[mask.index] = {pattern.toString()};
      }

      // Each pattern should be unique
      final allPatterns = patterns.values.expand((s) => s).toSet();
      expect(allPatterns.length, 8);
    });
  });
}
