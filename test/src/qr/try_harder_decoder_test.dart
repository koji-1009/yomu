import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';
import 'package:yomu/src/qr/detector/finder_pattern.dart';
import 'package:yomu/src/qr/detector/finder_pattern_finder.dart';
import 'package:yomu/src/qr/try_harder_decoder.dart';
import 'package:yomu/src/yomu_exception.dart';

import 'finder_pattern_helper.dart';

(LuminanceSource, BitMatrix) _loadFixture(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final converted = image.convert(format: img.Format.uint8, numChannels: 4);
  final gray = rgbaToGrayscale(
    converted.buffer.asUint8List(),
    image.width,
    image.height,
  );
  final source = LuminanceSource(
    width: image.width,
    height: image.height,
    luminances: gray,
  );
  return (source, Binarizer(source).getBlackMatrix());
}

FinderPattern _pattern(double x, double y, double size) =>
    FinderPattern(x: x, y: y, estimatedModuleSize: size);

void main() {
  // Instances are stateful (grid dedup + work budget), so each call site
  // creates a fresh one.
  TryHarderDecoder decoder() => TryHarderDecoder();

  group('TryHarderDecoder.decodeWithFinderInfo', () {
    test('rescues a perspective-distorted code (corner grid search)', () {
      final (_, matrix) = _loadFixture(
        'fixtures/distorted_images/perspective_y_0.2.png',
      );
      final finder = FinderPatternFinder(matrix);
      final info = finder.find();
      expect(finder.possibleCenters.length, greaterThanOrEqualTo(3));

      // The fast path fails on this image: the dimension is misestimated
      // and the parallelogram corner assumption does not hold.
      final detector = Detector(matrix, alignmentAreaAllowance: 15);
      expect(
        () => const QRCodeDecoder().decode(
          detector.processFinderPatternInfo(info).bits,
        ),
        throwsA(isA<YomuException>()),
      );

      final result = decoder().decodeWithFinderInfo(matrix, info);
      expect(result, isNotNull);
      expect(result!.text, 'Hello World');
    });

    test('returns null for degenerate patterns (zero top distance)', () {
      final matrix = BitMatrix(width: 50);
      final info = FinderPatternInfo(
        topLeft: _pattern(10, 10, 3),
        topRight: _pattern(10, 10, 3),
        bottomLeft: _pattern(10, 40, 3),
      );
      expect(decoder().decodeWithFinderInfo(matrix, info), isNull);
    });

    test('returns null for non-finite coordinates', () {
      final matrix = BitMatrix(width: 50);
      final info = FinderPatternInfo(
        topLeft: _pattern(double.nan, 10, 3),
        topRight: _pattern(40, 10, 3),
        bottomLeft: _pattern(10, 40, 3),
      );
      expect(decoder().decodeWithFinderInfo(matrix, info), isNull);
    });

    test('returns null for a sub-pixel module size', () {
      final matrix = BitMatrix(width: 50);
      final info = FinderPatternInfo(
        topLeft: _pattern(10, 10, 0.4),
        topRight: _pattern(40, 10, 0.4),
        bottomLeft: _pattern(10, 40, 0.4),
      );
      expect(decoder().decodeWithFinderInfo(matrix, info), isNull);
    });

    test('returns null when all dimension candidates are out of range', () {
      final matrix = BitMatrix(width: 50);
      // dist 10 / module 1 -> dim 17: candidates 17, 13, 21 - only 21
      // valid, but the matrix has no decodable content.
      final tooSmall = FinderPatternInfo(
        topLeft: _pattern(10, 10, 2),
        topRight: _pattern(14, 10, 2),
        bottomLeft: _pattern(10, 14, 2),
      );
      expect(decoder().decodeWithFinderInfo(matrix, tooSmall), isNull);

      // dist 2000 / module 1 -> dim far above 177 for all candidates.
      final tooLarge = FinderPatternInfo(
        topLeft: _pattern(0, 0, 1),
        topRight: _pattern(2000, 0, 1),
        bottomLeft: _pattern(0, 2000, 1),
      );
      expect(decoder().decodeWithFinderInfo(matrix, tooLarge), isNull);
    });

    test('returns null when the bottom-right estimate is non-finite', () {
      final matrix = BitMatrix(width: 50);
      final info = FinderPatternInfo(
        topLeft: _pattern(10, 10, 3),
        topRight: _pattern(40, 10, 3),
        bottomLeft: _pattern(double.infinity, 40, 3),
      );
      expect(decoder().decodeWithFinderInfo(matrix, info), isNull);
    });
  });

  group('TryHarderDecoder.decodeDeep', () {
    test('rescues salt & pepper noise via despeckle', () {
      final (_, matrix) = _loadFixture(
        'fixtures/distorted_images/damaged_noise_0.05.png',
      );
      final result = decoder().decodeDeep(matrix);
      expect(result, isNotNull);
      expect(result!.text, 'Hello World');
    });

    test('rescues strong perspective via the tolerant finder', () {
      final (_, matrix) = _loadFixture(
        'fixtures/distorted_images/perspective_y_0.3.png',
      );
      final result = decoder().decodeDeep(matrix);
      expect(result, isNotNull);
      expect(result!.text, 'Hello World');
    });

    test('rescues gray dirt occlusion', () {
      final (_, matrix) = _loadFixture(
        'fixtures/distorted_images/damaged_dirt_0.30.png',
      );
      final result = decoder().decodeDeep(matrix);
      expect(result, isNotNull);
      expect(result!.text, 'Hello World');
    });

    test('returns null when every stage fails', () {
      const width = 100;
      final luminances = Uint8List(width * width);
      for (var i = 0; i < luminances.length; i++) {
        luminances[i] = (i * 31) & 0xFF;
      }
      final source = LuminanceSource(
        width: width,
        height: width,
        luminances: luminances,
      );
      final matrix = Binarizer(source).getBlackMatrix();

      expect(decoder().decodeDeep(matrix), isNull);
    });

    test('returns null when finder patterns exist but contain no data', () {
      // Three valid finder patterns with an empty data area: the tolerant
      // triplet enumeration runs, every decode attempt fails.
      const width = 210;
      final matrix = BitMatrix(width: width);
      drawFinderPattern(matrix, 10, 10, moduleSize: 10);
      drawFinderPattern(matrix, 130, 10, moduleSize: 10);
      drawFinderPattern(matrix, 10, 130, moduleSize: 10);

      expect(decoder().decodeDeep(matrix), isNull);
    });
  });

  group('TryHarderDecoder dedup and work budget', () {
    test('repeated grid search on the same geometry is skipped', () {
      final (_, matrix) = _loadFixture(
        'fixtures/unsupported_images/curved_wavy_6.0.png',
      );
      final info = FinderPatternFinder(matrix).find();

      final d = decoder();
      expect(d.decodeWithFinderInfo(matrix, info), isNull);
      final consumed = TryHarderDecoder.gridPointBudget - d.remainingGridPoints;
      expect(consumed, greaterThan(0));

      // Second identical search is deduplicated: no extra budget consumed.
      expect(d.decodeWithFinderInfo(matrix, info), isNull);
      expect(
        TryHarderDecoder.gridPointBudget - d.remainingGridPoints,
        consumed,
      );
    });

    test('grid search stops once the work budget is exhausted', () {
      final (_, matrix) = _loadFixture(
        'fixtures/unsupported_images/curved_wavy_6.0.png',
      );
      final info = FinderPatternFinder(matrix).find();

      final d = decoder();
      // Burn the budget with shifted variants of the real geometry (each
      // shift creates a new dedup key on the same matrix).
      var shift = 0.0;
      while (d.hasBudget) {
        shift += 8.0;
        final shifted = FinderPatternInfo(
          topLeft: FinderPattern(
            x: info.topLeft.x + shift,
            y: info.topLeft.y,
            estimatedModuleSize: info.topLeft.estimatedModuleSize,
          ),
          topRight: FinderPattern(
            x: info.topRight.x + shift,
            y: info.topRight.y,
            estimatedModuleSize: info.topRight.estimatedModuleSize,
          ),
          bottomLeft: FinderPattern(
            x: info.bottomLeft.x + shift,
            y: info.bottomLeft.y,
            estimatedModuleSize: info.bottomLeft.estimatedModuleSize,
          ),
        );
        expect(d.decodeWithFinderInfo(matrix, shifted), isNull);
      }
      expect(d.hasBudget, isFalse);

      // A new geometry passes the gates but cannot consume further work.
      final remaining = d.remainingGridPoints;
      final fresh = FinderPatternInfo(
        topLeft: FinderPattern(
          x: info.topLeft.x,
          y: info.topLeft.y + 16,
          estimatedModuleSize: info.topLeft.estimatedModuleSize,
        ),
        topRight: FinderPattern(
          x: info.topRight.x,
          y: info.topRight.y + 16,
          estimatedModuleSize: info.topRight.estimatedModuleSize,
        ),
        bottomLeft: FinderPattern(
          x: info.bottomLeft.x,
          y: info.bottomLeft.y + 16,
          estimatedModuleSize: info.bottomLeft.estimatedModuleSize,
        ),
      );
      expect(d.decodeWithFinderInfo(matrix, fresh), isNull);
      expect(d.remainingGridPoints, remaining);
    });

    test('fixture rescues leave budget headroom', () {
      // The dirt image is rescued by the corner grid search directly on
      // the original matrix (stage 2); the budget must not be a limiting
      // factor for any rescued fixture.
      final (_, matrix) = _loadFixture(
        'fixtures/distorted_images/damaged_dirt_0.30.png',
      );
      final info = FinderPatternFinder(matrix).find();

      final d = decoder();
      final result = d.decodeWithFinderInfo(matrix, info);
      expect(result, isNotNull);
      expect(result!.text, 'Hello World');
      expect(d.hasBudget, isTrue, reason: 'rescue must fit in the budget');
    });
  });
}
