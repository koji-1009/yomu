import 'dart:typed_data';

import 'yomu_exception.dart';

/// Represents the pixel format of a [YomuImage].
enum YomuImageFormat {
  /// 8-bit grayscale (1 byte per pixel).
  grayscale,

  /// 32-bit RGBA (4 bytes per pixel).
  rgba,

  /// 32-bit BGRA (4 bytes per pixel).
  bgra,
}

/// A platform-agnostic image container for passing data to Yomu.
///
/// Supports strided image data (padding at the end of rows), which is common
/// when working with raw camera streams.
class YomuImage {
  /// Creates a grayscale image from raw bytes.
  factory YomuImage.grayscale({
    required Uint8List bytes,
    required int width,
    required int height,
    int? rowStride,
  }) {
    return YomuImage(
      bytes: bytes,
      width: width,
      height: height,
      format: YomuImageFormat.grayscale,
      rowStride: rowStride,
    );
  }

  /// Creates an RGBA image from raw bytes.
  factory YomuImage.rgba({
    required Uint8List bytes,
    required int width,
    required int height,
    int? rowStride,
  }) {
    return YomuImage(
      bytes: bytes,
      width: width,
      height: height,
      format: YomuImageFormat.rgba,
      rowStride: rowStride,
    );
  }

  /// Creates a BGRA image from raw bytes.
  factory YomuImage.bgra({
    required Uint8List bytes,
    required int width,
    required int height,
    int? rowStride,
  }) {
    return YomuImage(
      bytes: bytes,
      width: width,
      height: height,
      format: YomuImageFormat.bgra,
      rowStride: rowStride,
    );
  }

  /// Creates a [YomuImage] from the Y-plane (luminance) of a YUV420 image.
  ///
  /// This is a convenience factory that treats the Y-plane as a grayscale image.
  /// QR and barcode decoding only require the luminance data.
  factory YomuImage.yuv420({
    required Uint8List yBytes,
    required int width,
    required int height,
    int? yRowStride,
  }) {
    return YomuImage(
      bytes: yBytes,
      width: width,
      height: height,
      format: YomuImageFormat.grayscale,
      rowStride: yRowStride,
    );
  }

  /// Creates a [YomuImage] with the specified properties.
  YomuImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    int? rowStride,
  }) : rowStride =
           rowStride ??
           (width * (format == YomuImageFormat.grayscale ? 1 : 4)) {
    if (width <= 0 || height <= 0) {
      throw const ArgumentException('Width and height must be positive.');
    }
    final bytesPerPixel = format == YomuImageFormat.grayscale ? 1 : 4;
    if (this.rowStride < width * bytesPerPixel) {
      throw ArgumentException(
        'rowStride (${this.rowStride}) must be >= width * bytesPerPixel '
        '(${width * bytesPerPixel}).',
      );
    }
    if (bytes.length < this.rowStride * height) {
      throw ArgumentException(
        'bytes.length (${bytes.length}) is too small for the given dimensions '
        'and stride. Expected at least ${this.rowStride * height}.',
      );
    }
  }

  /// Raw pixel data.
  final Uint8List bytes;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// The number of bytes per row.
  ///
  /// This must be >= `width * bytesPerPixel`.
  /// Common usage: Camera APIs often return images with padding at the end of
  /// each row for memory alignment.
  final int rowStride;

  /// The pixel format of the data.
  final YomuImageFormat format;
}
