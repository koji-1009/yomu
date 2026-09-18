import 'dart:typed_data';

import 'barcode/barcode_result.dart';
import 'barcode/barcode_scanner.dart';
import 'common/binarizer/binarizer.dart';
import 'common/binarizer/luminance_source.dart';
import 'common/bit_matrix.dart';
import 'common/image_processor.dart';
import 'decode_effort.dart';
import 'image_data.dart';
import 'qr/decoder/decoded_bit_stream_parser.dart';
import 'qr/decoder/qrcode_decoder.dart';
import 'qr/detector/detector.dart';
import 'qr/detector/finder_pattern.dart';
import 'qr/detector/finder_pattern_finder.dart';
import 'qr/try_harder_decoder.dart';
import 'yomu_exception.dart';

/// The main entry point for QR code and barcode decoding operations.
///
/// [Yomu] provides a simple, high-level API for decoding QR codes and
/// 1D barcodes from raw image data.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:yomu/yomu.dart';
///
/// // Create a YomuImage container
/// final image = YomuImage.rgba(bytes: bytes, width: 300, height: 300);
///
/// // Decode
/// final result = Yomu.all.decode(image);
/// print(result.text);
/// ```
class Yomu {
  /// Creates a new [Yomu] decoder instance.
  ///
  /// Parameters:
  /// - [enableQRCode]: Whether to scan for QR codes (default: true)
  /// - [barcodeScanner]: Configuration for 1D barcode scanning (default: none)
  /// - [binarizerThreshold]: Threshold factor for binarization (default: 0.875)
  /// - [alignmentAreaAllowance]: Allowance for alignment pattern search (default: 15)
  /// - [effort]: How much work to spend on images the fast path cannot
  ///   decode (default: [DecodeEffort.thorough])
  /// - [readLightOnDark]: Whether to read QR codes printed with reflectance
  ///   reversal (default: true)
  const Yomu({
    required this.enableQRCode,
    required this.barcodeScanner,
    this.binarizerThreshold = 0.875,
    this.alignmentAreaAllowance = 15,
    DecodeEffort? effort,
    this.readLightOnDark = true,
    @Deprecated('Use effort: DecodeEffort.fast / .thorough instead')
    bool? tryHarder,
  }) : effort =
           effort ??
           (tryHarder == false ? DecodeEffort.fast : DecodeEffort.thorough);

  /// Whether to scan for QR codes.
  final bool enableQRCode;

  /// Configuration for 1D barcode scanning.
  final BarcodeScanner barcodeScanner;

  /// Threshold factor for binarization.
  final double binarizerThreshold;

  /// Allowance for alignment pattern search.
  final int alignmentAreaAllowance;

  /// How much work [decode] and [decodeAll] may spend on an image the fast
  /// path cannot decode.
  ///
  /// Retries only run on images the fast path cannot decode, so successful
  /// scans are unaffected by this. See [DecodeEffort] for the measured
  /// detection and latency of each level.
  final DecodeEffort effort;

  /// Whether to also read QR codes printed with reflectance reversal: light
  /// modules on a dark background (ISO/IEC 18004:2015, 6.2). This is a colour
  /// inversion, not a mirror image.
  ///
  /// On by default, as the symbology intends symbols to be read either way.
  /// The finder pattern scan then also checks light-on-dark candidates, which
  /// images holding no code pay for: on a textured Full HD frame, about 1ms
  /// at [DecodeEffort.fast] and [DecodeEffort.balanced]. Turn it off when
  /// every code you read is dark on light.
  final bool readLightOnDark;

  /// Whether any retry stage runs at all.
  @Deprecated('Use effort instead')
  bool get tryHarder => effort != DecodeEffort.fast;

  /// Whether [effort] admits stages that rebuild the image from the source
  /// pixels (full-resolution conversion, alternate binarization thresholds).
  bool get _rebuildsImage => effort == DecodeEffort.thorough;

  /// Shared decoder instance for QR code decoding.
  static const _decoder = QRCodeDecoder();

