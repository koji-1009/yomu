import 'dart:typed_data';

/// Represents a perspective transform (homography) between two planes.
/// Matrix M:
/// a11 a12 a13
/// a21 a22 a23
/// a31 a32 a33
///
/// Point (x,y) -> (x', y')
/// w' = a31*x + a32*y + a33
/// x' = (a11*x + a12*y + a13) / w'
/// y' = (a21*x + a22*y + a23) / w'
class PerspectiveTransform {
  const PerspectiveTransform({
    required this.a11,
    required this.a12,
    required this.a13,
    required this.a21,
    required this.a22,
    required this.a23,
    required this.a31,
    required this.a32,
    required this.a33,
  });
  final double a11, a12, a13;
  final double a21, a22, a23;
  final double a31, a32, a33;

  /// Creates a transform mapping a quadrilateral to another quadrilateral.
  static PerspectiveTransform quadrilateralToQuadrilateral({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double x3,
    required double y3,
    required double x0p,
    required double y0p,
    required double x1p,
    required double y1p,
    required double x2p,
    required double y2p,
    required double x3p,
    required double y3p,
  }) {
    final qToS = quadrilateralToSquare(
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      x3: x3,
      y3: y3,
    );
    final sToQ = squareToQuadrilateral(
      x0: x0p,
      y0: y0p,
      x1: x1p,
      y1: y1p,
      x2: x2p,
      y2: y2p,
      x3: x3p,
      y3: y3p,
    );
    return sToQ.times(qToS);
  }

  /// Maps (0,0)->(x0,y0), (1,0)->(x1,y1), (1,1)->(x2,y2), (0,1)->(x3,y3)
  static PerspectiveTransform squareToQuadrilateral({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double x3,
    required double y3,
  }) {
    final dx3 = x0 - x1 + x2 - x3;
    final dy3 = y0 - y1 + y2 - y3;

    if (dx3 == 0.0 && dy3 == 0.0) {
      // Affine
      return PerspectiveTransform(
        a11: x1 - x0,
        a12: x3 - x0,
        a13: x0,
        a21: y1 - y0,
        a22: y3 - y0,
        a23: y0,
        a31: 0.0,
        a32: 0.0,
        a33: 1.0,
      );
    } else {
      final dx1 = x1 - x2;
      final dx2 = x3 - x2;
      final dy1 = y1 - y2;
      final dy2 = y3 - y2;

      final degenerate = checkDegenerate(
        x0: x0,
        y0: y0,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        x3: x3,
        y3: y3,
      );
      if (degenerate != null) return degenerate;

      final denominator = dx1 * dy2 - dx2 * dy1;
      final a13 = (dx3 * dy2 - dx2 * dy3) / denominator;
      final a23 = (dx1 * dy3 - dx3 * dy1) / denominator;

      return PerspectiveTransform(
        a11: x1 - x0 + a13 * x1,
        a12: x3 - x0 + a23 * x3,
        a13: x0,
        a21: y1 - y0 + a13 * y1,
        a22: y3 - y0 + a23 * y3,
        a23: y0,
        a31: a13,
        a32: a23,
        a33: 1.0,
      );
    }
  }

  /// Checks for degenerate case and returns the fallback transform if applicable.
  /// Returns null if not degenerate.
  /// Uses a small epsilon to detect when the denominator is close to zero.
  static PerspectiveTransform? checkDegenerate({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double x3,
    required double y3,
  }) {
    final dx1 = x1 - x2;
    final dx2 = x3 - x2;
    final dy1 = y1 - y2;
    final dy2 = y3 - y2;
    final denominator = dx1 * dy2 - dx2 * dy1;

    if (denominator.abs() < 1e-10) {
      return PerspectiveTransform(
        a11: x1 - x0,
        a12: x3 - x0,
        a13: x0,
        a21: y1 - y0,
        a22: y3 - y0,
        a23: y0,
        a31: 0.0,
        a32: 0.0,
        a33: 1.0,
      );
    }
    return null;
  }

