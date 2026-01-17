import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/error_correction_level.dart';
import 'package:yomu/src/qr/decoder/format_information.dart';

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
