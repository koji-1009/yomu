import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_result.dart';

void main() {
  group('BarcodeResult Coverage', () {
    test('toString returns formatted string', () {
      const result = BarcodeResult(
        text: '123456789012',
        format: 'EAN_13',
        startX: 10,
        endX: 200,
        rowY: 50,
      );

      expect(result.toString(), contains('BarcodeResult'));
      expect(result.toString(), contains('EAN_13'));
      expect(result.toString(), contains('123456789012'));
    });

    test('fields are accessible', () {
      const result = BarcodeResult(
        text: 'TEST',
        format: 'CODE_128',
        startX: 5,
        endX: 100,
        rowY: 25,
      );

      expect(result.text, 'TEST');
      expect(result.format, 'CODE_128');
      expect(result.startX, 5);
      expect(result.endX, 100);
      expect(result.rowY, 25);
    });
  });

  group('BarcodeException Coverage', () {
    test('toString returns formatted message', () {
      const exception = BarcodeException('Barcode not found');

      expect(exception.toString(), contains('BarcodeException'));
      expect(exception.toString(), contains('Barcode not found'));
      expect(exception.message, 'Barcode not found');
    });
  });
}
