import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/code39_decoder.dart';

void main() {
  group('Code39Decoder', () {
    const decoder = Code39Decoder();

    test('format is CODE_39', () {
      expect(decoder.format, 'CODE_39');
    });

    test('returns null for invalid row data', () {
      final row = Uint8List(20);
      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );
      expect(result, isNull);
    });

    group('Logic Validation (runs)', () {
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

        final result = decoder.decodeRow(rowNumber: 0, width: 1000, runs: runs);

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

        final result = decoder.decodeRow(rowNumber: 0, width: 1000, runs: runs);

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

        final result = decoder.decodeRow(rowNumber: 0, width: 1000, runs: runs);

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

        final result = decoder.decodeRow(rowNumber: 0, width: 1000, runs: runs);

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

        final result = decoder.decodeRow(rowNumber: 0, width: 1000, runs: runs);

        expect(result, isNull, reason: '1 char should be rejected (min 2)');
      });
    });

    group('Utility Logic', () {
      test('validateMod43 should validate checksum', () {
        expect(Code39Decoder.validateMod43('CODE39W'), isTrue);
        expect(Code39Decoder.validateMod43('CODE39A'), isFalse);
      });

      test('Decoder with checkDigit=true should validate and strip', () {
        const decoder = Code39Decoder(checkDigit: true);
        final startStop = [10, 20, 10, 10, 20, 10, 20, 10, 10];
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

        final resultWithCheck = decoder.decodeRow(
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(resultWithCheck, isNotNull);
        expect(resultWithCheck!.text, '0');

        const decoderNoCheck = Code39Decoder(checkDigit: false);
        final resultNoCheck = decoderNoCheck.decodeRow(
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(resultNoCheck, isNotNull);
        expect(resultNoCheck!.text, '00');
      });
    });
  });
}
