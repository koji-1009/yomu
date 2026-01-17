/// 1D Barcode decoder result.
class BarcodeResult {
  /// Creates a new 1D barcode result.
  const BarcodeResult({
    required this.text,
    required this.format,
    required this.startX,
    required this.endX,
    required this.rowY,
  });

  /// The decoded text content.
  final String text;

  /// The barcode format (e.g., 'EAN_13', 'CODE_128').
  final String format;

  /// The starting X coordinate of the barcode in the image.
  final int startX;

  /// The ending X coordinate of the barcode in the image.
  final int endX;

  /// The Y coordinate of the row where the barcode was found.
  final int rowY;

  @override
  String toString() => 'BarcodeResult(format: $format, text: $text)';
}

/// Exception thrown when 1D barcode decoding fails.
class BarcodeException implements Exception {
  const BarcodeException(this.message);
  final String message;

  @override
  String toString() => 'BarcodeException: $message';
}
