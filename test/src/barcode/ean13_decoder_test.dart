import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/barcode/ean13_decoder.dart';

void main() {
  group('EAN13Decoder', () {
    const decoder = EAN13Decoder();

    test('format is EAN_13', () {
      expect(decoder.format, 'EAN_13');
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
  });
}
