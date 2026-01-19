import 'dart:typed_data';

import '../yomu_exception.dart';

/// A two-dimensional matrix of bits (boolean values).
///
/// [BitMatrix] is the core data structure used throughout the QR code
/// processing pipeline. It efficiently stores binary image data using
/// a packed [Uint32List] representation (32 bits per integer).
///
/// ## Memory Efficiency
///
/// Instead of using 1 byte per pixel (as with a `List<bool>`), this class
/// packs 32 pixels into each 32-bit integer, reducing memory usage by 32x.
///
/// ## Coordinate System
///
/// - Origin (0, 0) is at the **top-left** corner
/// - X increases to the right
/// - Y increases downward
///
/// See also:
/// - [Binarizer] which produces BitMatrix from images
/// - [Detector] which reads BitMatrix to find QR patterns
class BitMatrix {
  BitMatrix.fromBits({
    required this.width,
    required this.height,
    required Uint32List bits,
    int? rowStride,
  }) : _bits = bits,
       _rowStride = rowStride ?? (width + 31) ~/ 32;

  /// Creates a [BitMatrix] of size [width] x [height].
  /// If [height] is omitted, creates a square matrix of size [width] x [width].
  BitMatrix({required this.width, int? height}) : height = height ?? width {
    if (width < 1 || this.height < 1) {
      throw const ArgumentException('Both dimensions must be greater than 0');
    }
    _rowStride = (width + 31) ~/ 32;
    _bits = Uint32List(_rowStride * this.height);
  }

  final int width;
  final int height;
  late final int _rowStride;
  late final Uint32List _bits;

  /// The stride (in 32-bit words) between rows.
  int get rowStride => _rowStride;

  /// Returns the underlying bit storage.
  ///
  /// CAUTION: This exposes internal implementation details.
  /// Use only for high-performance optimization.
  Uint32List get bits => _bits;

  /// Gets the bit at [x], [y].
  ///
  /// Returns true if set (black), false otherwise (white).
  ///
  /// This method performs NO bounds checking for maximum performance.
  /// Caller must ensure coordinates are within bounds [0, width) and [0, height).
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  bool get(int x, int y) {
    final offset = y * _rowStride + (x >> 5);
    return (_bits[offset] & (1 << (x & 0x1f))) != 0;
  }

  /// Sets the bit at [x], [y] to true.
  ///
  /// This method performs NO bounds checking for maximum performance.
  /// Caller must ensure coordinates are within bounds [0, width) and [0, height).
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  void set(int x, int y) {
    final offset = y * _rowStride + (x >> 5);
    _bits[offset] |= (1 << (x & 0x1f));
  }

  /// Flips the bit at [x], [y].
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  void flip(int x, int y) {
    final offset = y * _rowStride + (x >> 5);
    _bits[offset] ^= (1 << (x & 0x1f));
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        buffer.write(get(x, y) ? 'X ' : '  ');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  BitMatrix clone() {
    return BitMatrix.fromBits(
      width: width,
      height: height,
      bits: Uint32List.fromList(_bits),
    );
  }
}
