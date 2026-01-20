import '../../common/bit_matrix.dart';

/// Represents an alignment pattern found in a QR code.
///
/// Alignment patterns are the smaller square patterns found in QR codes
/// version 2 and higher. They help correct for perspective distortion.
class AlignmentPattern {
  /// Creates an alignment pattern at the specified position.
  const AlignmentPattern({
    required this.x,
    required this.y,
    required this.estimatedModuleSize,
  });

  /// X coordinate of the pattern center.
  final double x;

  /// Y coordinate of the pattern center.
  final double y;

  /// Estimated size of a single module in pixels.
  final double estimatedModuleSize;

  /// Combines this pattern with a new estimate at (x, y).
  AlignmentPattern combineEstimate({
    required double y,
    required double x,
    required double newModuleSize,
  }) {
    final combinedX = (this.x + x) / 2.0;
    final combinedY = (this.y + y) / 2.0;
    final combinedModuleSize = (estimatedModuleSize + newModuleSize) / 2.0;
    return AlignmentPattern(
      x: combinedX,
      y: combinedY,
      estimatedModuleSize: combinedModuleSize,
    );
  }

  /// Checks if the given coordinates are close to this pattern.
  bool aboutEquals({
    required double moduleSize,
    required double y,
    required double x,
  }) {
    if ((y - this.y).abs() <= moduleSize && (x - this.x).abs() <= moduleSize) {
      final moduleSizeDiff = (moduleSize - estimatedModuleSize).abs();
      return moduleSizeDiff <= 1.0 || moduleSizeDiff <= estimatedModuleSize;
    }
    return false;
  }
}

/// Finds alignment patterns in a QR code image.
///
/// This class searches for the smaller square patterns used in QR codes
/// V2+ to improve perspective correction accuracy.
class AlignmentPatternFinder {
  /// Creates a finder for the given image.
  AlignmentPatternFinder(this._image, this._moduleSize);

  final BitMatrix _image;
  final double _moduleSize;

  final List<AlignmentPattern> _possibleCenters = [];

  /// Finds an alignment pattern near the expected position.
  ///
  /// [startX], [startY] define the top-left of the search area.
  /// [width], [height] define the search area size.
  AlignmentPattern? find({
    required int startX,
    required int startY,
    required int width,
    required int height,
  }) {
    final maxJ = startX + width;
    final middleI = startY + (height ~/ 2);

    // Search from middle outward
    for (var iGen = 0; iGen < height; iGen++) {
      final i =
          middleI + ((iGen & 1) == 0 ? (iGen + 1) ~/ 2 : -((iGen + 1) ~/ 2));
      if (i < 0 || i >= _image.height) continue;

      final stateCount = [0, 0, 0]; // white-black-white
      var j = startX;

      // Skip leading white modules
      while (j < maxJ && !_image.get(j, i)) {
        j++;
      }

      var currentState = 0;
      while (j < maxJ) {
        if (_image.get(j, i)) {
          // Black pixel
          if (currentState == 1) {
            stateCount[1]++;
          } else {
            if (currentState == 2) {
              // Found black-white-black
              if (foundPatternCross(stateCount, _moduleSize)) {
                final confirmed = _handlePossibleCenter(stateCount, i, j);
                if (confirmed != null) {
                  return confirmed;
                }
              }
              stateCount[0] = stateCount[2];
              stateCount[1] = 1;
              stateCount[2] = 0;
              currentState = 1;
            } else {
              currentState++;
              stateCount[currentState]++;
            }
          }
        } else {
          // White pixel
          if (currentState == 1) {
            currentState++;
          }
          stateCount[currentState]++;
        }
        j++;
      }

      if (foundPatternCross(stateCount, _moduleSize)) {
        final confirmed = _handlePossibleCenter(stateCount, i, maxJ);
        if (confirmed != null) {
          return confirmed;
        }
      }
    }

    // Return best candidate if any
    if (_possibleCenters.isNotEmpty) {
      return _possibleCenters.first;
    }
    return null;
  }

  /// Checks if the state count looks like an alignment pattern (1:1:1 ratio).
  static bool foundPatternCross(List<int> stateCount, double moduleSize) {
    final maxVariance = moduleSize / 2.0;

    // Check the center module (black) first.
    // Since it is the most distinct feature, checking it first allows for
    // earlier rejection of invalid candidates (false negatives).
    if ((stateCount[1] - moduleSize).abs() >= maxVariance) return false;
    if ((stateCount[0] - moduleSize).abs() >= maxVariance) return false;
    if ((stateCount[2] - moduleSize).abs() >= maxVariance) return false;

    return true;
  }

  /// Validates and refines a potential alignment pattern center.
  AlignmentPattern? _handlePossibleCenter(List<int> stateCount, int i, int j) {
    final stateCountTotal = stateCount[0] + stateCount[1] + stateCount[2];
    final centerJ = _centerFromEnd(stateCount, j);

    final centerI = _crossCheckVertical(
      i,
      centerJ.toInt(),
      stateCount[1],
      stateCountTotal,
    );
    if (centerI != null) {
      final estimatedModuleSize =
          (stateCount[0] + stateCount[1] + stateCount[2]) / 3.0;

      for (final center in _possibleCenters) {
        if (center.aboutEquals(
          moduleSize: estimatedModuleSize,
          y: centerI,
          x: centerJ,
        )) {
          return center.combineEstimate(
            y: centerI,
            x: centerJ,
            newModuleSize: estimatedModuleSize,
          );
        }
      }

      final point = AlignmentPattern(
        x: centerJ,
        y: centerI,
        estimatedModuleSize: estimatedModuleSize,
      );
      _possibleCenters.add(point);
    }
    return null;
  }

  /// Calculates center X from the end position and state counts.
  double _centerFromEnd(List<int> stateCount, int end) {
    return (end - stateCount[2]) - stateCount[1] / 2.0;
  }

  /// Cross-checks vertically for alignment pattern.
  double? _crossCheckVertical(
    int startI,
    int centerJ,
    int maxCount,
    int originalStateCountTotal,
  ) {
    final maxI = _image.height;
    final stateCount = [0, 0, 0];

    // Check upward from center
    var i = startI;
    while (i >= 0 && _image.get(centerJ, i) && stateCount[1] <= maxCount) {
      stateCount[1]++;
      i--;
    }
    if (i < 0 || stateCount[1] > maxCount) {
      return null;
    }
    while (i >= 0 && !_image.get(centerJ, i) && stateCount[0] <= maxCount) {
      stateCount[0]++;
      i--;
    }
    if (stateCount[0] > maxCount) {
      return null;
    }

    // Check downward from center
    i = startI + 1;
    while (i < maxI && _image.get(centerJ, i) && stateCount[1] <= maxCount) {
      stateCount[1]++;
      i++;
    }
    if (i == maxI || stateCount[1] > maxCount) {
      return null;
    }
    while (i < maxI && !_image.get(centerJ, i) && stateCount[2] <= maxCount) {
      stateCount[2]++;
      i++;
    }
    if (stateCount[2] > maxCount) {
      return null;
    }

    final stateCountTotal = stateCount[0] + stateCount[1] + stateCount[2];
    if (5 * (stateCountTotal - originalStateCountTotal).abs() >=
        originalStateCountTotal) {
      return null;
    }

    return foundPatternCross(stateCount, _moduleSize)
        ? (i - stateCount[2]) - stateCount[1] / 2.0
        : null;
  }
}
