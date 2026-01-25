import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

// Helper to create test images
YomuImage _createPattern(
  int width,
  int height,
  int Function(int x, int y) pixelGen,
) {
  final bytes = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[y * width + x] = pixelGen(x, y) & 0xFF;
    }
  }
  return YomuImage.grayscale(bytes: bytes, width: width, height: height);
}

void main() {
  group('Barcode Robustness Tests (False Positives)', () {
    test('Random Noise should not be detected', () {
      // Seeded random for reproducibility (simple LCG)
      var seed = 12345;
      int next() => (seed = (seed * 1103515245 + 12345) & 0x7fffffff);

      final image = _createPattern(400, 400, (x, y) => next() % 256);

      expect(
        () => Yomu.all.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Random noise should not be detected as code',
      );
    });

    test('Vertical stripes (Barcode imitation) should not be detected', () {
      // Simulate stripes like a keyboard or fence
      final image = _createPattern(400, 300, (x, y) {
        // Stripes every 10 pixels
        return (x % 20 < 10) ? 0 : 255;
      });

      expect(
        () => Yomu.all.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Perfect vertical stripes should not be detected as code',
      );
    });

    test('Horizontal stripes should not be detected', () {
      final image = _createPattern(400, 300, (x, y) {
        return (y % 20 < 10) ? 0 : 255;
      });

      expect(
        () => Yomu.all.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Horizontal stripes should not be detected',
      );
    });

    test('Grid/Keyboard-like pattern should not be detected', () {
      // simulating keys on a keyboard
      final image = _createPattern(500, 300, (x, y) {
        final xLine = (x % 40 < 5);
        final yLine = (y % 40 < 5);
        return (xLine || yLine) ? 50 : 200;
      });

      expect(
        () => Yomu.all.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Grid pattern should not be detected',
      );
    });

    test('Gradient should not be detected', () {
      final image = _createPattern(300, 300, (x, y) {
        return ((x + y) / 2).floor();
      });
      expect(
        () => Yomu.all.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Gradient should not be detected',
      );
    });

    // Explicitly check Barcode Only mode for sensitive patterns
    test('Barcode Only: Dense Vertical Stripes', () {
      // High frequency stripes, could look like 1D barcode
      final image = _createPattern(400, 200, (x, y) {
        return (x % 6 < 3) ? 20 : 230;
      });

      expect(
        () => Yomu.barcodeOnly.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Dense stripes should not be valid barcode',
      );
    });

    test('Barcode Only: Noisy Vertical Stripes', () {
      // Stripes with some noise
      var seed = 999;
      int noise() => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) % 64);

      final image = _createPattern(400, 200, (x, y) {
        final base = (x % 14 < 6) ? 30 : 220;
        return (base + noise()).clamp(0, 255);
      });

      expect(
        () => Yomu.barcodeOnly.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Noisy stripes should not be valid barcode',
      );
    });

    test('Barcode Only: ITF-like alternating pattern', () {
      // ITF is just pairs of bars. Very prone to false positives.
      // Create a pattern that looks like Start/Stop codes or simple data
      final image = _createPattern(400, 100, (x, y) {
        // Narrow-Narrow-Wide-Narrow pattern often triggers ITF
        final p = x % 10;
        if (p < 2) return 0; // Black
        if (p < 4) return 255; // White
        if (p < 8) return 0; // Wide Black
        return 255; // White
      });

      expect(
        () => Yomu.barcodeOnly.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Simple alternating pattern should not be detected as ITF',
      );
    });

    test('Barcode Only: Code39-like gaps', () {
      // Code39 is discrete, has gaps.
      final image = _createPattern(500, 100, (x, y) {
        // Random-ish looking bars with gaps
        if (x % 12 == 10) return 255; // Force gap
        return (x % 7 < 3) ? 0 : 255;
      });

      expect(
        () => Yomu.barcodeOnly.decode(image),
        throwsA(isA<DetectionException>()),
        reason: 'Pattern with gaps should not be detected as Code39',
      );
    });
  });
}
