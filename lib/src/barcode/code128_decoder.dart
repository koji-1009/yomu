import 'dart:typed_data';

import 'barcode_decoder.dart';
import 'barcode_result.dart';

/// Code 128 barcode decoder.
///
/// Code 128 is a high-density linear barcode symbology.
/// Each character is 11 modules wide (6 bars/spaces).
/// Stop pattern is 13 modules wide (7 bars/spaces).
class Code128Decoder extends BarcodeDecoder {
  const Code128Decoder();

  @override
  String get format => 'CODE_128';

  // Code 128 patterns: each is [bar, space, bar, space, bar, space] widths
  // totaling 11 modules
  static const List<List<int>> _patterns = [
    [2, 1, 2, 2, 2, 2], // 0
    [2, 2, 2, 1, 2, 2], // 1
    [2, 2, 2, 2, 2, 1], // 2
    [1, 2, 1, 2, 2, 3], // 3
    [1, 2, 1, 3, 2, 2], // 4
    [1, 3, 1, 2, 2, 2], // 5
    [1, 2, 2, 2, 1, 3], // 6
    [1, 2, 2, 3, 1, 2], // 7
    [1, 3, 2, 2, 1, 2], // 8
    [2, 2, 1, 2, 1, 3], // 9
    [2, 2, 1, 3, 1, 2], // 10
    [2, 3, 1, 2, 1, 2], // 11
    [1, 1, 2, 2, 3, 2], // 12
    [1, 2, 2, 1, 3, 2], // 13
    [1, 2, 2, 2, 3, 1], // 14
    [1, 1, 3, 2, 2, 2], // 15
    [1, 2, 3, 1, 2, 2], // 16
    [1, 2, 3, 2, 2, 1], // 17
    [2, 2, 3, 2, 1, 1], // 18
    [2, 2, 1, 1, 3, 2], // 19
    [2, 2, 1, 2, 3, 1], // 20
    [2, 1, 3, 2, 1, 2], // 21
    [2, 2, 3, 1, 1, 2], // 22
    [3, 1, 2, 1, 3, 1], // 23
    [3, 1, 1, 2, 2, 2], // 24
    [3, 2, 1, 1, 2, 2], // 25
    [3, 2, 1, 2, 2, 1], // 26
    [3, 1, 2, 2, 1, 2], // 27
    [3, 2, 2, 1, 1, 2], // 28
    [3, 2, 2, 2, 1, 1], // 29
    [2, 1, 2, 1, 2, 3], // 30
    [2, 1, 2, 3, 2, 1], // 31
    [2, 3, 2, 1, 2, 1], // 32
    [1, 1, 1, 3, 2, 3], // 33
    [1, 3, 1, 1, 2, 3], // 34
    [1, 3, 1, 3, 2, 1], // 35
    [1, 1, 2, 3, 1, 3], // 36
    [1, 3, 2, 1, 1, 3], // 37
    [1, 3, 2, 3, 1, 1], // 38
    [2, 1, 1, 3, 1, 3], // 39
    [2, 3, 1, 1, 1, 3], // 40
    [2, 3, 1, 3, 1, 1], // 41
    [1, 1, 2, 1, 3, 3], // 42
    [1, 1, 2, 3, 3, 1], // 43
    [1, 3, 2, 1, 3, 1], // 44
    [1, 1, 3, 1, 2, 3], // 45
    [1, 1, 3, 3, 2, 1], // 46
    [1, 3, 3, 1, 2, 1], // 47
    [3, 1, 3, 1, 2, 1], // 48
    [2, 1, 1, 3, 3, 1], // 49
    [2, 3, 1, 1, 3, 1], // 50
    [2, 1, 3, 1, 1, 3], // 51
    [2, 1, 3, 3, 1, 1], // 52
    [2, 1, 3, 1, 3, 1], // 53
    [3, 1, 1, 1, 2, 3], // 54
    [3, 1, 1, 3, 2, 1], // 55
    [3, 3, 1, 1, 2, 1], // 56
    [3, 1, 2, 1, 1, 3], // 57
    [3, 1, 2, 3, 1, 1], // 58
    [3, 3, 2, 1, 1, 1], // 59
    [3, 1, 4, 1, 1, 1], // 60
    [2, 2, 1, 4, 1, 1], // 61
    [4, 3, 1, 1, 1, 1], // 62
    [1, 1, 1, 2, 2, 4], // 63
    [1, 1, 1, 4, 2, 2], // 64
    [1, 2, 1, 1, 2, 4], // 65
    [1, 2, 1, 4, 2, 1], // 66
    [1, 4, 1, 1, 2, 2], // 67
    [1, 4, 1, 2, 2, 1], // 68
    [1, 1, 2, 2, 1, 4], // 69
    [1, 1, 2, 4, 1, 2], // 70
    [1, 2, 2, 1, 1, 4], // 71
    [1, 2, 2, 4, 1, 1], // 72
    [1, 4, 2, 1, 1, 2], // 73
    [1, 4, 2, 2, 1, 1], // 74
    [2, 4, 1, 2, 1, 1], // 75
    [2, 2, 1, 1, 1, 4], // 76
    [4, 1, 3, 1, 1, 1], // 77
    [2, 4, 1, 1, 1, 2], // 78
    [1, 3, 4, 1, 1, 1], // 79
    [1, 1, 1, 2, 4, 2], // 80
    [1, 2, 1, 1, 4, 2], // 81
    [1, 2, 1, 2, 4, 1], // 82
    [1, 1, 4, 2, 1, 2], // 83
    [1, 2, 4, 1, 1, 2], // 84
    [1, 2, 4, 2, 1, 1], // 85
    [4, 1, 1, 2, 1, 2], // 86
    [4, 2, 1, 1, 1, 2], // 87
    [4, 2, 1, 2, 1, 1], // 88
    [2, 1, 2, 1, 4, 1], // 89
    [2, 1, 4, 1, 2, 1], // 90
    [4, 1, 2, 1, 2, 1], // 91
    [1, 1, 1, 1, 4, 3], // 92
    [1, 1, 1, 3, 4, 1], // 93
    [1, 3, 1, 1, 4, 1], // 94
    [1, 1, 4, 1, 1, 3], // 95
    [1, 1, 4, 3, 1, 1], // 96
    [4, 1, 1, 1, 1, 3], // 97
    [4, 1, 1, 3, 1, 1], // 98
    [1, 1, 3, 1, 4, 1], // 99
    [1, 1, 4, 1, 3, 1], // 100
    [3, 1, 1, 1, 4, 1], // 101
    [4, 1, 1, 1, 3, 1], // 102
    [2, 1, 1, 4, 1, 2], // 103 - Start A
    [2, 1, 1, 2, 1, 4], // 104 - Start B
    [2, 1, 1, 2, 3, 2], // 105 - Start C
  ];

