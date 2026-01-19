import 'dart:math';

import '../../common/bit_matrix.dart';
import '../../yomu_exception.dart';
import 'finder_pattern.dart';

class FinderPatternFinder {
  FinderPatternFinder(this.image);

  final BitMatrix image;
  final List<FinderPattern> _possibleCenters = [];

  final List<int> _crossCheckStateCount = List<int>.filled(5, 0);

  FinderPatternInfo find() {
    final maxI = image.height;
    final maxJ = image.width;
    final bits = image.bits;
    final rowStride = image.rowStride;

    // Skip rows for speed (iSkip=3 is a good balance)
    const iSkip = 3;
    final stateCount = List<int>.filled(5, 0);

    // Center-first scanning: scan from center outward
    // This finds QR codes faster when they're centered (common case)
    final centerRow = maxI ~/ 2;
    final rowOrder = _generateCenterFirstRows(centerRow, maxI, iSkip);

    for (final i in rowOrder) {
      // Reset state
      stateCount.fillRange(0, 5, 0);
      var currentState = 0;
      final rowOffset = i * rowStride;

      var wordOffset = rowOffset;
      // Process row in 32-bit words
      // This reduces array access by 32x
      for (var j = 0; j < maxJ; j += 32) {
        final remaining = maxJ - j;
        final currentWord = bits[wordOffset++];

        final limit = (remaining < 32) ? remaining : 32;

        if (currentWord == 0 && (currentState & 1) == 1 && limit == 32) {
          // Optimization: All white, currently counting white
          stateCount[currentState] += 32;
          continue;
        }

        if (currentWord == 0xFFFFFFFF &&
            (currentState & 1) == 0 &&
            limit == 32) {
          // Optimization: All black, currently counting black
          stateCount[currentState] += 32;
          continue;
        }

        for (var b = 0; b < limit; b++) {
          if ((currentWord & (1 << b)) != 0) {
            // Black
            if ((currentState & 1) == 1) {
              currentState++;
            }
            stateCount[currentState]++;
          } else {
            // White
            if ((currentState & 1) == 0) {
              if (currentState == 4) {
                // Found B W B W B sequence
                if (foundPatternCross(stateCount)) {
                  // The actual pixel coordinate is j + b
                  final confirmed = _handlePossibleCenter(stateCount, i, j + b);
                  if (!confirmed) {
                    _shiftCounts2(stateCount);
                    currentState = 3; // Continue detecting
                    // No need to 'continue' here as we are in inner bit loop
                  } else {
                    currentState = 0;
                    stateCount.fillRange(0, 5, 0);
                  }
                } else {
                  _shiftCounts2(stateCount);
                  currentState = 3;
                }
              } else {
                currentState++;
                stateCount[currentState]++;
              }
            } else {
              stateCount[currentState]++;
            }
          }
        }
      }

      // Check end of row
      if (foundPatternCross(stateCount)) {
        _handlePossibleCenter(stateCount, i, maxJ);
      }
    }

    final patternInfo = _selectBestPatterns();
    return patternInfo;
  }

  /// Generate row indices from center outward for center-first scanning.
  /// This is more efficient for QR codes positioned in the center (common case).
  List<int> _generateCenterFirstRows(int center, int maxRows, int skip) {
    final rows = <int>[];
    var offset = 0;

    while (true) {
      final above = center - offset;
      final below = center + offset;

      if (above >= 0 && above % skip == (skip - 1) % skip) {
        // Ensure we hit proper skip alignment
        rows.add(above);
      }
      if (offset > 0 && below < maxRows && below % skip == (skip - 1) % skip) {
        rows.add(below);
      }

      offset++;
      if (above < 0 && below >= maxRows) break;
      if (rows.length > maxRows) break; // Safety limit
    }

    return rows;
  }

  void _shiftCounts2(List<int> stateCount) {
    stateCount[0] = stateCount[2];
    stateCount[1] = stateCount[3];
    stateCount[2] = stateCount[4];
    stateCount[3] = 1;
    stateCount[4] = 0;
  }

