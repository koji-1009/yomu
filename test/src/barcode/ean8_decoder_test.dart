import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/ean8_decoder.dart';

void main() {
  group('EAN8Decoder', () {
    const decoder = EAN8Decoder();

    test('format is EAN_8', () {
      expect(decoder.format, 'EAN_8');
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

    group('Logic Validation (runs)', () {
      // Start Pattern runs: 1, 1, 1 (Module width 1.0)
      final startRuns = [1, 1, 1];

      test('should reject invalid Start Quiet Zone (too small)', () {
        // Quiet Zone: Should be >= 10. Test with 9.
        final runs = Uint16List.fromList([
          9, // Invalid Quiet Zone
          ...startRuns,
          ...List.filled(40, 1), // Dummy data
          10,
        ]);

        final result = decoder.decodeRow(
          row: Uint8List(0),
          rowNumber: 0,
          width: 1000,
          runs: runs,
        );
        expect(result, isNull);
      });
    });
  });
}
