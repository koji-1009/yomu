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
/// ## Example
///
/// ```dart
/// final matrix = BitMatrix(21, 21); // Version 1 QR code size
/// matrix.set(0, 0);                  // Set top-left to black
/// print(matrix.get(0, 0));           // true
/// matrix.flip(0, 0);                 // Toggle the bit
/// print(matrix.get(0, 0));           // false
/// ```
///
/// See also:
/// - [GlobalHistogramBinarizer] which produces BitMatrix from images
/// - [Detector] which reads BitMatrix to find QR patterns
class BitMatrix {
  /// Creates a [BitMatrix] directly from a luminance array (grayscale).
  ///
  /// This is a high-performance optimization to avoid calling [set] for every pixel.
  /// It processes pixels in blocks of 32 to minimize memory writes and bounds checks.
  ///
  /// [luminances] is the linear array of grayscale values (0-255).
  /// [threshold] is the value below which a pixel is considered black (true).
  factory BitMatrix.fromLuminance({
    required int width,
    required int height,
    required Uint8List luminances,
    required int threshold,
  }) {
    if (width < 1 || height < 1) {
      throw const ArgumentException('Both dimensions must be greater than 0');
    }
    final totalPixelCount = width * height;
    if (luminances.length < totalPixelCount) {
      throw const ArgumentException('Luminance array is too small');
    }

    final rowStride = (width + 31) ~/ 32;
    final bits = Uint32List(rowStride * height);

    var yOffset = 0;
    var rowOffset = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x += 32) {
        final end = (x + 32 > width) ? width : x + 32;
        var word = 0;

        for (var k = x; k < end; k++) {
          if (luminances[yOffset + k] < threshold) {
            word |= 1 << (k & 0x1f);
          }
        }
        bits[rowOffset + (x >> 5)] = word;
      }
      yOffset += width;
      rowOffset += rowStride;
    }

    return BitMatrix.fromBits(
      width: width,
      height: height,
      bits: bits,
      rowStride: rowStride,
    );
  }

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
      throw ArgumentError('Both dimensions must be greater than 0');
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

  /// Gets the bit at [x], [y]. Returns true if set (black), false otherwise (white).
  ///
  /// Throws [RangeError] if coordinates are out of bounds.
  /// For performance-critical code, use [getUnchecked] instead.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  bool get({required int x, required int y}) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width, $height)');
    }
    return getUnchecked(x, y);
  }

  /// Gets the bit at [x], [y] without bounds checking.
  ///
  /// This is faster than [get] but will produce undefined behavior
  /// if coordinates are out of bounds. Use only in performance-critical
  /// inner loops where bounds have been pre-validated.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  bool getUnchecked(int x, int y) {
    final offset = y * _rowStride + (x >> 5);
    return (_bits[offset] & (1 << (x & 0x1f))) != 0;
  }

  /// Sets the bit at [x], [y] to true.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  void set({required int x, required int y}) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width, $height)');
    }
    final offset = y * _rowStride + (x >> 5);
    _bits[offset] |= (1 << (x & 0x1f));
  }

  /// Unsets the bit at [x], [y] (sets to false).
  void unset({required int x, required int y}) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width, $height)');
    }
    final offset = y * _rowStride + (x >> 5);
    _bits[offset] &= ~(1 << (x & 0x1f));
  }

  /// Flips the bit at [x], [y].
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  void flip({required int x, required int y}) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width, $height)');
    }
    final offset = y * _rowStride + (x >> 5);
    _bits[offset] ^= (1 << (x & 0x1f));
  }

  /// Clears the entire matrix (sets all bits to false).
  void clear() {
    // fast clear
    _bits.fillRange(0, _bits.length, 0);
  }

  /// Sets a rectangular region of bits to true.
  ///
  /// [left], [top] is the top-left corner.
  /// [width], [height] are the dimensions of the region.
  void setRegion({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    if (top < 0 || left < 0) {
      throw ArgumentError('Left and top must be non-negative');
    }
    if (height < 1 || width < 1) {
      throw ArgumentError('Height and width must be at least 1');
    }
    final right = left + width;
    final bottom = top + height;
    if (bottom > this.height || right > this.width) {
      throw RangeError('The region is out of the matrix bounds');
    }
    // Naive implementation loop.
    // Optimization possible but likely not the bottleneck for small QR codes yet.
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        set(x: x, y: y);
      }
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        buffer.write(get(x: x, y: y) ? 'X ' : '  ');
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
