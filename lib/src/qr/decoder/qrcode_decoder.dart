import 'dart:typed_data';

import '../../common/bit_matrix.dart';
import '../../yomu_exception.dart';
import '../version.dart';
import 'data_mask.dart';
import 'decoded_bit_stream_parser.dart';
import 'format_information.dart';
import 'generic_gf.dart';
import 'reed_solomon_decoder.dart';

/// Decodes a QR code from a [BitMatrix] of black/white modules.
///
/// Handles format information parsing, version detection, data unmasking,
/// codeword extraction, Reed-Solomon error correction, and data stream decoding.
/// Caches function pattern masks per version for efficiency.
class QRCodeDecoder {
  const QRCodeDecoder();

  static const _rsDecoder = ReedSolomonDecoder(GenericGF.qrCodeField256);

  /// Fixed-size cache for function pattern masks, indexed by version number.
  /// QR versions range from 1 to 40, so index 0 is unused.
  static final List<BitMatrix?> _maskCache = List<BitMatrix?>.filled(41, null);

  static BitMatrix _getFunctionPatternMask(Version version) {
    final versionNumber = version.versionNumber;
    final cached = _maskCache[versionNumber];
    if (cached != null) return cached;

    final dimension = version.dimensionForVersion;
    final mask = BitMatrix(width: dimension);

    for (var y = 0; y < dimension; y++) {
      for (var x = 0; x < dimension; x++) {
        var isFunction = false;

        // Finder Patterns + Format Info
        if ((x < 9 && y < 9) ||
            (x > dimension - 9 && y < 9) ||
            (x < 9 && y > dimension - 9)) {
          isFunction = true;
        }
        // Timing Patterns
        else if (x == 6 || y == 6) {
          isFunction = true;
        }
        // Version Info (V7+)
        else if (versionNumber >= 7 &&
            ((x >= dimension - 11 && x <= dimension - 9 && y <= 5) ||
                (x <= 5 && y >= dimension - 11 && y <= dimension - 9))) {
          isFunction = true;
        }
        // Alignment Patterns (V2+)
        else {
          final centers = version.alignmentPatternCenters;
          if (centers.length >= 2) {
            for (final cx in centers) {
              for (final cy in centers) {
                if ((cx <= 8 && cy <= 8) ||
                    (cx <= 8 && cy >= dimension - 9) ||
                    (cx >= dimension - 9 && cy <= 8)) {
                  continue;
                }
                if ((x - cx).abs() <= 2 && (y - cy).abs() <= 2) {
                  isFunction = true;
                  break;
                }
              }
              if (isFunction) break;
            }
          }
        }

        if (isFunction) {
          mask.set(x, y);
        }
      }
    }

    _maskCache[versionNumber] = mask;
    return mask;
  }

  /// Decodes a QR code from the given [bits] matrix.
  ///
  /// Returns a [DecoderResult] containing the decoded text and raw bytes.
  /// Throws [DecodeException] if the QR code cannot be decoded.
  DecoderResult decode(BitMatrix bits) {
    try {
      return _decodeBody(bits);
    } catch (e) {
      if (e is YomuException) {
        rethrow;
      }
      throw DecodeException('Decoding failed: $e');
    }
  }