  /// Verifies that the pixel counts matches the 1:1:3:1:1 pattern.
  ///
  /// The tolerance is computed from the total module size.
  static bool foundPatternCross(List<int> stateCount) {
    var totalModuleSize = 0;
    for (var i = 0; i < 5; i++) {
      final count = stateCount[i];
      if (count == 0) {
        return false;
      }
      totalModuleSize += count;
    }

    if (totalModuleSize < 7) return false;

    final moduleSize = totalModuleSize / 7.0;
    final maxVariance = moduleSize / 2.0;

    // Check 1:1:3:1:1 module ratios

    return (stateCount[0] - moduleSize).abs() < maxVariance &&
        (stateCount[1] - moduleSize).abs() < maxVariance &&
        (stateCount[2] - 3.0 * moduleSize).abs() < 3.0 * maxVariance &&
        (stateCount[3] - moduleSize).abs() < maxVariance &&
        (stateCount[4] - moduleSize).abs() < maxVariance;
  }

  bool _handlePossibleCenter(List<int> stateCount, int i, int j) {
    var stateCountTotal = 0;
    for (final count in stateCount) {
      stateCountTotal += count;
    }

    final centerJ = j - stateCount[4] - stateCount[3] - stateCount[2] / 2.0;

    // Vertical check
    final centerI = _crossCheckVertical(
      i,
      centerJ.toInt(),
      stateCount[2],
      stateCountTotal,
    );
    if (centerI != null) {
      // Add to possible centers
      final estimatedModuleSize = stateCountTotal / 7.0;
      var found = false;
      for (var idx = 0; idx < _possibleCenters.length; idx++) {
        final center = _possibleCenters[idx];
        // Look for similar center
        if ((center.x - centerJ).abs() < 10 &&
            (center.y - centerI).abs() < 10) {
          // Combine
          _possibleCenters[idx] = center.combineEstimate(
            centerI,
            centerJ,
            estimatedModuleSize,
          );
          found = true;
          break;
        }
      }
      if (!found) {
        _possibleCenters.add(
          FinderPattern(
            x: centerJ,
            y: centerI,
            estimatedModuleSize: estimatedModuleSize,
          ),
        );
      }
      return true;
    }
    return false;
  }

  double? _crossCheckVertical(
    int startI,
    int centerJ,
    int maxCount,
    int originalStateCountTotal,
  ) {
    // Scan up and down from centerJ, startI
    final bits = image.bits;
    final stride = image.rowStride;
    final maxI = image.height;
    var i = startI;

    // Precompute x offset and mask for this column
    final xOffset = centerJ >> 5;
    final xMask = 1 << (centerJ & 0x1f);

    // Use reusable buffer
    final stateCount = _crossCheckStateCount;
    stateCount.fillRange(0, 5, 0);

    // Start counting up from center
    // 2: center black

    // Initial offset for startI
    var offset = i * stride + xOffset;

    // We are "in" the center black module (state 2).
    // Up
    // 1. Scan up (decrease i) inside Black (state 2)
    while (i >= 0 && (bits[offset] & xMask) != 0) {
      stateCount[2]++;
      i--;
      offset -= stride;
    }
    if (i < 0) return null;

    // 2. Scan up White (state 1)
    while (i >= 0 && (bits[offset] & xMask) == 0 && stateCount[1] <= maxCount) {
      stateCount[1]++;
      i--;
      offset -= stride;
    }
    if (i < 0 || stateCount[1] > maxCount) return null;

    // 3. Scan up Black (state 0)
    while (i >= 0 && (bits[offset] & xMask) != 0 && stateCount[0] <= maxCount) {
      stateCount[0]++;
      i--;
      offset -= stride;
    }
    if (stateCount[0] > maxCount) return null;

    // Go down
    i = startI + 1;
    offset = i * stride + xOffset;

    // 4. Scan down Black (state 2 residue)
    while (i < maxI && (bits[offset] & xMask) != 0) {
      stateCount[2]++;
      i++;
      offset += stride;
    }
    if (i == maxI) return null;

    // 5. Scan down White (state 3)
    while (i < maxI &&
        (bits[offset] & xMask) == 0 &&
        stateCount[3] <= maxCount) {
      stateCount[3]++;
      i++;
      offset += stride;
    }
    if (i == maxI || stateCount[3] > maxCount) return null;

    // 6. Scan down Black (state 4)
    while (i < maxI &&
        (bits[offset] & xMask) != 0 &&
        stateCount[4] <= maxCount) {
      stateCount[4]++;
      i++;
      offset += stride;
    }
    if (stateCount[4] > maxCount) return null;

    var total = 0;
    for (final c in stateCount) {
      total += c;
    }

    if (5 * (total - originalStateCountTotal).abs() >=
        2 * originalStateCountTotal) {
      return null;
    }

    if (foundPatternCross(stateCount)) {
      return i - stateCount[4] - stateCount[3] - stateCount[2] / 2.0;
    }
    return null;
  }

