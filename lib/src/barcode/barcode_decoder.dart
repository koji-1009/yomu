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
  /// - [row]: The row data as a list of booleans (true = black, false = white)
  /// - [rowNumber]: The Y coordinate of this row in the image
  /// - [width]: The width of the row
  BarcodeResult? decodeRow({
    required List<bool> row,
    required int rowNumber,
    required int width,
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

    final row = List<bool>.filled(width, false);

    for (final y in rowPositions) {
      // Extract row data
      for (var x = 0; x < width; x++) {
        row[x] = matrix.get(x: x, y: y);
      }

      final result = decodeRow(row: row, rowNumber: y, width: width);
      if (result != null) {
        return result;
      }
    }

    return null;
  }
}
