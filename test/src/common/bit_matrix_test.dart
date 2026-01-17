import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';

void main() {
  group('BitMatrix', () {
    test('initialization creates empty matrix of correct size', () {
      final matrix = BitMatrix(width: 10);
      expect(matrix.width, 10);
      expect(matrix.height, 10);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          expect(matrix.get(x: x, y: y), isFalse);
        }
      }
    });

    test('initialization with rectangular dimensions', () {
      final matrix = BitMatrix(width: 5, height: 10);
      expect(matrix.width, 5);
      expect(matrix.height, 10);
    });

    test('throws on invalid dimensions', () {
      expect(() => BitMatrix(width: 0), throwsArgumentError);
      expect(() => BitMatrix(width: -1), throwsArgumentError);
      expect(() => BitMatrix(width: 5, height: 0), throwsArgumentError);
    });

    test('get and set bits', () {
      final matrix = BitMatrix(width: 3);
      matrix.set(x: 1, y: 1);
      expect(matrix.get(x: 1, y: 1), isTrue);
      expect(matrix.get(x: 0, y: 0), isFalse);

      matrix.unset(x: 1, y: 1);
      expect(matrix.get(x: 1, y: 1), isFalse);
    });

    test('getUnchecked works correctly', () {
      final matrix = BitMatrix(width: 10);
      matrix.set(x: 5, y: 5);
      expect(matrix.getUnchecked(5, 5), isTrue);
      expect(matrix.getUnchecked(0, 0), isFalse);
    });

    test('flip toggles bit value', () {
      final matrix = BitMatrix(width: 3);
      matrix.flip(x: 0, y: 0);
      expect(matrix.get(x: 0, y: 0), isTrue);
      matrix.flip(x: 0, y: 0);
      expect(matrix.get(x: 0, y: 0), isFalse);
    });

    test('clear resets all bits', () {
      final matrix = BitMatrix(width: 3);
      matrix.set(x: 0, y: 0);
      matrix.set(x: 1, y: 1);
      matrix.set(x: 2, y: 2);

      matrix.clear();

      expect(matrix.get(x: 0, y: 0), isFalse);
      expect(matrix.get(x: 1, y: 1), isFalse);
      expect(matrix.get(x: 2, y: 2), isFalse);
    });

    test('setRegion sets a block of bits', () {
      final matrix = BitMatrix(width: 5);
      matrix.setRegion(left: 1, top: 1, width: 2, height: 2);
      // Should set (1,1), (2,1), (1,2), (2,2)

      expect(matrix.get(x: 1, y: 1), isTrue);
      expect(matrix.get(x: 2, y: 1), isTrue);
      expect(matrix.get(x: 1, y: 2), isTrue);
      expect(matrix.get(x: 2, y: 2), isTrue);
      expect(matrix.get(x: 0, y: 0), isFalse);
      expect(matrix.get(x: 3, y: 3), isFalse);
    });

    test('setRegion throws on invalid arguments', () {
      final matrix = BitMatrix(width: 5);
      expect(
        () => matrix.setRegion(left: -1, top: 0, width: 2, height: 2),
        throwsArgumentError,
      );
      expect(
        () => matrix.setRegion(left: 0, top: -1, width: 2, height: 2),
        throwsArgumentError,
      );
      expect(
        () => matrix.setRegion(left: 0, top: 0, width: 0, height: 2),
        throwsArgumentError,
      );
      expect(
        () => matrix.setRegion(left: 0, top: 0, width: 2, height: 0),
        throwsArgumentError,
      );
      expect(
        () => matrix.setRegion(left: 4, top: 4, width: 2, height: 2),
        throwsRangeError,
      );
    });

    test('set throws on out of bounds', () {
      final matrix = BitMatrix(width: 5);
      expect(() => matrix.set(x: -1, y: 0), throwsRangeError);
      expect(() => matrix.set(x: 0, y: -1), throwsRangeError);
      expect(() => matrix.set(x: 5, y: 0), throwsRangeError);
      expect(() => matrix.set(x: 0, y: 5), throwsRangeError);
    });

    test('unset throws on out of bounds', () {
      final matrix = BitMatrix(width: 5);
      expect(() => matrix.unset(x: -1, y: 0), throwsRangeError);
      expect(() => matrix.unset(x: 5, y: 0), throwsRangeError);
    });

    test('flip throws on out of bounds', () {
      final matrix = BitMatrix(width: 5);
      expect(() => matrix.flip(x: -1, y: 0), throwsRangeError);
      expect(() => matrix.flip(x: 5, y: 0), throwsRangeError);
    });

    test('invalid access throws or handles logic', () {
      final matrix = BitMatrix(width: 5);
      expect(() => matrix.get(x: -1, y: 0), throwsRangeError);
      expect(() => matrix.get(x: 0, y: -1), throwsRangeError);
      expect(() => matrix.get(x: 5, y: 0), throwsRangeError);
      expect(() => matrix.get(x: 0, y: 5), throwsRangeError);
    });

    test('toString produces readable output', () {
      final matrix = BitMatrix(width: 3);
      matrix.set(x: 1, y: 1);
      final str = matrix.toString();
      expect(str, contains('X'));
      expect(str.split('\n').length, greaterThanOrEqualTo(3));
    });

    test('clone creates independent copy', () {
      final matrix = BitMatrix(width: 5);
      matrix.set(x: 2, y: 2);

      final cloned = matrix.clone();
      expect(cloned.get(x: 2, y: 2), isTrue);

      // Modify original
      matrix.unset(x: 2, y: 2);
      // Clone should be unchanged
      expect(cloned.get(x: 2, y: 2), isTrue);
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
          expect(matrix.get(x: x, y: y), isTrue);
        }
      }
    });

    test('handles large matrices', () {
      final matrix = BitMatrix(width: 100, height: 100);
      matrix.set(x: 99, y: 99);
      expect(matrix.get(x: 99, y: 99), isTrue);
      expect(matrix.get(x: 0, y: 0), isFalse);
    });
  });
}
