import 'dart:typed_data';

import '../../yomu_exception.dart';
import 'generic_gf.dart';
import 'generic_gf_poly.dart';

class ReedSolomonDecoder {
  const ReedSolomonDecoder(this.field);

  final GenericGF field;

  /// Decodes [received] codeword in-place.
  /// [twoS] is the number of error correction bytes (symbols).
  void decode({required Uint8List received, required int twoS}) {
    final poly = GenericGFPoly(field, received); // Copy input to poly
    final syndromeCoefficients = Uint8List(twoS);
    var noError = true;

    // Calculate syndromes
    // S_i = R(alpha^(generatorBase + i))
    for (var i = 0; i < twoS; i++) {
      final eval = poly.evaluateAt(field.exp(GenericGF.generatorBase + i));
      syndromeCoefficients[syndromeCoefficients.length - 1 - i] = eval;
      if (eval != 0) {
        noError = false;
      }
    }

    if (noError) {
      return;
    }

    final syndrome = GenericGFPoly(field, syndromeCoefficients);

    // Find error locator and evaluator polynomials using Euclidean Algorithm
    final sigmaOmega = _runEuclideanAlgorithm(
      a: field.buildMonomial(twoS, 1),
      b: syndrome,
      R: twoS,
    );
    final sigma = sigmaOmega[0];
    final omega = sigmaOmega[1];

    // Find error locations (roots of sigma)
    final errorLocations = _findErrorLocations(sigma);
    final errorMagnitudes = _findErrorMagnitudes(omega, errorLocations);

    for (var i = 0; i < errorLocations.length; i++) {
      final position = received.length - 1 - field.log(errorLocations[i]);
      if (position < 0) {
        throw const ReedSolomonException('Bad error location');
      }
      received[position] ^= errorMagnitudes[i];
    }
  }

  List<GenericGFPoly> _runEuclideanAlgorithm({
    required GenericGFPoly a,
    required GenericGFPoly b,
    required int R,
  }) {
    // Assume a.degree >= b.degree
    var rLast = a;
    var r = b;
    if (rLast.degree < r.degree) {
      final temp = rLast;
      rLast = r;
      r = temp;
    }

    var tLast = field.zero;
    var t = field.one;

    // Run until r degree < R/2
    while (r.degree >= R / 2) {
      if (r.isZero) {
        throw const ReedSolomonException('r is zero');
      }

      final rLastLast = rLast;
      final tLastLast = tLast;
      rLast = r;
      tLast = t;

      final divisionResult = rLastLast.divide(rLast);
      final q = divisionResult[0];
      r = divisionResult[1]; // Remainder

      // t = tLastLast + q * tLast
      t = q.multiply(tLast).addOrSubtract(tLastLast);
    }

    final sigmaTilde = t;
    final omegaTilde = r;

    // Verify sigma calculation
    final sigma0 = sigmaTilde.getCoefficient(0);
    if (sigma0 == 0) {
      throw const ReedSolomonException('sigma0 is zero');
    }

    final inverse = field.inverse(sigma0);
    final sigma = sigmaTilde.multiplyByScalar(inverse);
    final omega = omegaTilde.multiplyByScalar(inverse);

    return [sigma, omega];
  }

  Uint8List _findErrorLocations(GenericGFPoly errorLocator) {
    // Chien search
    final numErrors = errorLocator.degree;
    if (numErrors == 1) {
      return Uint8List.fromList([errorLocator.getCoefficient(1)]);
    }

    final result = Uint8List(numErrors);
    var count = 0;
    for (var i = 1; i < GenericGF.size && count < numErrors; i++) {
      if (errorLocator.evaluateAt(i) == 0) {
        result[count++] = field.inverse(i);
      }
    }

    if (count != numErrors) {
      throw const ReedSolomonException(
        'Error locator degree does not match number of roots',
      );
    }
    return result;
  }

  Uint8List _findErrorMagnitudes(
    GenericGFPoly errorEvaluator,
    Uint8List errorLocations,
  ) {
    // Forney algorithm
    final s = errorLocations.length;
    final result = Uint8List(s);

    for (var i = 0; i < s; i++) {
      final xiInverse = field.inverse(errorLocations[i]);
      var denominator = 1;
      for (var j = 0; j < s; j++) {
        if (i != j) {
          final term = field.multiply(errorLocations[j], xiInverse);
          final termPlus1 = (term ^ 1);
          denominator = field.multiply(denominator, termPlus1);
        }
      }

      result[i] = field.multiply(
        errorEvaluator.evaluateAt(xiInverse),
        field.inverse(denominator),
      );
    }
    return result;
  }
}
