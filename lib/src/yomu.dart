import 'dart:math' as math;
import 'dart:typed_data';

import 'barcode/barcode_result.dart';
import 'barcode/barcode_scanner.dart';
import 'common/binarizer/binarizer.dart';
import 'common/binarizer/luminance_source.dart';
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
/// // Decode QR codes and all barcode formats
/// final yomu = Yomu.all;
/// final result = yomu.decode(bytes: imageBytes, width: 300, height: 300);
/// print(result.text);
///
/// // QR code only
/// final qrOnly = Yomu.qrOnly;
///
/// // Barcodes only
/// final barcodeOnly = Yomu.barcodeOnly;
///
/// // Custom configuration
/// const custom = Yomu(
///   enableQRCode: true,
///   barcodeScanner: BarcodeScanner.retail,
/// );
/// ```
///
/// ## Architecture
///
/// The decoding pipeline consists of:
/// 1. **Binarization** - Converting grayscale to black/white using histogram analysis
/// 2. **Detection** - Finding finder patterns (QR) or bar patterns (1D)
/// 3. **Decoding** - Error correction and data parsing
///
/// See also:
/// - [DecoderResult] for QR code decoded data
/// - [BarcodeResult] for 1D barcode decoded data
/// - [BarcodeScanner] for 1D barcode scanning configuration
class Yomu {
  /// Creates a new [Yomu] decoder instance.
  ///
  /// Parameters:
  /// - [enableQRCode]: Whether to scan for QR codes (default: true)
  /// - [barcodeScanner]: Configuration for 1D barcode scanning (default: none)
  const Yomu({required this.enableQRCode, required this.barcodeScanner});

  /// Whether to scan for QR codes.
  final bool enableQRCode;

  /// Configuration for 1D barcode scanning.
  ///
  /// Set to [BarcodeScanner.all] for all formats, [BarcodeScanner.retail] for
  /// EAN/UPC only, or [BarcodeScanner.none] to disable 1D barcode scanning.
  final BarcodeScanner barcodeScanner;

  /// Decoder instance for QR code decoding.
  /// Note: QRCodeDecoder is not const, so we create it lazily.
  QRCodeDecoder get _decoder => QRCodeDecoder();

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

