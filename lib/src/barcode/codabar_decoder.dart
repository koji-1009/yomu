import 'dart:typed_data';

import 'barcode_decoder.dart';
import 'barcode_result.dart';

/// Codabar barcode decoder.
///
/// Codabar is a linear barcode used in libraries, blood banks, and FedEx.
/// It supports digits 0-9 and characters: - $ : / . +
/// Start/stop characters: A, B, C, D (also T, N, *, E)
///
/// Each character is encoded with 7 elements (4 bars + 3 spaces).
class CodabarDecoder extends BarcodeDecoder {
  const CodabarDecoder();

  @override
  String get format => 'CODABAR';

  // Character set
  static const String _characterSet = '0123456789-\$:/.+ABCD';

  // Patterns: 7 elements per character
  // 1 = wide, 0 = narrow
  // Format: bar-space-bar-space-bar-space-bar
  static const List<int> _patterns = [
    0x03, // 0: 0000011
    0x06, // 1: 0000110
    0x09, // 2: 0001001
    0x60, // 3: 1100000
    0x12, // 4: 0010010
    0x42, // 5: 1000010
    0x21, // 6: 0100001
    0x24, // 7: 0100100
    0x30, // 8: 0110000
    0x48, // 9: 1001000
    0x0C, // -: 0001100
    0x18, // $: 0011000
    0x45, // :: 1000101
    0x51, // /: 1010001
    0x54, // .: 1010100
    0x15, // +: 0010101
    0x1A, // A: 0011010
    0x29, // B: 0101001
    0x0B, // C: 0001011
    0x0E, // D: 0001110
  ];

  // Start/stop characters are A, B, C, D (indices 16-19)
  static const Set<int> _startStopIndices = {16, 17, 18, 19};

  @override
  BarcodeResult? decodeRow({
    required int rowNumber,
    required int width,
    required Uint16List runs,
    Uint8List? row,
  }) {
    if (runs.length < 10) return null;

    // Find start pattern (A, B, C, or D)
    final startInfo = _findStartPattern(runs);
    if (startInfo == null) return null;

    var runIndex = startInfo.$1;
    final narrowWidth = startInfo.$2;
    final startX = startInfo.$3;

    final result = StringBuffer();

    // Skip start character (7 runs + 1 inter-character gap)
    runIndex += 8;

    // Decode characters
    while (runIndex + 7 <= runs.length) {
      final charInfo = _decodeCharacter(runs, runIndex, narrowWidth);

      if (charInfo == null) break;

      final (charIndex, char) = charInfo;

      // Check for stop character
      if (_startStopIndices.contains(charIndex)) {
        // Run index currently points to start of this character.
        // Stop character is 7 runs.
        // Check Quiet Zone after stop character.
        if (runIndex + 7 < runs.length) {
          final quietZone = runs[runIndex + 7];
          // Use narrowWidth * 10 as standard quiet zone requirement
          if (quietZone < narrowWidth * 10) {
            return null;
          }
        }
        break;
      }

      result.write(char);
      runIndex += 8; // 7 runs + 1 inter-character gap
    }

    final text = result.toString();
    if (text.isEmpty) return null;

    final endX = startX + (runIndex * narrowWidth * 2).round();

    return BarcodeResult(
      text: text,
      format: format,
      startX: startX,
      endX: endX,
      rowY: rowNumber,
    );
  }

  /// Find start pattern and return (runIndex, narrowWidth, startX, startChar).
  (int, double, int, String)? _findStartPattern(Uint16List runs) {
    for (var i = 0; i < runs.length - 10; i++) {
      if (i % 2 == 0) {
        if (i + 7 >= runs.length) continue;

        final widths = _analyzeWidths(runs, i + 1);
        if (widths == null) continue;

        final (narrowWidth, wideWidth) = widths;

        // Validate quiet zone based on calculated narrow width
        if (runs[i] < narrowWidth * 10) continue;
        final pattern = _runsToPattern(runs, i + 1, narrowWidth, wideWidth);

        // Check if this is a start character (A, B, C, D)
        for (final idx in _startStopIndices) {
          if (_patterns[idx] == pattern) {
            var startX = 0;
            for (var j = 0; j <= i; j++) {
              startX += runs[j];
            }
            return (i + 1, narrowWidth, startX - runs[i], _characterSet[idx]);
          }
        }
      }
    }
    return null;
  }

  (double, double)? _analyzeWidths(Uint16List runs, int offset) {
    final sorted = Uint16List(7);
    for (var i = 0; i < 7; i++) {
      sorted[i] = runs[offset + i];
    }
    sorted.sort();

    // Codabar has 2-3 wide elements, rest are narrow
    final narrowSum = sorted[0] + sorted[1] + sorted[2] + sorted[3];
    final wideSum = sorted[4] + sorted[5] + sorted[6];

    final narrowAvg = narrowSum / 4.0;
    final wideAvg = wideSum / 3.0;

    final ratio = wideAvg / narrowAvg;
    if (ratio < 1.5 || ratio > 4.0) return null;

    return (narrowAvg, wideAvg);
  }

  int _runsToPattern(
    Uint16List runs,
    int offset,
    double narrowWidth,
    double wideWidth,
  ) {
    var pattern = 0;
    final threshold = (narrowWidth + wideWidth) / 2.0;

    for (var i = 0; i < 7; i++) {
      if (runs[offset + i] > threshold) {
        pattern |= (1 << (6 - i));
      }
    }

    return pattern;
  }

  (int, String)? _decodeCharacter(
    Uint16List runs,
    int offset,
    double narrowWidth,
  ) {
    final widths = _analyzeWidths(runs, offset);
    if (widths == null) return null;

    final (narrow, wide) = widths;
    final pattern = _runsToPattern(runs, offset, narrow, wide);

    for (var i = 0; i < _patterns.length; i++) {
      if (_patterns[i] == pattern) {
        return (i, _characterSet[i]);
      }
    }

    return null;
  }
}