  DecoderResult _decodeBody(BitMatrix bits) {
    final parser = BitMatrixParser(bits);

    // Read Format Information
    final formatInfo = parser.readFormatInformation();
    if (formatInfo == null) {
      throw const DecodeException('Invalid format information');
    }

    // Read Version
    final version = parser.readVersion();

    // Unmask in-place to avoid clone allocation
    final dataMask = DataMask.values[formatInfo.dataMask];
    dataMask.unmaskBitMatrix(bits, version.dimensionForVersion);

    try {
      // Read Codewords
      final codewords = parser.readCodewords(version: version);

      // De-interleave and Error Correct
      final ecBlocks = version.getECBlocksForLevel(
        formatInfo.errorCorrectionLevel,
      );
      if (ecBlocks == null) {
        throw const DecodeException('Invalid version/ec-level combination');
      }

      // Calculate total blocks and data bytes
      var totalBlocks = 0;
      for (final ecb in ecBlocks.ecBlocks) {
        totalBlocks += ecb.count;
      }

      var totalDataBytes = 0;
      for (final ecb in ecBlocks.ecBlocks) {
        totalDataBytes += ecb.count * ecb.dataCodewords;
      }

      final resultBytes = Uint8List(totalDataBytes);

      // We use a flat buffer for block info to avoid _DataBlock object allocations
      final blockDataLengths = Int32List(totalBlocks);
      final blockEcLengths = Int32List(totalBlocks);

      var blockIdx = 0;
      for (final ecb in ecBlocks.ecBlocks) {
        for (var i = 0; i < ecb.count; i++) {
          blockDataLengths[blockIdx] = ecb.dataCodewords;
          blockEcLengths[blockIdx] = ecBlocks.ecCodewordsPerBlock;
          blockIdx++;
        }
      }

      // De-interleave Data Codewords
      final blocksData = List<Uint8List>.generate(
        totalBlocks,
        (i) => Uint8List(blockDataLengths[i]),
      );
      var rawOffset = 0;
      var maxDataLength = 0;
      for (final l in blockDataLengths) {
        if (l > maxDataLength) maxDataLength = l;
      }

      for (var i = 0; i < maxDataLength; i++) {
        for (var j = 0; j < totalBlocks; j++) {
          if (i < blockDataLengths[j]) {
            if (rawOffset < codewords.length) {
              blocksData[j][i] = codewords[rawOffset++];
            }
          }
        }
      }

      // De-interleave EC Codewords
      final blocksEc = List<Uint8List>.generate(
        totalBlocks,
        (i) => Uint8List(blockEcLengths[i]),
      );
      for (var i = 0; i < ecBlocks.ecCodewordsPerBlock; i++) {
        for (var j = 0; j < totalBlocks; j++) {
          if (rawOffset < codewords.length) {
            blocksEc[j][i] = codewords[rawOffset++];
          }
        }
      }

      // Correct Errors and collect resulting data bytes
      var outOffset = 0;
      // Pre-allocate correction buffer for reuse
      final codewordBuffer = Uint8List(
        maxDataLength + ecBlocks.ecCodewordsPerBlock,
      );

      for (var j = 0; j < totalBlocks; j++) {
        final dataLen = blockDataLengths[j];
        final ecLen = blockEcLengths[j];
        final totalLen = dataLen + ecLen;

        codewordBuffer.setRange(0, dataLen, blocksData[j]);
        codewordBuffer.setRange(dataLen, totalLen, blocksEc[j]);

        try {
          _rsDecoder.decode(received: codewordBuffer, twoS: ecLen);
        } catch (e) {
          throw DecodeException('RS error: $e');
        }

        // Copy back corrected data
        for (var i = 0; i < dataLen; i++) {
          resultBytes[outOffset++] = codewordBuffer[i];
        }
      }

      return DecodedBitStreamParser.decode(
        bytes: resultBytes,
        version: version,
      );
    } finally {
      // Restore original bit matrix (unmasking is XOR, so unmasking again masks it back)
      dataMask.unmaskBitMatrix(bits, version.dimensionForVersion);
    }
  }
}

/// Extracts format information, version, and data codewords from a QR code
/// [BitMatrix].
///
/// Reads the two format information regions and two version information
/// regions (for V7+), then traverses the matrix in the zigzag pattern
/// defined by the QR specification to extract raw codewords.
class BitMatrixParser {
  BitMatrixParser(this.bits) {
    dimension = bits.height;
  }
  final BitMatrix bits;
  late final int dimension;

  FormatInformation? readFormatInformation() {
    var formatInfo1 = 0;
    formatInfo1 = _copyBit(0, 8, formatInfo1);
    formatInfo1 = _copyBit(1, 8, formatInfo1);
    formatInfo1 = _copyBit(2, 8, formatInfo1);
    formatInfo1 = _copyBit(3, 8, formatInfo1);
    formatInfo1 = _copyBit(4, 8, formatInfo1);
    formatInfo1 = _copyBit(5, 8, formatInfo1);
    formatInfo1 = _copyBit(7, 8, formatInfo1); // Skip 6
    formatInfo1 = _copyBit(8, 8, formatInfo1);
    formatInfo1 = _copyBit(8, 7, formatInfo1);
    formatInfo1 = _copyBit(8, 5, formatInfo1); // Skip 6 (8,6)
    formatInfo1 = _copyBit(8, 4, formatInfo1);
    formatInfo1 = _copyBit(8, 3, formatInfo1);
    formatInfo1 = _copyBit(8, 2, formatInfo1);
    formatInfo1 = _copyBit(8, 1, formatInfo1);
    formatInfo1 = _copyBit(8, 0, formatInfo1);

    var formatInfo2 = 0;
    final dim = dimension;
    formatInfo2 = _copyBit(8, dim - 1, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 2, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 3, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 4, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 5, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 6, formatInfo2);
    formatInfo2 = _copyBit(8, dim - 7, formatInfo2);

    formatInfo2 = _copyBit(dim - 8, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 7, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 6, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 5, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 4, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 3, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 2, 8, formatInfo2);
    formatInfo2 = _copyBit(dim - 1, 8, formatInfo2);

    return FormatInformation.decodeFormatInformation(formatInfo1, formatInfo2);
  }

