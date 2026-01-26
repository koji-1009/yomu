import 'dart:math' as math;
import 'dart:typed_data';

import 'barcode/barcode_result.dart';
import 'barcode/barcode_scanner.dart';
import 'common/binarizer/binarizer.dart';
import 'common/binarizer/luminance_source.dart';
import 'common/image_conversion.dart';
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
    final Uint8List pixels;
    final int processWidth;
    final int processHeight;

    if (image.format == YomuImageFormat.grayscale) {
      // Grayscale processing
      (pixels, processWidth, processHeight) = _processLuminance(
        image.bytes,
        image.width,
        image.height,
        image.rowStride,
      );
    } else {
      // RGBA/BGRA processing
      (pixels, processWidth, processHeight) = _convertAndMaybeDownsample(
        image: image,
      );
    }

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

    final Uint8List pixels;
    final int processWidth;
    final int processHeight;

    if (image.format == YomuImageFormat.grayscale) {
      (pixels, processWidth, processHeight) = _processLuminance(
        image.bytes,
        image.width,
        image.height,
        image.rowStride,
      );
    } else {
      (pixels, processWidth, processHeight) = _convertAndMaybeDownsample(
        image: image,
      );
    }
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
    final blackMatrix = Binarizer(
      source,
      thresholdFactor: binarizerThreshold,
    ).getBlackMatrix();
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

  /// Converts RGBA/BGRA bytes to grayscale luminance, downsampling if necessary.
  (Uint8List, int, int) _convertAndMaybeDownsample({required YomuImage image}) {
    final bytes = image.bytes;
    final width = image.width;
    final height = image.height;
    final stride = image.rowStride;
    final isBgra = image.format == YomuImageFormat.bgra;

    const targetPixels = 1000000;
    final totalPixels = width * height;

    if (totalPixels <= targetPixels && stride == width * 4) {
      // Small enough and no stride: direct conversion
      if (isBgra) {
        return (bgraToGrayscale(bytes, width, height), width, height);
      } else {
        return (rgbaToGrayscale(bytes, width, height), width, height);
      }
    }

    // Compute scale factor (1 for small images with stride, >1 for large images)
    final scaleFactor = totalPixels / targetPixels;
    final scale = scaleFactor <= 1.0 ? 1 : math.sqrt(scaleFactor).ceil();

    final dstWidth = width ~/ scale;
    final dstHeight = height ~/ scale;
    final result = Uint8List(dstWidth * dstHeight);
    final halfScale = scale ~/ 2;
    final pixelStride = scale * 4;

    for (var dstY = 0; dstY < dstHeight; dstY++) {
      final srcY = dstY * scale + halfScale;
      final rowOffset = srcY * stride; // Correct stride usage
      final dstRowOffset = dstY * dstWidth;

      var currentByteOffset = rowOffset + (halfScale * 4);

      for (var dstX = 0; dstX < dstWidth; dstX++) {
        final rIndex = isBgra ? currentByteOffset + 2 : currentByteOffset;
        final gIndex = currentByteOffset + 1;
        final bIndex = isBgra ? currentByteOffset : currentByteOffset + 2;

        final r = bytes[rIndex];
        final g = bytes[gIndex];
        final b = bytes[bIndex];

        // Integer approximation: (306 * r + 601 * g + 117 * b) >> 10
        result[dstRowOffset + dstX] = (306 * r + 601 * g + 117 * b) >> 10;
        currentByteOffset += pixelStride;
      }
    }

    return (result, dstWidth, dstHeight);
  }

  /// Processes grayscale luminance bytes, downsampling and/or removing stride if necessary.
  (Uint8List, int, int) _processLuminance(
    Uint8List luminance,
    int width,
    int height,
    int rowStride,
  ) {
    const targetPixels = 1000000;
    final totalPixels = width * height;

    if (totalPixels <= targetPixels) {
      if (rowStride == width) {
        return (
          luminance,
          width,
          height,
        ); // Zero copy if already packed and small
      }
      // Just remove stride
      return (
        _removeStride(luminance, width, height, rowStride),
        width,
        height,
      );
    }

    // Downsample
    final scaleFactor = totalPixels / targetPixels;
    final scale = math.sqrt(scaleFactor).ceil();

    final dstWidth = width ~/ scale;
    final dstHeight = height ~/ scale;
    final result = Uint8List(dstWidth * dstHeight);
    final halfScale = scale ~/ 2;

    for (var dstY = 0; dstY < dstHeight; dstY++) {
      final srcY = dstY * scale + halfScale;
      final rowOffset = srcY * rowStride;
      final dstRowOffset = dstY * dstWidth;

      var currentByteOffset = rowOffset + halfScale;

      for (var dstX = 0; dstX < dstWidth; dstX++) {
        result[dstRowOffset + dstX] = luminance[currentByteOffset];
        currentByteOffset += scale;
      }
    }

    return (result, dstWidth, dstHeight);
  }

  /// Helper to remove stride from grayscale image.
  Uint8List _removeStride(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
  ) {
    final result = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      result.setRange(y * width, (y + 1) * width, bytes, y * rowStride);
    }
    return result;
  }
}
