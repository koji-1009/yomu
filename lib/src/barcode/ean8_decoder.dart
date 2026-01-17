import 'barcode_decoder.dart';
import 'barcode_result.dart';

/// EAN-8 barcode decoder.
///
/// EAN-8 is an 8-digit barcode format used for small products.
/// Structure: [Start 3] + [Left 28] + [Center 5] + [Right 28] + [End 3] = 67 modules
///
/// Unlike EAN-13, EAN-8 has:
/// - 4 digits on each side (no parity encoding)
/// - All left digits use L-patterns
/// - All right digits use R-patterns
class EAN8Decoder extends BarcodeDecoder {
  const EAN8Decoder();

  @override
  String get format => 'EAN_8';

  // L-patterns: run-length format [space, bar, space, bar]
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

  // R-patterns (complement of L)
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

  @override
  BarcodeResult? decodeRow({
    required List<bool> row,
    required int rowNumber,
    required int width,
  }) {
    // Convert to run-length encoding
    final runs = _getRunLengths(row);
    if (runs.length < 44) return null; // Need at least 44 runs for EAN-8

    // Find start guard (1:1:1 pattern)
    final startInfo = _findStartGuard(runs);
    if (startInfo == null) return null;

    final startIndex = startInfo.$1;
    final moduleWidth = startInfo.$2;
    final startX = startInfo.$3;

    var runIndex = startIndex + 3; // Skip start guard

    // Decode left 4 digits (L pattern only)
    final digits = <int>[];

    for (var i = 0; i < 4; i++) {
      if (runIndex + 4 > runs.length) return null;

      final digitRuns = runs.sublist(runIndex, runIndex + 4);
      final digit = _decodeLeftDigit(digitRuns, moduleWidth);
      if (digit == null) return null;

      digits.add(digit);
      runIndex += 4;
    }

    // Skip center guard (5 runs = 01010)
    runIndex += 5;

    // Decode right 4 digits (R pattern only)
    for (var i = 0; i < 4; i++) {
      if (runIndex + 4 > runs.length) return null;

      final digitRuns = runs.sublist(runIndex, runIndex + 4);
      final digit = _decodeRightDigit(digitRuns, moduleWidth);
      if (digit == null) return null;

      digits.add(digit);
      runIndex += 4;
    }

    // Build result string
    final text = digits.join();

    // Validate checksum
    if (!_validateChecksum(text)) {
      return null;
    }

    // Calculate end position
    final endX = startX + (67 * moduleWidth).round();

    return BarcodeResult(
      text: text,
      format: format,
      startX: startX,
      endX: endX,
      rowY: rowNumber,
    );
  }

  List<int> _getRunLengths(List<bool> row) {
    final runs = <int>[];
    var currentPos = 0;
    var currentColor = row[0];

    while (currentPos < row.length) {
      var runLength = 0;
      while (currentPos < row.length && row[currentPos] == currentColor) {
        runLength++;
        currentPos++;
      }
      runs.add(runLength);
      currentColor = !currentColor;
    }

    return runs;
  }

  /// Find start guard and return (runIndex, moduleWidth, startX).
  (int, double, int)? _findStartGuard(List<int> runs) {
    for (var i = 0; i < runs.length - 44; i++) {
      if (i % 2 == 0) {
        final quietZone = runs[i];
        if (quietZone < 10) continue;

        final b1 = runs[i + 1];
        final w1 = runs[i + 2];
        final b2 = runs[i + 3];

        final total = b1 + w1 + b2;
        final avg = total / 3.0;

        if ((b1 - avg).abs() > avg * 0.5) continue;
        if ((w1 - avg).abs() > avg * 0.5) continue;
        if ((b2 - avg).abs() > avg * 0.5) continue;

        var startX = 0;
        for (var j = 0; j <= i; j++) {
          startX += runs[j];
        }

        return (i + 1, avg, startX - quietZone);
      }
    }
    return null;
  }

  int? _decodeLeftDigit(List<int> digitRuns, double moduleWidth) {
    final modules = digitRuns.map((r) => (r / moduleWidth).round()).toList();

    var bestDigit = -1;
    var bestError = 999;

    for (var d = 0; d < 10; d++) {
      final error = _patternError(modules, _lPatternRuns[d]);
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

  int? _decodeRightDigit(List<int> digitRuns, double moduleWidth) {
    final modules = digitRuns.map((r) => (r / moduleWidth).round()).toList();

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

  int _patternError(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return 999;

    var error = 0;
    for (var i = 0; i < actual.length; i++) {
      error += (actual[i] - expected[i]).abs();
    }
    return error;
  }

  bool _validateChecksum(String barcode) {
    if (barcode.length != 8) return false;

    // EAN-8 checksum: sum of (odd positions) + 3 * sum of (even positions)
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }

    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(barcode[7]);
  }
}
