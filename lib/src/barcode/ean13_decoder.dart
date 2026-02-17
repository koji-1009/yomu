import 'dart:typed_data';

import 'barcode_decoder.dart';
import 'barcode_result.dart';
import 'barcode_scanner.dart';

/// EAN-13 barcode decoder.
///
/// EAN-13 is a 13-digit barcode format used internationally for retail.
/// Total: 95 modules = [Start 3] + [Left 42] + [Center 5] + [Right 42] + [End 3]
class EAN13Decoder extends BarcodeDecoder {
  const EAN13Decoder();

  @override
  String get format => 'EAN_13';

  // L-patterns: 0 = white, 1 = black (module pattern)
  // These are the run-length patterns for L-codes
  // Format: [space, bar, space, bar] widths totaling 7 modules
  static const List<List<int>> _lPatternRuns = [
    [3, 2, 1, 1], // 0: 0001101
    [2, 2, 2, 1], // 1: 0011001
    [2, 1, 2, 2], // 2: 0010011
    [1, 4, 1, 1], // 3: 0111101
    [1, 1, 3, 2], // 4: 0100011
    [1, 2, 3, 1], // 5: 0110001
    [1, 1, 1, 4], // 6: 0101111
    [1, 3, 1, 2], // 7: 0111011
    [1, 2, 1, 3], // 8: 0110111
    [3, 1, 1, 2], // 9: 0001011
  ];

  // G-patterns (for left half based on first digit parity)
  static const List<List<int>> _gPatternRuns = [
    [1, 1, 2, 3], // 0: 0100111
    [1, 2, 2, 2], // 1: 0110011
    [2, 2, 1, 2], // 2: 0011011
    [1, 1, 4, 1], // 3: 0100001
    [2, 3, 1, 1], // 4: 0011101
    [1, 3, 2, 1], // 5: 0111001
    [4, 1, 1, 1], // 6: 0000101
    [2, 1, 3, 1], // 7: 0010001
    [3, 1, 2, 1], // 8: 0001001
    [2, 1, 1, 3], // 9: 0010111
  ];

  // R-patterns (right half)
  static const List<List<int>> _rPatternRuns = [
    [3, 2, 1, 1], // 0: 1110010
    [2, 2, 2, 1], // 1: 1100110
    [2, 1, 2, 2], // 2: 1101100
    [1, 4, 1, 1], // 3: 1000010
    [1, 1, 3, 2], // 4: 1011100
    [1, 2, 3, 1], // 5: 1001110
    [1, 1, 1, 4], // 6: 1010000
    [1, 3, 1, 2], // 7: 1000100
    [1, 2, 1, 3], // 8: 1001000
    [3, 1, 1, 2], // 9: 1110100
  ];

  // Parity patterns for first digit (0 = L, 1 = G)
  static const List<int> _parityPatterns = [
    0x00, // 0: LLLLLL (000000)
    0x0B, // 1: LLGLGG (001011)
    0x0D, // 2: LLGGLG (001101)
    0x0E, // 3: LLGGGL (001110)
    0x13, // 4: LGLLGG (010011)
    0x19, // 5: LGGLLG (011001)
    0x1C, // 6: LGGGLL (011100)
    0x15, // 7: LGLGLG (010101)
    0x16, // 8: LGLGGL (010110)
    0x1A, // 9: LGGLGL (011010)
  ];

  @override
  BarcodeResult? decodeRow({
    required Uint8List row,
    required int rowNumber,
    required int width,
    Uint16List? runs,
  }) {
    // Convert to run-length encoding
    final runData = runs ?? BarcodeScanner.getRunLengths(row);
    if (runData.length < 60) return null; // Need at least 60 runs for EAN-13

    // Find start guard (1:1:1 pattern starting after white quiet zone)
    final startInfo = _findStartGuard(runData);
    if (startInfo == null) return null;

    final startIndex = startInfo.$1;
    final moduleWidth = startInfo.$2;
    final startX = startInfo.$3;

    var runIndex = startIndex + 3; // Skip start guard (3 runs)

    // Decode left 6 digits
    var parityBits = 0;
    final digits = <int>[];

    for (var i = 0; i < 6; i++) {
      if (runIndex + 4 > runData.length) return null;

      final digitRuns = runData.sublist(runIndex, runIndex + 4);
      final digitInfo = _decodeLeftDigit(digitRuns, moduleWidth);
      if (digitInfo == null) return null;

      digits.add(digitInfo.$1);
      parityBits = (parityBits << 1) | digitInfo.$2;
      runIndex += 4;
    }

    // Skip center guard (5 runs = 01010)
    runIndex += 5;

    // Decode right 6 digits
    for (var i = 0; i < 6; i++) {
      if (runIndex + 4 > runData.length) return null;

      final digitRuns = runData.sublist(runIndex, runIndex + 4);
      final digit = _decodeRightDigit(digitRuns, moduleWidth);
      if (digit == null) return null;

      digits.add(digit);
      runIndex += 4;
    }

    // Determine first digit from parity pattern
    var firstDigit = -1;
    for (var i = 0; i < 10; i++) {
      if (_parityPatterns[i] == parityBits) {
        firstDigit = i;
        break;
      }
    }
    if (firstDigit < 0) return null;

    // Build result string
    final text = '$firstDigit${digits.join()}';

    // Validate checksum
    if (!_validateChecksum(text)) {
      return null;
    }

    // Calculate end position
    final endX = startX + (95 * moduleWidth).round();

    return BarcodeResult(
      text: text,
      format: format,
      startX: startX,
      endX: endX,
      rowY: rowNumber,
    );
  }

