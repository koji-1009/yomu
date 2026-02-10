/// Exception hierarchy for yomu library.
///
/// All yomu-specific exceptions extend [YomuException], making it easy
/// to catch all yomu errors with a single `on YomuException` clause.
library;

/// Base class for all yomu-specific exceptions.
///
/// Use this to catch any yomu error:
/// ```dart
/// try {
///   final result = yomu.decode(bytes, width, height);
/// } on YomuException catch (e) {
///   print('Decode failed: ${e.message}');
/// }
/// ```
abstract class YomuException implements Exception {
  /// Creates a yomu exception with the given message.
  const YomuException(this.message);

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when QR code or barcode detection fails.
///
/// This happens when:
/// - No finder patterns are detected
/// - Module size cannot be determined
/// - Perspective correction fails
class DetectionException extends YomuException {
  /// Creates a detection exception with the given message.
  const DetectionException(super.message);
}

/// Thrown when decoding the detected code fails.
///
/// This happens when:
/// - Not enough data bits available
/// - Invalid data format
/// - Error correction fails
/// - Unsupported encoding mode
class DecodeException extends YomuException {
  /// Creates a decode exception with the given message.
  const DecodeException(super.message);
}

/// Thrown when Reed-Solomon error correction fails.
///
/// This is a specific type of [DecodeException] for RS-related errors.
class ReedSolomonException extends DecodeException {
  /// Creates a Reed-Solomon exception with the given message.
  const ReedSolomonException(super.message);
}

/// Thrown when an invalid argument is provided to a Yomu method.
class ArgumentException extends YomuException {
  /// Creates an argument exception with the given message.
  const ArgumentException(super.message);
}

/// Thrown when image processing fails.
///
/// This happens when:
/// - Image processing downsampling fails
/// - Image format conversion fails
class ImageProcessingException extends YomuException {
  /// Creates an image processing exception with the given message.
  const ImageProcessingException(super.message);
}
