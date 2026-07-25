import 'dart:typed_data';

import 'error_correction_level.dart';

/// Holds the error correction level and data mask pattern decoded from
/// a QR code's format information bits.
class FormatInformation {
  const FormatInformation(this.errorCorrectionLevel, this.dataMask);

  /// The 15-bit codeword for each of the 32 format information values, so
  /// that `_decodeLookup[v]` is the encoding of value `v`.
  static const List<int> _decodeLookup = [
    0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0, //
    0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976,
    0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B,
    0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED,
  ];

  /// Largest value the codewords occupy, and the size of [_lut].
  static const int _maxFormatInfo = 0x7FFF;

  final ErrorCorrectionLevel errorCorrectionLevel;
  final int dataMask;

  /// Decodes format information from two 15-bit readings.
  ///
  /// Tries both raw and XOR-unmasked values, returning the best match
  /// within Hamming distance 3 of a known format info codeword.
  static FormatInformation? decodeFormatInformation(
    int maskedFormatInfo1,
    int maskedFormatInfo2,
  ) {
    final formatInfo = _doDecodeFormatInformation(
      maskedFormatInfo1,
      maskedFormatInfo2,
    );

    if (formatInfo != null) {
      return formatInfo;
    }
    return _doDecodeFormatInformation(
      maskedFormatInfo1 ^ 0x5412,
      maskedFormatInfo2 ^ 0x5412,
    );
  }

  static FormatInformation? _doDecodeFormatInformation(
    int maskedFormatInfo1,
    int maskedFormatInfo2,
  ) {
    final (value1, difference1) = _nearestCodeword(maskedFormatInfo1);
    final (value2, difference2) = _nearestCodeword(maskedFormatInfo2);

    // The first reading wins ties, matching the order the two were
    // searched in before.
    final bestDifference = difference1 <= difference2
        ? difference1
        : difference2;
    final bestFormatInfo = difference1 <= difference2 ? value1 : value2;

    // Hamming distance check
    if (bestDifference <= 3) {
      return FormatInformation(
        ErrorCorrectionLevel.forBits((bestFormatInfo >> 3) & 0x03),
        bestFormatInfo & 0x07,
      );
    }
    return null;
  }

  /// Returns the format information value nearest to [maskedFormatInfo] and
  /// its Hamming distance, or a distance of 32 when nothing lies within the
  /// three bits the code can correct.
  static (int, int) _nearestCodeword(int maskedFormatInfo) {
    if (maskedFormatInfo >= 0 && maskedFormatInfo <= _maxFormatInfo) {
      final entry = (_lut ??= _buildLut())[maskedFormatInfo];
      return entry < 0 ? (0, 32) : (entry & 0x1F, entry >> 5);
    }

    // Wider than a format information reading can be, so the table does not
    // cover it; fall back to the search it replaced rather than truncating
    // the input and reporting a match that isn't one.
    var bestValue = 0;
    var bestDifference = 32;
    for (var value = 0; value < _decodeLookup.length; value++) {
      final difference = _numBitsDiffering(
        maskedFormatInfo,
        _decodeLookup[value],
      );
      if (difference < bestDifference) {
        bestValue = value;
        bestDifference = difference;
      }
    }
    return (bestValue, bestDifference);
  }

  /// Every 15-bit reading mapped to `value | (distance << 5)`, or -1 when no
  /// codeword lies within the three bits BCH(15,5) can correct.
  ///
  /// Built lazily on first use, once per isolate. Reading the answer costs a
  /// single load, where the search it replaces cost up to 32 rounds of
  /// [_numBitsDiffering] - and the retry ladder pays that per rejected
  /// bottom-right corner candidate, not once per decode.
  static Int8List? _lut;

  static Int8List _buildLut() {
    // The code has minimum distance 7, so the radius-3 balls around the
    // codewords are disjoint: every entry below is written exactly once and
    // no distance comparison is needed while filling them.
    final lut = Int8List(_maxFormatInfo + 1)
      ..fillRange(0, _maxFormatInfo + 1, -1);
    for (var value = 0; value < _decodeLookup.length; value++) {
      final codeword = _decodeLookup[value];
      lut[codeword] = value;
      for (var b1 = 0; b1 < 15; b1++) {
        final one = codeword ^ (1 << b1);
        lut[one] = value | (1 << 5);
        for (var b2 = b1 + 1; b2 < 15; b2++) {
          final two = one ^ (1 << b2);
          lut[two] = value | (2 << 5);
          for (var b3 = b2 + 1; b3 < 15; b3++) {
            lut[two ^ (1 << b3)] = value | (3 << 5);
          }
        }
      }
    }
    return lut;
  }

  static int _numBitsDiffering(int a, int b) {
    var aXorB = a ^ b;
    var count = 0;
    while (aXorB != 0) {
      count++;
      aXorB &= (aXorB - 1);
    }
    return count;
  }
}
