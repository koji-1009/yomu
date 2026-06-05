import 'dart:math';

import '../common/bit_matrix.dart';
import '../common/grid_sampler.dart';
import '../common/perspective_transform.dart';
import 'decoder/decoded_bit_stream_parser.dart';
import 'decoder/qrcode_decoder.dart';
import 'detector/detector.dart';
import 'detector/finder_pattern.dart';
import 'detector/finder_pattern_finder.dart';
import 'detector/tolerant_finder_pattern_finder.dart';

/// Escalating retry strategies for QR decoding ("try harder" mode).
///
/// All strategies run only after the fast path has failed, so successful
/// scans pay nothing. Wrong results are impossible: every retry is
/// validated by format-information BCH and Reed-Solomon decoding.
///
/// Stages (cheapest first):
/// 1. [decodeWithFinderInfo] - dimension candidates and a grid search of
///    the bottom-right corner around the parallelogram estimate. Rescues
///    perspective-distorted codes whose finder patterns were located but
///    whose dimension/transform estimate was off.
/// 2. [decodeDeep] despeckle - a 3x3 majority filter removes salt & pepper
///    noise that breaks the 1:1:3:1:1 run detection, then re-detects.
/// 3. [decodeDeep] tolerant finder - clusters raw row-scan hits without the
///    strict vertical cross-check, recovering slanted finder patterns.
///
/// An instance is stateful and must be used for a single decode call: it
/// deduplicates repeated grid searches (the same finder geometry can
/// resurface in several stages) and enforces a deterministic work budget
/// so that undecodable inputs cannot make the retry ladder pathologically
/// slow.
class TryHarderDecoder {
  TryHarderDecoder({this.alignmentAreaAllowance = 15});

  /// Allowance for alignment pattern search (modules).
  final int alignmentAreaAllowance;

  /// Work budget for grid searches, in sampled grid points (dim^2 per
  /// attempt). Deterministic (machine independent), unlike a wall-clock
  /// budget, so retry outcomes are reproducible in tests and across
  /// devices. 500k points bound the grid work to roughly 10ms on M-class
  /// hardware (AOT). The offsets are searched nearest-first, so rescues
  /// hit early: the most expensive fixture rescue consumes ~88k points,
  /// leaving over 5x headroom.
  static const int gridPointBudget = 500000;

  int _remainingGridPoints = gridPointBudget;

  /// Remaining grid-search work budget in sampled points.
  /// Exposed for diagnostics and testing.
  int get remainingGridPoints => _remainingGridPoints;

  /// Whether any grid-search budget remains. [Yomu.decode] gates the
  /// full-resolution retry on this: an input that has already exhausted
  /// the budget on garbage candidates is not worth a full-resolution pass.
  bool get hasBudget => _remainingGridPoints > 0;

  /// Grid searches already performed, keyed by matrix identity, quantized
  /// finder geometry and dimension. The same (or nearly the same) triplet
  /// reappears across retry stages; re-searching it cannot succeed and
  /// would multiply the worst-case cost.
  final Set<int> _triedGridSearches = {};

  /// Bottom-right corner grid search half-extent in half-module steps
  /// (6 -> +-3 modules).
  static const int _brGridHalfExtent = 6;

  /// Maximum tolerant-finder triplets that get the (expensive) bottom-right
  /// grid search; the remaining triplets only get the plain decode attempt.
  static const int _maxGridSearchTriplets = 3;

  /// Minimum module size (pixels) for the grid search to be worthwhile.
  ///
  /// Below ~2px/module the sampled grid cannot be reliable anyway, and
  /// noise images produce false finder patterns with ~1.5px modules whose
  /// huge derived dimensions would make the grid search pathologically
  /// expensive (every rescued fixture has >= 3.4px modules).
  static const double _minGridSearchModuleSize = 2.0;

  static const _decoder = QRCodeDecoder();
  static const _sampler = GridSampler();

  /// Offsets (dy, dx) of the bottom-right grid search ordered by distance
  /// from the parallelogram estimate, so likely candidates decode first.
  static final List<(int, int)> _brGridOffsets = _buildGridOffsets();

  static List<(int, int)> _buildGridOffsets() {
    const n = _brGridHalfExtent;
    final offsets = <(int, int)>[];
    for (var dy = -n; dy <= n; dy++) {
      for (var dx = -n; dx <= n; dx++) {
        offsets.add((dy, dx));
      }
    }
    offsets.sort((a, b) {
      final da = a.$1 * a.$1 + a.$2 * a.$2;
      final db = b.$1 * b.$1 + b.$2 * b.$2;
      return da.compareTo(db);
    });
    return offsets;
  }

