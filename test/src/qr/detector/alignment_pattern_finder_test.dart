import 'package:test/test.dart';
import 'package:yomu/src/qr/detector/alignment_pattern_finder.dart';

void main() {
  group('AlignmentPatternFinder', () {
    test('foundPatternCross validates 1:1:1 module ratios', () {
      const moduleSize = 10.0;
      // Perfect 1:1:1
      final counts1 = [10, 10, 10];
      expect(
        AlignmentPatternFinder.foundPatternCross(counts1, moduleSize),
        isTrue,
      );

      // Within 50% variance
      // maxVariance = 5.0
      // 14 is < 15 (10+5). 6 is > 5 (10-5).

      final counts2 = [14, 10, 6];
      expect(
        AlignmentPatternFinder.foundPatternCross(counts2, moduleSize),
        isTrue,
      );

      // Outside variance
      final counts3 = [16, 10, 10]; // 16-10 = 6 > 5
      expect(
        AlignmentPatternFinder.foundPatternCross(counts3, moduleSize),
        isFalse,
      );
    });
  });
}
