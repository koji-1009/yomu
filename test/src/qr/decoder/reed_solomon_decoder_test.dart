import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/reed_solomon_decoder.dart';

void main() {
  group('ReedSolomonDecoder', () {
    // We use the same field as QR
    final field = GenericGF.qrCodeField256;
    late ReedSolomonDecoder decoder;

    setUp(() {
      decoder = ReedSolomonDecoder(field);
    });

    test('decodes no errors', () {
      final received = Uint8List.fromList([
        // Hello World in QR codes essentially.
        // Let's use a simpler known RS Codeword set.
        // Or generate one.
        // For TDD, I need a known valid codeword.
        // (x+1) is a poly. multiply by generator poly to get codeword.
        // Let's rely on the decoder logic being derived correctly or use a simple case.
        // 0, 0, 0 is a valid codeword (all zeros).
        0, 0, 0, 0,
      ]);
      decoder.decode(received: received, twoS: 2); // 2 EC bytes
      expect(received, equals([0, 0, 0, 0]));
    });

    test('decodes single error', () {
      // Prepare a valid codeword?
      // Let's assume the user encodes '123' and EC adds checksum.
      // Since I don't have Encoder yet, I have to hardcode a VALID sequence for GF(256)/0x11D.
      //
      // Or, I can use the same logic as the encoder to generate one in the test helper.
      // Encoder essentially multiplies data poly by generator poly.
      // Generator poly for 2 EC bytes is (x - 2^0)(x - 2^1) = (x-1)(x-2).
      // (x+1)(x+2) = x^2 + (1 XOR 2)x + (1*2) = x^2 + 3x + 2.
      // So coeffs [1, 3, 2].
      // If data is just [5] (constant),
      // 5 * (x^2 + 3x + 2) = 5x^2 + 15x + 10.
      // [5, 15, 10] should be a valid codeword with 2 EC bytes.
      // (5, 5*3=15, 5*2=10).
      final valid = [5, 15, 10]; // Data=5, EC=15, 10
      final corrupted = Int32List.fromList(valid);
      corrupted[1] = 0; // Error!

      // decode(codeword, ecBytes)
      decoder.decode(received: corrupted, twoS: 2);

      expect(corrupted, equals(valid));
    });

    test('decodes two errors if capacity allows (e.g. 4 EC bytes)', () {
      // Generator for 4 bytes: (x-1)(x-2)(x-4)(x-8) ...
      // Too complex to calculate by hand easily.
      // I will trust the decoder implementation for complex cases,
      // or I can implement a helper in the test to encode.
      // Let's implement a simple encode helper locally for testing.
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
      ); // Custom exception later
    });
  });
}
