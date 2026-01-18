import 'generic_gf.dart';

/// Represents a polynomial whose coefficients are elements of a GF(256).
class GenericGFPoly {
  /// Creates a polynomial with the given [coefficients].
  /// [coefficients] are ordered from highest degree to lowest degree.
  /// e.g. [3, 2, 1] means 3x^2 + 2x + 1.
  GenericGFPoly(this.field, List<int> coefficients)
    : coefficients = _normalizeCoefficients(field, coefficients);

  final GenericGF field;
  final List<int> coefficients;

  static List<int> _normalizeCoefficients(
    GenericGF field,
    List<int> coefficients,
  ) {
    if (coefficients.length > 1 && coefficients[0] == 0) {
      // Strip leading zeros
      var firstNonZero = 1;
      while (firstNonZero < coefficients.length &&
          coefficients[firstNonZero] == 0) {
        firstNonZero++;
      }
      if (firstNonZero == coefficients.length) {
        return [0];
      }
      return coefficients.sublist(firstNonZero);
    }
    return coefficients;
  }

  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int get degree => coefficients.length - 1;

  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  bool get isZero => coefficients[0] == 0;

  /// Returns the coefficient of x^degree.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int getCoefficient(int degree) {
    return coefficients[coefficients.length - 1 - degree];
  }

  /// Evaluate this polynomial at [a].
  int evaluateAt(int a) {
    if (a == 0) {
      // f(0) is just the constant term
      return getCoefficient(0);
    }
    if (a == 1) {
      // f(1) is sum of coeffs (XOR sum)
      var result = 0;
      for (final element in coefficients) {
        result ^= element;
      }
      return result;
    }
    var result = coefficients[0];
    for (var i = 1; i < coefficients.length; i++) {
      result = field.multiply(a, result) ^ coefficients[i];
    }
    return result;
  }

  GenericGFPoly addOrSubtract(GenericGFPoly other) {
    if (field != other.field) {
      throw ArgumentError('GenericGFPolys do not have same GenericGF field');
    }
    if (isZero) return other;
    if (other.isZero) return this;

    var smallerCoefficients = coefficients;
    var largerCoefficients = other.coefficients;
    if (smallerCoefficients.length > largerCoefficients.length) {
      final temp = smallerCoefficients;
      smallerCoefficients = largerCoefficients;
      largerCoefficients = temp;
    }

    final sumDiff = List<int>.filled(largerCoefficients.length, 0);
    final lengthDiff = largerCoefficients.length - smallerCoefficients.length;

    // Copy high-order terms only found in largerCoefficients
    // (XOR with 0 is itself)
    for (var i = 0; i < lengthDiff; i++) {
      sumDiff[i] = largerCoefficients[i];
    }

    // XOR the rest
    for (var i = lengthDiff; i < largerCoefficients.length; i++) {
      sumDiff[i] = smallerCoefficients[i - lengthDiff] ^ largerCoefficients[i];
    }

    return GenericGFPoly(field, sumDiff);
  }

  GenericGFPoly multiply(GenericGFPoly other) {
    if (field != other.field) {
      throw ArgumentError('GenericGFPolys do not have same GenericGF field');
    }
    if (isZero || other.isZero) {
      return field.zero;
    }
    final aCoefficients = coefficients;
    final aLength = aCoefficients.length;
    final bCoefficients = other.coefficients;
    final bLength = bCoefficients.length;
    final product = List<int>.filled(aLength + bLength - 1, 0);

    for (var i = 0; i < aLength; i++) {
      final aCoeff = aCoefficients[i];
      for (var j = 0; j < bLength; j++) {
        product[i + j] ^= field.multiply(aCoeff, bCoefficients[j]);
      }
    }
    return GenericGFPoly(field, product);
  }

  GenericGFPoly multiplyByScalar(int scalar) {
    if (scalar == 0) return field.zero;
    if (scalar == 1) return this;

    final size = coefficients.length;
    final product = List<int>.filled(size, 0);
    for (var i = 0; i < size; i++) {
      product[i] = field.multiply(coefficients[i], scalar);
    }
    return GenericGFPoly(field, product);
  }

  GenericGFPoly multiplyByMonomial(int degree, int coefficient) {
    if (degree < 0) throw ArgumentError();
    if (coefficient == 0) return field.zero;

    final size = coefficients.length;
    final product = List<int>.filled(size + degree, 0);
    for (var i = 0; i < size; i++) {
      product[i] = field.multiply(coefficients[i], coefficient);
    }
    return GenericGFPoly(field, product);
  }

  List<GenericGFPoly> divide(GenericGFPoly other) {
    if (field != other.field) {
      throw ArgumentError('GenericGFPolys do not have same GenericGF field');
    }
    if (other.isZero) {
      throw ArgumentError('Divide by 0');
    }

    var quotient = field.zero;
    var remainder = this;

    final denominatorLeadingTerm = other.getCoefficient(other.degree);
    final inverseDenominatorLeadingTerm = field.inverse(denominatorLeadingTerm);

    while (remainder.degree >= other.degree && !remainder.isZero) {
      final degreeDifference = remainder.degree - other.degree;
      final scale = field.multiply(
        remainder.getCoefficient(remainder.degree),
        inverseDenominatorLeadingTerm,
      );
      final term = other.multiplyByMonomial(degreeDifference, scale);
      final iterationQuotient = field.buildMonomial(degreeDifference, scale);

      quotient = quotient.addOrSubtract(iterationQuotient);
      remainder = remainder.addOrSubtract(term);
    }
    return [quotient, remainder];
  }

  @override
  String toString() {
    // Just for debugging
    final sb = StringBuffer();
    for (var i = 0; i < coefficients.length; i++) {
      if (i > 0) sb.write(' + ');
      final deg = coefficients.length - 1 - i;
      sb.write('${coefficients[i]}x^$deg');
    }
    return sb.toString();
  }
}
