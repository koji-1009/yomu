import 'dart:typed_data';

import '../common/binarizer/luminance_source.dart';
import 'barcode_decoder.dart';
import 'barcode_result.dart';
import 'codabar_decoder.dart';
import 'code128_decoder.dart';
import 'code39_decoder.dart';
import 'ean13_decoder.dart';
import 'ean8_decoder.dart';
import 'itf_decoder.dart';
import 'upca_decoder.dart';

/// 1D barcode scanner with configurable decoders.
///
/// Use [BarcodeScanner.all] for all supported formats, or create a custom
/// configuration by specifying which [decoders] to use.
///
/// ## Example
///
/// ```dart
/// // Scan for all barcode formats
/// final scanner = BarcodeScanner.all;
///
/// // Scan for retail formats only (EAN/UPC)
/// final scanner = BarcodeScanner.retail;
///
/// // Custom configuration
/// const scanner = BarcodeScanner(decoders: [EAN13Decoder(), Code128Decoder()]);
/// ```
class BarcodeScanner {
  /// Creates a barcode scanner with the specified decoders.
  const BarcodeScanner({required this.decoders});

  /// The list of decoders to use for scanning.
  final List<BarcodeDecoder> decoders;

  /// Scanner with all supported barcode formats enabled.
  static const all = BarcodeScanner(
    decoders: [
      EAN13Decoder(),
      EAN8Decoder(),
      UPCADecoder(),
      Code128Decoder(),
      Code39Decoder(),
      ITFDecoder(),
      CodabarDecoder(),
    ],
  );

  /// Scanner for retail barcode formats (EAN-13, EAN-8, UPC-A).
  static const retail = BarcodeScanner(
    decoders: [EAN13Decoder(), EAN8Decoder(), UPCADecoder()],
  );

  /// Scanner for industrial barcode formats (Code 128, Code 39, ITF, Codabar).
  static const industrial = BarcodeScanner(
    decoders: [
      Code128Decoder(),
      Code39Decoder(),
      ITFDecoder(),
      CodabarDecoder(),
    ],
  );

  /// Empty scanner that disables barcode scanning.
  ///
  /// Use this instead of null when you want to disable barcode scanning.
  static const none = BarcodeScanner(decoders: []);

  /// Returns true if this scanner has no decoders (disabled).
  bool get isEmpty => decoders.isEmpty;

  /// Scans for a 1D barcode in the image.
  ///
  /// Returns the first barcode found, or null if none found.
  BarcodeResult? scan(LuminanceSource source) {
    if (decoders.isEmpty) return null;

    final height = source.height;
    final width = source.width;

    // Try rows at 10%, 30%, 50%, 70%, 90% of height
    final rowPositions = [
      height ~/ 10,
      height * 3 ~/ 10,
      height ~/ 2,
      height * 7 ~/ 10,
      height * 9 ~/ 10,
    ];

    // Reusable buffer for luminance data
    final lumBuffer = Uint8List(width);
    final rowBuffer = Uint8List(width);
    final integralBuffer = Int32List(width + 1);

    for (final y in rowPositions) {
      // Extract row luminance data
      final lumRow = source.getRow(y, lumBuffer);

      // Binarize row directly (1D)
      _binarizeRow(lumRow, rowBuffer, integralBuffer);
      final runs = getRunLengths(rowBuffer);

      for (final decoder in decoders) {
        final result = decoder.decodeRow(
          rowNumber: y,
          width: width,
          runs: runs,
          row: rowBuffer,
        );
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  /// Scans for all 1D barcodes in the image.
  ///
  /// Returns a list of all barcodes found.
  List<BarcodeResult> scanAll(LuminanceSource source) {
    if (decoders.isEmpty) return [];

    final height = source.height;
    final width = source.width;
    final results = <BarcodeResult>[];

    // Try rows at 10%, 30%, 50%, 70%, 90% of height
    final rowPositions = [
      height ~/ 10,
      height * 3 ~/ 10,
      height ~/ 2,
      height * 7 ~/ 10,
      height * 9 ~/ 10,
    ];

    // Reusable buffer for luminance data
    final lumBuffer = Uint8List(width);
    final rowBuffer = Uint8List(width);
    final integralBuffer = Int32List(width + 1);

    for (final y in rowPositions) {
      // Extract row luminance data
      final lumRow = source.getRow(y, lumBuffer);

      // Binarize row directly (1D)
      _binarizeRow(lumRow, rowBuffer, integralBuffer);
      final runs = getRunLengths(rowBuffer);

      for (final decoder in decoders) {
        final result = decoder.decodeRow(
          rowNumber: y,
          width: width,
          runs: runs,
          row: rowBuffer,
        );
        if (result != null) {
          results.add(result);
        }
      }
    }

    return results;
  }

  /// Converts a row of booleans to run-length encoded data.
  static Uint16List getRunLengths(Uint8List row) {
    if (row.isEmpty) return Uint16List(0);

    // First pass: count runs to allocate exact size
    var runCount = 0;
    var currentPos = 0;
    var currentColor = row[0];

    while (currentPos < row.length) {
      while (currentPos < row.length && row[currentPos] == currentColor) {
        currentPos++;
      }
      runCount++;
      if (currentPos < row.length) {
        currentColor = row[currentPos];
      }
    }

    // Second pass: populate Uint16List
    final runs = Uint16List(runCount);
    currentPos = 0;
    currentColor = row[0];
    var index = 0;

    while (currentPos < row.length) {
      var runLength = 0;
      while (currentPos < row.length && row[currentPos] == currentColor) {
        runLength++;
        currentPos++;
      }
      runs[index++] = runLength;
      if (currentPos < row.length) {
        currentColor = row[currentPos];
      }
    }

    return runs;
  }

  /// Locally adaptive binarization for a single row.
  /// Uses a moving average window to determine the threshold.
  static void _binarizeRow(
    Uint8List luminance,
    Uint8List result,
    Int32List integral,
  ) {
    final width = luminance.length;

    // Adaptive window size: ~1/32 of width, clamped to sane bounds.
    // Minimum 16px to avoid noise, maximum 64px to capture local gradients.
    var windowSize = width ~/ 32;
    if (windowSize < 16) windowSize = 16;
    if (windowSize > 64) windowSize = 64;

    // Ensure windowSize doesn't exceed width (though width < 16 is unlikely)
    if (windowSize > width) windowSize = width;

    final halfWindow = windowSize >> 1;

    // Build integral array (prefix sums) for O(1) window sum calculation
    // Size is width + 1. integral[i] = sum(0..i-1)
    var runningSum = 0;
    integral[0] = 0;
    for (var i = 0; i < width; i++) {
      runningSum += luminance[i];
      integral[i + 1] = runningSum;
    }

    for (var x = 0; x < width; x++) {
      // Define window bounds [x - halfWindow, x + halfWindow]
      final left = (x - halfWindow < 0) ? 0 : x - halfWindow;
      final right = (x + halfWindow >= width) ? width - 1 : x + halfWindow;

      final count = right - left + 1;
      final sum = integral[right + 1] - integral[left];
      // Average = sum / count

      // Threshold: 7/8 of average (= 0.875 * average)
      // Pixel is black if pixel * count * 8 <= sum * 7
      // Using shifts for *8.
      if ((luminance[x] * count) << 3 <= sum * 7) {
        result[x] = 1; // Black
      } else {
        result[x] = 0; // White
      }
    }
  }
}
