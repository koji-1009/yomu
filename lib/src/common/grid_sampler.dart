import 'bit_matrix.dart';
import 'perspective_transform.dart';

/// Samples a region of a [BitMatrix] through a [PerspectiveTransform].
///
/// Maps a grid of points from the destination coordinate space back to the
/// source image, producing a corrected bit matrix for QR code decoding.
/// Uses inlined bit access for performance.
class GridSampler {
  const GridSampler();

  /// Samples a [dimensionX] x [dimensionY] grid from [image] using [transform].
  ///
  /// Each destination pixel is mapped back through the perspective transform
  /// to find the corresponding source pixel.
  ///
  /// The transform is applied inline rather than through
  /// [PerspectiveTransform.transformPoints]: a staging buffer would be
  /// written and read back once per point, and the terms that depend only on
  /// the row can be hoisted out of the column loop. Each point still goes
  /// through the same arithmetic in the same order, so the sampled bits are
  /// identical either way.
  BitMatrix sampleGrid(
    BitMatrix image,
    int dimensionX,
    int dimensionY,
    PerspectiveTransform transform,
  ) {
    if (dimensionX <= 0 || dimensionY <= 0) {
      throw ArgumentError('Dimensions must be positive');
    }

    final result = BitMatrix(width: dimensionX, height: dimensionY);
    final resultBits = result.bits;
    final resultStride = result.rowStride;

    // Direct access to source bit array
    final srcBits = image.bits;
    final srcStride = image.rowStride;
    final srcWidth = image.width;
    final srcHeight = image.height;

    final a11 = transform.a11;
    final a12 = transform.a12;
    final a13 = transform.a13;
    final a21 = transform.a21;
    final a22 = transform.a22;
    final a23 = transform.a23;
    final a31 = transform.a31;
    final a32 = transform.a32;
    final a33 = transform.a33;

    // Affine transforms need no division at all; see
    // [PerspectiveTransform.transformPoints].
    final isAffine = a31 == 0.0 && a32 == 0.0 && a33 == 1.0;

    for (var y = 0; y < dimensionY; y++) {
      final fy = y + 0.5;

      // Row-constant parts of each numerator and of the denominator.
      final rowX = a12 * fy + a13;
      final rowY = a22 * fy + a23;
      final rowW = a32 * fy + a33;

      final resultRowOffset = y * resultStride;

      for (var col = 0; col < dimensionX; col++) {
        final fx = col + 0.5;

        final int px;
        final int py;
        if (isAffine) {
          px = (a11 * fx + rowX).toInt();
          py = (a21 * fx + rowY).toInt();
        } else {
          final denominator = a31 * fx + rowW;
          if (denominator.abs() < 1e-10) {
            // Point at infinity: [PerspectiveTransform.transformPoints]
            // leaves such a point untouched, so the untransformed grid
            // coordinates are what gets sampled.
            px = fx.toInt();
            py = fy.toInt();
          } else {
            px = ((a11 * fx + rowX) / denominator).toInt();
            py = ((a21 * fx + rowY) / denominator).toInt();
          }
        }

        if (px >= 0 && px < srcWidth && py >= 0 && py < srcHeight) {
          // Inline image.get(px, py)
          final srcOffset = py * srcStride + (px >> 5);
          if ((srcBits[srcOffset] & (1 << (px & 0x1f))) != 0) {
            // Inline result.set(col, y)
            resultBits[resultRowOffset + (col >> 5)] |= (1 << (col & 0x1f));
          }
        }
      }
    }
    return result;
  }
}