  /// Retries decoding with located finder patterns: tries per-axis
  /// dimension candidates and brute-forces the bottom-right corner around
  /// the parallelogram estimate.
  ///
  /// Returns null if no candidate decodes.
  DecoderResult? decodeWithFinderInfo(
    BitMatrix matrix,
    FinderPatternInfo info,
  ) {
    final tl = info.topLeft;
    final tr = info.topRight;

    final distTop = _dist(tl, tr);
    if (!distTop.isFinite || distTop <= 0) {
      return null;
    }

    // Dimension from the top edge's own module size: more accurate than
    // the all-corners average when perspective skews the left edge.
    final msTop = (tl.estimatedModuleSize + tr.estimatedModuleSize) / 2.0;
    if (msTop < _minGridSearchModuleSize) {
      return null;
    }
    final dimTop = Detector.adjustDimension((distTop / msTop).round() + 7);

    final tried = <int>{};
    for (final dimBase in [dimTop, dimTop - 4, dimTop + 4]) {
      final dim = Detector.adjustDimension(dimBase);
      if (dim < 21 || dim > 177 || !tried.add(dim)) {
        continue;
      }

      final result = _gridSearchBottomRight(matrix, info, dim);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Runs the deep retry ladder: despeckle, then the tolerant finder.
  /// Returns null if everything fails.
  DecoderResult? decodeDeep(BitMatrix matrix) {
    // Stage: despeckle. Salt & pepper noise splits the 1:1:3:1:1 runs;
    // a 3x3 majority vote restores them (QR modules are wider than noise).
    final despeckled = matrix.majority3x3();
    final despeckledResult = _detectAndDecode(despeckled);
    if (despeckledResult != null) {
      return despeckledResult;
    }

    // Stage: tolerant finder on the original matrix. Slanted patterns
    // (perspective) fail the strict vertical cross-check but their row
    // hits still cluster.
    return _decodeTolerant(matrix);
  }

  /// Strict find -> decode -> bottom-right grid retry on [matrix].
  DecoderResult? _detectAndDecode(BitMatrix matrix) {
    final FinderPatternInfo info;
    try {
      info = FinderPatternFinder(matrix).find();
    } catch (_) {
      return null;
    }

    final detector = Detector(
      matrix,
      alignmentAreaAllowance: alignmentAreaAllowance,
    );
    try {
      return _decoder.decode(detector.processFinderPatternInfo(info).bits);
    } catch (_) {
      // Fall through to the grid retry with the same finder info.
    }
    return decodeWithFinderInfo(matrix, info);
  }

  /// Tolerant cluster-based finding plus decode attempts per triplet.
  DecoderResult? _decodeTolerant(BitMatrix matrix) {
    final patterns = TolerantFinderPatternFinder(matrix).find();
    final triplets = TolerantFinderPatternFinder.enumerateTriplets(patterns);
    if (triplets.isEmpty) {
      return null;
    }

    final detector = Detector(
      matrix,
      alignmentAreaAllowance: alignmentAreaAllowance,
    );

    // Cheap pass first: plain detection per triplet.
    for (final info in triplets) {
      try {
        return _decoder.decode(detector.processFinderPatternInfo(info).bits);
      } catch (_) {
        continue;
      }
    }

    // Expensive pass: bottom-right grid search on the strongest triplets.
    final gridLimit = min(triplets.length, _maxGridSearchTriplets);
    for (var t = 0; t < gridLimit; t++) {
      final result = decodeWithFinderInfo(matrix, triplets[t]);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Brute-forces the bottom-right corner around the parallelogram
  /// estimate at the given [dim]. Garbage samples fail fast at the format
  /// information BCH check, so the search is cheap relative to its reach.
  DecoderResult? _gridSearchBottomRight(
    BitMatrix matrix,
    FinderPatternInfo info,
    int dim,
  ) {
    final tl = info.topLeft;
    final tr = info.topRight;
    final bl = info.bottomLeft;

    // Module step vectors along the top and left edges.
    final modules = dim - 7;
    final unitTopX = (tr.x - tl.x) / modules;
    final unitTopY = (tr.y - tl.y) / modules;
    final unitLeftX = (bl.x - tl.x) / modules;
    final unitLeftY = (bl.y - tl.y) / modules;

    // Parallelogram estimate of the bottom-right pattern center.
    final brX = tr.x + bl.x - tl.x;
    final brY = tr.y + bl.y - tl.y;

    if (!brX.isFinite || !brY.isFinite) {
      return null;
    }

    // Deduplicate: the same geometry on the same matrix cannot succeed
    // twice. Coordinates are quantized to 2px so that near-identical
    // triplets from different stages collapse to one search.
    final key = Object.hash(
      identityHashCode(matrix),
      dim,
      (tl.x / 2).round(),
      (tl.y / 2).round(),
      (tr.x / 2).round(),
      (tr.y / 2).round(),
      (bl.x / 2).round(),
      (bl.y / 2).round(),
    );
    if (!_triedGridSearches.add(key)) {
      return null;
    }

    final pointsPerAttempt = dim * dim;
    final dimMinus3 = dim - 3.5;
    for (final (dy, dx) in _brGridOffsets) {
      if (_remainingGridPoints <= 0) {
        return null;
      }
      _remainingGridPoints -= pointsPerAttempt;

      final candX = brX + 0.5 * (dx * unitTopX + dy * unitLeftX);
      final candY = brY + 0.5 * (dx * unitTopY + dy * unitLeftY);

      try {
        final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
          x0: 3.5,
          y0: 3.5,
          x1: dimMinus3,
          y1: 3.5,
          x2: dimMinus3,
          y2: dimMinus3,
          x3: 3.5,
          y3: dimMinus3,
          x0p: tl.x,
          y0p: tl.y,
          x1p: tr.x,
          y1p: tr.y,
          x2p: candX,
          y2p: candY,
          x3p: bl.x,
          y3p: bl.y,
        );
        final bits = _sampler.sampleGrid(matrix, dim, dim, transform);
        return _decoder.decode(bits);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static double _dist(FinderPattern a, FinderPattern b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }
}