  /// Find start guard and return (runIndex, moduleWidth, startX).
  (int, double, int)? _findStartGuard(Uint16List runs) {
    // Look for white quiet zone followed by 1:1:1 pattern (black-white-black)
    for (var i = 0; i < runs.length - 60; i++) {
      if (i % 2 == 0) {
        // At white run (quiet zone)
        // Check next 3 runs for 1:1:1 ratio
        final b1 = runs[i + 1];
        final w1 = runs[i + 2];
        final b2 = runs[i + 3];

        final total = b1 + w1 + b2;
        final avg = total / 3.0; // approx module width

        // Strict Quiet Zone check (at least 10 * moduleWidth)
        final quietZone = runs[i];
        if (quietZone < avg * 10) continue; // Need quiet zone

        // Allow variance
        if ((b1 - avg).abs() > avg * 0.5) continue;
        if ((w1 - avg).abs() > avg * 0.5) continue;
        if ((b2 - avg).abs() > avg * 0.5) continue;

        // Calculate start X position
        var startX = 0;
        for (var j = 0; j <= i; j++) {
          startX += runs[j];
        }

        return (i + 1, avg, startX - quietZone);
      }
    }
    return null;
  }

  /// Decode a left-side digit, returns (digit, parity) where parity is 0=L, 1=G.
  (int, int)? _decodeLeftDigit(Uint16List digitRuns, double moduleWidth) {
    // Normalize runs to module counts
    final modules = Uint16List.fromList(
      digitRuns.map((r) => (r / moduleWidth).round()).toList(),
    );

    var bestDigit = -1;
    var bestParity = -1;
    var bestError = 999;

    // Try L patterns
    for (var d = 0; d < 10; d++) {
      final error = _patternError(modules, _lPatternRuns[d]);
      if (error < bestError) {
        bestError = error;
        bestDigit = d;
        bestParity = 0;
      }
    }

    // Try G patterns
    for (var d = 0; d < 10; d++) {
      final error = _patternError(modules, _gPatternRuns[d]);
      if (error < bestError) {
        bestError = error;
        bestDigit = d;
        bestParity = 1;
      }
    }

    // Only accept if error is small enough (total error <= 2)
    if (bestError <= 2 && bestDigit >= 0) {
      return (bestDigit, bestParity);
    }

    return null;
  }

  /// Decode a right-side digit (R pattern only).
  int? _decodeRightDigit(Uint16List digitRuns, double moduleWidth) {
    final modules = Uint16List.fromList(
      digitRuns.map((r) => (r / moduleWidth).round()).toList(),
    );

    var bestDigit = -1;
    var bestError = 999;

    for (var d = 0; d < 10; d++) {
      final error = _patternError(modules, _rPatternRuns[d]);
      if (error < bestError) {
        bestError = error;
        bestDigit = d;
      }
    }

    if (bestError <= 2 && bestDigit >= 0) {
      return bestDigit;
    }

    return null;
  }

  /// Calculate total error between two patterns.
  int _patternError(Uint16List actual, List<int> expected) {
    if (actual.length != expected.length) return 999;

    var error = 0;
    for (var i = 0; i < actual.length; i++) {
      error += (actual[i] - expected[i]).abs();
    }
    return error;
  }

  bool _validateChecksum(String barcode) {
    if (barcode.length != 13) return false;

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }

    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(barcode[12]);
  }
}
