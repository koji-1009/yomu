import '../common/binarizer/binarizer.dart';
import '../common/binarizer/luminance_source.dart';
import 'barcode_decoder.dart';
import 'barcode_result.dart';
import 'codabar_decoder.dart';
import 'code128_decoder.dart';
import 'code39_decoder.dart';
import 'ean13_decoder.dart';
import 'ean8_decoder.dart';
import 'itf_decoder.dart';
import 'upca_decoder.dart';

/// 1D barcode scanner with configurable decoders.
///
/// Use [BarcodeScanner.all] for all supported formats, or create a custom
/// configuration by specifying which [decoders] to use.
///
/// ## Example
///
/// ```dart
/// // Scan for all barcode formats
/// final scanner = BarcodeScanner.all;
///
/// // Scan for retail formats only (EAN/UPC)
/// final scanner = BarcodeScanner.retail;
///
/// // Custom configuration
/// const scanner = BarcodeScanner(decoders: [EAN13Decoder(), Code128Decoder()]);
/// ```
class BarcodeScanner {
  /// Creates a barcode scanner with the specified decoders.
  const BarcodeScanner({required this.decoders});

  /// The list of decoders to use for scanning.
  final List<BarcodeDecoder> decoders;

  /// Scanner with all supported barcode formats enabled.
  static const all = BarcodeScanner(
    decoders: [
      EAN13Decoder(),
      EAN8Decoder(),
      UPCADecoder(),
      Code128Decoder(),
      Code39Decoder(),
      ITFDecoder(),
      CodabarDecoder(),
    ],
  );

  /// Scanner for retail barcode formats (EAN-13, EAN-8, UPC-A).
  static const retail = BarcodeScanner(
    decoders: [EAN13Decoder(), EAN8Decoder(), UPCADecoder()],
  );

  /// Scanner for industrial barcode formats (Code 128, Code 39, ITF, Codabar).
  static const industrial = BarcodeScanner(
    decoders: [
      Code128Decoder(),
      Code39Decoder(),
      ITFDecoder(),
      CodabarDecoder(),
    ],
  );

  /// Empty scanner that disables barcode scanning.
  ///
  /// Use this instead of null when you want to disable barcode scanning.
  static const none = BarcodeScanner(decoders: []);

  /// Returns true if this scanner has no decoders (disabled).
  bool get isEmpty => decoders.isEmpty;

  /// Scans for a 1D barcode in the image.
  ///
  /// Returns the first barcode found, or null if none found.
  BarcodeResult? scan(RGBLuminanceSource source) {
    final matrix = GlobalHistogramBinarizer(source).getBlackMatrix();

    for (final decoder in decoders) {
      final result = decoder.decode(matrix);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  /// Scans for all 1D barcodes in the image.
  ///
  /// Returns a list of all barcodes found.
  List<BarcodeResult> scanAll(RGBLuminanceSource source) {
    final matrix = GlobalHistogramBinarizer(source).getBlackMatrix();
    final results = <BarcodeResult>[];

    for (final decoder in decoders) {
      final result = decoder.decode(matrix);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }
}
