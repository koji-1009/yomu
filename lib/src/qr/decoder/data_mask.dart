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
        // General path: build mask bit by bit
        var mask = 0;
        for (var b = 0; b < limit; b++) {
          if (isMasked(i, baseJ + b)) {
            mask |= (1 << b);
          }
        }
        return mask;
    }
  }
}
