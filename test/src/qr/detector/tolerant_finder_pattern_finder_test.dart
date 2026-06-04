import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/qr/detector/finder_pattern.dart';
import 'package:yomu/src/qr/detector/tolerant_finder_pattern_finder.dart';

import '../finder_pattern_helper.dart';

void main() {
  group('TolerantFinderPatternFinder', () {
    test('finds three patterns in a clean image', () {
      final matrix = BitMatrix(width: 100);
      drawFinderPattern(matrix, 10, 10, moduleSize: 3);
      drawFinderPattern(matrix, 70, 10, moduleSize: 3);
      drawFinderPattern(matrix, 10, 70, moduleSize: 3);

      final patterns = TolerantFinderPatternFinder(matrix).find();
      expect(patterns.length, 3);

      final centers = patterns.map((p) => (p.x.round(), p.y.round())).toSet();
      // Centers are at offset + 3.5 modules = offset + 10.5.
      expect(centers, contains((21, 21)));
      expect(centers, contains((81, 21)));
      expect(centers, contains((21, 81)));
      for (final p in patterns) {
        expect(p.estimatedModuleSize, closeTo(3.0, 0.5));
      }
    });

    test('returns empty list for a blank image', () {
      final matrix = BitMatrix(width: 50);
      expect(TolerantFinderPatternFinder(matrix).find(), isEmpty);
    });

    test('finds a pattern whose top ring is cropped by the image edge', () {
      final matrix = BitMatrix(width: 60);
      // Top two module-rows (ring + white) fall outside the image, like a
      // strongly perspective-distorted code: the strict vertical
      // cross-check fails, but row hits still cluster.
      drawFinderPattern(matrix, 10, -8, moduleSize: 4);

      final patterns = TolerantFinderPatternFinder(matrix).find();
      expect(patterns, hasLength(1));
      // X center remains accurate even though the top is cropped.
      expect(patterns.first.x, closeTo(10 + 3.5 * 4, 1.0));
    });

    test('detects a pattern ending exactly at the right image edge', () {
      // Pattern occupies the full width so the final black run terminates
      // at end-of-row instead of a white pixel.
      final matrix = BitMatrix(width: 28, height: 40);
      drawFinderPattern(matrix, 0, 8, moduleSize: 4);

      final patterns = TolerantFinderPatternFinder(matrix).find();
      expect(patterns, hasLength(1));
      expect(patterns.first.x, closeTo(14, 1.0));
      expect(patterns.first.y, closeTo(8 + 14, 1.0));
    });

    test('skips all-white and all-black words on large patterns', () {
      // Module size 32 exercises the 32-bit word skip paths.
      final matrix = BitMatrix(width: 320, height: 256);
      drawFinderPattern(matrix, 16, 16, moduleSize: 32);

      final patterns = TolerantFinderPatternFinder(matrix).find();
      expect(patterns, hasLength(1));
      expect(patterns.first.x, closeTo(16 + 3.5 * 32, 2.0));
      expect(patterns.first.y, closeTo(16 + 3.5 * 32, 2.0));
      expect(patterns.first.estimatedModuleSize, closeTo(32, 2.0));
    });

    test('caps the number of returned clusters', () {
      // 12 patterns -> must be capped to maxClusters.
      final matrix = BitMatrix(width: 4 * 30 + 10, height: 3 * 30 + 10);
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 4; col++) {
          drawFinderPattern(matrix, 5 + col * 30, 5 + row * 30, moduleSize: 3);
        }
      }

      final patterns = TolerantFinderPatternFinder(matrix).find();
      expect(patterns.length, TolerantFinderPatternFinder.maxClusters);
    });

    test('ignores isolated single-row hits', () {
      final matrix = BitMatrix(width: 40, height: 9);
      // A single row with a 1:1:3:1:1 run (one hit only: rowSpan 1 < 3).
      for (final x in [10, 12, 13, 14, 16]) {
        matrix.set(x, 4);
      }

      expect(TolerantFinderPatternFinder(matrix).find(), isEmpty);
    });
  });

  group('TolerantFinderPatternFinder.enumerateTriplets', () {
    FinderPattern pattern(double x, double y, double size) =>
        FinderPattern(x: x, y: y, estimatedModuleSize: size);

    test('returns empty for fewer than three patterns', () {
      expect(TolerantFinderPatternFinder.enumerateTriplets(const []), isEmpty);
      expect(
        TolerantFinderPatternFinder.enumerateTriplets([
          pattern(0, 0, 3),
          pattern(10, 0, 3),
        ]),
        isEmpty,
      );
    });

    test('orders a valid triplet into corner roles', () {
      final triplets = TolerantFinderPatternFinder.enumerateTriplets([
        pattern(10, 10, 3),
        pattern(50, 10, 3),
        pattern(10, 50, 3),
      ]);
      expect(triplets, hasLength(1));
      final info = triplets.first;
      expect(info.topLeft.x, 10);
      expect(info.topLeft.y, 10);
      expect(info.topRight.x, 50);
      expect(info.bottomLeft.y, 50);
    });

    test('skips triplets with incompatible module sizes', () {
      final triplets = TolerantFinderPatternFinder.enumerateTriplets([
        pattern(10, 10, 2),
        pattern(50, 10, 5), // 2.5x larger than the smallest
        pattern(10, 50, 2),
      ]);
      expect(triplets, isEmpty);
    });

    test('enumerates all combinations of four patterns', () {
      final triplets = TolerantFinderPatternFinder.enumerateTriplets([
        pattern(10, 10, 3),
        pattern(50, 10, 3),
        pattern(10, 50, 3),
        pattern(50, 50, 3),
      ]);
      expect(triplets, hasLength(4)); // C(4,3)
    });
  });
}
