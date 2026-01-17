import 'decoder/error_correction_level.dart';

class ECB {
  const ECB(this.count, this.dataCodewords);

  final int count;
  final int dataCodewords;
}

class ECBlocks {
  const ECBlocks(this.ecCodewordsPerBlock, this.ecBlocks);

  final int ecCodewordsPerBlock;
  final List<ECB> ecBlocks;
}

class Version {
  const Version(
    this.versionNumber,
    this.alignmentPatternCenters,
    this._ecBlocks,
  );

  final int versionNumber;
  final List<int> alignmentPatternCenters;
  final Map<ErrorCorrectionLevel, ECBlocks> _ecBlocks;

  int get totalCodewords {
    // Calculate total codewords from one of the EC levels (e.g. L)
    // Total = Data Codewords + EC Codewords * NumBlocks
    final ecb = _ecBlocks[ErrorCorrectionLevel.L]!;
    var total = 0;
    for (final block in ecb.ecBlocks) {
      total += block.count * (block.dataCodewords + ecb.ecCodewordsPerBlock);
    }
    return total;
  }

  int get dimensionForVersion => 17 + 4 * versionNumber;

  ECBlocks? getECBlocksForLevel(ErrorCorrectionLevel ecLevel) {
    return _ecBlocks[ecLevel];
  }

  static Version getVersionForNumber(int versionNumber) {
    if (versionNumber < 1 || versionNumber > 40) {
      throw ArgumentError.value(versionNumber, 'versionNumber');
    }
    return _versions[versionNumber - 1];
  }

  /// Decodes version information bits to a Version object.
  ///
  /// Version information is an 18-bit BCH(18,6) code with 12 error
  /// correction bits. This method attempts to decode and error-correct
  /// the version number.
  /// Public for unit testing.
  static Version? decodeVersionInformation(int versionBits) {
    // Version info lookup table (version 7-40)
    // Each entry is the 18-bit encoded value for that version
    const versionDecodeInfo = <int>[
      0x07C94, 0x085BC, 0x09A99, 0x0A4D3, 0x0BBF6, 0x0C762, 0x0D847, 0x0E60D, //
      0x0F928, 0x10B78, 0x1145D, 0x12A17, 0x13532, 0x149A6, 0x15683, 0x168C9,
      0x177EC, 0x18EC4, 0x191E1, 0x1AFAB, 0x1B08E, 0x1CC1A, 0x1D33F, 0x1ED75,
      0x1F250, 0x209D5, 0x216F0, 0x228BA, 0x2379F, 0x24B0B, 0x2542E, 0x26A64,
      0x27541, 0x28C69,
    ];

    var bestDifference = 32;
    var bestVersion = 0;

    for (var i = 0; i < versionDecodeInfo.length; i++) {
      final targetInfo = versionDecodeInfo[i];
      if (targetInfo == versionBits) {
        return Version.getVersionForNumber(i + 7);
      }

      // Count bit differences (Hamming distance)
      final bitsDifference = _countBitDifference(versionBits, targetInfo);
      if (bitsDifference < bestDifference) {
        bestVersion = i + 7;
        bestDifference = bitsDifference;
      }
    }

    // Accept if 3 or fewer bit errors (BCH can correct up to 3)
    if (bestDifference <= 3) {
      return Version.getVersionForNumber(bestVersion);
    }

    return null;
  }

  /// Counts the number of differing bits between two integers.
  static int _countBitDifference(int a, int b) {
    var diff = a ^ b;
    var count = 0;
    while (diff != 0) {
      count += diff & 1;
      diff >>= 1;
    }
    return count;
  }

  static Version getProvisionalVersionForDimension(int dimension) {
    if (dimension % 4 != 1) throw ArgumentError();
    try {
      return getVersionForNumber((dimension - 17) ~/ 4);
    } catch (_) {
      throw ArgumentError();
    }
  }

