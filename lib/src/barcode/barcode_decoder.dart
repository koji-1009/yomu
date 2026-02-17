import 'dart:typed_data';

import '../common/bit_matrix.dart';
import 'barcode_result.dart';

/// Abstract base class for 1D barcode decoders.
///
/// Implement this class to add support for new barcode formats.
abstract class BarcodeDecoder {
  const BarcodeDecoder();

  /// The format name of this decoder (e.g., 'EAN_13', 'CODE_128').
  String get format;

  /// Attempts to decode a barcode from a single row of the bit matrix.
  ///
  /// Returns [BarcodeResult] if successful, null if not found.
  ///
  /// Parameters:
  /// - [row]: The row data as a Uint8List (1 = black, 0 = white)
  /// - [rowNumber]: The Y coordinate of this row in the image
  /// - [width]: The width of the row
  /// - [runs]: Optional pre-calculated run-length encoded data for this row.
  BarcodeResult? decodeRow({
    required Uint8List row,
    required int rowNumber,
    required int width,
    Uint16List? runs,
  });

  /// Scans the bit matrix to find and decode a barcode.
  ///
  /// Tries multiple rows at different positions to find barcodes.
  BarcodeResult? decode(BitMatrix matrix) {
    final height = matrix.height;
    final width = matrix.width;

    // Try rows at 10%, 30%, 50%, 70%, 90% of height
    final rowPositions = [
      height ~/ 10,
      height * 3 ~/ 10,
      height ~/ 2,
      height * 7 ~/ 10,
      height * 9 ~/ 10,
    ];

    final row = Uint8List(width);

    for (final y in rowPositions) {
      // Extract row data
      for (var x = 0; x < width; x++) {
        row[x] = matrix.get(x, y) ? 1 : 0;
      }

      final result = decodeRow(row: row, rowNumber: y, width: width);
      if (result != null) {
        return result;
      }
    }

    return null;
  }
}
