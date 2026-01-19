import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_decoder.dart';
import 'package:yomu/src/barcode/barcode_result.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_conversion.dart';

void main() {
  group('BarcodeScanner Coverage with Mocks', () {
    test('scan iterates through rows and decoders', () {
      final mockDecoder = MockBarcodeDecoder(
        shouldReturn: true,
        atRowIndex: 2, // 3rd row position (middle)
        returnValue: const BarcodeResult(
          text: 'MOCK',
          format: 'MOCK',
          startX: 0,
          endX: 10,
          rowY: 50,
        ),
      );

      final scanner = BarcodeScanner(decoders: [mockDecoder]);

      // Create a 100x100 white image
      final pixels = Int32List(100 * 100);
      final luminances = int32ToGrayscale(pixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
      );

      final result = scanner.scan(source);

      expect(result, isNotNull);
      expect(result!.text, 'MOCK');
      expect(mockDecoder.decodeRowCount, greaterThan(0));
    });

    test('scanAll collects all results', () {
      final mockDecoder = MockBarcodeDecoder(
        shouldReturn: true,
        returnAlways: true, // Return result for every row
        returnValue: const BarcodeResult(
          text: 'MOCK',
          format: 'MOCK',
          startX: 0,
          endX: 10,
          rowY: 0, // Mock ignores this
        ),
      );

      final scanner = BarcodeScanner(decoders: [mockDecoder]);
      final pixels = Int32List(100 * 100);
      final luminances = int32ToGrayscale(pixels, 100, 100);
      final source = LuminanceSource(
        width: 100,
        height: 100,
        luminances: luminances,
      );

      final results = scanner.scanAll(source);

      // 5 row positions checked -> 5 results
      expect(results, hasLength(5));
    });

    test('isEmpty returns correct state', () {
      expect(BarcodeScanner.none.isEmpty, isTrue);
      expect(BarcodeScanner.retail.isEmpty, isFalse);
    });
  });
}

class MockBarcodeDecoder extends BarcodeDecoder {
  MockBarcodeDecoder({
    this.shouldReturn = false,
    this.atRowIndex = -1,
    this.returnAlways = false,
    this.returnValue,
  });

  final bool shouldReturn;
  final int atRowIndex;
  final bool returnAlways;
  final BarcodeResult? returnValue;

  int decodeRowCount = 0;

  @override
  String get format => 'MOCK';

  @override
  BarcodeResult? decodeRow({
    required List<bool> row,
    required int rowNumber,
    required int width,
    List<int>? runs,
  }) {
    final currentIndex = decodeRowCount++;

    if (returnAlways) {
      return returnValue;
    }

    if (shouldReturn && currentIndex == atRowIndex) {
      return returnValue;
    }
    return null;
  }
}