  static const List<Version> _versions = [
    Version(1, [], {
      ErrorCorrectionLevel.L: ECBlocks(7, [ECB(1, 19)]),
      ErrorCorrectionLevel.M: ECBlocks(10, [ECB(1, 16)]),
      ErrorCorrectionLevel.Q: ECBlocks(13, [ECB(1, 13)]),
      ErrorCorrectionLevel.H: ECBlocks(17, [ECB(1, 9)]),
    }),
    Version(
      2,
      [6, 18],
      {
        ErrorCorrectionLevel.L: ECBlocks(10, [ECB(1, 34)]),
        ErrorCorrectionLevel.M: ECBlocks(16, [ECB(1, 28)]),
        ErrorCorrectionLevel.Q: ECBlocks(22, [ECB(1, 22)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(1, 16)]),
      },
    ),
    Version(
      3,
      [6, 22],
      {
        ErrorCorrectionLevel.L: ECBlocks(15, [ECB(1, 55)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(1, 44)]),
        ErrorCorrectionLevel.Q: ECBlocks(18, [ECB(2, 17)]),
        ErrorCorrectionLevel.H: ECBlocks(22, [ECB(2, 13)]),
      },
    ),
    Version(
      4,
      [6, 26],
      {
        ErrorCorrectionLevel.L: ECBlocks(20, [ECB(1, 80)]),
        ErrorCorrectionLevel.M: ECBlocks(18, [ECB(2, 32)]),
        ErrorCorrectionLevel.Q: ECBlocks(26, [ECB(2, 24)]),
        ErrorCorrectionLevel.H: ECBlocks(16, [ECB(4, 9)]),
      },
    ),
    Version(
      5,
      [6, 30],
      {
        ErrorCorrectionLevel.L: ECBlocks(26, [ECB(1, 108)]),
        ErrorCorrectionLevel.M: ECBlocks(24, [ECB(2, 43)]),
        ErrorCorrectionLevel.Q: ECBlocks(18, [ECB(2, 15), ECB(2, 16)]),
        ErrorCorrectionLevel.H: ECBlocks(22, [ECB(2, 11), ECB(2, 12)]),
      },
    ),
    Version(
      6,
      [6, 34],
      {
        ErrorCorrectionLevel.L: ECBlocks(18, [ECB(2, 68)]),
        ErrorCorrectionLevel.M: ECBlocks(16, [ECB(4, 27)]),
        ErrorCorrectionLevel.Q: ECBlocks(24, [ECB(4, 19)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(4, 15)]),
      },
    ),
    Version(
      7,
      [6, 22, 38],
      {
        ErrorCorrectionLevel.L: ECBlocks(20, [ECB(2, 78)]),
        ErrorCorrectionLevel.M: ECBlocks(18, [ECB(4, 31)]),
        ErrorCorrectionLevel.Q: ECBlocks(18, [ECB(2, 14), ECB(4, 15)]),
        ErrorCorrectionLevel.H: ECBlocks(26, [ECB(4, 13), ECB(1, 14)]),
      },
    ),
    Version(
      8,
      [6, 24, 42],
      {
        ErrorCorrectionLevel.L: ECBlocks(24, [ECB(2, 97)]),
        ErrorCorrectionLevel.M: ECBlocks(22, [ECB(2, 38), ECB(2, 39)]),
        ErrorCorrectionLevel.Q: ECBlocks(22, [ECB(4, 18), ECB(2, 19)]),
        ErrorCorrectionLevel.H: ECBlocks(26, [ECB(4, 14), ECB(2, 15)]),
      },
    ),
    Version(
      9,
      [6, 26, 46],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(2, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(22, [ECB(3, 36), ECB(2, 37)]),
        ErrorCorrectionLevel.Q: ECBlocks(20, [ECB(4, 16), ECB(4, 17)]),
        ErrorCorrectionLevel.H: ECBlocks(24, [ECB(4, 12), ECB(4, 13)]),
      },
    ),
    Version(
      10,
      [6, 28, 50],
      {
        ErrorCorrectionLevel.L: ECBlocks(18, [ECB(2, 68), ECB(2, 69)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(4, 43), ECB(1, 44)]),
        ErrorCorrectionLevel.Q: ECBlocks(24, [ECB(6, 19), ECB(2, 20)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(6, 15), ECB(2, 16)]),
      },
    ),
    Version(
      11,
      [6, 30, 54],
      {
        ErrorCorrectionLevel.L: ECBlocks(20, [ECB(4, 81)]),
        ErrorCorrectionLevel.M: ECBlocks(30, [ECB(1, 50), ECB(4, 51)]),
        ErrorCorrectionLevel.Q: ECBlocks(28, [ECB(4, 22), ECB(4, 23)]),
        ErrorCorrectionLevel.H: ECBlocks(24, [ECB(3, 12), ECB(8, 13)]),
      },
    ),
    Version(
      12,
      [6, 32, 58],
      {
        ErrorCorrectionLevel.L: ECBlocks(24, [ECB(2, 92), ECB(2, 93)]),
        ErrorCorrectionLevel.M: ECBlocks(22, [ECB(6, 36), ECB(2, 37)]),
        ErrorCorrectionLevel.Q: ECBlocks(26, [ECB(4, 20), ECB(6, 21)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(7, 14), ECB(4, 15)]),
      },
    ),
    Version(
      13,
      [6, 34, 62],
      {
        ErrorCorrectionLevel.L: ECBlocks(26, [ECB(4, 107)]),
        ErrorCorrectionLevel.M: ECBlocks(22, [ECB(8, 37), ECB(1, 38)]),
        ErrorCorrectionLevel.Q: ECBlocks(24, [ECB(8, 20), ECB(4, 21)]),
        ErrorCorrectionLevel.H: ECBlocks(22, [ECB(12, 11), ECB(4, 12)]),
      },
    ),
    Version(
      14,
      [6, 26, 46, 66],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(3, 115), ECB(1, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(24, [ECB(4, 40), ECB(5, 41)]),
        ErrorCorrectionLevel.Q: ECBlocks(20, [ECB(11, 16), ECB(5, 17)]),
        ErrorCorrectionLevel.H: ECBlocks(24, [ECB(11, 12), ECB(5, 13)]),
      },
    ),
    Version(
      15,
      [6, 26, 48, 70],
      {
        ErrorCorrectionLevel.L: ECBlocks(22, [ECB(5, 87), ECB(1, 88)]),
        ErrorCorrectionLevel.M: ECBlocks(24, [ECB(5, 41), ECB(5, 42)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(5, 24), ECB(7, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(24, [ECB(11, 12), ECB(7, 13)]),
      },
    ),
    Version(
      16,
      [6, 26, 50, 74],
      {
        ErrorCorrectionLevel.L: ECBlocks(24, [ECB(5, 98), ECB(1, 99)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(7, 45), ECB(3, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(24, [ECB(15, 19), ECB(2, 20)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(3, 15), ECB(13, 16)]),
      },
    ),
    Version(
      17,
      [6, 30, 54, 78],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(1, 107), ECB(5, 108)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(10, 46), ECB(1, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(28, [ECB(1, 22), ECB(15, 23)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(2, 14), ECB(17, 15)]),
      },
    ),
    Version(
      18,
      [6, 30, 56, 82],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(5, 120), ECB(1, 121)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(9, 43), ECB(4, 44)]),
        ErrorCorrectionLevel.Q: ECBlocks(28, [ECB(17, 22), ECB(1, 23)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(2, 14), ECB(19, 15)]),
      },
    ),
    Version(
      19,
      [6, 30, 58, 86],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(3, 113), ECB(4, 114)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(3, 44), ECB(11, 45)]),
        ErrorCorrectionLevel.Q: ECBlocks(26, [ECB(17, 21), ECB(4, 22)]),
        ErrorCorrectionLevel.H: ECBlocks(26, [ECB(9, 13), ECB(16, 14)]),
      },
    ),
    Version(
      20,
      [6, 34, 62, 90],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(3, 107), ECB(5, 108)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(3, 41), ECB(13, 42)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(15, 24), ECB(5, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(28, [ECB(15, 15), ECB(10, 16)]),
      },
    ),
    Version(
      21,
      [6, 28, 50, 72, 94],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(4, 116), ECB(4, 117)]),
        ErrorCorrectionLevel.M: ECBlocks(26, [ECB(17, 42)]),
        ErrorCorrectionLevel.Q: ECBlocks(28, [ECB(17, 22), ECB(6, 23)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(19, 16), ECB(6, 17)]),
      },
    ),
    Version(
      22,
      [6, 26, 50, 74, 98],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(2, 111), ECB(7, 112)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(17, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(7, 24), ECB(16, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(24, [ECB(34, 13)]),
      },
    ),
    Version(
      23,
      [6, 30, 54, 78, 102],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(4, 121), ECB(5, 122)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(4, 47), ECB(14, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(11, 24), ECB(14, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(16, 15), ECB(14, 16)]),
      },
    ),
    Version(
      24,
      [6, 28, 54, 80, 106],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(6, 117), ECB(4, 118)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(6, 45), ECB(14, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(11, 24), ECB(16, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(30, 16), ECB(2, 17)]),
      },
    ),
    Version(
      25,
      [6, 32, 58, 84, 110],
      {
        ErrorCorrectionLevel.L: ECBlocks(26, [ECB(8, 106), ECB(4, 107)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(8, 47), ECB(13, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(7, 24), ECB(22, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(22, 15), ECB(13, 16)]),
      },
    ),
    Version(
      26,
      [6, 30, 58, 86, 114],
      {
        ErrorCorrectionLevel.L: ECBlocks(28, [ECB(10, 114), ECB(2, 115)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(19, 46), ECB(4, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(28, [ECB(28, 22), ECB(6, 23)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(33, 16), ECB(4, 17)]),
      },
    ),
    Version(
      27,
      [6, 34, 62, 90, 118],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(8, 122), ECB(4, 123)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(22, 45), ECB(3, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(8, 23), ECB(26, 24)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(12, 15), ECB(28, 16)]),
      },
    ),
    Version(
      28,
      [6, 26, 50, 74, 98, 122],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(3, 117), ECB(10, 118)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(3, 45), ECB(23, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(4, 24), ECB(31, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(11, 15), ECB(31, 16)]),
      },
    ),
    Version(
      29,
      [6, 30, 54, 78, 102, 126],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(7, 116), ECB(7, 117)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(21, 45), ECB(7, 46)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(1, 23), ECB(37, 24)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(19, 15), ECB(26, 16)]),
      },
    ),
    Version(
      30,
      [6, 26, 52, 78, 104, 130],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(5, 115), ECB(10, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(19, 47), ECB(10, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(15, 24), ECB(25, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(23, 15), ECB(25, 16)]),
      },
    ),

    Version(
      31,
      [6, 30, 56, 82, 108, 134],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(13, 115), ECB(3, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(2, 46), ECB(29, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(42, 24), ECB(1, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(23, 15), ECB(28, 16)]),
      },
    ),
    Version(
      32,
      [6, 34, 60, 86, 112, 138],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(17, 115)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(10, 46), ECB(23, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(10, 24), ECB(35, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(19, 15), ECB(35, 16)]),
      },
    ),
    Version(
      33,
      [6, 30, 58, 86, 114, 142],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(17, 115), ECB(1, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(14, 46), ECB(21, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(29, 24), ECB(19, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(11, 15), ECB(46, 16)]),
      },
    ),
    Version(
      34,
      [6, 34, 62, 90, 118, 146],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(13, 115), ECB(6, 116)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(14, 46), ECB(23, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(44, 24), ECB(7, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(59, 16), ECB(1, 17)]),
      },
    ),
    Version(
      35,
      [6, 30, 54, 78, 102, 126, 150],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(12, 121), ECB(7, 122)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(12, 47), ECB(26, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(39, 24), ECB(14, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(22, 15), ECB(41, 16)]),
      },
    ),
    Version(
      36,
      [6, 24, 50, 76, 102, 128, 154],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(6, 121), ECB(14, 122)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(6, 47), ECB(34, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(46, 24), ECB(10, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(2, 15), ECB(64, 16)]),
      },
    ),
    Version(
      37,
      [6, 28, 54, 80, 106, 132, 158],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(17, 122), ECB(4, 123)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(29, 46), ECB(14, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(49, 24), ECB(10, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(24, 15), ECB(46, 16)]),
      },
    ),
    Version(
      38,
      [6, 32, 58, 84, 110, 136, 162],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(4, 122), ECB(18, 123)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(13, 46), ECB(32, 47)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(48, 24), ECB(14, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(42, 15), ECB(32, 16)]),
      },
    ),
    Version(
      39,
      [6, 26, 52, 78, 104, 130, 156, 182],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(20, 117), ECB(4, 118)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(40, 47), ECB(7, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(43, 24), ECB(22, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(10, 15), ECB(67, 16)]),
      },
    ),
    Version(
      40,
      [6, 30, 58, 86, 114, 142, 170, 198],
      {
        ErrorCorrectionLevel.L: ECBlocks(30, [ECB(19, 127), ECB(6, 128)]),
        ErrorCorrectionLevel.M: ECBlocks(28, [ECB(18, 47), ECB(31, 48)]),
        ErrorCorrectionLevel.Q: ECBlocks(30, [ECB(34, 24), ECB(34, 25)]),
        ErrorCorrectionLevel.H: ECBlocks(30, [ECB(20, 15), ECB(61, 16)]),
      },
    ),
  ];

  @override
  String toString() => '$versionNumber';
}
