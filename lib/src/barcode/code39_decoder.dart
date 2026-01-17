import 'barcode_decoder.dart';
import 'barcode_result.dart';

/// Code 39 barcode decoder.
///
/// Code 39 is a variable length, discrete barcode symbology.
/// Each character is represented by 9 bars/spaces: 5 bars and 4 spaces.
/// 3 of these 9 elements are wide (hence "Code 39" = 3 of 9).
///
/// Supported characters: 0-9, A-Z, -, ., $, /, +, %, space
/// Start/Stop character: * (asterisk)
class Code39Decoder extends BarcodeDecoder {
  const Code39Decoder();

  @override
  String get format => 'CODE_39';

  // Character set for Code 39
  static const String _characterSet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. \$/+%*';

  // Patterns: 9 elements per character (5 bars + 4 spaces)
  // 1 = wide, 0 = narrow
  // Format: bar-space-bar-space-bar-space-bar-space-bar
  static const List<int> _patterns = [
    0x034, // 0: 000110100 = NnNwWnWnN
    0x121, // 1: 100100001 = WnNnNnNwW
    0x061, // 2: 001100001 = NnWnNnNwW
    0x160, // 3: 101100000 = WnWnNnNnN ... (simplified)
    0x031, // 4: 000110001
    0x130, // 5: 100110000
    0x070, // 6: 001110000
    0x025, // 7: 000100101
    0x124, // 8: 100100100
    0x064, // 9: 001100100
    0x109, // A: 100001001
    0x049, // B: 001001001
    0x148, // C: 101001000
    0x019, // D: 000011001
    0x118, // E: 100011000
    0x058, // F: 001011000
    0x00D, // G: 000001101
    0x10C, // H: 100001100
    0x04C, // I: 001001100
    0x01C, // J: 000011100
    0x103, // K: 100000011
    0x043, // L: 001000011
    0x142, // M: 101000010
    0x013, // N: 000010011
    0x112, // O: 100010010
    0x052, // P: 001010010
    0x007, // Q: 000000111
    0x106, // R: 100000110
    0x046, // S: 001000110
    0x016, // T: 000010110
    0x181, // U: 110000001
    0x0C1, // V: 011000001
    0x1C0, // W: 111000000
    0x091, // X: 010010001
    0x190, // Y: 110010000
    0x0D0, // Z: 011010000
    0x085, // -: 010000101
    0x184, // .: 110000100
    0x0C4, // (space): 011000100
    0x0A8, // $: 010101000
    0x0A2, // /: 010100010
    0x08A, // +: 010001010
    0x02A, // %: 000101010
    0x094, // *: 010010100 (start/stop)
  ];

  @override
  BarcodeResult? decodeRow({
    required List<bool> row,
    required int rowNumber,
    required int width,
  }) {
    // Convert to run-length encoding
    final runs = _getRunLengths(row);
    if (runs.length < 10) return null;

    // Find start pattern (*)
    final startInfo = _findStartPattern(runs);
    if (startInfo == null) return null;

    var runIndex = startInfo.$1;
    final narrowWidth = startInfo.$2;
    final startX = startInfo.$3;

    final result = StringBuffer();

    // Skip start pattern (9 runs + 1 inter-character space)
    runIndex += 10;

    // Decode characters
    while (runIndex + 9 <= runs.length) {
      final charRuns = runs.sublist(runIndex, runIndex + 9);
      final char = _decodeCharacter(charRuns, narrowWidth);

      if (char == null) break;

      // Check for stop pattern
      if (char == '*') {
        break;
      }

      result.write(char);
      runIndex += 10; // 9 runs + 1 inter-character gap
    }

    final text = result.toString();
    if (text.isEmpty) return null;

    return BarcodeResult(
      text: text,
      format: format,
      startX: startX,
      endX: runIndex,
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

  /// Find start pattern (*) and return (runIndex, narrowWidth, startX).
  (int, double, int)? _findStartPattern(List<int> runs) {
    // Look for quiet zone followed by start pattern
    for (var i = 0; i < runs.length - 10; i++) {
      if (i % 2 == 0 && runs[i] > 5) {
        // Potential quiet zone
        final patternRuns = runs.sublist(i + 1, i + 10);

        // Calculate narrow and wide widths
        final widths = _analyzeWidths(patternRuns);
        if (widths == null) continue;

        final (narrowWidth, wideWidth) = widths;

        // Check if this matches start pattern (*)
        final pattern = _runsToPattern(patternRuns, narrowWidth, wideWidth);
        if (pattern == _patterns[43]) {
          // * is at index 43
          var startX = 0;
          for (var j = 0; j <= i; j++) {
            startX += runs[j];
          }
          return (i + 1, narrowWidth, startX - runs[i]);
        }
      }
    }
    return null;
  }

  /// Analyze runs to determine narrow and wide widths.
  (double, double)? _analyzeWidths(List<int> runs) {
    if (runs.length != 9) return null;

    // Sort to find narrow and wide groups
    final sorted = List<int>.from(runs)..sort();

    // In Code 39, 3 elements are wide, 6 are narrow
    // Wide should be ~2-3x narrow
    final narrowSum = sorted.take(6).reduce((a, b) => a + b);
    final wideSum = sorted.skip(6).take(3).reduce((a, b) => a + b);

    final narrowAvg = narrowSum / 6.0;
    final wideAvg = wideSum / 3.0;

    // Validate ratio (should be 2:1 to 3:1)
    final ratio = wideAvg / narrowAvg;
    if (ratio < 1.5 || ratio > 4.0) return null;

    return (narrowAvg, wideAvg);
  }

  /// Convert runs to pattern bits.
  int _runsToPattern(List<int> runs, double narrowWidth, double wideWidth) {
    var pattern = 0;
    final threshold = (narrowWidth + wideWidth) / 2.0;

    for (var i = 0; i < 9; i++) {
      if (runs[i] > threshold) {
        pattern |= (1 << (8 - i));
      }
    }

    return pattern;
  }

  String? _decodeCharacter(List<int> runs, double narrowWidth) {
    final widths = _analyzeWidths(runs);
    if (widths == null) return null;

    final (narrow, wide) = widths;
    final pattern = _runsToPattern(runs, narrow, wide);

    // Find matching pattern
    for (var i = 0; i < _patterns.length; i++) {
      if (_patterns[i] == pattern) {
        return _characterSet[i];
      }
    }

    return null;
  }
}
