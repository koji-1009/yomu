import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('BitMatrix', () {
    test('initialization creates empty matrix of correct size', () {
      final matrix = BitMatrix(width: 10);
      expect(matrix.width, 10);
      expect(matrix.height, 10);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          expect(matrix.get(x, y), isFalse);
        }
      }
    });

    test('initialization with rectangular dimensions', () {
      final matrix = BitMatrix(width: 5, height: 10);
      expect(matrix.width, 5);
      expect(matrix.height, 10);
    });

    test('throws on invalid dimensions', () {
      expect(() => BitMatrix(width: 0), throwsA(isA<ArgumentException>()));
      expect(() => BitMatrix(width: -1), throwsA(isA<ArgumentException>()));
      expect(
        () => BitMatrix(width: 5, height: 0),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('get and set bits', () {
      final matrix = BitMatrix(width: 3);
      matrix.set(1, 1);
      expect(matrix.get(1, 1), isTrue);
      expect(matrix.get(0, 0), isFalse);
    });

    test('flip toggles bit value', () {
      final matrix = BitMatrix(width: 3);
      matrix.flip(0, 0);
      expect(matrix.get(0, 0), isTrue);
      matrix.flip(0, 0);
      expect(matrix.get(0, 0), isFalse);
    });

    test('toString produces readable output', () {
      final matrix = BitMatrix(width: 3);
      matrix.set(1, 1);
      final str = matrix.toString();
      expect(str, contains('X'));
      expect(str.split('\n').length, greaterThanOrEqualTo(3));
    });

    test('clone creates independent copy', () {
      final matrix = BitMatrix(width: 5);
      matrix.set(2, 2);

      final cloned = matrix.clone();
      expect(cloned.get(2, 2), isTrue);

      // Modify original
      matrix.flip(2, 2);
      // Clone should be unchanged
      expect(cloned.get(2, 2), isTrue);
    });

    test('fromBits constructor works correctly', () {
      // 4x4 matrix. Stride = 1. Buffer size = 4.
      final bits = Uint32List(4);
      bits.fillRange(0, 4, 0xFFFFFFFF); // All set
      final matrix = BitMatrix.fromBits(width: 4, height: 4, bits: bits);
      expect(matrix.width, 4);
      expect(matrix.height, 4);
      // First 16 bits should be set
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          expect(matrix.get(x, y), isTrue);
        }
      }
    });

    test('handles large matrices', () {
      final matrix = BitMatrix(width: 100, height: 100);
      matrix.set(99, 99);
      expect(matrix.get(99, 99), isTrue);
      expect(matrix.get(0, 0), isFalse);
    });
  });
}
