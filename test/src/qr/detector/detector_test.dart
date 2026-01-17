import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/qr/detector/detector.dart';

void main() {
  group('Detector', () {
    test('detects simple synthetic code', () {
      // 21x21 matrix
      final matrix = BitMatrix(width: 21);

      // Draw Patterns (7x7)
      _drawFinderPattern(matrix, 0, 0);
      _drawFinderPattern(matrix, 14, 0);
      _drawFinderPattern(matrix, 0, 14);

      // Add a timing pattern?
      // Horizontal (6, 8) to (14, 8) ? No, row 6 (0-indexed).
      // Alternating B W.
      for (var i = 8; i < 13; i++) {
        matrix.set(x: i, y: 6);
        matrix.set(x: 6, y: i);
      }

      final detector = Detector(matrix);
      final result = detector.detect();

      expect(result.bits.width, 21);
      expect(result.bits.height, 21);

      // Verify corners of result bits
      // (0,0) in result bits corresponds to TopLeft module.
      // TopLeft finder pattern is 7x7. (0,0) to (6,6).
      // result.bits should contain the sampled data.
      // (0,0) of sampled grid is (0,0) of image?
      // GridSampler logic maps (0,0) grid to 3.5,3.5 image?
      // Wait. GridSampler transform: (3.5, 3.5) -> topLeft (3.5, 3.5).
      // So (0,0) grid -> (0,0) image roughly.
      // So result.bits.get(0,0) should check image(0,0).

      expect(
        result.bits.get(x: 0, y: 0),
        isTrue,
      ); // Top left of Finder is Black
      expect(result.bits.get(x: 3, y: 3), isTrue); // Center of Finder is Black
    });
  });
}

void _drawFinderPattern(BitMatrix matrix, int xStart, int yStart) {
  for (var y = 0; y < 7; y++) {
    for (var x = 0; x < 7; x++) {
      if (y == 0 || y == 6 || x == 0 || x == 6) {
        matrix.set(x: xStart + x, y: yStart + y);
      } else if (y == 1 || y == 5 || x == 1 || x == 5) {
        // White
      } else {
        // Black 3x3
        matrix.set(x: xStart + x, y: yStart + y);
      }
    }
  }
}
