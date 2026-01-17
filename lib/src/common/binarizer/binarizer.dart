import 'dart:typed_data';

import '../bit_matrix.dart';
import 'luminance_source.dart';

class GlobalHistogramBinarizer {
  GlobalHistogramBinarizer(this.source);
  static const int _luminanceBuckets = 32;
  late Uint8List _luminances;
  final int _luminanceBits = 5;
  final RGBLuminanceSource source;

  BitMatrix getBlackMatrix() {
    final source = this.source;
    final width = source.width;
    final height = source.height;

    // Get all luminances
    _luminances = source.matrix;

    // Compute histogram
    final buckets = List<int>.filled(_luminanceBuckets, 0);
    for (var i = 0; i < width * height; i++) {
      // 256 -> 32 buckets implies >> 3
      // 5 bits for 32 buckets. 8 bits total. so >> 3.
      buckets[(_luminances[i] & 0xFF) >> (8 - _luminanceBits)]++;
    }

    // Calculate black point from histogram
    final blackPoint = estimateBlackPoint(buckets);
    return BitMatrix.fromLuminance(
      width: width,
      height: height,
      luminances: _luminances,
      threshold: blackPoint,
    );
  }

  static int estimateBlackPoint(List<int> buckets) {
    // Find tallest peak
    final numBuckets = buckets.length;
    var maxBucketCount = 0;
    var firstPeak = 0;
    var firstPeakSize = 0;

    for (var x = 0; x < numBuckets; x++) {
      if (buckets[x] > firstPeakSize) {
        firstPeak = x;
        firstPeakSize = buckets[x];
      }
      if (buckets[x] > maxBucketCount) {
        maxBucketCount = buckets[x];
      }
    }

    // 1. Find the highest peak.
    // 2. Find a "second peak" that is far enough away.

    var secondPeak = 0;
    var secondPeakScore = 0; // score = counts * distance^2
    for (var x = 0; x < numBuckets; x++) {
      final distanceToFirst = x - firstPeak;
      // score = counts * distance^2
      final score = buckets[x] * distanceToFirst * distanceToFirst;
      if (score > secondPeakScore) {
        secondPeak = x;
        secondPeakScore = score;
      }
    }

    // Threshold is between them.

    var bestValley = firstPeak;

    if (firstPeak > secondPeak) {
      final temp = firstPeak;
      firstPeak = secondPeak;
      secondPeak = temp;
    }

    // Found two peaks. Valley is between.
    if (secondPeak - firstPeak <= numBuckets ~/ 16) {
      // Peaks too close.
      // Return middle for safety.
      return 128; // Default unsafe
    }

    // Find min between peaks
    var minVal = maxBucketCount; // start high

    for (var x = firstPeak + 1; x < secondPeak; x++) {
      final score = buckets[x];
      if (score < minVal) {
        minVal = score;
        bestValley = x;
      }
    }

    // Convert bucket back to 0-255 luminance
    // _luminanceBits = 5, so shift is 3.
    return (bestValley << 3);
  }
}
