import 'dart:typed_data';

import 'barcode_decoder.dart';
import 'barcode_result.dart';
import 'barcode_scanner.dart';

/// ITF (Interleaved 2 of 5) barcode decoder.
///
/// ITF is a numeric-only, variable-length barcode used in logistics.
/// ITF-14 is a specific 14-digit variant for shipping containers.
///
/// Structure:
/// - Start pattern: narrow-narrow-narrow-narrow (NNNN)
/// - Data: pairs of digits interleaved (bars encode first, spaces encode second)
/// - End pattern: wide-narrow-narrow (WNN)
///
/// Each digit is encoded with 2 wide + 3 narrow elements.
class ITFDecoder extends BarcodeDecoder {
  const ITFDecoder();
  @override
  String get format => 'ITF';

  // Pattern for each digit: 1 = wide, 0 = narrow
  // Each digit has 5 elements (2 wide, 3 narrow)
  static const List<int> _patterns = [
    0x06, // 0: 00110 = NNWWN
    0x11, // 1: 10001 = WNNNN + W at end
    0x09, // 2: 01001 = NWNNN + W at end
    0x18, // 3: 11000 = WWNNN
    0x05, // 4: 00101 = NNWNN + W at end
    0x14, // 5: 10100 = WNWNN
    0x0C, // 6: 01100 = NWWNN
    0x03, // 7: 00011 = NNNWW
    0x12, // 8: 10010 = WNNWN
    0x0A, // 9: 01010 = NWNWN
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
    if (runData.length < 10) return null;

    // Find start pattern (4 narrow elements: NNNN)
    final startInfo = _findStartPattern(runData);
    if (startInfo == null) return null;

    var runIndex = startInfo.$1;
    final narrowWidth = startInfo.$2;
    final startX = startInfo.$3;

    // Skip start pattern (4 runs)
    runIndex += 4;

    final digits = <int>[];
    var foundEndPattern = false;

    // Decode digit pairs
    // Each pair uses 10 runs (5 bars + 5 spaces)
    // Loop checks for End Pattern (3 runs) first.
    while (runIndex + 3 <= runData.length) {
      // Check for end pattern (3 runs: WNN)
      if (_isEndPattern(runData, runIndex, narrowWidth)) {
        foundEndPattern = true;
        break;
      }

      // If not end pattern, we need a full pair (10 runs)
      if (runIndex + 10 > runData.length) break;

      // Decode pair of digits
      final pairRuns = runData.sublist(runIndex, runIndex + 10);
      final pair = _decodeDigitPair(pairRuns, narrowWidth);
      if (pair == null) break;

      digits.add(pair.$1);
      digits.add(pair.$2);
      runIndex += 10;
    }

    if (!foundEndPattern || digits.isEmpty) return null;

    final text = digits.join();

    // Default minimum length for ITF to avoid false positives is 6.
    if (text.length < 6) {
      return null;
    }

    // Validate checksum if it's ITF-14 (14 digits)
    if (text.length == 14 && !validateITF14Checksum(text)) {
      return null;
    }

    final endX = startX + (runIndex * narrowWidth * 2.5).round();

    return BarcodeResult(
      text: text,
      format: text.length == 14 ? 'ITF_14' : format,
      startX: startX,
      endX: endX,
      rowY: rowNumber,
    );
  }

  /// Find start pattern (NNNN) and return (runIndex, narrowWidth, startX).
  (int, double, int)? _findStartPattern(Uint16List runs) {
    for (var i = 0; i < runs.length - 10; i++) {
      if (i % 2 == 0 && runs[i] > 5) {
        // At white quiet zone
        // Start pattern is 4 narrow elements (NNNN)
        if (i + 5 >= runs.length) continue;

        final startRuns = runs.sublist(i + 1, i + 5);

        // All should be relatively narrow (less than the wide bars in data)
        // Use the minimum as reference for narrow width
        final minWidth = startRuns.reduce((a, b) => a < b ? a : b);
        final maxWidth = startRuns.reduce((a, b) => a > b ? a : b);

        // Allow 100% variance (maxWidth <= 2 * minWidth)
        if (maxWidth > minWidth * 2) continue;

        final avg = startRuns.reduce((a, b) => a + b) / 4.0;

        // Check strict Quiet Zone (at least 10 * narrowWidth)
        // runs[i] covers the quiet zone before the start pattern
        if (runs[i] < avg * 10) continue;

        var startX = 0;
        for (var j = 0; j <= i; j++) {
          startX += runs[j];
        }

        return (i + 1, avg, startX - runs[i]);
      }
    }
    return null;
  }

  bool _isEndPattern(Uint16List runs, int index, double narrowWidth) {
    if (index + 4 > runs.length) return false;

    final r1 = runs[index];
    final r2 = runs[index + 1];
    final r3 = runs[index + 2];
    final quietZone = runs[index + 3];

    // End pattern: Wide, Narrow, Narrow, followed by quiet zone
    final wideThreshold = narrowWidth * 1.8;

    return r1 > wideThreshold &&
        r2 < wideThreshold &&
        r3 < wideThreshold &&
        quietZone >= narrowWidth * 10; // Quiet zone should be large (>=10x)
  }

  /// Decode a pair of digits from 10 runs (5 bars + 5 spaces).
  (int, int)? _decodeDigitPair(Uint16List pairRuns, double narrowWidth) {
    if (pairRuns.length != 10) return null;

    // Extract bar widths (odd indices: 0, 2, 4, 6, 8)
    // Extract space widths (even indices: 1, 3, 5, 7, 9)
    final barWidths = Uint16List(5);
    final spaceWidths = Uint16List(5);
    var barIndex = 0;
    var spaceIndex = 0;

    for (var i = 0; i < 10; i++) {
      if (i % 2 == 0) {
        barWidths[barIndex++] = pairRuns[i];
      } else {
        spaceWidths[spaceIndex++] = pairRuns[i];
      }
    }

    // Determine threshold for wide/narrow
    final allWidths = Uint16List.fromList([...barWidths, ...spaceWidths]);
    allWidths.sort();
    // ITF digit pair has 4 wide and 6 narrow elements.
    // Sorted indices 0-5 should be narrow, 6-9 should be wide.
    // Threshold should be between index 5 (max narrow) and 6 (min wide).
    final threshold = (allWidths[5] + allWidths[6]) / 2.0;

    // Convert to patterns
    final barPattern = _toPattern(barWidths, threshold);
    final spacePattern = _toPattern(spaceWidths, threshold);

    // Find matching digits
    int? digit1;
    int? digit2;

    for (var d = 0; d < 10; d++) {
      if (_patterns[d] == barPattern) {
        digit1 = d;
      }
      if (_patterns[d] == spacePattern) {
        digit2 = d;
      }
    }

    if (digit1 != null && digit2 != null) {
      return (digit1, digit2);
    }

    return null;
  }

  int _toPattern(Uint16List widths, double threshold) {
    var pattern = 0;
    for (var i = 0; i < widths.length; i++) {
      if (widths[i] > threshold) {
        pattern |= (1 << (4 - i));
      }
    }
    return pattern;
  }

  /// For testing: validates ITF-14 checksum
  static bool validateITF14Checksum(String barcode) {
    if (barcode.length != 14) return false;

    var sum = 0;
    for (var i = 0; i < 13; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }

    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(barcode[13]);
  }
}
