import 'package:test/test.dart';
import 'package:yomu/src/barcode/itf_decoder.dart';

void main() {
  group('ITFDecoder', () {
    test('validateITF14Checksum returns true for valid checksum', () {
      // 14 digits
      // Example: 00012345678905
      // 0*3 + 0*1 + 0*3 + 1*1 + 2*3 + 3*1 + 4*3 + 5*1 + 6*3 + 7*1 + 8*3 + 9*1 + 0*3
      // = 0 + 0 + 0 + 1 + 6 + 3 + 12 + 5 + 18 + 7 + 24 + 9 + 0 = 85
      // Check digit = (10 - (85 % 10)) % 10 = (10 - 5) % 10 = 5
      // Last digit is 5. Match.
      expect(ITFDecoder.validateITF14Checksum('00012345678905'), isTrue);
    });

    test('validateITF14Checksum returns false for invalid checksum', () {
      expect(ITFDecoder.validateITF14Checksum('00012345678900'), isFalse);
    });

    test('validateITF14Checksum returns false for invalid length', () {
      expect(ITFDecoder.validateITF14Checksum('123'), isFalse);
    });
  });
}
