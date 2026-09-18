import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
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

  group('getRunLengths', () {
    test('starts with the white run of a row that starts white', () {
      final row = Uint8List.fromList([0, 0, 1, 1, 1, 0]);
      expect(BarcodeScanner.getRunLengths(row), [2, 3, 1]);
    });

    test('starts with an empty white run when the row starts black', () {
      // Decoders read even indices as white. A row whose first pixel is
      // black - a dark border, or a dark object at the left edge - would
      // otherwise shift every run to the other colour.
      final row = Uint8List.fromList([1, 1, 0, 0, 0, 1]);
      expect(BarcodeScanner.getRunLengths(row), [0, 2, 3, 1]);
    });
  });

  group('rows that start black', () {
    // A Code 128 barcode from the fixture corpus with a 10px dark band added
    // to the left of the image. Its quiet zone is left intact.
    test('still decode', () {
      const band = 10;
      final file = File('fixtures/barcode_images/code128_hello.png');
      final decoded = img.decodePng(file.readAsBytesSync())!;
      final gray = decoded.convert(format: img.Format.uint8, numChannels: 1);
      final source = gray.buffer.asUint8List();
      final width = gray.width + band;
      final pixels = Uint8List(width * gray.height);
      for (var y = 0; y < gray.height; y++) {
        pixels.setRange(
          y * width + band,
          y * width + width,
          source,
          y * gray.width,
        );
      }

      final result = BarcodeScanner.all.scan(
        LuminanceSource(width: width, height: gray.height, luminances: pixels),
      );

      expect(result?.text, 'Hello World');
      // Positions still count from the image's left edge.
      expect(result?.startX, greaterThanOrEqualTo(band));
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
    required int rowNumber,
    required int width,
    required Uint16List runs,
    Uint8List? row,
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
