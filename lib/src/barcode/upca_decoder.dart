import 'dart:typed_data';

import 'barcode_result.dart';
import 'ean13_decoder.dart';

/// UPC-A barcode decoder.
///
/// UPC-A is a 12-digit barcode format used primarily in North America.
/// It is essentially EAN-13 with a leading 0, so we can delegate to EAN-13
/// and strip the leading zero from the result.
///
/// Structure: [Start 3] + [Left 42] + [Center 5] + [Right 42] + [End 3] = 95 modules
class UPCADecoder extends EAN13Decoder {
  const UPCADecoder();

  @override
  String get format => 'UPC_A';

  @override
  BarcodeResult? decodeRow({
    required Uint8List row,
    required int rowNumber,
    required int width,
    Uint16List? runs,
  }) {
    // UPC-A is EAN-13 with first digit = 0
    final ean13Result = super.decodeRow(
      row: row,
      rowNumber: rowNumber,
      width: width,
      runs: runs,
    );

    if (ean13Result == null) return null;

    // Check if it's a valid UPC-A (starts with 0)
    if (!ean13Result.text.startsWith('0')) {
      return null;
    }

    // Return with UPC-A format and stripped leading zero
    return BarcodeResult(
      text: ean13Result.text.substring(1), // Remove leading 0 -> 12 digits
      format: format,
      startX: ean13Result.startX,
      endX: ean13Result.endX,
      rowY: ean13Result.rowY,
    );
  }
}
