import 'dart:typed_data';

import '../yomu_exception.dart';

/// Converts raw RGBA bytes to a grayscale luminance array.
///
/// Input [bytes] must be in RGBA format (4 bytes per pixel).
/// Output is a [Uint8List] where each byte represents the luminance (Y) of a pixel.
///
/// Formula: Y = 0.299R + 0.587G + 0.114B
/// Approximated as: (306 * R + 601 * G + 117 * B) >> 10
Uint8List rgbaToGrayscale(Uint8List bytes, int width, int height) {
  final total = width * height;
  if (bytes.length < total * 4) {
    throw ArgumentException(
      'Input bytes length is too small for ${width}x$height RGBA image',
    );
  }

  final luminance = Uint8List(total);
  var offset = 0;

  for (var i = 0; i < total; i++) {
    final r = bytes[offset];
    final g = bytes[offset + 1];
    final b = bytes[offset + 2];
    // Ignore A (offset+3)

    luminance[i] = (306 * r + 601 * g + 117 * b) >> 10;
    offset += 4;
  }
  return luminance;
}

/// Converts ARGB Int32 pixels (0xAARRGGBB) to a grayscale luminance array.
///
/// Helper for compatibility with legacy tests that use Int32List pixels.
Uint8List int32ToGrayscale(Int32List pixels, int width, int height) {
  final total = width * height;
  if (pixels.length < total) {
    throw ArgumentException(
      'Input pixels length is too small for ${width}x$height image',
    );
  }

  final luminance = Uint8List(total);

  for (var i = 0; i < total; i++) {
    final pixel = pixels[i];
    final r = (pixel >> 16) & 0xFF;
    final g = (pixel >> 8) & 0xFF;
    final b = pixel & 0xFF;

    if (r == g && g == b) {
      luminance[i] = r;
    } else {
      luminance[i] = (306 * r + 601 * g + 117 * b) >> 10;
    }
  }
  return luminance;
}

/// Converts raw BGRA bytes to a grayscale luminance array.
///
/// Input [bytes] must be in BGRA format (4 bytes per pixel).
/// Output is a [Uint8List] where each byte represents the luminance (Y) of a pixel.
///
/// Formula: Y = 0.299R + 0.587G + 0.114B
Uint8List bgraToGrayscale(Uint8List bytes, int width, int height) {
  final total = width * height;
  if (bytes.length < total * 4) {
    throw ArgumentException(
      'Input bytes length is too small for ${width}x$height BGRA image',
    );
  }

  final luminance = Uint8List(total);
  var offset = 0;

  for (var i = 0; i < total; i++) {
    final b = bytes[offset];
    final g = bytes[offset + 1];
    final r = bytes[offset + 2];
    // Ignore A (offset+3)

    luminance[i] = (306 * r + 601 * g + 117 * b) >> 10;
    offset += 4;
  }
  return luminance;
}
