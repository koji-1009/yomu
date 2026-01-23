/// Yomu - Pure Dart QR Code and Barcode Reader Library
///
/// A zero-dependency QR code and barcode decoding library for Dart and Flutter.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:yomu/yomu.dart';
///
/// // Create a YomuImage container
/// final image = YomuImage.rgba(bytes: imageBytes, width: 300, height: 300);
///
/// // Decode QR codes and all barcode formats
/// final result = Yomu.all.decode(image);
/// print(result.text);
///
/// // Decode QR codes only
/// final qrResult = Yomu.qrOnly.decode(image);
/// ```
///
/// ## Main Classes
///
/// - [Yomu] - The main entry point for QR code and barcode decoding
/// - [DecoderResult] - Contains the decoded text and metadata
/// - [BarcodeScanner] - Configuration for 1D barcode scanning
/// - [BarcodeResult] - Contains the decoded barcode text and metadata
///
/// ## Exception Handling
///
/// All yomu-specific exceptions extend [YomuException]:
/// - [DetectionException] - QR code/barcode detection failed
/// - [DecodeException] - Data decoding failed
/// - [ReedSolomonException] - Error correction failed
///
/// ```dart
/// try {
///   final image = YomuImage.rgba(bytes: imageBytes, width: 300, height: 300);
///   final result = Yomu.all.decode(image);
/// } on YomuException catch (e) {
///   print('Failed: ${e.message}');
/// }
/// ```
library;

// 1D Barcodes
export 'src/barcode/barcode_decoder.dart' show BarcodeDecoder;
export 'src/barcode/barcode_result.dart' show BarcodeResult, BarcodeException;
export 'src/barcode/barcode_scanner.dart' show BarcodeScanner;
export 'src/barcode/codabar_decoder.dart' show CodabarDecoder;
export 'src/barcode/code128_decoder.dart' show Code128Decoder;
export 'src/barcode/code39_decoder.dart' show Code39Decoder;
export 'src/barcode/ean13_decoder.dart' show EAN13Decoder;
export 'src/barcode/ean8_decoder.dart' show EAN8Decoder;
export 'src/barcode/itf_decoder.dart' show ITFDecoder;
export 'src/barcode/upca_decoder.dart' show UPCADecoder;
// Image Utilities
export 'src/image_data.dart' show YomuImage, YomuImageFormat;
// QR Code
export 'src/qr/decoder/decoded_bit_stream_parser.dart' show DecoderResult;
// Core API
export 'src/yomu.dart' show Yomu;
export 'src/yomu_exception.dart';
