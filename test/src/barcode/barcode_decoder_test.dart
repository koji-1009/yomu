import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_decoder.dart';
import 'package:yomu/src/barcode/barcode_result.dart';
import 'package:yomu/src/common/bit_matrix.dart';

class MockBarcodeDecoder extends BarcodeDecoder {
  const MockBarcodeDecoder() : super();

  @override
  String get format => 'MOCK';

  @override
  BarcodeResult? decodeRow({
    required int rowNumber,
    required int width,
    required Uint16List runs,
    Uint8List? row,
  }) {
    // Return result if middle pixel is black (1)
    if (width > 0 && row != null && row[width ~/ 2] == 1) {
      return BarcodeResult(
        text: 'FOUND at $rowNumber',
        format: format,
        startX: 0,
        endX: width,
        rowY: rowNumber,
      );
    }
    return null;
  }
}

void main() {
  group('BarcodeDecoder', () {
    test('decode scans multiple rows', () {
      const decoder = MockBarcodeDecoder();
      final matrix = BitMatrix(width: 100, height: 100);

      // decode checks rows at 10, 30, 50, 70, 90.
      // Let's set a bit at row 50 (middle).
      matrix.set(50, 50);

      final result = decoder.decode(matrix);
      expect(result, isNotNull);
      expect(result!.text, contains('50'));
    });

    test('decode returns null if not found', () {
      const decoder = MockBarcodeDecoder();
      final matrix = BitMatrix(width: 100, height: 100);

      final result = decoder.decode(matrix);
      expect(result, isNull);
    });
  });
}
