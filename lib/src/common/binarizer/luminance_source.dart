import 'dart:typed_data';

/// A source of luminance (grayscale) data.
///
/// This class wraps a [Uint8List] of luminance values.
class LuminanceSource {
  const LuminanceSource({
    required this.width,
    required this.height,
    required this.luminances,
  });

  final int width;
  final int height;
  final Uint8List luminances;

  /// Gets a single row of luminance values.
  ///
  /// If [row] is provided and large enough, it acts as a reusable buffer.
  Uint8List getRow(int y, Uint8List? row) {
    row ??= Uint8List(width);
    final offset = y * width;
    for (var x = 0; x < width; x++) {
      row[x] = luminances[offset + x];
    }
    return row;
  }
}
