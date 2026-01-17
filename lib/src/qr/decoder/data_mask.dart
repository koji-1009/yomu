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
    for (var i = 0; i < dimension; i++) {
      for (var j = 0; j < dimension; j++) {
        if (isMasked(i, j)) {
          bits.flip(x: j, y: i);
        }
      }
    }
  }
}