  FinderPatternInfo _selectBestPatterns() {
    if (_possibleCenters.length < 3) {
      throw const DetectionException('Could not find 3 finder patterns');
    }

    // Sort by count (descending)
    _possibleCenters.sort((a, b) => b.count.compareTo(a.count));

    final p1 = _possibleCenters[0];
    final p2 = _possibleCenters[1];
    final p3 = _possibleCenters[2];

    // Determine which is BL, TL, TR.
    // Calculate distances.
    final d12 = _dist(p1, p2);
    final d23 = _dist(p2, p3);
    final d13 = _dist(p1, p3);

    FinderPattern bottomLeft, topLeft, topRight;
    // The pair with the longest distance is TR <-> BL (Hypotenuse).
    // The point not in that pair is TL (Top Left 90 degree corner).

    if (d12 >= d23 && d12 >= d13) {
      // 1 and 2 are corners. 3 is TL.
      topLeft = p3;
      bottomLeft = p1;
      topRight = p2;
    } else if (d23 >= d12 && d23 >= d13) {
      // 2 and 3 are corners. 1 is TL.
      topLeft = p1;
      bottomLeft = p2;
      topRight = p3;
    } else {
      // 1 and 3 are corners. 2 is TL.
      topLeft = p2;
      bottomLeft = p1;
      topRight = p3;
    }

    // Determine which is BL and TR.
    // Vector TL->P_A
    // Vector TL->P_B
    // Cross product should tell orientation.
    // Standard QR: BL is "down", TR is "right".
    // Cross product to determine orientation.
    // If we walk TL->TR, then TR should be "right" or "up-right".
    // BL should be "down".

    final crossProduct =
        (topRight.x - topLeft.x) * (bottomLeft.y - topLeft.y) -
        (topRight.y - topLeft.y) * (bottomLeft.x - topLeft.x);

    // Screen coordinates: y is DOWN.
    // Valid orientation -> +ve.

    if (crossProduct < 0) {
      // Swap
      final temp = bottomLeft;
      bottomLeft = topRight;
      topRight = temp;
    }

    return FinderPatternInfo(
      bottomLeft: bottomLeft,
      topLeft: topLeft,
      topRight: topRight,
    );
  }

  static double _dist(FinderPattern a, FinderPattern b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  }

  /// Finds multiple QR codes in the image.
  ///
  /// Returns a list of all valid finder pattern triplets detected.
  /// Each triplet represents one potential QR code.
  List<FinderPatternInfo> findMulti() {
    // Clear previous state
    _possibleCenters.clear();

    // First, detect all possible centers (same as find())
    final maxI = image.height;
    final maxJ = image.width;

    const iSkip = 3;

    final stateCount = List<int>.filled(5, 0);

    for (var i = iSkip - 1; i < maxI; i += iSkip) {
      stateCount.fillRange(0, 5, 0);
      var currentState = 0;

      for (var j = 0; j < maxJ; j++) {
        if (image.get(j, i)) {
          if ((currentState & 1) == 1) {
            currentState++;
          }
          stateCount[currentState]++;
        } else {
          if ((currentState & 1) == 0) {
            if (currentState == 4) {
              if (foundPatternCross(stateCount)) {
                _handlePossibleCenter(stateCount, i, j);
                stateCount.fillRange(0, 5, 0);
                currentState = 0;
              } else {
                _shiftCounts2(stateCount);
                currentState = 3;
              }
            } else {
              currentState++;
              stateCount[currentState]++;
            }
          } else {
            stateCount[currentState]++;
          }
        }
      }

      if (foundPatternCross(stateCount)) {
        _handlePossibleCenter(stateCount, i, maxJ);
      }
    }

    // Now enumerate all valid triplets
    return _selectMultiplePatterns();
  }

