import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/code39_decoder.dart';

void main() {
  group('Code39Decoder', () {
    const decoder = Code39Decoder();

    test('format is CODE_39', () {
      expect(decoder.format, 'CODE_39');
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

    group('Logic Validation (runs)', () {
      // Basic correct patterns
      final startPattern = [1, 2, 1, 1, 2, 1, 2, 1, 1];
      final stopPattern = [1, 2, 1, 1, 2, 1, 2, 1, 1];
      final gap = [1];
      final charA = [2, 1, 1, 1, 1, 2, 1, 1, 2];
      final charB = [1, 1, 2, 1, 1, 2, 1, 1, 2];

      test('should reject invalid Quiet Zone (too small)', () {
        final runs = Uint16List.fromList([
          5, // INVALID Quiet Zone
          ...startPattern, ...gap,
          ...charA, ...gap,
          ...charB, ...gap,
          ...stopPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNull, reason: 'Quiet Zone 5 should be rejected');
      });

      test('should reject invalid Gap (too wide)', () {
        final runs = Uint16List.fromList([
          10,
          ...startPattern,
          3, // INVALID GAP
          ...charA, ...gap,
          ...charB, ...gap,
          ...stopPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNull, reason: 'Gap 3 should be rejected');
      });

      test('should reject invalid Stop Quiet Zone (too small)', () {
        final runs = Uint16List.fromList([
          10,
          ...startPattern, ...gap,
          ...charA, ...gap,
          ...charB, ...gap,
          ...stopPattern,
          5, // INVALID Quiet Zone at end
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNull, reason: 'Stop Quiet Zone 5 should be rejected');
      });

      test('should accept valid Quiet Zone and Gap', () {
        final runs = Uint16List.fromList([
          10, // Valid Quiet Zone
          ...startPattern, ...gap,
          ...charA, ...gap,
          ...charB, ...gap,
          ...stopPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNotNull);
        expect(result!.text, 'AB');
      });

      test('should reject too short codes', () {
        final runs = Uint16List.fromList([
          10,
          ...startPattern,
          ...gap,
          ...charA,
          ...gap,
          ...stopPattern,
          10,
        ]);

        final result = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );

        expect(result, isNull, reason: '1 char should be rejected (min 2)');
      });
    });

    group('Utility Logic', () {
      test('validateMod43 should validate checksum', () {
        // 'CODE39' -> 75 % 43 = 32 ('W')
        expect(Code39Decoder.validateMod43('CODE39W'), isTrue);
        expect(Code39Decoder.validateMod43('CODE39A'), isFalse);
      });

      test('Decoder with checkDigit=true should validate and strip', () {
        const decoder = Code39Decoder(checkDigit: true);

        // Pattern for '*': N W N N W N W N N (10, 20...)
        final startStop = [10, 20, 10, 10, 20, 10, 20, 10, 10];
        // Pattern for '0': N n N w W n W n N
        final char0 = [10, 10, 10, 20, 20, 10, 20, 10, 10];
        final gap = [10];

        final runs = Uint16List.fromList([
          150, // Quiet
          ...startStop, ...gap,
          ...char0, ...gap, // Data 0
          ...char0, ...gap, // Check 0
          ...startStop,
          150, // Quiet
        ]);

        // 1. With Check Digit Validation Enabled
        final resultWithCheck = decoder.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(resultWithCheck, isNotNull);
        expect(
          resultWithCheck!.text,
          '0',
          reason: 'Should strip check digit 0',
        );

        // 2. With Check Digit Validation Disabled (Default)
        const decoderNoCheck = Code39Decoder(checkDigit: false);
        final resultNoCheck = decoderNoCheck.decodeRow(
          row: [],
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(resultNoCheck, isNotNull);
        expect(
          resultNoCheck!.text,
          '00',
          reason: 'Should keep check digit 0 as data',
        );
      });
    });
  });
}
