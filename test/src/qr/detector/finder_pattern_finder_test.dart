import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/qr/detector/finder_pattern.dart';
import 'package:yomu/src/qr/detector/finder_pattern_finder.dart';

void main() {
  group('FinderPatternFinder', () {
    test('finds finder patterns in perfect image', () {
      final matrix = BitMatrix(width: 21);

      // Top Left (0,0)
      _drawFinderPattern(matrix, 0, 0);
      // Top Right (14, 0) -> pattern 7x7. starts at 14. 14+7=21.
      _drawFinderPattern(matrix, 14, 0);
      // Bottom Left (0, 14)

      _drawFinderPattern(matrix, 0, 14);

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

    group('findMulti', () {
      test('finds finder pattern at the very right edge of image', () {
        // Width 21. Indices 0..20.
        final matrix = BitMatrix(width: 21, height: 21);

        // Place a finder pattern at the right edge
        // x=14 to x=20 (width-1)
        _drawFinderPattern(matrix, 14, 0);

        // Place other patterns to form a valid QR code
        _drawFinderPattern(matrix, 0, 0);
        _drawFinderPattern(matrix, 0, 14);

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

void _drawFinderPattern(BitMatrix matrix, int xStart, int yStart) {
  // 7x7 box
  // Black fill
  for (var y = 0; y < 7; y++) {
    for (var x = 0; x < 7; x++) {
      if (y == 0 || y == 6 || x == 0 || x == 6) {
        matrix.set(xStart + x, yStart + y);
      } else if (y == 1 || y == 5 || x == 1 || x == 5) {
        // White
      } else {
        // Black 3x3
        matrix.set(xStart + x, yStart + y);
      }
    }
  }
}
