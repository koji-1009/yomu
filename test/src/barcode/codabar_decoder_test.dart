import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/codabar_decoder.dart';

void main() {
  group('CodabarDecoder', () {
    const decoder = CodabarDecoder();

    test('format is CODABAR', () {
      expect(decoder.format, 'CODABAR');
    });

    test('returns null for invalid row data', () {
      final row = Uint8List(20);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );
      expect(result, isNull);
    });

    test('returns null for all-white row', () {
      final row = Uint8List(200);
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );
      expect(result, isNull);
    });

    test('returns null for all-black row', () {
      final row = Uint8List.fromList(List<int>.filled(200, 1));
      final result = decoder.decodeRow(
        row: row,
        rowNumber: 0,
        width: row.length,
      );
      expect(result, isNull);
    });

    group('Logic Validation (runs)', () {
      // Codabar patterns
      // Start A (0x1A = 0011010): N N W W N W N
      final startA = [1, 1, 2, 2, 1, 2, 1];
      final stopB = [1, 2, 1, 2, 1, 1, 2]; // B: 0x29 = 0101001 -> N W N W N N W
      final char0 = [1, 1, 1, 1, 1, 2, 2]; // 0: 0x03 = 0000011 -> N N N N N W W
      final gap = [1];

      test('should reject invalid Start Quiet Zone (too small)', () {
        final runs = Uint16List.fromList([
          5, // INVALID Start QZ
          ...startA, ...gap,
          ...char0, ...gap,
          ...stopB,
          10,
        ]);

        final result = decoder.decodeRow(
          row: Uint8List(0),
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNull, reason: 'Start Quiet Zone 5 should be rejected');
      });

      test('should reject invalid Stop Quiet Zone (too small)', () {
        final runs = Uint16List.fromList([
          10,
          ...startA, ...gap,
          ...char0, ...gap,
          ...stopB,
          5, // INVALID Stop QZ
        ]);

        final result = decoder.decodeRow(
          row: Uint8List(0),
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNull, reason: 'Stop Quiet Zone 5 should be rejected');
      });

      test('should reject too short codes (only Start/Stop)', () {
        final runs = Uint16List.fromList([
          10,
          ...startA, ...gap,
          ...stopB, // No data
          10,
        ]);

        final result = decoder.decodeRow(
          row: Uint8List(0),
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNull, reason: 'Start/Stop only should be rejected');
      });

      test('should accept valid Codabar', () {
        final runs = Uint16List.fromList([
          10,
          ...startA,
          ...gap,
          ...char0,
          ...gap,
          ...stopB,
          10,
        ]);

        final result = decoder.decodeRow(
          row: Uint8List(0),
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNotNull);
        expect(result!.text, '0');
      });
    });
  });
}
