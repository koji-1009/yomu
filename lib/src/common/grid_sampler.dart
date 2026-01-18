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

    final bits = BitMatrix(width: dimensionX, height: dimensionY);
    final points = List<double>.filled(2 * dimensionX, 0.0);

    for (var y = 0; y < dimensionY; y++) {
      final max = points.length;
      final iValue = y + 0.5;
      for (var x = 0; x < max; x += 2) {
        points[x] = (x >> 1) + 0.5;
        points[x + 1] = iValue;
      }

      transform.transformPoints(points);

      for (var x = 0; x < max; x += 2) {
        final px = points[x].toInt();
        final py = points[x + 1].toInt();

        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          if (image.get(px, py)) {
            bits.set(x >> 1, y);
          }
        }
      }
    }
    return bits;
  }
}
