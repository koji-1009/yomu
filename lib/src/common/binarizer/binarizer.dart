import 'dart:typed_data';

import '../bit_matrix.dart';
import 'luminance_source.dart';

/// A binarizer that uses a block-averaged integral image for fast,
/// locally-adaptive thresholding.
///
/// Luminance is first reduced to per-block means ([_blockSize] x [_blockSize]
/// pixels per block), and the local window average is computed from an
/// integral image over those means. Since the adaptive window is at least
/// [_minWindowSize] pixels wide, the threshold surface varies far more slowly
/// than the block grid, so quantizing it to blocks costs no meaningful
/// accuracy while cutting the per-pixel work to a single load and compare.
///
/// This is robust to lighting gradients and shadows, and the integral is
/// built over means (never raw sums), so it cannot overflow 32-bit storage
/// even for very large images.
class Binarizer {
  const Binarizer(this.source, {this.thresholdFactor = 0.875});

  final LuminanceSource source;
  final double thresholdFactor;

  /// Minimum side length of the local averaging window, in pixels.
  /// 1/32nd of the image's longer side is a reasonable heuristic for QR
  /// codes, floored here so that small images still average over enough
  /// context to survive noise.
  static const int _minWindowSize = 40;

  /// Side length of a block in pixels, as a shift (4x4 pixels).
  static const int _blockShift = 2;
  static const int _blockSize = 1 << _blockShift;

  /// Pixels per full block, as a shift (16 = 4x4), so that the common
  /// full-block mean is a shift instead of a division.
  static const int _blockAreaShift = _blockShift * 2;

  BitMatrix getBlackMatrix() {
    final width = source.width;
    final height = source.height;
    final luminances = source.luminances;

    // Constructed first so that invalid dimensions fail before any work.
    final matrix = BitMatrix(width: width, height: height);
    final bits = matrix.bits;
    final rowStride = matrix.rowStride;

    var windowSize = (width > height ? width : height) ~/ 32;
    if (windowSize < _minWindowSize) {
      windowSize = _minWindowSize;
    }
    // Safety: clamp the window to the image dimensions.
    if (windowSize > width) windowSize = width;
    if (windowSize > height) windowSize = height;
    final halfWindow = windowSize >> 1;

    final blocksX = (width + _blockSize - 1) >> _blockShift;
    final blocksY = (height + _blockSize - 1) >> _blockShift;

    // Half window expressed in blocks (rounded), never below 1 so the
    // window always spans at least three blocks.
    var halfWindowBlocks = (halfWindow + (_blockSize >> 1)) >> _blockShift;
    if (halfWindowBlocks < 1) {
      halfWindowBlocks = 1;
    }

    final integralStride = blocksX + 1;
    final integral = Int32List(integralStride * (blocksY + 1));

    _buildBlockIntegral(
      luminances: luminances,
      width: width,
      height: height,
      blocksX: blocksX,
      blocksY: blocksY,
      integral: integral,
      integralStride: integralStride,
    );

    // Window width in blocks depends only on the block column, so the
    // reciprocal can be hoisted out of the per-block-row loop.
    final invWindowCols = Float64List(blocksX);
    for (var bx = 0; bx < blocksX; bx++) {
      final bx1 = bx - halfWindowBlocks < 0 ? 0 : bx - halfWindowBlocks;
      final bx2 = bx + halfWindowBlocks > blocksX - 1
          ? blocksX - 1
          : bx + halfWindowBlocks;
      invWindowCols[bx] = 1.0 / (bx2 - bx1 + 1);
    }

    final thresholds = Int32List(blocksX);

    for (var by = 0; by < blocksY; by++) {
      final by1 = by - halfWindowBlocks < 0 ? 0 : by - halfWindowBlocks;
      final by2 = by + halfWindowBlocks > blocksY - 1
          ? blocksY - 1
          : by + halfWindowBlocks;

      final topOffset = by1 * integralStride;
      final bottomOffset = (by2 + 1) * integralStride;
      final rowFactor = thresholdFactor / (by2 - by1 + 1);

      for (var bx = 0; bx < blocksX; bx++) {
        final bx1 = bx - halfWindowBlocks < 0 ? 0 : bx - halfWindowBlocks;
        final bx2 = bx + halfWindowBlocks > blocksX - 1
            ? blocksX - 1
            : bx + halfWindowBlocks;

        final sum =
            integral[bottomOffset + bx2 + 1] -
            integral[bottomOffset + bx1] -
            integral[topOffset + bx2 + 1] +
            integral[topOffset + bx1];

        thresholds[bx] = (sum * invWindowCols[bx] * rowFactor).toInt();
      }

      final yStart = by << _blockShift;
      var yEnd = yStart + _blockSize;
      if (yEnd > height) {
        yEnd = height;
      }

      for (var y = yStart; y < yEnd; y++) {
        _thresholdRow(
          luminances: luminances,
          lumOffset: y * width,
          width: width,
          thresholds: thresholds,
          bits: bits,
          bitsOffset: y * rowStride,
        );
      }
    }

    return matrix;
  }