  /// Decodes a QR code or barcode from an RGBA byte array.
  ///
  /// Tries QR code first (if enabled), then falls back to 1D barcodes.
  ///
  /// ## Parameters
  ///
  /// - [bytes]: Raw RGBA pixel data (4 bytes per pixel: R, G, B, A)
  /// - [width]: Image width in pixels
  /// - [height]: Image height in pixels
  ///
  /// ## Returns
  ///
  /// A [DecoderResult] containing the decoded text and metadata.
  ///
  /// ## Throws
  ///
  /// - [ArgumentError] if [bytes] length is less than `width * height * 4`
  /// - [DetectionException] if no valid code is found
  /// - [DecodeException] if decoding fails
  ///
  /// ## Example
  ///
  /// ```dart
  /// final result = Yomu.all.decode(bytes: imageBytes, width: 300, height: 300);
  /// print(result.text);
  /// ```
  DecoderResult decode({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    if (bytes.length < width * height * 4) {
      throw ArgumentError('Byte array too small for RGBA image');
    }

    final (pixels, processWidth, processHeight) = _convertAndMaybeDownsample(
      bytes: bytes,
      width: width,
      height: height,
    );

    // Try QR code first
    if (enableQRCode) {
      try {
        return _decodeQRFromPixels(
          pixels: pixels,
          width: processWidth,
          height: processHeight,
        );
      } on DetectionException {
        // Fall through to barcode scanning (e.g. maybe it wasn't a QR code)
      }
      // Note: Other exceptions (like DecodeException/ReedSolomonException) will propagate.
      // This is an optimization: if we found a QR code pattern but failed to decode it,
      // we assume it is NOT a barcode and abort to save time.
    }

    // Try 1D barcodes
    if (!barcodeScanner.isEmpty) {
      final barcodeResult = _decodeBarcodeFromPixels(
        pixels: pixels,
        width: processWidth,
        height: processHeight,
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

  /// Decodes all QR codes from an RGBA byte array.
  ///
  /// This method attempts to find and decode multiple QR codes in a single image.
  /// Note: This does not include 1D barcodes.
  ///
  /// ## Parameters
  ///
  /// - [bytes]: Raw RGBA pixel data (4 bytes per pixel: R, G, B, A)
  /// - [width]: Image width in pixels
  /// - [height]: Image height in pixels
  ///
  /// ## Returns
  ///
  /// A list of [DecoderResult] objects, one for each successfully decoded QR code.
  /// Returns an empty list if no QR codes are found.
  List<DecoderResult> decodeAll({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    if (bytes.length < width * height * 4) {
      throw ArgumentError('Byte array too small for RGBA image');
    }

    if (!enableQRCode) {
      return const [];
    }

    final (pixels, processWidth, processHeight) = _convertAndMaybeDownsample(
      bytes: bytes,
      width: width,
      height: height,
    );
    return _decodeAllQRFromPixels(
      pixels: pixels,
      width: processWidth,
      height: processHeight,
    );
  }

  /// Converts RGBA bytes to Int32List pixels.
  Int32List _rgbaToPixels({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    final pixels = Int32List(width * height);
    var offset = 0;
    final total = width * height;
    for (var i = 0; i < total; i++) {
      final r = bytes[offset];
      final g = bytes[offset + 1];
      final b = bytes[offset + 2];
      pixels[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
      offset += 4;
    }
    return pixels;
  }

  /// Internal: Decodes a QR code from pixel array.
  DecoderResult _decodeQRFromPixels({
    required Int32List pixels,
    required int width,
    required int height,
  }) {
    final source = RGBLuminanceSource(
      width: width,
      height: height,
      pixels: pixels,
    );
    final blackMatrix = Binarizer(source).getBlackMatrix();
    final detector = Detector(blackMatrix);
    final detectorResult = detector.detect();

    return _decoder.decode(detectorResult.bits);
  }

  /// Internal: Decodes a barcode from pixel array.
  BarcodeResult? _decodeBarcodeFromPixels({
    required Int32List pixels,
    required int width,
    required int height,
  }) {
    final source = RGBLuminanceSource(
      width: width,
      height: height,
      pixels: pixels,
    );
    return barcodeScanner.scan(source);
  }

  /// Internal: Decodes all QR codes from pixel array.
  List<DecoderResult> _decodeAllQRFromPixels({
    required Int32List pixels,
    required int width,
    required int height,
  }) {
    final source = RGBLuminanceSource(
      width: width,
      height: height,
      pixels: pixels,
    );
    final blackMatrix = Binarizer(source).getBlackMatrix();
    final detector = Detector(blackMatrix);
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

  /// Converts bytes to pixels, downsampling if necessary.
  /// This fused operation avoids allocating full-size buffers for large images.
  (Int32List, int, int) _convertAndMaybeDownsample({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    const targetPixels = 1000000;
    final totalPixels = width * height;

    if (totalPixels <= targetPixels) {
      // Small enough: direct conversion
      return (
        _rgbaToPixels(bytes: bytes, width: width, height: height),
        width,
        height,
      );
    }

    final scaleFactor = totalPixels / targetPixels;
    final scale = math.sqrt(scaleFactor).ceil();

    // Large image: fused convert + downsample
    // O(TargetSize) instead of O(OriginalSize)
    final dstWidth = width ~/ scale;
    final dstHeight = height ~/ scale;
    final result = Int32List(dstWidth * dstHeight);
    final halfScale = scale ~/ 2;

    // Pre-calculate stride for inner loop
    final pixelStride = scale * 4;
    for (var dstY = 0; dstY < dstHeight; dstY++) {
      final srcY = dstY * scale + halfScale;

      final rowOffset = srcY * width * 4;
      final dstRowOffset = dstY * dstWidth;

      // Start srcX at halfScale
      var currentByteOffset = rowOffset + (halfScale * 4);

      for (var dstX = 0; dstX < dstWidth; dstX++) {
        final r = bytes[currentByteOffset];
        final g = bytes[currentByteOffset + 1];
        final b = bytes[currentByteOffset + 2];

        result[dstRowOffset + dstX] = (0xFF << 24) | (r << 16) | (g << 8) | b;

        // Advance to next sample pixel
        currentByteOffset += pixelStride;
      }
    }

    return (result, dstWidth, dstHeight);
  }
}
