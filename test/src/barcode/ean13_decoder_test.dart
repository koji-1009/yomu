import 'package:test/test.dart';
import 'package:yomu/src/barcode/ean13_decoder.dart';

void main() {
  group('EAN13Decoder', () {
    const decoder = EAN13Decoder();

    test('format is EAN_13', () {
      expect(decoder.format, 'EAN_13');
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
  });
}
