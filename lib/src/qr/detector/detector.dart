import 'dart:math';

import '../../common/bit_matrix.dart';
import '../../common/grid_sampler.dart';
import '../../common/perspective_transform.dart';
import '../../yomu_exception.dart';
import '../version.dart';
import 'alignment_pattern_finder.dart';
import 'finder_pattern.dart';
import 'finder_pattern_finder.dart';

class DetectorResult {
  const DetectorResult({required this.bits, required this.points});

  final BitMatrix bits;
  final List<FinderPattern> points;
}

class Detector {
  const Detector(
    this.image, {
    this.gridSampler = const GridSampler(),
    this.alignmentAreaAllowance = 15,
  });

  final BitMatrix image;
  final GridSampler gridSampler;
  final int alignmentAreaAllowance;

  DetectorResult detect() {
    final finder = FinderPatternFinder(image);
    final info = finder.find();

    return processFinderPatternInfo(info);
  }

  DetectorResult processFinderPatternInfo(FinderPatternInfo info) {
    final topLeft = info.topLeft;
    final topRight = info.topRight;
    final bottomLeft = info.bottomLeft;

    final moduleSize = _calculateModuleSize(topLeft, topRight, bottomLeft);
    if (moduleSize < 1.0) {
      throw const DetectionException('Invalid module size');
    }

    final dimension = _computeDimension(
      topLeft,
      topRight,
      bottomLeft,
      moduleSize,
    );

    // Determine version from dimension
    final provisionalVersion = (dimension - 17) ~/ 4;

    // For Version 2+, try to find alignment pattern
    AlignmentPattern? alignmentPattern;
    double bottomRightX;
    double bottomRightY;

    if (provisionalVersion > 1) {
      // Get alignment pattern centers for this version
      final version = Version.getVersionForNumber(provisionalVersion);
      final alignmentCenters = version.alignmentPatternCenters;

      // Version 2+ has alignment patterns, but only if centers.length > 2
      // (Version 2 has [6, 18] which is 2 items - creates 1 alignment pattern)
      if (alignmentCenters.length >= 2) {
        // Reduce allowance now that we have better estimation
        // 5 was too tight for some tilts. 10 is safe enough (~100px).
        // Reduce allowance now that we have better estimation
        // 5 is tight but necessary to avoid false positives in noisy images (e.g. uneven lighting).

        // Estimate where the bottom-right alignment should be
        // We know the AP is at (dim-7, dim-7) in module space.
        // The vector (BL-TL + TR-TL) points to (dim-3.5, dim-3.5).
        // Ratio t = (dim-7 - 3.5) / (dim-3.5 - 3.5) = (dim-10.5) / (dim-7).
        final correctionToTopLeft = (dimension - 10.5) / (dimension - 7.0);

        final estAlignmentX =
            topLeft.x +
            correctionToTopLeft *
                (bottomLeft.x - topLeft.x + topRight.x - topLeft.x);
        final estAlignmentY =
            topLeft.y +
            correctionToTopLeft *
                (bottomLeft.y - topLeft.y + topRight.y - topLeft.y);

        // Validate estimated coordinates are finite
        if (estAlignmentX.isFinite && estAlignmentY.isFinite) {
          // Search for alignment pattern
          alignmentPattern = _findAlignmentInRegion(
            moduleSize,
            estAlignmentX.toInt(),
            estAlignmentY.toInt(),
            alignmentAreaAllowance.toDouble(),
          );
        }
      }
    }

    // Calculate bottom-right corner
    if (alignmentPattern != null) {
      bottomRightX = alignmentPattern.x;
      bottomRightY = alignmentPattern.y;
    } else {
      // For Version 1 (or failed Alignment search), use parallelogram assumption
      bottomRightX = topRight.x - topLeft.x + bottomLeft.x;
      bottomRightY = topRight.y - topLeft.y + bottomLeft.y;
    }

    final transform = _createTransform(
      topLeft,
      topRight,
      bottomLeft,
      bottomRightX,
      bottomRightY,
      dimension,
      alignmentPattern,
    );

    final bits = gridSampler.sampleGrid(image, dimension, dimension, transform);

    return DetectorResult(bits: bits, points: [bottomLeft, topLeft, topRight]);
  }

