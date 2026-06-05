import 'dart:math';

import '../../common/bit_matrix.dart';
import 'finder_pattern.dart';
import 'finder_pattern_finder.dart';

/// A candidate finder-pattern location built from clustered row-scan hits.
///
/// Unlike [FinderPatternFinder], no vertical cross-check is applied while
/// clustering, so patterns slanted by perspective distortion (whose columns
/// drift sideways) are still captured.
class PatternCluster {
  PatternCluster({
    required this.firstRow,
    required double x,
    required double moduleSize,
  }) : lastRow = firstRow,
       lastX = x,
       _sumX = x,
       _sumModuleSize = moduleSize,
       hitCount = 1;

  int firstRow;
  int lastRow;
  double lastX;
  double _sumX;
  double _sumModuleSize;
  int hitCount;

  double get avgX => _sumX / hitCount;
  double get avgModuleSize => _sumModuleSize / hitCount;
  int get rowSpan => lastRow - firstRow + 1;
  double get centerY => (firstRow + lastRow) / 2.0;

  void add(int row, double x, double moduleSize) {
    lastRow = row;
    lastX = x;
    _sumX += x;
    _sumModuleSize += moduleSize;
    hitCount++;
  }
}

/// Locates finder patterns tolerantly for retry paths.
///
/// Scans every row for the 1:1:3:1:1 ratio, clusters hits by drifting-x
/// proximity (tracking slanted patterns), refines each cluster's vertical
/// center by a local column scan, and returns candidates ordered by
/// hit count.
///
/// This is slower than [FinderPatternFinder] (no row skipping, more
/// candidates kept) and less strict, so it must only run after the strict
/// finder has failed. Decoding validates the result, so false positives
/// cost time but never produce wrong output.
class TolerantFinderPatternFinder {
  TolerantFinderPatternFinder(this.image);

  /// Maximum number of clusters considered for triplet enumeration.
  static const int maxClusters = 8;

  /// Maximum row gap within a cluster (allows noise-broken rows).
  static const int _maxRowGap = 3;

  final BitMatrix image;

  /// Finds candidate finder patterns, strongest (most row hits) first.
  List<FinderPattern> find() {
    final clusters = _scanClusters();

    // A finder pattern's center square is 3 modules tall; require enough
    // vertical evidence while tolerating perspective compression.
    final valid =
        clusters
            .where((c) => c.hitCount >= 3 && c.rowSpan >= c.avgModuleSize * 1.2)
            .toList()
          ..sort((a, b) => b.hitCount.compareTo(a.hitCount));

    if (valid.length > maxClusters) {
      valid.removeRange(maxClusters, valid.length);
    }

    return valid.map(_toPattern).toList();
  }

  /// Enumerates plausible (bottomLeft, topLeft, topRight) triplets from
  /// [patterns], strongest first, capped to keep retry cost bounded.
  static List<FinderPatternInfo> enumerateTriplets(
    List<FinderPattern> patterns,
  ) {
    final n = patterns.length;
    if (n < 3) {
      return const [];
    }

    final result = <FinderPatternInfo>[];
    for (var i = 0; i < n - 2; i++) {
      for (var j = i + 1; j < n - 1; j++) {
        for (var k = j + 1; k < n; k++) {
          final a = patterns[i];
          final b = patterns[j];
          final c = patterns[k];

          // Perspective changes module sizes between corners; allow up to
          // 2x (the strict finder requires 1.5x).
          final maxSize = max(
            a.estimatedModuleSize,
            max(b.estimatedModuleSize, c.estimatedModuleSize),
          );
          final minSize = min(
            a.estimatedModuleSize,
            min(b.estimatedModuleSize, c.estimatedModuleSize),
          );
          if (maxSize > minSize * 2.0) {
            continue;
          }

          result.add(FinderPatternFinder.orderPatterns(a, b, c));
        }
      }
    }
    return result;
  }

