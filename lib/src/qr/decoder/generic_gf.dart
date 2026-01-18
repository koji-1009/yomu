import 'dart:typed_data';

import 'generic_gf_poly.dart';

/// Utility class to perform arithmetic in GF(256).
class GenericGF {
  GenericGF({
    required int primitive,
    required int size,
    required int generatorBase,
  }) : _primitive = primitive,
       _size = size,
       _generatorBase = generatorBase {
    _expTable = Int16List(_size);
    _logTable = Int16List(_size);
    var x = 1;
    for (var i = 0; i < _size; i++) {
      _expTable[i] = x;
      x *= 2;
      if (x >= _size) {
        x ^= _primitive;
        x &= (_size - 1);
      }
    }
    for (var i = 0; i < _size - 1; i++) {
      _logTable[_expTable[i]] = i;
    }
    // zero/one initialization
    zero = GenericGFPoly(this, Uint8List.fromList([0]));
    one = GenericGFPoly(this, Uint8List.fromList([1]));
  }

  static final GenericGF qrCodeField256 = GenericGF(
    primitive: 0x011D,
    size: 256,
    generatorBase: 0,
  );

  final int _primitive;
  final int _size;
  final int _generatorBase;
  late final Int16List _expTable;
  late final Int16List _logTable;
  late final GenericGFPoly zero;
  late final GenericGFPoly one;

  /// 2^a
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int exp(int a) {
    return _expTable[a];
  }

  /// log(a)
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int log(int a) {
    return _logTable[a];
  }

  /// Inverse of a
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int inverse(int a) {
    return _expTable[_size - 1 - _logTable[a]];
  }

  /// a * b
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int multiply(int a, int b) {
    if (a == 0 || b == 0) {
      return 0;
    }
    return _expTable[(_logTable[a] + _logTable[b]) % (_size - 1)];
  }

  int get size => _size;
  int get generatorBase => _generatorBase;

  /// Helper to build a monomial
  GenericGFPoly buildMonomial(int degree, int coefficient) {
    if (coefficient == 0) return zero;
    final coeffs = List<int>.filled(degree + 1, 0);
    coeffs[0] = coefficient;
    return GenericGFPoly(this, coeffs);
  }
}
