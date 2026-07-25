import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/qr/detector/finder_pattern.dart';
import 'package:yomu/src/qr/detector/finder_pattern_finder.dart';

import '../finder_pattern_helper.dart';

void main() {
  group('FinderPatternFinder', () {
    test('finds finder patterns in perfect image', () {
      final matrix = BitMatrix(width: 21);

      // Top Left (0,0)
      drawFinderPattern(matrix, 0, 0);
      // Top Right (14, 0) -> pattern 7x7. starts at 14. 14+7=21.
      drawFinderPattern(matrix, 14, 0);
      // Bottom Left (0, 14)

      drawFinderPattern(matrix, 0, 14);

      final finder = FinderPatternFinder(matrix);
      final info = finder.find();

      // Centers should be at offset + 3.5
      expect(info.topLeft.x, closeTo(3.5, 0.5));
      expect(info.topLeft.y, closeTo(3.5, 0.5));

      expect(info.topRight.x, closeTo(17.5, 0.5));
      expect(info.topRight.y, closeTo(3.5, 0.5));

      expect(info.bottomLeft.x, closeTo(3.5, 0.5));
      expect(info.bottomLeft.y, closeTo(17.5, 0.5));
    });

    group('foundPatternCross', () {
      test('validates exact 1:1:3:1:1 pattern', () {
        // Module size = 10
        // 10 : 10 : 30 : 10 : 10
        final stateCount = [10, 10, 30, 10, 10];
        expect(FinderPatternFinder.foundPatternCross(stateCount), isTrue);
      });

      test('validates patterns within acceptable variance', () {
        // Module size ranges.
        // Total = 70. Module = 10. Max Variance = 5.
        // [10, 10, 30, 10, 10]

        // Variance acceptable (< 5)
        // 14 is just under 15 (10+5). But wait, stateCount[0] -moduleSize < maxVariance
        // |14 - 10| = 4 < 5. OK.

        final stateCount = [14, 10, 30, 10, 10];
        expect(FinderPatternFinder.foundPatternCross(stateCount), isTrue);
      });

      test('rejects patterns outside variance', () {
        // Total = 70 + 5 = 75. Module = 10.7. Variance = 5.35.
        // |16 - 10.7| = 5.3 ~ close.

        // Let's rely on exact failing case.
        // [10, 10, 30, 10, 10]. Module=10. Var=5.
        // Try stateCount[0] = 15. |15-10| = 5. Not < 5. Should fail.
        // But changing one value changes total size and module size.
        // 15, 10, 30, 10, 10 -> Total 75. Mod 10.71. Var 5.35.
        // |15 - 10.71| = 4.29 < 5.35. PASSES.

        // Try extreme.
        // 20, 10, 30, 10, 10 -> Total 80. Mod 11.4. Var 5.7.
        // |20 - 11.4| = 8.6 > 5.7. FAIL.
        expect(
          FinderPatternFinder.foundPatternCross([20, 10, 30, 10, 10]),
          isFalse,
        );
      });

      test('rejects zero counts', () {
        expect(
          FinderPatternFinder.foundPatternCross([0, 10, 30, 10, 10]),
          isFalse,
        );
        expect(
          FinderPatternFinder.foundPatternCross([10, 0, 30, 10, 10]),
          isFalse,
        );
        expect(
          FinderPatternFinder.foundPatternCross([10, 10, 30, 0, 10]),
          isFalse,
        );
      });

      test('rejects small total size', () {
        // Less than 7 total pixels
        expect(FinderPatternFinder.foundPatternCross([1, 1, 1, 1, 1]), isFalse);
        // Total 5. < 7. False.
      });
    });

    group('isValidTriplet', () {
      test('accepts valid right isosceles triangle', () {
        // 0,0  10,0  0,10
        const p1 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10, count: 1);
        const p2 = FinderPattern(
          x: 100,
          y: 0,
          estimatedModuleSize: 10,
          count: 1,
        ); // TR
        const p3 = FinderPattern(
          x: 0,
          y: 100,
          estimatedModuleSize: 10,
          count: 1,
        ); // BL

        // Shorter sides: 100, 100.
        // Hypotenuse: sqrt(100^2 + 100^2) = 141.4
        // 100 * 1.414 = 141.4. Match.

        expect(FinderPatternFinder.isValidTriplet(p1, p2, p3), isTrue);
      });

      test('rejects scalene triangle with wrong ratios', () {
        const p1 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10, count: 1);
        const p2 = FinderPattern(
          x: 100,
          y: 0,
          estimatedModuleSize: 10,
          count: 1,
        );
        const p3 = FinderPattern(
          x: 50,
          y: 200,
          estimatedModuleSize: 10,
          count: 1,
        );

        expect(FinderPatternFinder.isValidTriplet(p1, p2, p3), isFalse);
      });

      test('rejects if module sizes vary too much', () {
        const p1 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10, count: 1);
        const p2 = FinderPattern(
          x: 100,
          y: 0,
          estimatedModuleSize: 10,
          count: 1,
        );
        const p3 = FinderPattern(
          x: 0,
          y: 100,
          estimatedModuleSize: 20,
          count: 1,
        ); // 2x size

        // max > min * 1.5 -> 20 > 10 * 1.5 (15). True. Should return false.
        expect(FinderPatternFinder.isValidTriplet(p1, p2, p3), isFalse);
      });

      test('does not depend on the order the patterns are passed in', () {
        // The same three corners, so every permutation has to reach the same
        // verdict however the distances and module sizes happen to be
        // ordered on the way in.
        const corner = FinderPattern(
          x: 0,
          y: 0,
          estimatedModuleSize: 10,
          count: 1,
        );
        const right = FinderPattern(
          x: 100,
          y: 0,
          estimatedModuleSize: 11,
          count: 1,
        );
        const below = FinderPattern(
          x: 0,
          y: 100,
          estimatedModuleSize: 12,
          count: 1,
        );

        const permutations = [
          [corner, right, below],
          [corner, below, right],
          [right, corner, below],
          [right, below, corner],
          [below, corner, right],
          [below, right, corner],
        ];

        for (final permutation in permutations) {
          expect(
            FinderPatternFinder.isValidTriplet(
              permutation[0],
              permutation[1],
              permutation[2],
            ),
            isTrue,
            reason: 'permutation $permutation',
          );
        }
      });

      test('rejects a triangle whose longest side is not the hypotenuse', () {
        // Equilateral: the two shortest sides match, but the longest is
        // nowhere near sqrt(2) times them.
        const p1 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10, count: 1);
        const p2 = FinderPattern(
          x: 100,
          y: 0,
          estimatedModuleSize: 10,
          count: 1,
        );
        const p3 = FinderPattern(
          x: 50,
          y: 86.6,
          estimatedModuleSize: 10,
          count: 1,
        );

        expect(FinderPatternFinder.isValidTriplet(p1, p2, p3), isFalse);
      });
    });

    group('orderPatterns', () {
      test('orders patterns correctly (normal orientation)', () {
        // TL(0,0), TR(10,0), BL(0,10)
        const p1 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10);
        const p2 = FinderPattern(x: 10, y: 0, estimatedModuleSize: 10);
        const p3 = FinderPattern(x: 0, y: 10, estimatedModuleSize: 10);

        final info = FinderPatternFinder.orderPatterns(p1, p2, p3);

        expect(info.topLeft, equals(p1));
        expect(info.topRight, equals(p2));
        expect(info.bottomLeft, equals(p3));
      });

      test('orders patterns correctly (rotated)', () {
        // Rotated 90 degrees.
        // TL at (10,0). TR at (10,10). BL at (0,0).
        // Verify: distance TL-TR=10. TL-BL=10. TR-BL=sqrt(200)=14.1

        const p1 = FinderPattern(x: 10, y: 0, estimatedModuleSize: 10); // TL
        const p2 = FinderPattern(x: 10, y: 10, estimatedModuleSize: 10); // TR
        const p3 = FinderPattern(x: 0, y: 0, estimatedModuleSize: 10); // BL

        // orderPatterns should correctly identify them based on geometry
        final info = FinderPatternFinder.orderPatterns(p1, p2, p3);

        expect(info.topLeft, equals(p1));
        expect(info.topRight, equals(p2));
        expect(info.bottomLeft, equals(p3));
      });
    });

    test('does not mistake a long run for a finder pattern', () {
      // A run is as long as the image allows, so the counters have to hold
      // more than a byte. Here the white gap is 266 pixels: read modulo 256
      // it reads as 10, which turns black(10) gap(266) black(30) white(10)
      // black(10) into a textbook 1:1:3:1:1 that it is not.
      final matrix = BitMatrix(width: 400, height: 400);

      void fillRow(int y, int from, int to) {
        for (var x = from; x <= to; x++) {
          matrix.set(x, y);
        }
      }

      // Rows 200-229 carry the horizontal run pattern.
      for (var y = 200; y <= 229; y++) {
        fillRow(y, 0, 9); // black, 10 wide
        // x 10-275 stays white: a 266 pixel gap
        fillRow(y, 276, 305); // black, 30 wide
        // x 306-315 white, 10 wide
        fillRow(y, 316, 325); // black, 10 wide
      }

      // Column 291 alone gets a genuine 1:1:3:1:1 profile, so the vertical
      // cross-check cannot be what rejects the candidate.
      for (var y = 180; y <= 189; y++) {
        matrix.set(291, y);
      }
      for (var y = 240; y <= 249; y++) {
        matrix.set(291, y);
      }

      final finder = FinderPatternFinder(matrix);
      finder.findMulti();

      expect(
        finder.possibleCenters,
        isEmpty,
        reason: 'the 266 pixel gap is not one module wide',
      );
    });

    group('findMulti', () {
      test('finds finder pattern at the very right edge of image', () {
        // Width 21. Indices 0..20.
        final matrix = BitMatrix(width: 21, height: 21);

        // Place a finder pattern at the right edge
        // x=14 to x=20 (width-1)
        drawFinderPattern(matrix, 14, 0);

        // Place other patterns to form a valid QR code
        drawFinderPattern(matrix, 0, 0);
        drawFinderPattern(matrix, 0, 14);

        final finder = FinderPatternFinder(matrix);
        // Use findMulti() to exercise the loop that hits line 405
        final infoList = finder.findMulti();

        expect(infoList, hasLength(1));
        // Verify detection of the Top Right pattern
        expect(infoList.first.topRight.x, closeTo(17.5, 0.5));
      });
    });
  });
}
