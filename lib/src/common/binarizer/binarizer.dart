import 'dart:typed_data';

import '../bit_matrix.dart';
import 'luminance_source.dart';

/// A binarizer that uses integral images for fast, locally-adaptive thresholding.
///
/// This approach is O(1) per pixel for window sum calculation, making it
/// significantly faster than traditional local thresholding while being
/// robust to lighting gradients and shadows.
class Binarizer {
  const Binarizer(this.source);

  final RGBLuminanceSource source;

  // Block size for the window.
  // 1/8th of the image width is a reasonable heuristic for QR codes.
  static const int _minWindowSize = 40;

  BitMatrix getBlackMatrix() {
    final width = source.width;
    final height = source.height;
    final luminances = source.matrix;

    // 1. Calculate Integral Image
    // S[y][x] = sum(p[i][j]) for 0<=i<=y, 0<=j<=x

    final integral = Int32List(width * height);

    // First row
    var sum = 0;
    for (var x = 0; x < width; x++) {
      sum += luminances[x];
      integral[x] = sum;
    }

    // Remaining rows
    for (var y = 1; y < height; y++) {
      sum = 0;
      final rowOffset = y * width;
      final prevRowOffset = (y - 1) * width;
      for (var x = 0; x < width; x++) {
        sum += luminances[rowOffset + x];
        integral[rowOffset + x] = integral[prevRowOffset + x] + sum;
      }
    }

    final matrix = BitMatrix(width: width, height: height);

    // 2. Adaptive Thresholding
    // Calculate local threshold based on S*S window average.
    var windowSize = (width > height ? width : height) ~/ 32;
    if (windowSize < _minWindowSize) {
      windowSize = _minWindowSize;
    }
    // Safety: Clamp window to image dimensions to prevent out-of-bounds access
    // in boundary loops which depend on window size.
    if (windowSize > width) windowSize = width;
    if (windowSize > height) windowSize = height;

    final halfWindow = windowSize >> 1;

    // Precompute constant area for the core region
    final coreArea = (2 * halfWindow + 1) * (2 * halfWindow + 1);
    final coreAreaX8 = coreArea << 3; // area * 8

    // Access bits directly to avoid method call overhead and hoist row offsets.
    final bits = matrix.bits;
    final rowStride = matrix.rowStride;

    // Helper to process a single pixel (Slow/Boundary version)
    void thresholdPixel(int x, int y) {
      final x1 = (x - halfWindow).clamp(0, width - 1);
      final x2 = (x + halfWindow).clamp(0, width - 1);
      final y1 = (y - halfWindow).clamp(0, height - 1);
      final y2 = (y + halfWindow).clamp(0, height - 1);

      final br = integral[y2 * width + x2];
      final bl = (x1 > 0) ? integral[y2 * width + (x1 - 1)] : 0;
      final tr = (y1 > 0) ? integral[(y1 - 1) * width + x2] : 0;
      final tl = (x1 > 0 && y1 > 0) ? integral[(y1 - 1) * width + (x1 - 1)] : 0;

      final sumWindow = br - bl - tr + tl;
      final area = (x2 - x1 + 1) * (y2 - y1 + 1);

      if ((luminances[y * width + x] * area) << 3 <= sumWindow * 7) {
        bits[y * rowStride + (x >> 5)] |= (1 << (x & 31));
      }
    }

    // Top Boundary (Expand to cover halfWindow)
    final coreYStart = halfWindow + 1;
    for (var y = 0; y < coreYStart; y++) {
      for (var x = 0; x < width; x++) {
        thresholdPixel(x, y);
      }
    }

    // Middle Rows
    final maxY = height - halfWindow;
    final maxX = width - halfWindow;

    final coreXStart = halfWindow + 1;

    // Pre-calculate offsets for the core loop
    // Offsets for window relative to center (x, y)
    // TL: (x-half-1, y-half-1), TR: (x+half, y-half-1)
    // BL: (x-half-1, y+half),   BR: (x+half, y+half)
    final offsetBR = halfWindow * width + halfWindow;
    final offsetBL = halfWindow * width - halfWindow - 1;
    final offsetTR = -(halfWindow + 1) * width + halfWindow;
    final offsetTL = -(halfWindow + 1) * width - halfWindow - 1;

    for (var y = coreYStart; y < maxY; y++) {
      final rowOffset = y * width;
      final bitsRowOffset = y * rowStride;

      // Left Boundary
      for (var x = 0; x < coreXStart; x++) {
        thresholdPixel(x, y);
      }

      // Core Loop (No clamping, no conditionals)

      for (var x = coreXStart; x < maxX; x++) {
        final centerIdx = rowOffset + x;

        final br = integral[centerIdx + offsetBR];
        final bl = integral[centerIdx + offsetBL];
        final tr = integral[centerIdx + offsetTR];
        final tl = integral[centerIdx + offsetTL];

        final sumWindow = br - bl - tr + tl;

        // pixel * coreArea * 8 <= sum * 7
        if ((luminances[centerIdx] * coreAreaX8) <= sumWindow * 7) {
          bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
        }
      }

      // Right Boundary
      for (var x = maxX; x < width; x++) {
        thresholdPixel(x, y);
      }
    }

    // Bottom Boundary
    for (var y = maxY; y < height; y++) {
      for (var x = 0; x < width; x++) {
        thresholdPixel(x, y);
      }
    }

    return matrix;
  }
}
