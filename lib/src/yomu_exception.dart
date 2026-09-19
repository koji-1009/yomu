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

/// Formerly thrown in place of any error other than a [YomuException] that
/// image processing ran into.
///
/// Nothing throws it any more: an image whose bytes do not fit its size is
/// reported as an [ArgumentException], and an exception thrown by a
/// [YomuImage] implementation itself now reaches the caller unchanged.
@Deprecated('No longer thrown; catch ArgumentException instead')
class ImageProcessingException extends YomuException {
  /// Creates an image processing exception with the given message.
  const ImageProcessingException(super.message);
}
