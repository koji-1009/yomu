import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';

void main() {
  group('GlobalHistogramBinarizer', () {
    test('estimateBlackPoint finds valley between two peaks', () {
      final buckets = List<int>.filled(32, 5); // Noise floor 5

      // Peak 1 at index 5
      buckets[4] = 15;
      buckets[5] = 25;
      buckets[6] = 15;

      // Valley at index 14 (True valley)
      buckets[13] = 2; // Below noise floor
      buckets[14] = 1; // Minimum
      buckets[15] = 2;

      // Peak 2 at index 25
      buckets[24] = 15;
      buckets[25] = 25;
      buckets[26] = 15;

      // Expected valley is index 14.
      // Output is shifted by 3 bits (<< 3) -> * 8
      // 14 * 8 = 112

      final threshold = GlobalHistogramBinarizer.estimateBlackPoint(buckets);
      expect(threshold, 112);
    });

    test('estimateBlackPoint handles unimodal histogram (peaks too close)', () {
      final buckets = List<int>.filled(
        32,
        0,
      ); // No noise to avoid false second peaks

      // Single peak at index 10
      buckets[8] = 10;
      buckets[9] = 15;
      buckets[10] = 25; // Peak
      buckets[11] = 15;
      buckets[12] = 10;

      // If peaks are too close (distance <= 32/16 = 2)
      // Second peak calculation:
      // x=12: count 10 * dist 2^2 = 40
      // x=8: count 10 * dist 2^2 = 40
      // x=9,11: count 15 * dist 1^2 = 15
      // Max score at 8 or 12. Dist 2.
      // 2 <= 2. Returns 128.

      final threshold = GlobalHistogramBinarizer.estimateBlackPoint(buckets);
      expect(threshold, 128); // Defaults to 128 when reliable valley not found
    });
  });
}
