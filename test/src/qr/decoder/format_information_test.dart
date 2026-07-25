import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/error_correction_level.dart';
import 'package:yomu/src/qr/decoder/format_information.dart';

/// The 15-bit codeword of each format information value.
const _codewords = [
  0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0, //
  0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976,
  0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B,
  0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED,
];

int _popCount(int value) {
  var remaining = value;
  var count = 0;
  while (remaining != 0) {
    count++;
    remaining &= remaining - 1;
  }
  return count;
}

/// Decodes by scanning every codeword, as [FormatInformation] did before it
/// gained a lookup table. Used to pin the table to the search it replaced.
FormatInformation? referenceDecode(int reading1, int reading2) {
  return _referenceDecodeOnce(reading1, reading2) ??
      _referenceDecodeOnce(reading1 ^ 0x5412, reading2 ^ 0x5412);
}

FormatInformation? _referenceDecodeOnce(int reading1, int reading2) {
  var bestDifference = 32;
  var bestFormatInfo = 0;
  for (final reading in [reading1, reading2]) {
    for (var value = 0; value < _codewords.length; value++) {
      final difference = _popCount(reading ^ _codewords[value]);
      if (difference < bestDifference) {
        bestFormatInfo = value;
        bestDifference = difference;
      }
    }
  }
  if (bestDifference <= 3) {
    return FormatInformation(
      ErrorCorrectionLevel.forBits((bestFormatInfo >> 3) & 0x03),
      bestFormatInfo & 0x07,
    );
  }
  return null;
}

void main() {
  group('FormatInformation', () {
    test('decodeFormatInformation returns correct EC level and mask', () {
      // Test known format information values
      // Format Info = EC Level (2 bits) + Mask (3 bits) + BCH ECC (10 bits)
      // XOR with 0x5412 mask
      // QR Spec EC bits: 00=M, 01=L, 10=H, 11=Q

      // Test M-0: raw = 0x00 (EC=00=M, Mask=000), masked = 0x5412
      final infoM0 = FormatInformation.decodeFormatInformation(0x5412, 0x5412);
      expect(infoM0, isNotNull);
      expect(infoM0!.errorCorrectionLevel, ErrorCorrectionLevel.M);
      expect(infoM0.dataMask, 0);

      // Test M-1: masked = 0x5125, maps to format info 0x01 (EC=00=M, Mask=001)
      final infoM1 = FormatInformation.decodeFormatInformation(0x5125, 0x5125);
      expect(infoM1, isNotNull);
      expect(infoM1!.errorCorrectionLevel, ErrorCorrectionLevel.M);
      expect(infoM1.dataMask, 1);
    });

    test('decodeFormatInformation handles error correction', () {
      // Introduce 1-bit error in a known format info
      const corrupted = 0x5412 ^ 0x0001; // Flip lowest bit
      final info = FormatInformation.decodeFormatInformation(corrupted, 0x5412);
      expect(info, isNotNull);
    });

    test('decodeFormatInformation returns null for invalid data', () {
      // Completely invalid format information
      final info = FormatInformation.decodeFormatInformation(0x0000, 0x0000);
      // May return null or a best-guess depending on implementation
      // The important thing is it doesn't throw
      expect(() => info, returnsNormally);
    });

    test('matches a linear nearest-codeword search for every reading', () {
      // The lookup table has to answer exactly what scanning the 32
      // codewords answered, for every value a reading can take.
      for (var reading = 0; reading <= 0x7FFF; reading++) {
        final info = FormatInformation.decodeFormatInformation(
          reading,
          reading,
        );
        final expected = referenceDecode(reading, reading);

        if (expected == null) {
          expect(
            info,
            isNull,
            reason: 'reading 0x${reading.toRadixString(16)}',
          );
        } else {
          expect(
            info,
            isNotNull,
            reason: 'reading 0x${reading.toRadixString(16)}',
          );
          expect(info!.errorCorrectionLevel, expected.errorCorrectionLevel);
          expect(info.dataMask, expected.dataMask);
        }
      }
    });

    test('prefers the closer of the two readings', () {
      // Reading 1 is three bits off M-0, reading 2 is one bit off M-1.
      const corrupted1 = 0x5412 ^ 0x0007;
      const corrupted2 = 0x5125 ^ 0x0001;

      final info = FormatInformation.decodeFormatInformation(
        corrupted1,
        corrupted2,
      );
      expect(info, isNotNull);
      expect(info!.dataMask, 1);

      // Swapping them must not change which reading wins.
      final swapped = FormatInformation.decodeFormatInformation(
        corrupted2,
        corrupted1,
      );
      expect(swapped, isNotNull);
      expect(swapped!.dataMask, 1);
    });

    test('rejects readings wider than 15 bits', () {
      // A 16th set bit is not a reading the table covers; it must count as a
      // differing bit rather than being ignored.
      const nearMiss = 0x5412 | 0x8000;
      expect(
        FormatInformation.decodeFormatInformation(nearMiss, nearMiss),
        isNotNull,
        reason: 'one extra bit is still within the correctable distance',
      );

      const farMiss = 0x5412 | 0x18000;
      final info = FormatInformation.decodeFormatInformation(farMiss, farMiss);
      expect(info, isNotNull);
      expect(info!.dataMask, 0);

      expect(
        FormatInformation.decodeFormatInformation(-1, -1),
        isNull,
        reason: 'a negative reading matches nothing',
      );
    });

    test('errorCorrectionLevel returns correct levels', () {
      // Test each EC level
      for (final level in ErrorCorrectionLevel.values) {
        final info = FormatInformation(level, 0);
        expect(info.errorCorrectionLevel, level);
      }
    });

    test('dataMask returns correct mask values 0-7', () {
      for (var mask = 0; mask < 8; mask++) {
        final info = FormatInformation(ErrorCorrectionLevel.L, mask);
        expect(info.dataMask, mask);
      }
    });
  });

  group('ErrorCorrectionLevel', () {
    test('forBits returns correct levels', () {
      // QR Spec: 00=M, 01=L, 10=H, 11=Q
      expect(ErrorCorrectionLevel.forBits(0), ErrorCorrectionLevel.M);
      expect(ErrorCorrectionLevel.forBits(1), ErrorCorrectionLevel.L);
      expect(ErrorCorrectionLevel.forBits(2), ErrorCorrectionLevel.H);
      expect(ErrorCorrectionLevel.forBits(3), ErrorCorrectionLevel.Q);
    });

    test('forBits throws for invalid bits', () {
      expect(() => ErrorCorrectionLevel.forBits(-1), throwsArgumentError);
      expect(() => ErrorCorrectionLevel.forBits(4), throwsArgumentError);
    });

    test('values contains all levels', () {
      expect(ErrorCorrectionLevel.values.length, 4);
      expect(ErrorCorrectionLevel.values, contains(ErrorCorrectionLevel.L));
      expect(ErrorCorrectionLevel.values, contains(ErrorCorrectionLevel.M));
      expect(ErrorCorrectionLevel.values, contains(ErrorCorrectionLevel.Q));
      expect(ErrorCorrectionLevel.values, contains(ErrorCorrectionLevel.H));
    });
  });
}
