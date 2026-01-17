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

    test('totalCodewords is consistent across versions', () {
      // Version 1: 26 total codewords
      final v1 = Version.getVersionForNumber(1);
      expect(v1.totalCodewords, 26);

      // Version 2: 44 total codewords
      final v2 = Version.getVersionForNumber(2);
      expect(v2.totalCodewords, 44);
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
}
