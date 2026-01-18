import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
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
