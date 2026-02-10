import 'dart:typed_data';

import 'barcode/barcode_result.dart';
import 'barcode/barcode_scanner.dart';
import 'common/binarizer/binarizer.dart';
import 'common/binarizer/luminance_source.dart';
import 'common/image_processor.dart';
import 'image_data.dart';
import 'qr/decoder/decoded_bit_stream_parser.dart';
import 'qr/decoder/qrcode_decoder.dart';
import 'qr/detector/detector.dart';
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
  const Yomu({
    required this.enableQRCode,
    required this.barcodeScanner,
    this.binarizerThreshold = 0.875,
    this.alignmentAreaAllowance = 15,
  });

  /// Whether to scan for QR codes.
  final bool enableQRCode;

  /// Configuration for 1D barcode scanning.
  final BarcodeScanner barcodeScanner;

  /// Threshold factor for binarization.
  final double binarizerThreshold;

  /// Allowance for alignment pattern search.
  final int alignmentAreaAllowance;

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

  /// Decodes a QR code or barcode from a [YomuImage].
  ///
  /// This is the preferred method for decoding as it handles different image formats
  /// and row strides correctly.
  DecoderResult decode(YomuImage image) {
    final (pixels, processWidth, processHeight) = _processImage(image);

    // Try QR code first
    if (enableQRCode) {
      try {
        return _decodeQRFromPixels(pixels, processWidth, processHeight);
      } on DetectionException {
        // Fall through to barcode scanning
      }
    }

    // Try 1D barcodes
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

    throw const DetectionException('No QR code or barcode found');
  }

  /// Decodes all QR codes from a [YomuImage].
  List<DecoderResult> decodeAll(YomuImage image) {
    if (!enableQRCode) {
      return const [];
    }

    final (pixels, processWidth, processHeight) = _processImage(image);
    return _decodeAllQRFromPixels(pixels, processWidth, processHeight);
  }

  /// Internal: Decodes a QR code from luminance array.
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

    // Detection Strategy:
    // 1. Try with standard/tight alignment allowance (5) first.
    //    This avoids false positives in standard/clean images where noise might exist far away.
    //    If successful, return result.
    if (alignmentAreaAllowance > 5) {
      try {
        final detector = Detector(blackMatrix, alignmentAreaAllowance: 5);
        final detectorResult = detector.detect();
        return _decoder.decode(detectorResult.bits);
      } catch (_) {
        // If detection fails or decoding (RS error) fails, fall through to expanded search.
        // We ignore exceptions here to allow retry.
      }
    }

    // 2. Expanded Search (User allowed)
    final detector = Detector(
      blackMatrix,
      alignmentAreaAllowance: alignmentAreaAllowance,
    );
    final detectorResult = detector.detect();

    return _decoder.decode(detectorResult.bits);
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
