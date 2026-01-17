import 'dart:typed_data';

/// A source of luminance (grayscale) data based on an integer array of pixels (ARGB).
class RGBLuminanceSource {
  const RGBLuminanceSource({
    required this.width,
    required this.height,
    required Int32List pixels,
  }) : _pixels = pixels;

  final Int32List _pixels;
  final int width;
  final int height;

  /// Gets a single row of luminance values.
  Uint8List getRow(int y, Uint8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    if (row == null || row.length < width) {
      row = Uint8List(width);
    }

    final offset = y * width;
    for (var x = 0; x < width; x++) {
      final pixel = _pixels[offset + x];
      // 0xAARRGGBB
      final r = (pixel >> 16) & 0xFF;
      final g = (pixel >> 8) & 0xFF;
      final b = pixel & 0xFF;

      // Standard weights: 0.299R, 0.587G, 0.114B
      if (r == g && g == b) {
        row[x] = r;
      } else {
        // Integer approximation: (306 * r + 601 * g + 117 * b) >> 10
        row[x] = ((306 * r + 601 * g + 117 * b) >> 10);
      }
    }
    return row;
  }

  /// Gets the entire image as a luminance matrix.
  Uint8List get matrix {
    final matrix = Uint8List(width * height);
    for (var i = 0; i < _pixels.length; i++) {
      final pixel = _pixels[i];
      final r = (pixel >> 16) & 0xFF;
      final g = (pixel >> 8) & 0xFF;
      final b = pixel & 0xFF;
      if (r == g && g == b) {
        matrix[i] = r;
      } else {
        matrix[i] = ((306 * r + 601 * g + 117 * b) >> 10);
      }
    }
    return matrix;
  }
}