  /// Yomu with QR code and all barcode formats enabled.
  static const all = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.all,
  );

  /// Yomu with only QR code scanning enabled.
  static const qrOnly = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.none,
  );

  /// Yomu with only 1D barcode scanning enabled.
  static const barcodeOnly = Yomu(
    enableQRCode: false,
    barcodeScanner: BarcodeScanner.all,
  );

  /// Yomu tuned for real-time per-frame scanning (camera preview).
  ///
  /// Identical to [all] but at [DecodeEffort.fast]: frames without a code
  /// fail as fast as possible instead of paying the retry ladder. A code
  /// missed on one frame is simply caught on a later one.
  static const realtime = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.all,
    effort: DecodeEffort.fast,
  );

  /// Yomu for streams that can afford more than [realtime] per frame.
  ///
  /// All formats at [DecodeEffort.balanced]: every retry that reuses the
  /// binarized image runs, but none that rebuilds it, so a frame holding no
  /// code costs a few times the fast path rather than an order of magnitude.
  static const responsive = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.all,
    effort: DecodeEffort.balanced,
  );

  /// Decodes a QR code or barcode from a [YomuImage].
  ///
  /// This is the preferred method for decoding as it handles different image formats
  /// and row strides correctly.
  ///
  /// A QR code printed with reflectance reversal (light modules on a dark
  /// background) is read at every [DecodeEffort]. Its finder patterns are
  /// collected by the same row scan as the normal ones, and tried once the
  /// normal attempt and barcode scanning fail.
  ///
  /// Above [DecodeEffort.fast], escalating retry strategies run when the
  /// fast path fails: bottom-right corner grid search, despeckle and the
  /// tolerant finder, plus - at [DecodeEffort.thorough] - a full-resolution
  /// retry and a sweep of alternate binarization thresholds. In those modes
  /// a detected-but-undecodable QR code falls through to barcode scanning
  /// instead of propagating a [DecodeException].
  DecoderResult decode(YomuImage image) {
    final (pixels, processWidth, processHeight) = _processImage(image);

    if (effort == DecodeEffort.fast) {
      return _decodeFastOnly(pixels, processWidth, processHeight);
    }

    final source = LuminanceSource(
      width: processWidth,
      height: processHeight,
      luminances: pixels,
    );

    BitMatrix? matrix;
    BitMatrix? inverted;
    FinderPatternFinder? finder;

    // One retry decoder per decode call: it deduplicates grid searches
    // across stages and enforces the deterministic work budget.
    final retry = _newTryHarderDecoder();

    // Stage 1+2: fast QR path, then dimension/corner retries reusing the
    // located finder patterns. The row scan also collects light-on-dark
    // finder patterns for the reflectance reversal stage.
    if (enableQRCode) {
      matrix = Binarizer(
        source,
        thresholdFactor: binarizerThreshold,
      ).getBlackMatrix();
      inverted = _lightOnDarkImage(matrix);
      finder = FinderPatternFinder(matrix, invertedImage: inverted);

      final fast = _decodeLocated(matrix, finder.find, retry);
      if (fast != null) {
        return fast;
      }
    }

    // Barcode before the deep QR retries: scanning is cheap and barcode
    // images rarely contain QR finder patterns, so they exit here without
    // paying the retry cost.
    if (!barcodeScanner.isEmpty) {
      final barcodeResult = _scanBarcode(pixels, processWidth, processHeight);
      if (barcodeResult != null) {
        return barcodeResult;
      }
    }

    if (enableQRCode) {
      // Reflectance reversal: light modules on a dark background, from the
      // finder patterns stage 1 already collected.
      if (finder!.inverted case final lightOnDark?) {
        final reversed = _decodeLocated(
          inverted!,
          lightOnDark.selectBest,
          retry,
        );
        if (reversed != null) {
          return reversed;
        }
      }

      // Stages 3-4: despeckle, tolerant finder.
      final deep = retry.decodeDeep(matrix!);
      if (deep != null) {
        return deep;
      }

      // Stage 5: full-resolution retry. Downsampling can shrink small
      // codes below the detectable module size. Skipped when the work
      // budget is already exhausted on garbage candidates.
      if (_rebuildsImage &&
          (processWidth < image.width || processHeight < image.height) &&
          retry.hasBudget) {
        final fullRes = _decodeFullResolution(image, retry);
        if (fullRes != null) {
          return fullRes;
        }
      }

      // Stage 6: alternate binarization thresholds, cheapest attempt first
      // across all of them. Placing the whole sweep last costs the images it
      // rescues one wasted ladder, but placing even its cheap half earlier
      // would tax every image that the earlier stages already rescue - and
      // those are the far more common case.
      if (_rebuildsImage) {
        final swept = _decodeWithAlternateThresholds(source);
        if (swept != null) {
          return swept;
        }
      }
    }

    throw const DetectionException('No QR code or barcode found');
  }

  /// Previous (fast-only) decode behavior, used when [tryHarder] is off.
  DecoderResult _decodeFastOnly(Uint8List pixels, int width, int height) {
    BitMatrix? inverted;
    FinderPatternFinder? finder;

    // Try QR code first
    if (enableQRCode) {
      final matrix = Binarizer(
        LuminanceSource(width: width, height: height, luminances: pixels),
        thresholdFactor: binarizerThreshold,
      ).getBlackMatrix();
      inverted = _lightOnDarkImage(matrix);
      finder = FinderPatternFinder(matrix, invertedImage: inverted);
      try {
        return _decodeQRFromInfo(matrix, finder.find());
      } on DetectionException {
        // Fall through to barcode scanning
      }
    }

    // Try 1D barcodes
    if (!barcodeScanner.isEmpty) {
      final barcodeResult = _scanBarcode(pixels, width, height);
      if (barcodeResult != null) {
        return barcodeResult;
      }
    }

    // Reflectance reversal: light modules on a dark background, from the
    // finder patterns the QR attempt's row scan already collected.
    if (finder?.inverted case final lightOnDark?) {
      try {
        return _decodeQRFromInfo(inverted!, lightOnDark.selectBest());
      } on DetectionException {
        // Fall through
      }
    }

    throw const DetectionException('No QR code or barcode found');
  }

  /// Scans for a 1D barcode and wraps the result as a [DecoderResult].
  DecoderResult? _scanBarcode(Uint8List pixels, int width, int height) {
    final barcodeResult = _decodeBarcodeFromPixels(pixels, width, height);
    if (barcodeResult == null) {
      return null;
    }
    return DecoderResult(
      text: barcodeResult.text,
      byteSegments: const [],
      ecLevel: null,
    );
  }

  /// Builds the retry decoder configured like this instance.
  TryHarderDecoder _newTryHarderDecoder({int? gridPointBudget}) {
    return TryHarderDecoder(
      alignmentAreaAllowance: alignmentAreaAllowance,
      gridPointBudget:
          gridPointBudget ?? TryHarderDecoder.defaultGridPointBudget,
    );
  }

  /// Stage 1+2: locates finder patterns once, tries the fast decode, then
  /// the dimension/corner retries. Returns null on failure.
  DecoderResult? _decodeFastWithCornerRetry(
    BitMatrix matrix,
    TryHarderDecoder retry,
  ) {
    return _decodeLocated(matrix, FinderPatternFinder(matrix).find, retry);
  }

  /// Stage 1+2 on the finder patterns [locate] returns for [matrix]: the
  /// fast decode, then the dimension/corner retries. Returns null on
  /// failure.
  DecoderResult? _decodeLocated(
    BitMatrix matrix,
    FinderPatternInfo Function() locate,
    TryHarderDecoder retry,
  ) {
    final FinderPatternInfo info;
    try {
      info = locate();
    } on YomuException {
      return null;
    }

    final fast = _decodeWithAllowances(matrix, info);
    if (fast != null) {
      return fast;
    }
    return retry.decodeWithFinderInfo(matrix, info);
  }

  /// Decodes with the tight-then-expanded alignment allowance strategy,
  /// reusing already located finder patterns.
  ///
  /// With [rethrowFinal] the expanded attempt's exception propagates
  /// instead of returning null (the fast-only contract, where a
  /// [DecodeException] must reach the caller).
  DecoderResult? _decodeWithAllowances(
    BitMatrix matrix,
    FinderPatternInfo info, {
    bool rethrowFinal = false,
  }) {
    // Tight allowance first: avoids false-positive alignment patterns in
    // clean images where noise might exist far away.
    if (alignmentAreaAllowance > 5) {
      try {
        final detector = Detector(matrix, alignmentAreaAllowance: 5);
        return _decoder.decode(detector.processFinderPatternInfo(info).bits);
      } catch (_) {
        // Fall through to the expanded allowance.
      }
    }

    try {
      final detector = Detector(
        matrix,
        alignmentAreaAllowance: alignmentAreaAllowance,
      );
      return _decoder.decode(detector.processFinderPatternInfo(info).bits);
    } catch (_) {
      if (rethrowFinal) {
        rethrow;
      }
      return null;
    }
  }

  /// Threshold factors retried once every stage at [binarizerThreshold] has
  /// failed, ordered by how much they recover in practice.
  ///
  /// The default factor assumes a code whose ink is clearly darker than its
  /// local mean. Screen moire and washed-out prints push the modules toward
  /// that mean, so a darker factor is needed to keep them black; heavy
  /// sensor noise and scan blur do the opposite, lifting the background into
  /// the code, where only a factor above 1 separates them again.
  static const _retryThresholdFactors = [0.6, 1.0, 1.1];

  /// Binarizes [source] once per entry in [_retryThresholdFactors],
  /// skipping the configured [binarizerThreshold] (already tried).
  List<BitMatrix> _alternateMatrices(LuminanceSource source) {
    return [
      for (final factor in _retryThresholdFactors)
        if (factor != binarizerThreshold)
          Binarizer(source, thresholdFactor: factor).getBlackMatrix(),
    ];
  }

  /// Grid-search budget granted to each alternate binarization.
  ///
  /// A fresh allowance is required: the default-threshold stages typically
  /// spend theirs on candidates that were never going to decode, and a
  /// sweep sharing that exhausted budget could not run the grid search that
  /// actually rescues the image. It is half of
  /// [TryHarderDecoder.defaultGridPointBudget] so that granting one per
  /// factor still bounds the whole call: the most expensive rescue observed
  /// on an alternate threshold costs ~152k points, leaving headroom without
  /// letting the sweep dominate the worst case.
  static const _sweepGridPointBudget = 250000;

  /// Final QR stage: retries every alternate binarization on the fast path
  /// before any of them pays for the deep ladder, so a code that merely
  /// needed a different threshold is not charged for the expensive stages.
  DecoderResult? _decodeWithAlternateThresholds(LuminanceSource source) {
    final alternates = _alternateMatrices(source);
    final retries = [
      for (var i = 0; i < alternates.length; i++)
        _newTryHarderDecoder(gridPointBudget: _sweepGridPointBudget),
    ];

    for (var i = 0; i < alternates.length; i++) {
      final result = _decodeFastWithCornerRetry(alternates[i], retries[i]);
      if (result != null) {
        return result;
      }
    }
    for (var i = 0; i < alternates.length; i++) {
      final result = retries[i].decodeDeep(alternates[i]);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Stage 5: re-runs conversion at full resolution and tries the fast
  /// path plus the corner retry. Returns null on failure.
  DecoderResult? _decodeFullResolution(
    YomuImage image,
    TryHarderDecoder retry,
  ) {
    final matrix = _fullResolutionMatrix(image);
    if (matrix == null) {
      return null;
    }
    return _decodeFastWithCornerRetry(matrix, retry);
  }

  /// Converts and binarizes [image] at full resolution. Returns null when
  /// the conversion fails.
  BitMatrix? _fullResolutionMatrix(YomuImage image) {
    final Uint8List pixels;
    final int width;
    final int height;
    try {
      (pixels, width, height) = ImageProcessor.process(
        image,
        allowDownsample: false,
      );
    } catch (_) {
      return null;
    }

    final source = LuminanceSource(
      width: width,
      height: height,
      luminances: pixels,
    );
    return Binarizer(
      source,
      thresholdFactor: binarizerThreshold,
    ).getBlackMatrix();
  }

  /// Decodes all QR codes from a [YomuImage].
  ///
  /// When the normal pass decodes nothing, the light-on-dark finder patterns
  /// its row scan collected are tried, for codes printed with reflectance
  /// reversal.
  ///
  /// Above [DecodeEffort.fast], codes that are detected but fail to decode
  /// get the corner-grid rescue, and when an entire pass finds nothing the
  /// scan escalates to despeckle; at [DecodeEffort.thorough] it also
  /// re-scans at alternate thresholds and at full resolution. Sheets that
  /// decode on the fast pass pay no retry cost.
  List<DecoderResult> decodeAll(YomuImage image) {
    if (!enableQRCode) {
      return const [];
    }

    final (pixels, processWidth, processHeight) = _processImage(image);

    if (effort == DecodeEffort.fast) {
      return _decodeAllQRFromPixels(pixels, processWidth, processHeight);
    }

    final retry = _newTryHarderDecoder();
    final source = LuminanceSource(
      width: processWidth,
      height: processHeight,
      luminances: pixels,
    );
    final matrix = Binarizer(
      source,
      thresholdFactor: binarizerThreshold,
    ).getBlackMatrix();
    final inverted = _lightOnDarkImage(matrix);
    final finder = FinderPatternFinder(matrix, invertedImage: inverted);

    // Pass 1: fast multi scan (with the in-pass corner rescue). Its row
    // scan also collects light-on-dark finder patterns.
    final fast = _decodeAllOnInfos(matrix, finder.findMulti(), retry);
    if (fast.decodedAll) {
      return fast.results;
    }

    // Pass 2: alternate binarization thresholds. Unlike the passes below,
    // this one also runs when pass 1 found *some* codes: a sheet can hold
    // codes of differing contrast, and the factor that resolves an occluded
    // one is not the factor that already resolved the clean one.
    if (_rebuildsImage && fast.detected > fast.results.length) {
      // The sweep only ever returns a strictly better pass, so any result
      // it hands back is worth preferring - including a partial one, which
      // still recovers a code the default threshold could not.
      final swept = _decodeAllWithAlternateThresholds(source, fast);
      if (swept.results.length > fast.results.length) {
        return swept.results;
      }
    }
    if (fast.results.isNotEmpty) {
      return fast.results;
    }

    // Reflectance reversal: light modules on a dark background.
    if (finder.inverted case final lightOnDark?) {
      final reversed = _decodeAllOnInfos(
        inverted!,
        lightOnDark.selectMultiple(),
        retry,
      );
      if (reversed.results.isNotEmpty) {
        return reversed.results;
      }
    }

    // Pass 3: despeckle. Noise breaks every code on the sheet at once.
    final despeckled = _decodeAllOnMatrix(matrix.majority3x3(), retry);
    if (despeckled.results.isNotEmpty) {
      return despeckled.results;
    }

    // Pass 4: full resolution. Downsampling shrinks every code at once.
    if (_rebuildsImage &&
        (processWidth < image.width || processHeight < image.height) &&
        retry.hasBudget) {
      final fullMatrix = _fullResolutionMatrix(image);
      if (fullMatrix != null) {
        final fullResults = _decodeAllOnMatrix(fullMatrix, retry);
        if (fullResults.results.isNotEmpty) {
          return fullResults.results;
        }
      }
    }

    return const [];
  }

  /// Re-runs the multi scan at each of [_retryThresholdFactors], returning
  /// the best pass (the one that decoded the most of its detected codes).
  ///
  /// Passes are compared rather than merged: two codes carrying the same
  /// text are legitimate on one sheet, so deduplicating results would lose
  /// one of them.
  _MultiScan _decodeAllWithAlternateThresholds(
    LuminanceSource source,
    _MultiScan best,
  ) {
    for (final matrix in _alternateMatrices(source)) {
      final scan = _decodeAllOnMatrix(
        matrix,
        _newTryHarderDecoder(gridPointBudget: _sweepGridPointBudget),
      );
      if (scan.results.length > best.results.length) {
        best = scan;
      }
      if (best.decodedAll) {
        break;
      }
    }
    return best;
  }

  /// Multi-code scan on a single matrix: every disjoint finder triplet
  /// gets the fast decode, then the corner-grid rescue if it was detected
  /// but failed to decode.
  _MultiScan _decodeAllOnMatrix(BitMatrix matrix, TryHarderDecoder retry) {
    return _decodeAllOnInfos(
      matrix,
      FinderPatternFinder(matrix).findMulti(),
      retry,
    );
  }

  /// [_decodeAllOnMatrix] on already located finder triplets.
  _MultiScan _decodeAllOnInfos(
    BitMatrix matrix,
    List<FinderPatternInfo> infos,
    TryHarderDecoder retry,
  ) {
    final results = <DecoderResult>[];
    for (final info in infos) {
      final result =
          _decodeWithAllowances(matrix, info) ??
          retry.decodeWithFinderInfo(matrix, info);
      if (result != null) {
        results.add(result);
      }
    }
    return _MultiScan(results: results, detected: infos.length);
  }

  /// Internal: Decodes a QR code from located finder patterns (fast-only
  /// path).
  ///
  /// A failed finder throws DetectionException before this is reached,
  /// which the caller turns into the barcode fallback; rethrowFinal
  /// preserves the expanded attempt's exception (e.g. an RS
  /// DecodeException) for the caller.
  DecoderResult _decodeQRFromInfo(
    BitMatrix blackMatrix,
    FinderPatternInfo info,
  ) {
    return _decodeWithAllowances(blackMatrix, info, rethrowFinal: true)!;
  }

  /// Internal: Decodes a barcode from luminance array.
  BarcodeResult? _decodeBarcodeFromPixels(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final source = LuminanceSource(
      width: width,
      height: height,
      luminances: pixels,
    );
    return barcodeScanner.scan(source);
  }

  /// Internal: Decodes all QR codes from luminance array.
  List<DecoderResult> _decodeAllQRFromPixels(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final source = LuminanceSource(
      width: width,
      height: height,
      luminances: pixels,
    );
    final binarizer = Binarizer(source, thresholdFactor: binarizerThreshold);
    final blackMatrix = binarizer.getBlackMatrix();
    final inverted = _lightOnDarkImage(blackMatrix);

    // One row scan collects the finder patterns of both reflectances.
    final finder = FinderPatternFinder(blackMatrix, invertedImage: inverted);
    final results = _decodeAllQRFromInfos(blackMatrix, finder.findMulti());
    if (results.isNotEmpty) {
      return results;
    }
    // Reflectance reversal: light modules on a dark background.
    if (finder.inverted case final lightOnDark?) {
      return _decodeAllQRFromInfos(inverted!, lightOnDark.selectMultiple());
    }
    return results;
  }

  /// The inverse of [matrix], in which light-on-dark codes read as normal
  /// ones, or null when [readLightOnDark] is off.
  BitMatrix? _lightOnDarkImage(BitMatrix matrix) {
    return readLightOnDark ? matrix.inverted() : null;
  }

  /// Internal: Decodes every located finder triplet (fast-only path).
  List<DecoderResult> _decodeAllQRFromInfos(
    BitMatrix blackMatrix,
    List<FinderPatternInfo> infos,
  ) {
    // Strategy: Try standard (5) first.
    if (alignmentAreaAllowance > 5) {
      final results = _decodeInfos(
        Detector(blackMatrix, alignmentAreaAllowance: 5),
        infos,
      );
      if (results.isNotEmpty) {
        return results;
      }
    }

    // Fallback: Expanded search
    return _decodeInfos(
      Detector(blackMatrix, alignmentAreaAllowance: alignmentAreaAllowance),
      infos,
    );
  }

  /// Samples and decodes each of [infos] with [detector], skipping those
  /// that fail.
  List<DecoderResult> _decodeInfos(
    Detector detector,
    List<FinderPatternInfo> infos,
  ) {
    final results = <DecoderResult>[];
    for (final info in infos) {
      try {
        results.add(
          _decoder.decode(detector.processFinderPatternInfo(info).bits),
        );
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  /// Internal: Wraps image processing to catch errors.
  (Uint8List, int, int) _processImage(YomuImage image) {
    try {
      return ImageProcessor.process(image);
    } catch (e) {
      if (e is YomuException) rethrow;
      throw ImageProcessingException('Failed to process image: $e');
    }
  }
}

/// Outcome of one multi-code pass: what decoded, and how many codes the
/// finder located.
///
/// The gap between the two is what tells [Yomu.decodeAll] that a sheet still
/// holds an undecoded code and that further passes are worth their cost.
class _MultiScan {
  const _MultiScan({required this.results, required this.detected});

  final List<DecoderResult> results;
  final int detected;

  /// Whether every located code decoded (and at least one was located).
  bool get decodedAll => results.isNotEmpty && results.length == detected;
}
