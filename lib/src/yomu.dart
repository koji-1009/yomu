import 'dart:typed_data';

import 'barcode/barcode_result.dart';
import 'barcode/barcode_scanner.dart';
import 'common/binarizer/binarizer.dart';
import 'common/binarizer/luminance_source.dart';
import 'common/bit_matrix.dart';
import 'common/image_processor.dart';
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
  /// - [tryHarder]: Whether to run escalating retry strategies when the
  ///   fast path fails (default: true)
  const Yomu({
    required this.enableQRCode,
    required this.barcodeScanner,
    this.binarizerThreshold = 0.875,
    this.alignmentAreaAllowance = 15,
    this.tryHarder = true,
  });

  /// Whether to scan for QR codes.
  final bool enableQRCode;

  /// Configuration for 1D barcode scanning.
  final BarcodeScanner barcodeScanner;

  /// Threshold factor for binarization.
  final double binarizerThreshold;

  /// Allowance for alignment pattern search.
  final int alignmentAreaAllowance;

  /// Whether [decode] runs escalating retry strategies (corner grid
  /// search, despeckle, tolerant finder, full-resolution retry) when the
  /// fast path fails.
  ///
  /// Retries only run on images the fast path cannot decode, so successful
  /// scans are unaffected. Disable for latency-critical pipelines (e.g.
  /// per-frame camera scanning) where a missed frame is cheaper than a
  /// slower failure path.
  final bool tryHarder;

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
  /// Identical to [all] but with [tryHarder] disabled: frames without a
  /// code fail as fast as possible instead of paying the retry ladder.
  /// A code missed on one frame is simply caught on a later one.
  static const realtime = Yomu(
    enableQRCode: true,
    barcodeScanner: BarcodeScanner.all,
    tryHarder: false,
  );

  /// Decodes a QR code or barcode from a [YomuImage].
  ///
  /// This is the preferred method for decoding as it handles different image formats
  /// and row strides correctly.
  ///
  /// With [tryHarder] enabled (the default), escalating retry strategies
  /// run when the fast path fails: bottom-right corner grid search,
  /// despeckle, tolerant finder and a full-resolution retry for
  /// downsampled images. In this mode a detected-but-undecodable QR code
  /// falls through to barcode scanning instead of propagating a
  /// [DecodeException].
  DecoderResult decode(YomuImage image) {
    final (pixels, processWidth, processHeight) = _processImage(image);

    if (!tryHarder) {
      return _decodeFastOnly(pixels, processWidth, processHeight);
    }

    BitMatrix? matrix;

    // One retry decoder per decode call: it deduplicates grid searches
    // across stages and enforces the deterministic work budget.
    final retry = _newTryHarderDecoder();

    // Stage 1+2: fast QR path, then dimension/corner retries reusing the
    // located finder patterns.
    if (enableQRCode) {
      final source = LuminanceSource(
        width: processWidth,
        height: processHeight,
        luminances: pixels,
      );
      matrix = Binarizer(
        source,
        thresholdFactor: binarizerThreshold,
      ).getBlackMatrix();

      final fast = _decodeFastWithCornerRetry(matrix, retry);
      if (fast != null) {
        return fast;
      }
    }

    // Barcode before the deep QR retries: scanning is cheap and barcode
    // images rarely contain QR finder patterns, so they exit here without
    // paying the retry cost.
    if (!barcodeScanner.isEmpty) {
      final barcodeResult = _decodeBarcodeFromPixels(
        pixels,
        processWidth,
        processHeight,
      );
      if (barcodeResult != null) {
        return DecoderResult(
          text: barcodeResult.text,
          byteSegments: const [],
          ecLevel: null,
        );
      }
    }

    if (enableQRCode) {
      // Stages 3-4: despeckle, tolerant finder.
      final deep = retry.decodeDeep(matrix!);
      if (deep != null) {
        return deep;
      }

      // Stage 5: full-resolution retry. Downsampling can shrink small
      // codes below the detectable module size. Skipped when the work
      // budget is already exhausted on garbage candidates.
      if ((processWidth < image.width || processHeight < image.height) &&
          retry.hasBudget) {
        final fullRes = _decodeFullResolution(image, retry);
        if (fullRes != null) {
          return fullRes;
        }
      }
    }

    throw const DetectionException('No QR code or barcode found');
  }

  /// Previous (fast-only) decode behavior, used when [tryHarder] is off.
  DecoderResult _decodeFastOnly(Uint8List pixels, int width, int height) {
    // Try QR code first
    if (enableQRCode) {
      try {
        return _decodeQRFromPixels(pixels, width, height);
      } on DetectionException {
        // Fall through to barcode scanning
      }
    }

    // Try 1D barcodes
    if (!barcodeScanner.isEmpty) {
      final barcodeResult = _decodeBarcodeFromPixels(pixels, width, height);
      if (barcodeResult != null) {
        return DecoderResult(
          text: barcodeResult.text,
          byteSegments: const [],
          ecLevel: null,
        );
      }
    }

    throw const DetectionException('No QR code or barcode found');
  }

  /// Builds the retry decoder configured like this instance.
  TryHarderDecoder _newTryHarderDecoder() {
    return TryHarderDecoder(alignmentAreaAllowance: alignmentAreaAllowance);
  }

  /// Stage 1+2: locates finder patterns once, tries the fast decode, then
  /// the dimension/corner retries. Returns null on failure.
  DecoderResult? _decodeFastWithCornerRetry(
    BitMatrix matrix,
    TryHarderDecoder retry,
  ) {
    final FinderPatternInfo info;
    try {
      info = FinderPatternFinder(matrix).find();
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
  /// With [tryHarder] enabled (the default), codes that are detected but
  /// fail to decode get the corner-grid rescue, and when an entire pass
  /// finds nothing the scan escalates: despeckle, then a full-resolution
  /// pass for downsampled images. Sheets that decode on the fast pass pay
  /// no retry cost.
  List<DecoderResult> decodeAll(YomuImage image) {
    if (!enableQRCode) {
      return const [];
    }

    final (pixels, processWidth, processHeight) = _processImage(image);

    if (!tryHarder) {
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

    // Pass 1: fast multi scan (with the in-pass corner rescue).
    final fast = _decodeAllOnMatrix(matrix, retry);
    if (fast.isNotEmpty) {
      return fast;
    }

    // Pass 2: despeckle. Noise breaks every code on the sheet at once.
    final despeckled = _decodeAllOnMatrix(matrix.majority3x3(), retry);
    if (despeckled.isNotEmpty) {
      return despeckled;
    }

    // Pass 3: full resolution. Downsampling shrinks every code at once.
    if ((processWidth < image.width || processHeight < image.height) &&
        retry.hasBudget) {
      final fullMatrix = _fullResolutionMatrix(image);
      if (fullMatrix != null) {
        final fullResults = _decodeAllOnMatrix(fullMatrix, retry);
        if (fullResults.isNotEmpty) {
          return fullResults;
        }
      }
    }

    return const [];
  }

  /// Multi-code scan on a single matrix: every disjoint finder triplet
  /// gets the fast decode, then the corner-grid rescue if it was detected
  /// but failed to decode.
  List<DecoderResult> _decodeAllOnMatrix(
    BitMatrix matrix,
    TryHarderDecoder retry,
  ) {
    final infos = FinderPatternFinder(matrix).findMulti();
    final results = <DecoderResult>[];
    for (final info in infos) {
      final result =
          _decodeWithAllowances(matrix, info) ??
          retry.decodeWithFinderInfo(matrix, info);
      if (result != null) {
        results.add(result);
      }
    }
    return results;
  }

  /// Internal: Decodes a QR code from luminance array (fast-only path).
  DecoderResult _decodeQRFromPixels(Uint8List pixels, int width, int height) {
    final source = LuminanceSource(
      width: width,
      height: height,
      luminances: pixels,
    );
    final blackMatrix = Binarizer(
      source,
      thresholdFactor: binarizerThreshold,
    ).getBlackMatrix();

    // A failed finder throws DetectionException, which the caller turns
    // into the barcode fallback; rethrowFinal preserves the expanded
    // attempt's exception (e.g. an RS DecodeException) for the caller.
    final info = FinderPatternFinder(blackMatrix).find();
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

    // Strategy: Try standard (5) first.
    if (alignmentAreaAllowance > 5) {
      final detector = Detector(blackMatrix, alignmentAreaAllowance: 5);
      final detectorResults = detector.detectMulti();
      final results = <DecoderResult>[];
      for (final detectorResult in detectorResults) {
        try {
          results.add(_decoder.decode(detectorResult.bits));
        } catch (_) {
          continue;
        }
      }
      if (results.isNotEmpty) {
        return results;
      }
    }

    // Fallback: Expanded search
    final detector = Detector(
      blackMatrix,
      alignmentAreaAllowance: alignmentAreaAllowance,
    );
    final detectorResults = detector.detectMulti();

    final results = <DecoderResult>[];
    for (final detectorResult in detectorResults) {
      try {
        results.add(_decoder.decode(detectorResult.bits));
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