  /// Computes the inverse of [squareToQuadrilateral] via the adjoint matrix.
  static PerspectiveTransform quadrilateralToSquare({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double x3,
    required double y3,
  }) {
    // Inverse of squareToQuadrilateral
    return squareToQuadrilateral(
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      x3: x3,
      y3: y3,
    ).buildAdjoint();
  }

  /// Returns the adjoint (transpose of cofactor matrix) of this transform.
  PerspectiveTransform buildAdjoint() {
    // Adjoint = Transpose of Cofactor Matrix
    // B_ij = Cofactor(A_ji)

    // A11 A12 A13
    // A21 A22 A23
    // A31 A32 A33

    // B11 = + Det(A22 A23; A32 A33)
    final b11 = a22 * a33 - a23 * a32;

    // B12 = Cofactor(A21) = - Det(A12 A13; A32 A33)
    final b12 = a13 * a32 - a12 * a33;

    // B13 = Cofactor(A31) = + Det(A12 A13; A22 A23)
    final b13 = a12 * a23 - a13 * a22;

    // B21 = Cofactor(A12) = - Det(A21 A23; A31 A33)
    final b21 = a23 * a31 - a21 * a33;

    // B22 = Cofactor(A22) = + Det(A11 A13; A31 A33)
    final b22 = a11 * a33 - a13 * a31;

    // B23 = Cofactor(A32) = - Det(A11 A13; A21 A23)
    final b23 = a13 * a21 - a11 * a23;

    // B31 = Cofactor(A13) = + Det(A21 A22; A31 A32)
    final b31 = a21 * a32 - a22 * a31;

    // B32 = Cofactor(A23) = - Det(A11 A12; A31 A32)
    final b32 = a12 * a31 - a11 * a32;

    // B33 = Cofactor(A33) = + Det(A11 A12; A21 A22)
    final b33 = a11 * a22 - a12 * a21;

    return PerspectiveTransform(
      a11: b11,
      a12: b12,
      a13: b13,
      a21: b21,
      a22: b22,
      a23: b23,
      a31: b31,
      a32: b32,
      a33: b33,
    );
  }

  /// Returns the matrix product of this transform and [other].
  PerspectiveTransform times(PerspectiveTransform other) {
    // Matrix multiplication
    return PerspectiveTransform(
      a11: a11 * other.a11 + a12 * other.a21 + a13 * other.a31,
      a12: a11 * other.a12 + a12 * other.a22 + a13 * other.a32,
      a13: a11 * other.a13 + a12 * other.a23 + a13 * other.a33,

      a21: a21 * other.a11 + a22 * other.a21 + a23 * other.a31,
      a22: a21 * other.a12 + a22 * other.a22 + a23 * other.a32,
      a23: a21 * other.a13 + a22 * other.a23 + a23 * other.a33,

      a31: a31 * other.a11 + a32 * other.a21 + a33 * other.a31,
      a32: a31 * other.a12 + a32 * other.a22 + a33 * other.a32,
      a33: a31 * other.a13 + a32 * other.a23 + a33 * other.a33,
    );
  }

  /// Transforms [points] in-place, where each consecutive pair is (x, y).
  ///
  /// Uses an optimized fast path when the transform is affine (no perspective).
  void transformPoints(Float64List points) {
    final max = points.length;
    // Optimization: Check for Affine transform (a31=0, a32=0, a33=1)
    // This avoids expensive division per point
    if (a31 == 0.0 && a32 == 0.0 && a33 == 1.0) {
      for (var i = 0; i < max; i += 2) {
        final x = points[i];
        final y = points[i + 1];
        points[i] = a11 * x + a12 * y + a13;
        points[i + 1] = a21 * x + a22 * y + a23;
      }
      return;
    }

    for (var i = 0; i < max; i += 2) {
      final x = points[i];
      final y = points[i + 1];
      final denominator = a31 * x + a32 * y + a33;
      // Avoid division by zero
      if (denominator.abs() < 1e-10) {
        // Point at infinity - keep original or use a safe default
        continue;
      }
      points[i] = (a11 * x + a12 * y + a13) / denominator;
      points[i + 1] = (a21 * x + a22 * y + a23) / denominator;
    }
  }
}
