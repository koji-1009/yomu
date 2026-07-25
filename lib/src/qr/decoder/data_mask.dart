import 'dart:typed_data';

import '../../common/bit_matrix.dart';

/// The eight QR code data mask patterns (ISO 18004 Table 10).
///
/// Each pattern defines a condition on module coordinates (i, j) that
/// determines whether a data module is masked. Uses word-oriented
/// 32-bit batch processing for efficient unmasking.
enum DataMask {
  binary000,
  binary001,
  binary010,
  binary011,
  binary100,
  binary101,
  binary110,
  binary111;

  /// Returns true if the module at row [i], column [j] is masked.
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

  /// Toggles masked data modules in [bits] in-place using XOR.
  ///
  /// Processes 32 columns at a time via [_buildMaskWord] for performance.
  /// Calling this twice restores the original matrix.
  void unmaskBitMatrix(BitMatrix bits, int dimension) {
    final bitStorage = bits.bits;
    final rowStride = bits.rowStride;

    for (var i = 0; i < dimension; i++) {
      final rowOffset = i * rowStride;
      for (var w = 0; w < rowStride; w++) {
        final baseJ = w << 5; // w * 32
        final remaining = dimension - baseJ;
        final limit = remaining < 32 ? remaining : 32;
        final mask = _buildMaskWord(i, baseJ, limit);
        bitStorage[rowOffset + w] ^= mask;
      }
    }
  }

  /// Builds a 32-bit mask word for row [i] starting at column [baseJ].
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  int _buildMaskWord(int i, int baseJ, int limit) {
    // Fast paths for simple patterns
    switch (this) {
      case binary001:
        // (i & 0x01) == 0 → entire row masked when i is even
        return (i & 0x01) == 0
            ? (limit == 32 ? 0xFFFFFFFF : (1 << limit) - 1)
            : 0;
      case binary000:
        // ((i + j) & 0x01) == 0 → checkerboard
        final base = (i & 0x01) == 0
            ? 0x55555555 // even row: columns 0,2,4... masked
            : 0xAAAAAAAA; // odd row: columns 1,3,5... masked
        // Adjust for baseJ offset
        final shifted = (baseJ & 0x01) == 0 ? base : ~base;
        return limit == 32 ? shifted : shifted & ((1 << limit) - 1);
      default:
        // General path: every mask condition is periodic, so the word is
        // one of a handful of precomputed constants.
        final word =
            _wordTable[index][(i % _rowPeriod) * _wordPhases +
                (baseJ >> 5) % _wordPhases];
        return limit == 32 ? word : word & ((1 << limit) - 1);
    }
  }

  /// Row period shared by all eight conditions: lcm(2, 4, 6).
  ///
  /// [binary001] and [binary000] step on `i` modulo 2, [binary100] on
  /// `i ~/ 2` (period 4), and the `i * j` patterns on `i` modulo 6.
  static const int _rowPeriod = 12;

  /// Distinct word alignments. The column period is lcm(2, 3, 6) = 6, and a
  /// word covering columns `32 * w` onwards starts at `(32 * w) % 6`, which
  /// is `(2 * w) % 6` - three values, one per residue of `w` modulo 3.
  static const int _wordPhases = 3;

  /// One 32-bit mask word per (row phase, word phase), per mask: 12 * 3
  /// words each, 1.1 KiB in total, built once per isolate.
  ///
  /// Unmasking a version 40 symbol touches ~1000 words and runs twice per
  /// decode attempt (XOR unmasks, XOR again restores), so building each of
  /// those words a bit at a time - with two integer modulos per bit - is
  /// what this replaces.
  static final List<Uint32List> _wordTable = [
    for (final mask in values)
      Uint32List.fromList([
        for (var row = 0; row < _rowPeriod; row++)
          for (var phase = 0; phase < _wordPhases; phase++)
            mask._maskWordAt(row, phase * 2),
      ]),
  ];

  /// Builds one whole 32-bit mask word bit by bit. Only used to fill
  /// [_wordTable].
  int _maskWordAt(int i, int baseJ) {
    var mask = 0;
    for (var b = 0; b < 32; b++) {
      if (isMasked(i, baseJ + b)) {
        mask |= (1 << b);
      }
    }
    return mask;
  }
}
