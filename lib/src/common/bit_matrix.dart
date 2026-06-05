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

  BitMatrix clone() {
    return BitMatrix.fromBits(
      width: width,
      height: height,
      bits: Uint32List.fromList(_bits),
    );
  }

  /// Returns a new matrix where each bit is the 3x3 majority of its
  /// neighborhood (out-of-bounds cells count as white).
  ///
  /// This acts as a despeckle filter: isolated black pixels (salt & pepper
  /// noise) are removed and isolated white holes inside black areas are
  /// filled, while features 2+ pixels wide are preserved.
  ///
  /// The filter is computed word-parallel: 32 pixels per operation using
  /// bitwise full adders, so a full pass is cheap enough for retry paths.
  BitMatrix majority3x3() {
    final result = BitMatrix(width: width, height: height);
    final src = _bits;
    final dst = result._bits;
    final stride = _rowStride;
    const mask32 = 0xFFFFFFFF;

    // Mask for valid bits in the last word of each row, so that bits beyond
    // [width] never leak into the output.
    final tailBits = width & 31;
    final tailMask = tailBits == 0 ? mask32 : (1 << tailBits) - 1;

    for (var y = 0; y < height; y++) {
      final rowOffset = y * stride;
      final upOffset = y > 0 ? rowOffset - stride : -1;
      final downOffset = y < height - 1 ? rowOffset + stride : -1;

      for (var w = 0; w < stride; w++) {
        // Per-pixel neighbor count (0..9) kept as bit-sliced binary across
        // 32 lanes: count = 8*s8 + 4*s4 + 2*s2 + s1.
        var s1 = 0;
        var s2 = 0;
        var s4 = 0;
        var s8 = 0;

        for (var r = 0; r < 3; r++) {
          final offset = switch (r) {
            0 => upOffset,
            1 => rowOffset,
            _ => downOffset,
          };
          if (offset < 0) {
            continue;
          }
          final center = src[offset + w];
          final prev = w > 0 ? src[offset + w - 1] : 0;
          final next = w < stride - 1 ? src[offset + w + 1] : 0;

          // Bit b corresponds to x = w*32 + b, so the west neighbor lives
          // one bit lower (shift left to align) and east one bit higher.
          final west = ((center << 1) & mask32) | (prev >>> 31);
          final east = (center >>> 1) | ((next << 31) & mask32);

          // Full adder for (west, center, east) of this row:
          // hs = weight-1 sum bit, hc = weight-2 carry bit.
          final xor = west ^ east;
          final hs = xor ^ center;
          final hc = (west & east) | (center & xor);

          // Ripple-carry the row sum (hs + 2*hc) into the running count.
          final c1 = s1 & hs;
          s1 ^= hs;
          // Add the two weight-2 bits (hc, c1) to s2; carry has weight 4.
          final c2 = (s2 & (hc | c1)) | (hc & c1);
          s2 ^= hc ^ c1;
          // Add the weight-4 carry to s4; carry has weight 8.
          final c4 = s4 & c2;
          s4 ^= c2;
          s8 |= c4;
        }

        // count >= 5  <=>  count == 8..9 (s8) or count == 5..7
        // (s4 with at least one of s2/s1).
        final majority = s8 | (s4 & (s2 | s1));

        var value = majority;
        if (w == stride - 1) {
          value &= tailMask;
        }
        dst[rowOffset + w] = value;
      }
    }
    return result;
  }
}
