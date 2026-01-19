import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/generic_gf_poly.dart';
import 'package:yomu/src/qr/decoder/reed_solomon_decoder.dart';

void main() {
  group('ReedSolomonDecoder', () {
    // We use the same field as QR
    final field = GenericGF.qrCodeField256;
    late ReedSolomonDecoder decoder;

    setUp(() {
      decoder = ReedSolomonDecoder(field);
    });

    // Helper to build generator poly
    GenericGFPoly buildGenerator(GenericGF field, int ecBytes) {
      var g = GenericGFPoly(field, [1]);
      for (var i = 0; i < ecBytes; i++) {
        // (x + alpha^i) in GF2^n
        // coeffs: [1, alpha^i]
        final term = GenericGFPoly(field, [1, field.exp(i)]);
        g = g.multiply(term);
      }
      return g;
    }

    // Helper to generate a valid RS codeword
    List<int> encode(List<int> data, int ecBytes) {
      final generator = buildGenerator(field, ecBytes);
      final dataPoly = GenericGFPoly(field, data);

      // Multiply by x^ecBytes (shift)
      final shifted = dataPoly.multiplyByMonomial(ecBytes, 1);

      // Remainder = shifted % generator
      final result = shifted.divide(generator);
      final remainder = result[1];

      // Result = shifted + remainder (effectively [data] + [ec])
      final resultPoly = shifted.addOrSubtract(remainder);
      final coeffs = resultPoly.coefficients.toList();

      // Pad leading zeros if necessary to match expected length
      final expectedLength = data.length + ecBytes;
      if (coeffs.length < expectedLength) {
        final padded = List<int>.filled(expectedLength, 0);
        final offset = expectedLength - coeffs.length;
        for (var i = 0; i < coeffs.length; i++) {
          padded[offset + i] = coeffs[i];
        }
        return padded;
      }
      return coeffs;
    }

    test('decodes no errors', () {
      final received = Uint8List.fromList([0, 0, 0, 0]);
      decoder.decode(received: received, twoS: 2); // 2 EC bytes
      expect(received, equals([0, 0, 0, 0]));
    });

    test('decodes single error', () {
      // 5 * (x^2 + 3x + 2) = 5x^2 + 15x + 10
      final valid = [5, 15, 10]; // Data=5, EC=15, 10
      final corrupted = Int32List.fromList(valid);
      corrupted[1] = 0; // Error!

      decoder.decode(received: corrupted, twoS: 2);

      expect(corrupted, equals(valid));
    });

    test('decodes two errors if capacity allows (e.g. 4 EC bytes)', () {
      // 4 EC bytes can correct 2 errors.
      final data = [10, 20, 30];
      const ecBytes = 4;

      final valid = encode(data, ecBytes);
      // Verify length: 3 data + 4 EC = 7 bytes
      expect(valid.length, 7);

      final corrupted = Int32List.fromList(valid);

      // Corrupt 2 positions
      corrupted[1] ^= 0xFF; // Corrupt data
      corrupted[5] ^= 0xFF; // Corrupt EC

      decoder.decode(received: corrupted, twoS: ecBytes);

      // Should result in original valid sequence
      expect(corrupted, equals(valid));
    });

    test('throws ReedSolomonException when too many errors', () {
      // [5, 15, 10] with 2 EC bytes can correct 1 error.
      // Corrupt 2 bytes.
      final corrupted = Int32List.fromList([5, 15, 10]);
      corrupted[0] = 99;
      corrupted[1] = 99;

      expect(
        () => decoder.decode(received: corrupted, twoS: 2),
        throwsException,
      );
    });
  });
}