  /// Searches for an alignment pattern near the expected position.
  AlignmentPattern? _findAlignmentInRegion(
    double overallEstModuleSize,
    int estAlignmentX,
    int estAlignmentY,
    double allowanceFactor,
  ) {
    final allowance = (allowanceFactor * overallEstModuleSize).toInt();

    final alignmentAreaLeftX = max(0, estAlignmentX - allowance);
    final alignmentAreaRightX = min(image.width - 1, estAlignmentX + allowance);
    if (alignmentAreaRightX - alignmentAreaLeftX < overallEstModuleSize * 3) {
      return null;
    }

    final alignmentAreaTopY = max(0, estAlignmentY - allowance);
    final alignmentAreaBottomY = min(
      image.height - 1,
      estAlignmentY + allowance,
    );
    if (alignmentAreaBottomY - alignmentAreaTopY < overallEstModuleSize * 3) {
      return null;
    }

    final alignmentFinder = AlignmentPatternFinder(image, overallEstModuleSize);

    return alignmentFinder.find(
      startX: alignmentAreaLeftX,
      startY: alignmentAreaTopY,
      width: alignmentAreaRightX - alignmentAreaLeftX,
      height: alignmentAreaBottomY - alignmentAreaTopY,
    );
  }

  double _calculateModuleSize(
    FinderPattern topLeft,
    FinderPattern topRight,
    FinderPattern bottomLeft,
  ) {
    // Average of estimated module sizes
    return (topLeft.estimatedModuleSize +
            topRight.estimatedModuleSize +
            bottomLeft.estimatedModuleSize) /
        3.0;
  }

  int _computeDimension(
    FinderPattern topLeft,
    FinderPattern topRight,
    FinderPattern bottomLeft,
    double moduleSize,
  ) {
    // Distance TR to TL
    final distTop = _dist(topLeft, topRight);
    final distLeft = _dist(topLeft, bottomLeft);

    // Modules = dist / moduleSize
    // Patterns are centered at (3.5, 3.5), so distance between centers = dim - 7
    final dimTop = (distTop / moduleSize).round() + 7;
    final dimLeft = (distLeft / moduleSize).round() + 7;

    final dimension = (dimTop + dimLeft) ~/ 2;

    // Dimension n = 4V + 17, so n mod 4 == 1
    return adjustDimension(dimension);
  }

  /// Adjusts the dimension to be valid (mod 4 == 1).
  /// Public for unit testing verification of logic.
  static int adjustDimension(int dimension) {
    return switch (dimension % 4) {
      0 => dimension + 1,
      2 => dimension - 1,
      3 => dimension + 2,
      _ => dimension,
    };
  }

  PerspectiveTransform _createTransform(
    FinderPattern topLeft,
    FinderPattern topRight,
    FinderPattern bottomLeft,
    double bottomRightX,
    double bottomRightY,
    int dimension,
    AlignmentPattern? alignmentPattern,
  ) {
    final dimMinus3 = dimension - 3.5;

    double sourceBottomRightX;
    double sourceBottomRightY;

    if (alignmentPattern != null) {
      // Alignment pattern is centered at (dim - 7) + 0.5 = dim - 6.5
      sourceBottomRightX = dimension - 6.5;
      sourceBottomRightY = dimension - 6.5;
    } else {
      sourceBottomRightX = dimMinus3;
      sourceBottomRightY = dimMinus3;
    }

    return PerspectiveTransform.quadrilateralToQuadrilateral(
      x0: 3.5,
      y0: 3.5, // TL desired (Modules)
      x1: dimMinus3,
      y1: 3.5, // TR desired
      x2: sourceBottomRightX,
      y2: sourceBottomRightY, // BR desired
      x3: 3.5,
      y3: dimMinus3, // BL desired

      x0p: topLeft.x,
      y0p: topLeft.y,
      x1p: topRight.x,
      y1p: topRight.y,
      x2p: bottomRightX,
      y2p: bottomRightY,
      x3p: bottomLeft.x,
      y3p: bottomLeft.y,
    );
  }

  double _dist(FinderPattern a, FinderPattern b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  }

  /// Detects multiple QR codes in the image.
  ///
  /// Returns a list of detector results, one for each detected QR code.
  List<DetectorResult> detectMulti() {
    final finder = FinderPatternFinder(image);
    final infoList = finder.findMulti();

    final results = <DetectorResult>[];
    for (final info in infoList) {
      try {
        results.add(processFinderPatternInfo(info));
      } catch (_) {
        // Skip invalid patterns
        continue;
      }
    }

    return results;
  }
}
