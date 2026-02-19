import 'dart:typed_data';

import '../../common/bit_matrix.dart';

enum DataMask {
  binary000,
  binary001,
  binary010,
  binary011,
  binary100,
  binary101,
  binary110,
  binary111;

  bool isMasked(int i, int j) => switch (this) {
    binary000 => ((i + j) & 0x01) == 0,
    binary001 => (i & 0x01) == 0,
    binary010 => j % 3 == 0,
    binary011 => (i + j) % 3 == 0,
    binary100 => (((i ~/ 2) + (j ~/ 3)) & 0x01) == 0,
    binary101 => (i * j) % 2 + (i * j) % 3 == 0,
    binary110 => (((i * j) % 2 + (i * j) % 3) & 0x01) == 0,
    binary111 => ((((i + j) & 0x01) + ((i * j) % 3)) & 0x01) == 0,
  };

  /// Applies this data mask to a [BitMatrix] using word-level XOR operations.
  ///
  /// Instead of flipping individual bits (dimension² calls to [BitMatrix.flip]),
  /// this method computes 32-bit mask words for each row and applies them with
  /// a single XOR per word. This reduces the number of operations by up to 32x.
  ///
  /// For masks with simple column-periodic patterns (binary000, binary001,
  /// binary010, binary011), precomputed word patterns are tiled across rows.
  /// For masks with row-dependent column patterns (binary100–binary111),
  /// mask words are computed per-row.
  void unmaskBitMatrix(BitMatrix bits, int dimension) {
    final rawBits = bits.bits;
    final rowStride = bits.rowStride;

    // Mask for clearing unused trailing bits in the last word of each row.
    // e.g., dimension=21: trailingBits=21, lastWordMask = (1 << 21) - 1
    final trailingBits = dimension & 0x1f; // dimension % 32
    final lastWordMask = trailingBits == 0
        ? 0xFFFFFFFF
        : (1 << trailingBits) - 1;

    switch (this) {
      case binary001:
        // (i & 1) == 0 → even rows: flip all bits; odd rows: no-op
        for (var i = 0; i < dimension; i += 2) {
          final rowOffset = i * rowStride;
          for (var w = 0; w < rowStride - 1; w++) {
            rawBits[rowOffset + w] ^= 0xFFFFFFFF;
          }
          rawBits[rowOffset + rowStride - 1] ^= lastWordMask;
        }

      case binary000:
        // ((i + j) & 1) == 0 → checkerboard
        // Even rows: even columns masked → 0x55555555
        // Odd rows:  odd columns masked  → 0xAAAAAAAA
        const evenWord = 0x55555555; // bits 0,2,4,...
        const oddWord = 0xAAAAAAAA; // bits 1,3,5,...
        for (var i = 0; i < dimension; i++) {
          final rowOffset = i * rowStride;
          final fullWord = (i & 1) == 0 ? evenWord : oddWord;
          for (var w = 0; w < rowStride - 1; w++) {
            rawBits[rowOffset + w] ^= fullWord;
          }
          rawBits[rowOffset + rowStride - 1] ^= fullWord & lastWordMask;
        }

      case binary010:
        // j % 3 == 0 → same pattern every row, period 3
        // Precompute 3-word cycle (LCM(32,3) = 96 bits)
        final cycle = _buildColumnCycleMask(3, (j) => j % 3 == 0);
        _applyFixedCycle(rawBits, rowStride, dimension, lastWordMask, cycle);

      case binary011:
        // (i + j) % 3 == 0 → period-3 column pattern, shifts with row
        final cycle0 = _buildColumnCycleMask(3, (j) => j % 3 == 0);
        final cycle1 = _buildColumnCycleMask(3, (j) => (1 + j) % 3 == 0);
        final cycle2 = _buildColumnCycleMask(3, (j) => (2 + j) % 3 == 0);
        final cycles = [cycle0, cycle1, cycle2];
        for (var i = 0; i < dimension; i++) {
          final rowOffset = i * rowStride;
          final cycle = cycles[i % 3];
          final cycleLen = cycle.length;
          for (var w = 0; w < rowStride - 1; w++) {
            rawBits[rowOffset + w] ^= cycle[w % cycleLen];
          }
          rawBits[rowOffset + rowStride - 1] ^=
              cycle[(rowStride - 1) % cycleLen] & lastWordMask;
        }

      case binary100:
      case binary101:
      case binary110:
      case binary111:
        // Row-dependent column patterns: build mask word per row
        _unmaskGeneric(rawBits, rowStride, dimension, lastWordMask);
    }
  }

  /// Applies a fixed column-cycle mask to every row.
  static void _applyFixedCycle(
    Uint32List rawBits,
    int rowStride,
    int dimension,
    int lastWordMask,
    Uint32List cycle,
  ) {
    final cycleLen = cycle.length;
    for (var i = 0; i < dimension; i++) {
      final rowOffset = i * rowStride;
      for (var w = 0; w < rowStride - 1; w++) {
        rawBits[rowOffset + w] ^= cycle[w % cycleLen];
      }
      rawBits[rowOffset + rowStride - 1] ^=
          cycle[(rowStride - 1) % cycleLen] & lastWordMask;
    }
  }

  /// Builds a cycle of 32-bit mask words for a column-periodic pattern.
  ///
  /// The cycle length is LCM(32, [period]) / 32 words.
  static Uint32List _buildColumnCycleMask(
    int period,
    bool Function(int j) isMaskedCol,
  ) {
    final lcm = 32 * period ~/ _gcd(32, period);
    final wordCount = lcm ~/ 32;
    final result = Uint32List(wordCount);
    for (var w = 0; w < wordCount; w++) {
      var word = 0;
      for (var bit = 0; bit < 32; bit++) {
        final j = w * 32 + bit;
        if (isMaskedCol(j)) {
          word |= 1 << bit;
        }
      }
      result[w] = word;
    }
    return result;
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  /// Generic fallback: builds 32-bit mask words per row.
  ///
  /// Used for masks whose column pattern depends on the row index
  /// (binary100–binary111).
  void _unmaskGeneric(
    Uint32List rawBits,
    int rowStride,
    int dimension,
    int lastWordMask,
  ) {
    for (var i = 0; i < dimension; i++) {
      final rowOffset = i * rowStride;
      for (var w = 0; w < rowStride; w++) {
        var maskWord = 0;
        final jBase = w * 32;
        final jEnd = w == rowStride - 1 ? dimension - jBase : 32;
        for (var bit = 0; bit < jEnd; bit++) {
          if (isMasked(i, jBase + bit)) {
            maskWord |= 1 << bit;
          }
        }
        rawBits[rowOffset + w] ^= maskWord;
      }
    }
  }
}
