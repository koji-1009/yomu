import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/generic_gf_poly.dart';

void main() {
  group('GenericGFPoly', () {
    final field = GenericGF.qrCodeField256;

    // Helper to create poly from coefficients (highest degree first)
    GenericGFPoly poly(List<int> coeffs) => GenericGFPoly(field, coeffs);

    test('addOrSubtract adds coefficients', () {
      // 3x^2 + 5x + 1
      final p1 = poly([3, 5, 1]);
      // 3x^2 + 4x + 10
      final p2 = poly([3, 4, 10]);

      // (3^3)x^2 + (5^4)x + (1^10)
      // 0x^2 + 1x + 11
      final sum = p1.addOrSubtract(p2);

      expect(sum.coefficients, [1, 11]); // Leading zeros should be stripped
    });

    test('multiplyByScalar', () {
      final p = poly([1, 2, 3]);
      final res = p.multiplyByScalar(5);
      // 1*5, 2*5, 3*5
      expect(res.coefficients, [
        field.multiply(1, 5),
        field.multiply(2, 5),
        field.multiply(3, 5),
      ]);
    });

    test('multiply poly', () {
      // (x + 1) * (x + 1) = x^2 + 0x + 1 = x^2 + 1 (in GF2^n addition is xor)
      final p1 = poly([1, 1]); // x + 1
      final product = p1.multiply(p1);
      expect(product.coefficients, [1, 0, 1]);
    });

    test('multiply with zero returns zero', () {
      final p1 = poly([1, 1]); // x + 1
      final zero = poly([0]);

      expect(p1.multiply(zero).isZero, isTrue);
      expect(zero.multiply(p1).isZero, isTrue);
    });

    test('evaluateAt', () {
      // f(x) = x^2 + 2x + 1
      // f(3) = 9 + 6 + 1 = (9^6)^1 ? No, arithmetic is in GF.
      // 3^2 = 5 (from previous test/known)
      // 2*3 =
      // 1 = 1
      final p = poly([1, 2, 1]);
      final res = p.evaluateAt(3);
      // expected: 3^2 + 2*3 + 1
      final expected = (field.multiply(3, 3) ^ field.multiply(2, 3)) ^ 1;
      expect(res, expected);
    });

    test('divide', () {
      // x^3 + 1 divided by x + 1
      // should be x^2 + x + 1 ?
      // (x+1)(x^2+x+1) = x^3 + x^2 + x + x^2 + x + 1 = x^3 + 1 (since 2x^2=0 etc)
      final dividend = poly([1, 0, 0, 1]);
      final divisor = poly([1, 1]);

      final result = dividend.divide(divisor);
      final quotient = result[0];
      final remainder = result[1];

      expect(quotient.coefficients, [1, 1, 1]);
      expect(remainder.isZero, isTrue);
    });
  });

  group('GenericGFPoly Exception Paths', () {
    test('divide by zero throws', () {
      final field = GenericGF.qrCodeField256;
      final poly1 = GenericGFPoly(field, [1, 2, 3]);
      final zero = field.zero;

      expect(() => poly1.divide(zero), throwsA(isA<ArgumentError>()));
    });

    test('multiplyByMonomial with negative degree throws', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2]);

      expect(
        () => poly.multiplyByMonomial(-1, 3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('evaluateAt with zero returns constant term', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [5, 10, 15]);
      expect(poly.evaluateAt(0), 15);
    });

    test('multiply by scalar zero returns zero poly', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2, 3]);
      final result = poly.multiplyByScalar(0);
      expect(result.isZero, isTrue);
    });

    test('add/subtract identical polys returns zero', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2, 3]);
      final result = poly.addOrSubtract(poly);
      expect(result.isZero, isTrue);
    });

    test('multiply by monomial', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2]);
      final result = poly.multiplyByMonomial(2, 3);
      expect(result.degree, poly.degree + 2);
    });

    test('divide returns quotient and remainder', () {
      final field = GenericGF.qrCodeField256;
      final dividend = GenericGFPoly(field, [1, 2, 3, 4]);
      final divisor = GenericGFPoly(field, [1, 1]);
      final result = dividend.divide(divisor);
      expect(result.length, 2); // [quotient, remainder]
    });
  });
}