  // Stop pattern: [2, 3, 3, 1, 1, 1, 2] (7 elements, 13 modules)
  static const List<int> _stopPattern = [2, 3, 3, 1, 1, 1, 2];

  @override
  BarcodeResult? decodeRow({
    required List<bool> row,
    required int rowNumber,
    required int width,
    Uint16List? runs,
  }) {
    // Convert to run-length encoding
    final runData = runs ?? _getRunLengths(row);
    if (runData.length < 10) return null; // Need at least start + stop

    // Find start pattern
    final startInfo = _findStartPattern(runData);
    if (startInfo == null) return null;

    var runIndex = startInfo.$1;
    final moduleWidth = startInfo.$2;
    final startCode = startInfo.$3;
    final startX = startInfo.$4;

    // Determine initial code set
    int codeSet;
    switch (startCode) {
      case 103:
        codeSet = 0; // Code A
      case 104:
        codeSet = 1; // Code B
      case 105:
        codeSet = 2; // Code C
      default:
        return null;
    }

    final codes = <int>[startCode];
    final decodedChars = <String>[]; // Store each decoded character
    var checksum = startCode;
    var checksumWeight = 1;

    // Skip start pattern (6 runs)
    runIndex += 6;

    // Decode data characters
    while (runIndex + 6 <= runData.length) {
      // Check for stop pattern (7 runs)
      if (runIndex + 7 <= runData.length) {
        final stopRuns = runData.sublist(runIndex, runIndex + 7);
        if (_matchStop(stopRuns, moduleWidth)) {
          break;
        }
      }

      // Decode character (6 runs)
      final charRuns = runData.sublist(runIndex, runIndex + 6);
      final code = _decodeCharacter(charRuns, moduleWidth);
      if (code == null) break;

      codes.add(code);
      checksum += code * checksumWeight;
      checksumWeight++;
      runIndex += 6;

      // Handle code set switches
      final newSet = findCodeSetSwitch(code);
      if (newSet != null) {
        codeSet = newSet;
      } else if (code == 102) {
        // FNC1: Typically used as a field separator in GS1-128.
        // Map to ASCII Group Separator (GS, 0x1D)
        decodedChars.add(String.fromCharCode(0x1D));
      } else if (code < 96) {
        decodedChars.add(_decodeValue(code, codeSet));
      }
    }

    if (codes.length < 3) return null; // Need at least start + data + check

    // Last code is checksum
    final checksumCode = codes.last;
    codes.removeLast();
    // Checksum matches everything except the checksum itself and stop pattern
    // checksum is updated during the loop
    // But we need to subtract the last code contribution to checksum
    // Since checksum logic in loop adds (code * weight), and weight increments
    // We need to verify correctness.
    // Loop sums all codes including checksum code.
    // Standard validation: sum(codes) % 103 == checksumCode
    // But verify implementation logic:
    // checksum variable holds running sum.
    // last added was checksumCode * (weight-1).
    checksum -= checksumCode * (checksumWeight - 1);

    if (checksum % 103 != checksumCode) return null;

    // Remove the last decoded character if checksum was a printable character
    // (checksum code < 96 means it was added to decodedChars)
    if (decodedChars.isNotEmpty && checksumCode < 96) {
      decodedChars.removeLast();
    }

    final text = decodedChars.join();
    if (text.isEmpty) return null;

    // Calculate end position
    final endX =
        startX + ((runIndex - startInfo.$1 + 7) * moduleWidth * 11 / 6).round();

    return BarcodeResult(
      text: text,
      format: format,
      startX: startX,
      endX: endX,
      rowY: rowNumber,
    );
  }

