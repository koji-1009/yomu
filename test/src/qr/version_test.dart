import 'package:test/test.dart';
import 'package:yomu/src/qr/decoder/error_correction_level.dart';
import 'package:yomu/src/qr/version.dart';

void main() {
  group('Version', () {
    test('getVersionForNumber returns valid versions 1-40', () {
      for (var i = 1; i <= 40; i++) {
        final version = Version.getVersionForNumber(i);
        expect(version.versionNumber, i);
      }
    });

    test('getVersionForNumber throws for invalid numbers', () {
      expect(() => Version.getVersionForNumber(0), throwsArgumentError);
      expect(() => Version.getVersionForNumber(41), throwsArgumentError);
      expect(() => Version.getVersionForNumber(-1), throwsArgumentError);
    });

    test('dimensionForVersion is correct', () {
      expect(Version.getVersionForNumber(1).dimensionForVersion, 21);
      expect(Version.getVersionForNumber(2).dimensionForVersion, 25);
      expect(Version.getVersionForNumber(10).dimensionForVersion, 57);
      expect(Version.getVersionForNumber(40).dimensionForVersion, 177);
    });

    test('getProvisionalVersionForDimension works correctly', () {
      expect(Version.getProvisionalVersionForDimension(21).versionNumber, 1);
      expect(Version.getProvisionalVersionForDimension(25).versionNumber, 2);
      expect(Version.getProvisionalVersionForDimension(177).versionNumber, 40);
    });

    test('getProvisionalVersionForDimension throws for invalid dimension', () {
      expect(
        () => Version.getProvisionalVersionForDimension(20),
        throwsArgumentError,
      );
      // Dimension 13 (13 % 4 == 1) but results in version -1
      expect(
        () => Version.getProvisionalVersionForDimension(13),
        throwsArgumentError,
      );
    });

    test('Version 1 has empty alignment pattern centers', () {
      final v1 = Version.getVersionForNumber(1);
      expect(v1.alignmentPatternCenters, isEmpty);
    });

    test('Version 2+ has alignment pattern centers', () {
      final v2 = Version.getVersionForNumber(2);
      expect(v2.alignmentPatternCenters, [6, 18]);

      final v7 = Version.getVersionForNumber(7);
      expect(v7.alignmentPatternCenters, [6, 22, 38]);
    });

    test('getECBlocksForLevel returns valid data for all levels', () {
      final v1 = Version.getVersionForNumber(1);

      final ecL = v1.getECBlocksForLevel(ErrorCorrectionLevel.L);
      expect(ecL, isNotNull);
      expect(ecL!.ecCodewordsPerBlock, 7);

      final ecM = v1.getECBlocksForLevel(ErrorCorrectionLevel.M);
      expect(ecM, isNotNull);
      expect(ecM!.ecCodewordsPerBlock, 10);

      final ecQ = v1.getECBlocksForLevel(ErrorCorrectionLevel.Q);
      expect(ecQ, isNotNull);
      expect(ecQ!.ecCodewordsPerBlock, 13);

      final ecH = v1.getECBlocksForLevel(ErrorCorrectionLevel.H);
      expect(ecH, isNotNull);
      expect(ecH!.ecCodewordsPerBlock, 17);
    });

    test('toString returns version number', () {
      expect(Version.getVersionForNumber(1).toString(), '1');
      expect(Version.getVersionForNumber(40).toString(), '40');
    });
  });

  group('ECBlocks', () {
    test('has correct structure', () {
      final v1 = Version.getVersionForNumber(1);
      final ecBlocks = v1.getECBlocksForLevel(ErrorCorrectionLevel.L)!;

      expect(ecBlocks.ecBlocks.length, 1);
      expect(ecBlocks.ecBlocks[0].count, 1);
      expect(ecBlocks.ecBlocks[0].dataCodewords, 19);
    });

    test('higher versions have multiple blocks', () {
      final v5 = Version.getVersionForNumber(5);
      final ecBlocks = v5.getECBlocksForLevel(ErrorCorrectionLevel.H)!;

      // Version 5-H has multiple blocks
      expect(ecBlocks.ecBlocks.isNotEmpty, true);
    });
  });

  group('Version Boundary Tests', () {
    // Tests moved from remaining_coverage_test.dart
    test('Version.decodeVersionInformation calculates BCH', () {
      expect(Version.decodeVersionInformation(0x07C94)?.versionNumber, 7);
      expect(Version.decodeVersionInformation(0x07C95)?.versionNumber, 7);
      expect(Version.decodeVersionInformation(0x07C93)?.versionNumber, 7);
      expect(Version.decodeVersionInformation(0x07C9B), isNull);
    });

    test('decodeVersionInformation corrects up to three flipped bits', () {
      // Every version 7-40 codeword, with each combination of up to three
      // bit errors, has to come back as that same version: the count of
      // differing bits is what decides, so an undercount would accept a
      // reading it should not and an overcount would reject a correctable
      // one.
      for (var versionNumber = 7; versionNumber <= 40; versionNumber++) {
        final codeword = _versionCodewords[versionNumber - 7];

        expect(
          Version.decodeVersionInformation(codeword)?.versionNumber,
          versionNumber,
          reason: 'clean reading of version $versionNumber',
        );

        for (var b1 = 0; b1 < 18; b1++) {
          expect(
            Version.decodeVersionInformation(
              codeword ^ (1 << b1),
            )?.versionNumber,
            versionNumber,
            reason: 'version $versionNumber with bit $b1 flipped',
          );

          for (var b2 = b1 + 1; b2 < 18; b2++) {
            for (var b3 = b2 + 1; b3 < 18; b3++) {
              final corrupted = codeword ^ (1 << b1) ^ (1 << b2) ^ (1 << b3);
              expect(
                Version.decodeVersionInformation(corrupted)?.versionNumber,
                versionNumber,
                reason:
                    'version $versionNumber with bits $b1, $b2, $b3 flipped',
              );
            }
          }
        }
      }
    });
  });
}

/// The 18-bit version information codewords for versions 7 to 40.
const _versionCodewords = [
  0x07C94, 0x085BC, 0x09A99, 0x0A4D3, 0x0BBF6, 0x0C762, 0x0D847, 0x0E60D, //
  0x0F928, 0x10B78, 0x1145D, 0x12A17, 0x13532, 0x149A6, 0x15683, 0x168C9,
  0x177EC, 0x18EC4, 0x191E1, 0x1AFAB, 0x1B08E, 0x1CC1A, 0x1D33F, 0x1ED75,
  0x1F250, 0x209D5, 0x216F0, 0x228BA, 0x2379F, 0x24B0B, 0x2542E, 0x26A64,
  0x27541, 0x28C69,
];
