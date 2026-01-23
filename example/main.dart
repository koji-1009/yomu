import 'dart:typed_data';

import 'package:qr/qr.dart';
import 'package:yomu/yomu.dart';

/// A simple example showing how to use Yomu to decode a QR code.
///
/// This example demonstrates a full round-trip:
/// 1. Generating a QR code using various `package:qr`.
/// 2. Parsing (Decoding) it back using `package:yomu`.
void main() {
  // 1. Generate a QR code
  const qrMessage = 'Hello, Yomu! 🚀';
  final qr = QrCode(4, QrErrorCorrectLevel.L)..addData(qrMessage);
  final qrImage = QrImage(qr);

  print('Original Text: "$qrMessage"');
  print(
    'Generated QR: Version ${qr.typeNumber} (${qrImage.moduleCount}x${qrImage.moduleCount})',
  );

  // 2. Render to RGBA pixels (Simulate an image)
  // Yomu expects a flat Uint8List of RGBA bytes (or other supported inputs).
  final width = qrImage.moduleCount;
  final height = qrImage.moduleCount;
  final pixels = _renderQrImage(qrImage);

  // 3. Decode with Yomu
  // We don't even need to save it to a file!
  print('\nDecoding...');

  try {
    // Create a YomuImage
    final image = YomuImage.rgba(bytes: pixels, width: width, height: height);

    // Decode!
    final result = Yomu.qrOnly.decode(image);

    print('----------- RESULT -----------');
    print('Decoded Text: ${result.text}');
    print('EC Level:     ${result.ecLevel}');
    print('Match:        ${result.text == qrMessage ? "✅ YES" : "❌ NO"}');
    print('------------------------------');
  } catch (e) {
    print('Failed to decode: $e');
  }
}

/// Renders a [QrImage] to a flat RGBA 32-bit pixel array (Uint8List).
///
/// Returns a [Uint8List] where every 4 bytes represents a pixel (R, G, B, A).
Uint8List _renderQrImage(QrImage qrImage) {
  final width = qrImage.moduleCount;
  final height = qrImage.moduleCount;
  final pixels = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final isDark = qrImage.isDark(y, x);
      final offset = (y * width + x) * 4;

      // RGBA: Black (0,0,0,255) for dark, White (255,255,255,255) for light
      final value = isDark ? 0 : 255;

      pixels[offset] = value; // R
      pixels[offset + 1] = value; // G
      pixels[offset + 2] = value; // B
      pixels[offset + 3] = 255; // A
    }
  }
  return pixels;
}