  Uint16List _getRunLengths(List<bool> row) {
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

    return Uint16List.fromList(runs);
  }

  /// Find start pattern and return (runIndex, moduleWidth, startCode, startX).
  (int, double, int, int)? _findStartPattern(Uint16List runs) {
    for (var i = 0; i < runs.length - 10; i++) {
      if (i % 2 == 0 && runs[i] > 5) {
        // At white run (quiet zone)
        if (i + 6 >= runs.length) continue;

        final startRuns = runs.sublist(i + 1, i + 7);
        final total = startRuns.reduce((a, b) => a + b);
        final moduleWidth = total / 11.0;

        // Strict Quiet Zone check (at least 10 * moduleWidth)
        if (runs[i] < moduleWidth * 10) continue;

        // Try each start pattern
        for (var code = 103; code <= 105; code++) {
          if (_matchPatternWithError(startRuns, _patterns[code], moduleWidth) <=
              2) {
            // Calculate startX
            var startX = 0;
            for (var j = 0; j <= i; j++) {
              startX += runs[j];
            }
            return (i + 1, moduleWidth, code, startX - runs[i]);
          }
        }
      }
    }
    return null;
  }

  int? _decodeCharacter(Uint16List charRuns, double globalModuleWidth) {
    // Calculate local module width from this character's runs
    // Each Code128 character is 11 modules
    final total = charRuns.reduce((a, b) => a + b);
    final localModuleWidth = total / 11.0;

    final modules = Uint16List.fromList(
      charRuns.map((r) => (r / localModuleWidth).round()).toList(),
    );

    var bestCode = -1;
    var bestError = 999;

    for (var code = 0; code < _patterns.length; code++) {
      final error = _patternError(modules, _patterns[code]);
      if (error < bestError) {
        bestError = error;
        bestCode = code;
      }
    }

    if (bestError <= 3 && bestCode >= 0) {
      return bestCode;
    }

    return null;
  }

  int _patternError(Uint16List actual, List<int> expected) {
    if (actual.length != expected.length) return 999;

    var error = 0;
    for (var i = 0; i < actual.length; i++) {
      error += (actual[i] - expected[i]).abs();
    }
    return error;
  }

  int _matchPatternWithError(
    Uint16List runs,
    List<int> pattern,
    double moduleWidth,
  ) {
    if (runs.length != pattern.length) return 999;

    final modules = Uint16List.fromList(
      runs.map((r) => (r / moduleWidth).round()).toList(),
    );
    return _patternError(modules, pattern);
  }

  bool _matchStop(Uint16List runs, double globalModuleWidth) {
    if (runs.length != 7) return false;

    // Stop pattern is 13 modules, calculate local module width
    final total = runs.reduce((a, b) => a + b);
    final localModuleWidth = total / 13.0;

    final modules = Uint16List.fromList(
      runs.map((r) => (r / localModuleWidth).round()).toList(),
    );
    return _patternError(modules, _stopPattern) == 0; // Exact match only
  }

  String _decodeValue(int code, int codeSet) {
    if (codeSet == 2) {
      // Code C: pairs of digits
      if (code < 100) {
        return code.toString().padLeft(2, '0');
      }
    } else if (codeSet == 1) {
      // Code B: ASCII 32-127
      if (code < 96) {
        return String.fromCharCode(code + 32);
      }
    } else {
      // Code A: ASCII 0-95
      if (code < 64) {
        return String.fromCharCode(code + 32);
      } else if (code < 96) {
        return String.fromCharCode(code - 64);
      }
    }
    return '';
  }

  /// Finds the target code set if the code is a switch code.
  /// Returns null if not a switch code.
  /// Public for unit testing verification of logic.
  int? findCodeSetSwitch(int code) {
    if (code == 99) return 2; // Switch to C
    if (code == 100) return 1; // Switch to B
    if (code == 101) return 0; // Switch to A
    return null;
  }
}
