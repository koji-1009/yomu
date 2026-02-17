import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/code128_decoder.dart';

void main() {
  group('Code128Decoder', () {
    late Code128Decoder decoder;

    setUp(() {
      decoder = const Code128Decoder();
    });

    test('format is CODE_128', () {
      expect(decoder.format, 'CODE_128');
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

    // Helper to generate a Uint8List row from bar/space widths
    Uint8List generateRow(List<int> widths) {
      final row = <int>[];
      // Let's assume start with sufficient White quiet zone.
      row.addAll(List.filled(20, 0));

      // Then patterns
      // Pattern widths: [bar, space, bar, space, bar, space]
      var isBar = true;
      for (final w in widths) {
        row.addAll(List.filled(w, isBar ? 1 : 0));
        isBar = !isBar;
      }

      // Trailing quiet zone
      row.addAll(List.filled(20, 0));
      return Uint8List.fromList(row);
    }

    // Patterns (Module widths)
    // Start B (104): [2, 1, 1, 2, 1, 4] -> Code Set B
    const startB = [2, 1, 1, 2, 1, 4];

    // 'A' (33) in Set B: [1, 1, 1, 3, 2, 3] -> Value 33 ('A')
    const charaSetb = [1, 1, 1, 3, 2, 3];

    // Stop: [2, 3, 3, 1, 1, 1, 2]
    const stop = [2, 3, 3, 1, 1, 1, 2];

    test('decodes simple Code Set B string "A"', () {
      // Start B (104) -> 'A' (33) -> Checksum (?) -> Stop
      // Checksum = Start + data*1
      // = 104 + 33*1 = 137.
      // 137 % 103 = 34.
      // Code 34 patterns: [1, 3, 1, 1, 2, 3]
      const check34 = [1, 3, 1, 1, 2, 3];

      final rowData = [...startB, ...charaSetb, ...check34, ...stop];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNotNull);
      expect(result!.text, 'A');
    });

    test('fails on invalid checksum', () {
      // Same as above 'A' but wrong checksum (e.g. 35 instead of 34)
      // Code 35: [1, 3, 1, 3, 2, 1]
      const check35 = [1, 3, 1, 3, 2, 1];

      final rowData = [
        ...startB,
        ...charaSetb,
        ...check35, // wrong
        ...stop,
      ];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNull);
    });

    test('fails when missing stop pattern', () {
      // Start B + 'A' + Check34 ... but no Stop
      const check34 = [1, 3, 1, 1, 2, 3];
      final rowData = [...startB, ...charaSetb, ...check34];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );
      expect(result, isNull);
    });

    test('handles Code Set switching (B -> C)', () {
      // Start B (104)
      // 'B' (34) -> [1, 3, 1, 1, 2, 3]
      // Switch to C (99) -> [1, 1, 3, 1, 4, 1]
      // Set C '12' -> Value 12: [1, 1, 2, 2, 3, 2]
      // Stop

      // Checksum:
      // StartB(104) + 'B'(34)*1 + SwitchC(99)*2 + '12'(12)*3
      // = 104 + 34 + 198 + 36 = 372
      // 372 % 103 = 63
      // Code 63: [1, 1, 1, 2, 2, 4]

      const charbSetb = [1, 3, 1, 1, 2, 3]; // 34
      const switchC = [1, 1, 3, 1, 4, 1]; // 99
      const char12 = [1, 1, 2, 2, 3, 2]; // 12
      const check63 = [1, 1, 1, 2, 2, 4]; // 63

      final rowData = [
        ...startB,
        ...charbSetb,
        ...switchC,
        ...char12,
        ...check63,
        ...stop,
      ];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNotNull);
      // 'B' from Set B, then '12' from Set C
      expect(result!.text, 'B12');
    });

    test('handles FNC1 in Code Set C (GS1-128)', () {
      // Start C (105): [2, 1, 1, 2, 3, 2]
      // FNC1 (102): [4, 1, 1, 1, 3, 1]
      // '12' (12): [1, 1, 2, 2, 3, 2]
      // Checksum: 105 + 102*1 + 12*2 = 105 + 102 + 24 = 231
      // 231 % 103 = 25
      // Code 25: [3, 2, 1, 1, 2, 2]

      const startC = [2, 1, 1, 2, 3, 2];
      const fnc1 = [4, 1, 1, 1, 3, 1];
      const char12 = [1, 1, 2, 2, 3, 2];
      const check25 = [3, 2, 1, 1, 2, 2];

      final rowData = [...startC, ...fnc1, ...char12, ...check25, ...stop];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNotNull);
      expect(result!.text, '\x1D12'); // FNC1 skipped/converted to GS
    });

    test('decodes Code Set A (Control characters logic)', () {
      // Start A (103): [2, 1, 1, 4, 1, 2]
      // Code 65: [1, 2, 1, 1, 2, 4] -> ASCII 1 (SOH)
      // Checksum: 103 + 65*1 = 168. 168 % 103 = 65.

      const startA = [2, 1, 1, 4, 1, 2];
      const char65 = [1, 2, 1, 1, 2, 4]; // Test code > 64 branch
      const check65 = char65;

      final rowData = [...startA, ...char65, ...check65, ...stop];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNotNull);
      // 65 - 64 = 1 (SOH). String.fromCharCode(1).
      expect(result!.text.codeUnitAt(0), 1);
    });

    test('handles Code Set switching (A -> B)', () {
      // Start A (103)
      // Switch to B (100): [1, 1, 4, 1, 3, 1]
      // 'a' (65 in Set B): [1, 2, 1, 1, 2, 4]
      // Checksum: 103 + 100*1 + 65*2 = 103 + 100 + 130 = 333
      // 333 % 103 = 24
      // Code 24: [3, 1, 1, 2, 2, 2]

      const startA = [2, 1, 1, 4, 1, 2];
      const switchB = [1, 1, 4, 1, 3, 1];
      const char65 = [1, 2, 1, 1, 2, 4];
      const check24 = [3, 1, 1, 2, 2, 2];

      final rowData = [...startA, ...switchB, ...char65, ...check24, ...stop];
      final row = generateRow(rowData);

      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );

      expect(result, isNotNull);
      expect(result!.text, 'a');
    });

    test('handles Code Set switching (B -> A)', () {
      // Start B (104)
      // Switch to A (101): [3, 1, 1, 1, 4, 1]
      // NUL (64 in Set A): [1, 1, 1, 4, 2, 2]
      // Checksum: 104 + 101*1 + 64*2 = 104 + 101 + 128 = 333
      // 333 % 103 = 24
      const startB = [2, 1, 1, 2, 1, 4];
      const switchA = [3, 1, 1, 1, 4, 1];
      const char64 = [1, 1, 1, 4, 2, 2];
      const check24 = [3, 1, 1, 2, 2, 2];

      final rowData = [...startB, ...switchA, ...char64, ...check24, ...stop];
      final row = generateRow(rowData);
      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );
      expect(result, isNotNull);
      expect(result!.text.codeUnitAt(0), 0); // NUL
    });

    test('returns null for too short row (header missing)', () {
      // Just Start pattern
      const startB = [2, 1, 1, 2, 1, 4];
      final row = generateRow(startB);
      // generateRow adds 20px padding * 2 = 40. + 6 = 46.
      final result = decoder.decodeRow(
        rowNumber: 0,
        width: row.length,
        runs: BarcodeScanner.getRunLengths(row),
      );
      expect(result, isNull);
    });
  });
}
