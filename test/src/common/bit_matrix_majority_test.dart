import 'dart:math';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';

/// Naive 3x3 majority reference implementation (out-of-bounds = white).
BitMatrix _naiveMajority(BitMatrix src) {
  final result = BitMatrix(width: src.width, height: src.height);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var black = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final ny = y + dy;
          final nx = x + dx;
          if (ny < 0 || ny >= src.height || nx < 0 || nx >= src.width) {
            continue;
          }
          if (src.get(nx, ny)) black++;
        }
      }
      if (black >= 5) result.set(x, y);
    }
  }
  return result;
}

void _expectMatrixEquals(BitMatrix actual, BitMatrix expected) {
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      expect(
        actual.get(x, y),
        expected.get(x, y),
        reason: 'mismatch at ($x, $y)',
      );
    }
  }
}

void main() {
  group('BitMatrix.majority3x3', () {
    test('removes isolated black pixels (salt noise)', () {
      final matrix = BitMatrix(width: 9);
      matrix.set(4, 4);
      matrix.set(0, 0);
      matrix.set(8, 8);

      final filtered = matrix.majority3x3();
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 9; x++) {
          expect(filtered.get(x, y), isFalse);
        }
      }
    });

    test('fills isolated white holes inside black areas (pepper noise)', () {
      final matrix = BitMatrix(width: 9);
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 9; x++) {
          matrix.set(x, y);
        }
      }
      matrix.flip(4, 4); // white hole, 8 black neighbors -> filled

      final filtered = matrix.majority3x3();
      expect(filtered.get(4, 4), isTrue);
    });

    test('preserves solid 3x3 blocks', () {
      final matrix = BitMatrix(width: 9);
      for (var y = 3; y < 6; y++) {
        for (var x = 3; x < 6; x++) {
          matrix.set(x, y);
        }
      }

      final filtered = matrix.majority3x3();
      // The center has 9 black neighbors, kept.
      expect(filtered.get(4, 4), isTrue);
      // Block corners have only 4 black cells in their neighborhood, removed.
      expect(filtered.get(3, 3), isFalse);
    });

    test('keeps pixel with exactly 5 black neighbors, drops at 4', () {
      // Plus-shape: center + 4 orthogonal neighbors = 5 black in the
      // center's neighborhood.
      final plus = BitMatrix(width: 5);
      plus.set(2, 2);
      plus.set(1, 2);
      plus.set(3, 2);
      plus.set(2, 1);
      plus.set(2, 3);
      expect(plus.majority3x3().get(2, 2), isTrue);

      // Remove one arm: 4 black -> dropped.
      plus.flip(2, 3);
      expect(plus.majority3x3().get(2, 2), isFalse);
    });

    test('treats out-of-bounds as white at the edges', () {
      // Full 3x3 matrix: corner neighborhoods contain only 4 in-bounds
      // cells, so corners cannot reach a majority of 5.
      final matrix = BitMatrix(width: 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          matrix.set(x, y);
        }
      }

      final filtered = matrix.majority3x3();
      expect(filtered.get(0, 0), isFalse);
      expect(filtered.get(2, 0), isFalse);
      expect(filtered.get(0, 2), isFalse);
      expect(filtered.get(2, 2), isFalse);
      // Edge midpoints see 6 in-bounds black cells.
      expect(filtered.get(1, 0), isTrue);
      // Center sees all 9.
      expect(filtered.get(1, 1), isTrue);
    });

    test('matches the naive reference on random matrices', () {
      final random = Random(20260604);
      // Widths chosen around the 32-bit word boundaries.
      for (final width in [5, 31, 32, 33, 63, 64, 65, 100]) {
        for (final fill in [0.1, 0.5, 0.9]) {
          final matrix = BitMatrix(width: width, height: 40);
          for (var y = 0; y < matrix.height; y++) {
            for (var x = 0; x < width; x++) {
              if (random.nextDouble() < fill) {
                matrix.set(x, y);
              }
            }
          }
          _expectMatrixEquals(matrix.majority3x3(), _naiveMajority(matrix));
        }
      }
    });

    test('keeps tail bits of the last word clean', () {
      // Width 33: the second word has 1 valid bit and 31 tail bits.
      final matrix = BitMatrix(width: 33, height: 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 33; x++) {
          matrix.set(x, y);
        }
      }

      final filtered = matrix.majority3x3();
      for (var y = 0; y < 8; y++) {
        // Bits beyond width must remain zero in the backing store.
        final lastWord = filtered.bits[y * filtered.rowStride + 1];
        expect(lastWord & ~1, 0, reason: 'tail bits leaked in row $y');
      }
    });

    test('handles single row and single column matrices', () {
      final row = BitMatrix(width: 8, height: 1);
      for (var x = 0; x < 8; x++) {
        row.set(x, 0);
      }
      // Max neighborhood count in a single row is 3 < 5.
      final filteredRow = row.majority3x3();
      for (var x = 0; x < 8; x++) {
        expect(filteredRow.get(x, 0), isFalse);
      }

      final column = BitMatrix(width: 1, height: 8);
      for (var y = 0; y < 8; y++) {
        column.set(0, y);
      }
      final filteredColumn = column.majority3x3();
      for (var y = 0; y < 8; y++) {
        expect(filteredColumn.get(0, y), isFalse);
      }
    });
  });
}
