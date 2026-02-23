import 'dart:typed_data';

import 'bit_matrix.dart';
import 'perspective_transform.dart';

class GridSampler {
  const GridSampler();

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
    final points = Float64List(2 * dimensionX);

    // Direct access to source bit array
    final srcBits = image.bits;
    final srcStride = image.rowStride;
    final srcWidth = image.width;
    final srcHeight = image.height;

    for (var y = 0; y < dimensionY; y++) {
      final max = points.length;
      final iValue = y + 0.5;
      for (var x = 0; x < max; x += 2) {
        points[x] = (x >> 1) + 0.5;
        points[x + 1] = iValue;
      }

      transform.transformPoints(points);

      final resultRowOffset = y * resultStride;
      for (var x = 0; x < max; x += 2) {
        final px = points[x].toInt();
        final py = points[x + 1].toInt();

        if (px >= 0 && px < srcWidth && py >= 0 && py < srcHeight) {
          // Inline image.get(px, py)
          final srcOffset = py * srcStride + (px >> 5);
          if ((srcBits[srcOffset] & (1 << (px & 0x1f))) != 0) {
            // Inline bits.set(x >> 1, y)
            final col = x >> 1;
            resultBits[resultRowOffset + (col >> 5)] |= (1 << (col & 0x1f));
          }
        }
      }
    }
    return result;
  }
}
