import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';

void main() {
  group('GenericGF', () {
    // QR Code uses GF(256) with primitive polynomial 0x11D (285 decimal)
    // Generator for RS is usually 2.
    final field = GenericGF.qrCodeField256;

    test('exp returns correct power of 2', () {
      expect(field.exp(0), 1);
      expect(field.exp(1), 2);
      expect(field.exp(2), 4);
      // 2^8 = 256. In GF(256) mod 0x11D:
      // 256 XOR 285 = 29
      expect(field.exp(8), 29);
    });

    test('log returns correct logarithm base 2', () {
      expect(field.log(1), 0);
      expect(field.log(2), 1);
      expect(field.log(29), 8);
    });

    test('multiply returns product in field', () {
      expect(field.multiply(0, 5), 0);
      expect(field.multiply(5, 0), 0);
      expect(
        field.multiply(3, 3),
        5,
      ); // 2+1 * 2+1 = 4 + 2 + 2 + 1 = 4+1 = 5? No.
      // 3 = a^25 (actually generator is 2, so 3 is not simple power of 2 directly, wait)
      // 2^1 = 2, 2^0 = 1. 3 = 2^1 + 2^0?
      // Multiplication is (a^i) * (a^j) = a^(i+j).
      // Let's use exp/log table consistency.
      final a = field.exp(10);
      final b = field.exp(20);
      final prod = field.exp(30);
      expect(field.multiply(a, b), prod);
    });

    test('inverse returns multiplicative inverse', () {
      for (var i = 1; i < 256; i++) {
        final inv = field.inverse(i);
        expect(field.multiply(i, inv), 1);
      }
    });
  });

  group('GenericGF operations', () {
    test('buildMonomial creates correct polynomial', () {
      final field = GenericGF.qrCodeField256;
      final mono = field.buildMonomial(3, 5);
      expect(mono.degree, 3);
      expect(mono.getCoefficient(3), 5);
    });

    test('exp and log are inverse operations', () {
      final field = GenericGF.qrCodeField256;
      for (var i = 0; i < 10; i++) {
        final exp = field.exp(i);
        final log = field.log(exp);
        expect(log, i);
      }
    });

    test('inverse produces correct result', () {
      final field = GenericGF.qrCodeField256;
      for (var i = 1; i < 10; i++) {
        final inv = field.inverse(i);
        final product = field.multiply(i, inv);
        expect(product, 1);
      }
    });
  });
}
