import 'dart:typed_data';

import '../yomu_exception.dart';

/// Integer luminance weights approximating Y = 0.299R + 0.587G + 0.114B
/// as `(306 * R + 601 * G + 117 * B) >> 10`.
const int _weightR = 306;
const int _weightG = 601;
const int _weightB = 117;

/// Number of bits the weighted sum is shifted down by.
const int _weightShift = 10;

/// Returns a 32-bit view over [bytes] covering [pixelCount] whole pixels, or
/// null when whole-pixel reads would be unsafe.
///
/// Reading a packed 32-bit pixel as one word replaces three bounds-checked
/// byte loads with a single load, which is the dominant cost of conversion on
/// large images. It is only valid on a little-endian host (so that the first
/// byte of the pixel occupies the low bits) and when the view's byte offset is
/// 4-aligned, which a strided camera buffer need not be.
Uint32List? packedPixelView(Uint8List bytes, int pixelCount) {
  if (Endian.host != Endian.little) {
    return null;
  }
  final offsetInBytes = bytes.offsetInBytes;
  if ((offsetInBytes & 3) != 0 || (bytes.lengthInBytes >> 2) < pixelCount) {
    return null;
  }
  return bytes.buffer.asUint32List(offsetInBytes, pixelCount);
}

/// Weight applied to the byte that comes *first* in memory for [isBgra].
///
/// In a little-endian word that byte occupies the low 8 bits, so swapping
/// this weight with [highByteWeight] converts either channel order without a
/// per-pixel branch.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
int lowByteWeight({required bool isBgra}) => isBgra ? _weightB : _weightR;

/// Weight applied to the third byte of the pixel (the high bits of the word).
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
int highByteWeight({required bool isBgra}) => isBgra ? _weightR : _weightB;

/// Converts one packed little-endian pixel word to luminance.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
int luminanceOfWord(int pixel, int weightLow, int weightHigh) {
  return (weightLow * (pixel & 0xFF) +
          _weightG * ((pixel >> 8) & 0xFF) +
          weightHigh * ((pixel >> 16) & 0xFF)) >>
      _weightShift;
}

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
  return _packedToGrayscale(bytes, total, isBgra: false);
}

/// Converts raw BGRA bytes to a grayscale luminance array.
///
/// Input [bytes] must be in BGRA format (4 bytes per pixel).
/// Output is a [Uint8List] where each byte represents the luminance (Y) of a pixel.
///
/// Formula: Y = 0.299R + 0.587G + 0.114B
Uint8List bgraToGrayscale(Uint8List bytes, int width, int height) {
  return _packedToGrayscale(bytes, width * height, isBgra: true);
}

/// Shared conversion for the two packed 4-byte formats.
Uint8List _packedToGrayscale(
  Uint8List bytes,
  int total, {
  required bool isBgra,
}) {
  final luminance = Uint8List(total);
  final weightLow = lowByteWeight(isBgra: isBgra);
  final weightHigh = highByteWeight(isBgra: isBgra);

  final words = packedPixelView(bytes, total);
  if (words != null) {
    for (var i = 0; i < total; i++) {
      luminance[i] = luminanceOfWord(words[i], weightLow, weightHigh);
    }
    return luminance;
  }

  var offset = 0;
  for (var i = 0; i < total; i++) {
    luminance[i] =
        (weightLow * bytes[offset] +
            _weightG * bytes[offset + 1] +
            weightHigh * bytes[offset + 2]) >>
        _weightShift;
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
      luminance[i] =
          (_weightR * r + _weightG * g + _weightB * b) >> _weightShift;
    }
  }
  return luminance;
}
