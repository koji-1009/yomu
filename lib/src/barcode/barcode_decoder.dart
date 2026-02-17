import 'dart:typed_data';

import '../common/bit_matrix.dart';
import 'barcode_result.dart';
import 'barcode_scanner.dart';

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
  /// - [rowNumber]: The Y coordinate of this row in the image
  /// - [width]: The width of the row
  /// - [runs]: Pre-calculated run-length encoded data for this row.
  /// - [row]: Optional raw row data as a Uint8List (1 = black, 0 = white)
  BarcodeResult? decodeRow({
    required int rowNumber,
    required int width,
    required Uint16List runs,
    Uint8List? row,
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

      final runs = BarcodeScanner.getRunLengths(row);
      final result = decodeRow(
        rowNumber: y,
        width: width,
        runs: runs,
        row: row,
      );
      if (result != null) {
        return result;
      }
    }

    return null;
  }
}