  List<PatternCluster> _scanClusters() {
    final maxJ = image.width;
    final maxI = image.height;
    final bits = image.bits;
    final rowStride = image.rowStride;

    final open = <PatternCluster>[];
    final closed = <PatternCluster>[];
    final stateCount = List<int>.filled(5, 0);

    for (var i = 0; i < maxI; i++) {
      stateCount.fillRange(0, 5, 0);
      var currentState = 0;
      var wordOffset = i * rowStride;

      for (var j = 0; j < maxJ; j += 32) {
        final remaining = maxJ - j;
        final currentWord = bits[wordOffset++];
        final limit = (remaining < 32) ? remaining : 32;

        if (currentWord == 0 && (currentState & 1) == 1 && limit == 32) {
          stateCount[currentState] += 32;
          continue;
        }
        if (currentWord == 0xFFFFFFFF &&
            (currentState & 1) == 0 &&
            limit == 32) {
          stateCount[currentState] += 32;
          continue;
        }

        for (var b = 0; b < limit; b++) {
          if ((currentWord & (1 << b)) != 0) {
            if ((currentState & 1) == 1) {
              currentState++;
            }
            stateCount[currentState]++;
          } else {
            if ((currentState & 1) == 0) {
              if (currentState == 4) {
                if (FinderPatternFinder.foundPatternCross(stateCount)) {
                  _recordHit(
                    open: open,
                    row: i,
                    endX: j + b,
                    stateCount: stateCount,
                  );
                }
                stateCount[0] = stateCount[2];
                stateCount[1] = stateCount[3];
                stateCount[2] = stateCount[4];
                stateCount[3] = 1;
                stateCount[4] = 0;
                currentState = 3;
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

      // End of row: the pattern may end at the right edge.
      if (currentState == 4 &&
          FinderPatternFinder.foundPatternCross(stateCount)) {
        _recordHit(open: open, row: i, endX: maxJ, stateCount: stateCount);
      }

      // Retire clusters that have not been extended recently.
      for (var idx = open.length - 1; idx >= 0; idx--) {
        if (i - open[idx].lastRow > _maxRowGap) {
          closed.add(open[idx]);
          open.removeAt(idx);
        }
      }
    }

    closed.addAll(open);
    return closed;
  }

  void _recordHit({
    required List<PatternCluster> open,
    required int row,
    required int endX,
    required List<int> stateCount,
  }) {
    var total = 0;
    for (var s = 0; s < 5; s++) {
      total += stateCount[s];
    }
    final centerX = endX - stateCount[4] - stateCount[3] - stateCount[2] / 2.0;
    final moduleSize = total / 7.0;

    PatternCluster? best;
    var bestDist = double.infinity;
    for (final c in open) {
      final dist = (c.lastX - centerX).abs();
      if (dist < c.avgModuleSize * 1.5 && dist < bestDist) {
        best = c;
        bestDist = dist;
      }
    }

    if (best != null) {
      best.add(row, centerX, moduleSize);
    } else {
      open.add(
        PatternCluster(firstRow: row, x: centerX, moduleSize: moduleSize),
      );
    }
  }

  FinderPattern _toPattern(PatternCluster cluster) {
    final refinedY = _refineVerticalCenter(cluster);
    return FinderPattern(
      x: cluster.avgX,
      y: refinedY ?? cluster.centerY,
      estimatedModuleSize: cluster.avgModuleSize,
      count: cluster.hitCount,
    );
  }

  /// Refines the vertical center by walking the column at the cluster's
  /// center and validating the local 1:1:3:1:1 ratio. Returns null when the
  /// column does not exhibit the ratio (e.g. cropped patterns), in which
  /// case the row-span midpoint remains the best estimate.
  double? _refineVerticalCenter(PatternCluster cluster) {
    final x = cluster.avgX.round();
    if (x < 0 || x >= image.width) {
      return null;
    }
    final y = cluster.centerY.round();
    if (y < 0 || y >= image.height || !image.get(x, y)) {
      return null;
    }

    // Bound ring runs generously: perspective can stretch the vertical
    // module size well beyond the horizontal estimate. The final ratio
    // check validates the result, so the bound only limits walk cost.
    // The center run is unbounded; it terminates at the ring's inner white.
    final maxRun = (cluster.avgModuleSize * 3).ceil() + 1;

    // Walk up from the center: black (2), white (1), black (0).
    final up2 = _runLength(x: x, startY: y, step: -1, dark: true);
    final s1 = _runLength(
      x: x,
      startY: y - up2,
      step: -1,
      dark: false,
      limit: maxRun,
    );
    final s0 = _runLength(
      x: x,
      startY: y - up2 - s1,
      step: -1,
      dark: true,
      limit: maxRun,
    );

    // Walk down: black (2), white (3), black (4).
    final down2 = _runLength(x: x, startY: y + 1, step: 1, dark: true);
    final s3 = _runLength(
      x: x,
      startY: y + 1 + down2,
      step: 1,
      dark: false,
      limit: maxRun,
    );
    final s4 = _runLength(
      x: x,
      startY: y + 1 + down2 + s3,
      step: 1,
      dark: true,
      limit: maxRun,
    );

    final stateCount = [s0, s1, up2 + down2, s3, s4];
    if (!FinderPatternFinder.foundPatternCross(stateCount)) {
      return null;
    }
    final bottom = y + 1 + down2 + s3 + s4;
    return bottom - s4 - s3 - (up2 + down2) / 2.0;
  }

  /// Counts consecutive pixels of the given color along the column at [x],
  /// starting at [startY] and moving by [step], stopping at the image edge
  /// or after [limit] pixels.
  int _runLength({
    required int x,
    required int startY,
    required int step,
    required bool dark,
    int? limit,
  }) {
    final height = image.height;
    var y = startY;
    var count = 0;
    while (y >= 0 &&
        y < height &&
        image.get(x, y) == dark &&
        (limit == null || count < limit)) {
      count++;
      y += step;
    }
    return count;
  }
}
