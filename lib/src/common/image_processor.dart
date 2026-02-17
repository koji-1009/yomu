import 'dart:math' as math;
import 'dart:typed_data';

import '../image_data.dart';
import 'image_conversion.dart';

/// Utilities for processing and preparing images for decoding.
class ImageProcessor {
  static const int _targetPixels = 800000;

  /// Processes a [YomuImage] to produce a grayscale luminance image,
  /// downsampling if necessary to improve performance.
  ///
  /// Returns a record containing the pixel data, width, and height.
  static (Uint8List, int, int) process(YomuImage image) {
    if (image.format == YomuImageFormat.grayscale) {
      return _processLuminance(
        image.bytes,
        image.width,
        image.height,
        image.rowStride,
      );
    } else {
      return _convertAndMaybeDownsample(image: image);
    }
  }

  /// Converts RGBA/BGRA bytes to grayscale luminance, downsampling if necessary.
  static (Uint8List, int, int) _convertAndMaybeDownsample({
    required YomuImage image,
  }) {
    final bytes = image.bytes;
    final width = image.width;
    final height = image.height;
    final stride = image.rowStride;
    final isBgra = image.format == YomuImageFormat.bgra;

    final totalPixels = width * height;

    if (totalPixels <= _targetPixels && stride == width * 4) {
      // Small enough and no stride: direct conversion
      if (isBgra) {
        return (bgraToGrayscale(bytes, width, height), width, height);
      } else {
        return (rgbaToGrayscale(bytes, width, height), width, height);
      }
    }

    // Compute scale factor
    // We use a slightly more aggressive scaling for very large images
    final scale = math.sqrt(totalPixels / _targetPixels).round().clamp(1, 8);

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
  static (Uint8List, int, int) _processLuminance(
    Uint8List luminance,
    int width,
    int height,
    int rowStride,
  ) {
    final totalPixels = width * height;

    if (totalPixels <= _targetPixels) {
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
    final scaleFactor = totalPixels / _targetPixels;
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
  static Uint8List _removeStride(
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
