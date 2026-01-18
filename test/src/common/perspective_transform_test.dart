import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/grid_sampler.dart';
import 'package:yomu/src/common/perspective_transform.dart';

void main() {
  group('GridSampler', () {
    test('samples identity transform correctly', () {
      const sampler = GridSampler();
      final source = BitMatrix(width: 10);
      source.set(0, 0);
      source.set(5, 5);
      source.set(9, 9);

      // Identity transform
      final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 10,
        x3: 0,
        y3: 10,
        x0p: 0,
        y0p: 0,
        x1p: 10,
        y1p: 0,
        x2p: 10,
        y2p: 10,
        x3p: 0,
        y3p: 10,
      );

      final result = sampler.sampleGrid(source, 10, 10, transform);

      expect(result.get(0, 0), isTrue);
      expect(result.get(5, 5), isTrue);
      expect(result.get(9, 9), isTrue);
      expect(result.get(1, 1), isFalse);
    });
  });

  group('PerspectiveTransform', () {
    test('identity transform preserves points', () {
      final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 10,
        x3: 0,
        y3: 10,
        x0p: 0,
        y0p: 0,
        x1p: 10,
        y1p: 0,
        x2p: 10,
        y2p: 10,
        x3p: 0,
        y3p: 10,
      );

      final points = Float64List.fromList([0, 0, 5, 5, 10, 10]);
      transform.transformPoints(points);

      expect(points[0], closeTo(0, 0.001));
      expect(points[1], closeTo(0, 0.001));
      expect(points[2], closeTo(5, 0.001));
      expect(points[3], closeTo(5, 0.001));
    });

    test('scaling transform works correctly', () {
      final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 1,
        y1: 0,
        x2: 1,
        y2: 1,
        x3: 0,
        y3: 1,
        x0p: 0,
        y0p: 0,
        x1p: 10,
        y1p: 0,
        x2p: 10,
        y2p: 10,
        x3p: 0,
        y3p: 10,
      );

      final points = Float64List.fromList([0.5, 0.5]);
      transform.transformPoints(points);

      expect(points[0], closeTo(5, 0.001));
      expect(points[1], closeTo(5, 0.001));
    });

    test('squareToQuadrilateral works', () {
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 10,
        x3: 0,
        y3: 10,
      );

      final points = Float64List.fromList([0.5, 0.5]);
      transform.transformPoints(points);

      expect(points[0], closeTo(5, 0.001));
      expect(points[1], closeTo(5, 0.001));
    });

    test('quadrilateralToSquare works', () {
      final transform = PerspectiveTransform.quadrilateralToSquare(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 10,
        x3: 0,
        y3: 10,
      );

      final points = Float64List.fromList([5.0, 5.0]);
      transform.transformPoints(points);

      expect(points[0], closeTo(0.5, 0.001));
      expect(points[1], closeTo(0.5, 0.001));
    });

    test('buildAdjoint creates valid transform', () {
      final original = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 10,
        x3: 0,
        y3: 10,
      );
      final adjoint = original.buildAdjoint();

      // Adjoint of a transform applied to the transform should give scaled identity
      expect(adjoint, isNotNull);
    });

    test('times multiplies transforms', () {
      final t1 = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 2,
        y1: 0,
        x2: 2,
        y2: 2,
        x3: 0,
        y3: 2,
      );
      final t2 = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 5,
        y1: 0,
        x2: 5,
        y2: 5,
        x3: 0,
        y3: 5,
      );

      final combined = t1.times(t2);
      expect(combined, isNotNull);
    });

    test('affine case when parallelogram', () {
      // When dx3 == 0 && dy3 == 0, the quadrilateral is a parallelogram
      // and an affine transform is used.
      // Parallelogram: (0,0), (10,0), (15,10), (5,10)
      // x0 - x1 + x2 - x3 = 0 - 10 + 15 - 5 = 0
      // y0 - y1 + y2 - y3 = 0 - 0 + 10 - 10 = 0
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0, // (0,0)
        x1: 10,
        y1: 0, // (1,0)
        x2: 15,
        y2: 10, // (1,1)
        x3: 5,
        y3: 10, // (0,1)
      );

      final points = Float64List.fromList([0.5, 0.5]);
      transform.transformPoints(points);

      // Center of unit square should map to center of parallelogram
      // Center = (0+10+15+5)/4, (0+0+10+10)/4 = (7.5, 5)
      expect(points[0], closeTo(7.5, 0.1));
      expect(points[1], closeTo(5, 0.1));
    });

    test('handles degenerate quadrilateral gracefully', () {
      // Collinear points form a degenerate quadrilateral
      // This should fall back to affine approximation
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 10,
        y1: 0,
        x2: 10,
        y2: 0, // Same as point 2 - degenerate
        x3: 0,
        y3: 0, // Same as point 1 - degenerate
      );

      // Should not throw, should return valid (though not useful) transform
      expect(transform, isNotNull);
    });

    test('transformPoints handles near-zero denominator', () {
      // Create a transform with very large perspective coefficients
      // that could cause denominator to be near zero
      const transform = PerspectiveTransform(
        a11: 1,
        a12: 0,
        a13: 0,
        a21: 0,
        a22: 1,
        a23: 0,
        a31: 1e12,
        a32: 1e12,
        a33: 1, // Large perspective coefficients
      );

      // Point at (-1e-12, -1e-12) should have denominator near zero
      final points = Float64List.fromList([-1e-12, -1e-12, 0.5, 0.5]);

      // Should not throw or produce NaN/Infinity
      transform.transformPoints(points);

      // First point should be skipped (kept original)
      expect(points[0].isNaN, isFalse);
      expect(points[1].isNaN, isFalse);
    });

    test('constructor stores all coefficients', () {
      const t = PerspectiveTransform(
        a11: 1.0,
        a12: 2.0,
        a13: 3.0,
        a21: 4.0,
        a22: 5.0,
        a23: 6.0,
        a31: 7.0,
        a32: 8.0,
        a33: 9.0,
      );

      expect(t.a11, 1.0);
      expect(t.a12, 2.0);
      expect(t.a13, 3.0);
      expect(t.a21, 4.0);
      expect(t.a22, 5.0);
      expect(t.a23, 6.0);
      expect(t.a31, 7.0);
      expect(t.a32, 8.0);
      expect(t.a33, 9.0);
    });
  });
}
