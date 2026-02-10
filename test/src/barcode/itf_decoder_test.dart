import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/itf_decoder.dart';

void main() {
  group('ITFDecoder', () {
    const decoder = ITFDecoder();

    test('format is ITF', () {
      expect(decoder.format, 'ITF');
    });

    test('returns null for invalid row data', () {
      final row = List<bool>.filled(20, false);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );
      expect(result, isNull);
    });

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

    group('Logic Validation (runs)', () {
      final startPattern = [1, 1, 1, 1];
      final endPattern = [3, 1, 1];
      final pair00 = [1, 1, 1, 1, 3, 3, 3, 3, 1, 1]; // '00'

      test('should reject invalid Quiet Zone (too small)', () {
        // Narrow width = 1. Quiet Zone requires >= 10.
        final runs = Uint16List.fromList([
          5, // INVALID Start Quiet Zone
          ...startPattern,
          ...pair00, ...pair00, ...pair00,
          ...endPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(
          result,
          isNull,
          reason: 'Quiet Zone 5 (Start) should be rejected',
        );
      });

      test('should reject invalid End Quiet Zone (too small)', () {
        final runs = Uint16List.fromList([
          10,
          ...startPattern,
          ...pair00, ...pair00, ...pair00,
          ...endPattern,
          5, // INVALID End Quiet Zone
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNull, reason: 'Quiet Zone 5 (End) should be rejected');
      });

      test('should accept valid Quiet Zone', () {
        final runs = Uint16List.fromList([
          10, // Valid
          ...startPattern,
          ...pair00, ...pair00, ...pair00,
          ...endPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNotNull);
        expect(result!.text, '000000');
      });

      test('should reject too short codes', () {
        final runs = Uint16List.fromList([
          10,
          ...startPattern,
          ...pair00,
          ...endPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNull, reason: '2 digits should be rejected (min 6)');
      });
    });
  });
}