  /// Reads the QR code version from the matrix.
  ///
  /// For versions 1-6, the version is determined from the dimension.
  /// For versions 7+, the version is encoded in two 18-bit regions.
  Version readVersion() {
    if (dimension < 17) throw const DecodeException('Too small');

    final provisional = (dimension - 17) ~/ 4;
    if (provisional <= 6) {
      // Versions 1-6 don't have version information encoded
      return Version.getVersionForNumber(provisional);
    }

    // For versions 7+, read version info from the two regions
    // Region 1: Bottom-left of top-right finder pattern
    var versionBits1 = 0;
    for (var y = 5; y >= 0; y--) {
      for (var x = dimension - 9; x >= dimension - 11; x--) {
        versionBits1 = _copyBit(x, y, versionBits1);
      }
    }

    // Region 2: Top-right of bottom-left finder pattern
    var versionBits2 = 0;
    for (var x = 5; x >= 0; x--) {
      for (var y = dimension - 9; y >= dimension - 11; y--) {
        versionBits2 = _copyBit(x, y, versionBits2);
      }
    }

    // Decode version from the bits
    final decodedVersion = Version.decodeVersionInformation(versionBits1);
    if (decodedVersion != null) {
      return decodedVersion;
    }

    final decodedVersion2 = Version.decodeVersionInformation(versionBits2);
    if (decodedVersion2 != null) {
      return decodedVersion2;
    }

    // Fallback to provisional if decoding fails
    return Version.getVersionForNumber(provisional);
  }

  Uint8List readCodewords({required Version version}) {
    final mask = QRCodeDecoder._getFunctionPatternMask(version);
    // Allocate per-call to avoid shared mutable static state.
    // Upper bound: dimension^2 / 8 (slightly over actual codewords; short-lived).
    final dim = version.dimensionForVersion;
    final result = Uint8List((dim * dim) >> 3);
    var resultOffset = 0;

    // Direct bit array access for both mask and data matrices
    final maskBits = mask.bits;
    final maskStride = mask.rowStride;
    final dataBits = bits.bits;
    final dataStride = bits.rowStride;

    var col = dimension - 1;
    var upward = true;

    var currentByte = 0;
    var bitsRead = 0;

    while (col > 0) {
      if (col == 6) col--;

      for (var i = 0; i < dimension; i++) {
        final r = upward ? dimension - 1 - i : i;
        final maskRowOffset = r * maskStride;
        final dataRowOffset = r * dataStride;

        for (var c = 0; c < 2; c++) {
          final xx = col - c;
          final wordIdx = xx >> 5;
          final bitMask = 1 << (xx & 0x1f);

          // Inline mask.get(xx, r)
          if ((maskBits[maskRowOffset + wordIdx] & bitMask) == 0) {
            bitsRead++;
            // Inline bits.get(xx, r)
            final bitVal = (dataBits[dataRowOffset + wordIdx] & bitMask) != 0
                ? 1
                : 0;
            currentByte = (currentByte << 1) | bitVal;
            if (bitsRead == 8) {
              result[resultOffset++] = currentByte;
              currentByte = 0;
              bitsRead = 0;
            }
          }
        }
      }
      upward = !upward;
      col -= 2;
    }
    // Return a copy only once per QR code
    return result.sublist(0, resultOffset);
  }

  int _copyBit(int x, int y, int versionBits) {
    final bit = bits.get(x, y);
    return (versionBits << 1) | (bit ? 1 : 0);
  }
}
