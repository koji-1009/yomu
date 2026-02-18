import 'dart:typed_data';

import '../../common/bit_matrix.dart';
import '../../yomu_exception.dart';
import '../version.dart';
import 'data_mask.dart';
import 'decoded_bit_stream_parser.dart';
import 'format_information.dart';
import 'generic_gf.dart';
import 'reed_solomon_decoder.dart';

class QRCodeDecoder {
  const QRCodeDecoder();

  static const _rsDecoder = ReedSolomonDecoder(GenericGF.qrCodeField256);

  static final Map<int, BitMatrix> _maskCache = {};

  static BitMatrix _getFunctionPatternMask(Version version) {
    final dimension = version.dimensionForVersion;
    final cached = _maskCache[dimension];
    if (cached != null) return cached;

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
        else if (version.versionNumber >= 7 &&
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

    _maskCache[dimension] = mask;
    return mask;
  }

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

  static final Uint8List _codewordsBuffer = Uint8List(3706);

  Uint8List readCodewords({required Version version}) {
    final mask = QRCodeDecoder._getFunctionPatternMask(version);
    final result = _codewordsBuffer;
    var resultOffset = 0;

    var col = dimension - 1;
    var upward = true;

    var currentByte = 0;
    var bitsRead = 0;

    while (col > 0) {
      if (col == 6) col--;

      for (var i = 0; i < dimension; i++) {
        final r = upward ? dimension - 1 - i : i;

        for (var c = 0; c < 2; c++) {
          final xx = col - c;
          if (!mask.get(xx, r)) {
            bitsRead++;
            currentByte = (currentByte << 1) | (bits.get(xx, r) ? 1 : 0);
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