  /// Fills [integral] with the 2D prefix sum of per-block mean luminance.
  ///
  /// `integral[(by + 1) * stride + bx + 1]` is the sum of the means of all
  /// blocks in `[0, by] x [0, bx]`; row and column 0 stay zero.
  static void _buildBlockIntegral({
    required Uint8List luminances,
    required int width,
    required int height,
    required int blocksX,
    required int blocksY,
    required Int32List integral,
    required int integralStride,
  }) {
    // Columns covered by the (possibly partial) last block.
    final lastBlockCols = width - ((blocksX - 1) << _blockShift);
    final fullBlocksX = width >> _blockShift;
    final rowSums = Int32List(blocksX);

    for (var by = 0; by < blocksY; by++) {
      rowSums.fillRange(0, blocksX, 0);

      final yStart = by << _blockShift;
      var yEnd = yStart + _blockSize;
      if (yEnd > height) {
        yEnd = height;
      }

      for (var y = yStart; y < yEnd; y++) {
        final offset = y * width;
        var x = 0;
        for (var bx = 0; bx < fullBlocksX; bx++) {
          rowSums[bx] +=
              luminances[offset + x] +
              luminances[offset + x + 1] +
              luminances[offset + x + 2] +
              luminances[offset + x + 3];
          x += _blockSize;
        }
        if (x < width) {
          var tail = 0;
          for (; x < width; x++) {
            tail += luminances[offset + x];
          }
          rowSums[fullBlocksX] += tail;
        }
      }

      final rows = yEnd - yStart;
      final fullArea = rows << _blockShift;
      final tailArea = rows * lastBlockCols;

      final rowOffset = (by + 1) * integralStride;
      final prevOffset = by * integralStride;
      var prefix = 0;

      for (var bx = 0; bx < blocksX; bx++) {
        final sum = rowSums[bx];
        // Rounded, not truncated: a floored block mean biases every window
        // average downward, which shifts the threshold and costs contrast
        // on images that sit close to it (fine textures, moire).
        final int mean;
        if (rows == _blockSize && bx < fullBlocksX) {
          mean = (sum + (1 << (_blockAreaShift - 1))) >> _blockAreaShift;
        } else {
          final area = bx < fullBlocksX ? fullArea : tailArea;
          mean = (sum + (area >> 1)) ~/ area;
        }
        prefix += mean;
        integral[rowOffset + bx + 1] = integral[prevOffset + bx + 1] + prefix;
      }
    }
  }

  /// Thresholds one pixel row against the per-block [thresholds], packing
  /// 32 pixels per output word so the bit array is written once per word
  /// instead of once per black pixel.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  static void _thresholdRow({
    required Uint8List luminances,
    required int lumOffset,
    required int width,
    required Int32List thresholds,
    required Uint32List bits,
    required int bitsOffset,
  }) {
    // A block is exactly [_blockSize] pixels and a word exactly 32, so a
    // whole word covers a whole number of blocks. Emitting one block at a
    // time keeps the threshold lookup out of the per-pixel path and lets the
    // four comparisons be independent, instead of a bit-at-a-time loop whose
    // `word |= 1 << bit` serializes on the accumulator.
    const blocksPerWord = 32 ~/ _blockSize;
    final wholeWords = width >> 5;

    var wordIndex = 0;
    var x = 0;
    var blockIndex = 0;

    while (wordIndex < wholeWords) {
      var word = 0;
      for (var b = 0; b < blocksPerWord; b++) {
        // `luminance <= threshold` as arithmetic rather than a branch:
        // `luminance - (threshold + 1)` is negative exactly when the pixel is
        // black, so its sign bit is the output bit. The difference always
        // fits in 32 bits, which keeps the shift portable to the web
        // backends. Binarizing a photograph means one unpredictable branch
        // per pixel otherwise, and the misprediction dominates the compare.
        final limit = thresholds[blockIndex++] + 1;
        final offset = lumOffset + x;
        final mask =
            (((luminances[offset] - limit) >> 31) & 1) |
            (((luminances[offset + 1] - limit) >> 31) & 2) |
            (((luminances[offset + 2] - limit) >> 31) & 4) |
            (((luminances[offset + 3] - limit) >> 31) & 8);
        word |= mask << (b << _blockShift);
        x += _blockSize;
      }
      bits[bitsOffset + wordIndex++] = word;
    }

    // Tail: the last word of a row whose width is not a multiple of 32.
    if (x < width) {
      var word = 0;
      var bit = 0;
      while (x < width) {
        if (luminances[lumOffset + x] <= thresholds[x >> _blockShift]) {
          word |= 1 << bit;
        }
        x++;
        bit++;
      }
      bits[bitsOffset + wordIndex] = word;
    }
  }
}