  /// Enumerates all valid triangle triplets from possible centers.
  ///
  /// Filters out overlapping/duplicate QR codes based on distance.
  List<FinderPatternInfo> _selectMultiplePatterns() {
    final count = _possibleCenters.length;
    if (count < 3) {
      return [];
    }

    // Sort by count (most confirmed first)
    _possibleCenters.sort((a, b) => b.count.compareTo(a.count));

    final results = <FinderPatternInfo>[];
    final used = List<bool>.filled(count, false);

    // Try all combinations of 3 patterns
    for (var i = 0; i < count - 2; i++) {
      if (used[i]) continue;

      for (var j = i + 1; j < count - 1; j++) {
        if (used[j]) continue;

        for (var k = j + 1; k < count; k++) {
          if (used[k]) continue;

          final p1 = _possibleCenters[i];
          final p2 = _possibleCenters[j];
          final p3 = _possibleCenters[k];

          // Check if this triplet forms a valid QR code (same QR code patterns)
          if (isValidTriplet(p1, p2, p3)) {
            final info = orderPatterns(p1, p2, p3);
            results.add(info);

            // Mark these patterns as used
            used[i] = true;
            used[j] = true;
            used[k] = true;

            // Break out of k loop to try next i,j combination
            break;
          }
        }
        // If we found a valid triplet starting with i,j, try next i
        if (used[i]) break;
      }
    }

    return results;
  }

  /// Checks if three patterns form a valid QR code triangle.
  ///
  /// QR code finder patterns form a right-angle isoceles triangle:
  /// - Two sides are equal (TL-TR and TL-BL)
  /// - The hypotenuse (TR-BL) is approximately √2 times the other sides
  static bool isValidTriplet(
    FinderPattern p1,
    FinderPattern p2,
    FinderPattern p3,
  ) {
    final d12 = _dist(p1, p2);
    final d23 = _dist(p2, p3);
    final d13 = _dist(p1, p3);

    // Sort distances to find the two shorter sides and the hypotenuse
    final distances = [d12, d23, d13]..sort();
    final shorter1 = distances[0];
    final shorter2 = distances[1];
    final hypotenuse = distances[2];

    // The two shorter sides should be approximately equal (within 20%)
    if ((shorter1 - shorter2).abs() > shorter1 * 0.2) {
      return false;
    }

    // The hypotenuse should be approximately √2 times the shorter sides (within 20%)
    final expectedHypotenuse = shorter1 * 1.414; // √2 ≈ 1.414
    if ((hypotenuse - expectedHypotenuse).abs() > expectedHypotenuse * 0.2) {
      return false;
    }

    // Check that module sizes are similar (within 50%)
    final sizes = [
      p1.estimatedModuleSize,
      p2.estimatedModuleSize,
      p3.estimatedModuleSize,
    ];
    final maxSize = sizes.reduce(max);
    final minSize = sizes.reduce(min);

    if (maxSize > minSize * 1.5) {
      return false;
    }

    return true;
  }

  /// Orders three patterns into bottomLeft, topLeft, topRight.
  /// Orders three patterns into bottomLeft, topLeft, topRight.
  static FinderPatternInfo orderPatterns(
    FinderPattern p1,
    FinderPattern p2,
    FinderPattern p3,
  ) {
    final d12 = _dist(p1, p2);
    final d23 = _dist(p2, p3);
    final d13 = _dist(p1, p3);

    FinderPattern bottomLeft, topLeft, topRight;

    if (d12 >= d23 && d12 >= d13) {
      topLeft = p3;
      bottomLeft = p1;
      topRight = p2;
    } else if (d23 >= d12 && d23 >= d13) {
      topLeft = p1;
      bottomLeft = p2;
      topRight = p3;
    } else {
      topLeft = p2;
      bottomLeft = p1;
      topRight = p3;
    }

    final crossProduct =
        (topRight.x - topLeft.x) * (bottomLeft.y - topLeft.y) -
        (topRight.y - topLeft.y) * (bottomLeft.x - topLeft.x);

    if (crossProduct < 0) {
      final temp = bottomLeft;
      bottomLeft = topRight;
      topRight = temp;
    }

    return FinderPatternInfo(
      bottomLeft: bottomLeft,
      topLeft: topLeft,
      topRight: topRight,
    );
  }
}
