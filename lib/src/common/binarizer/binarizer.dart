import 'dart:typed_data';

import '../bit_matrix.dart';
import 'luminance_source.dart';

/// A binarizer that uses integral images for fast, locally-adaptive thresholding.
///
/// This approach is O(1) per pixel for window sum calculation, making it
/// significantly faster than traditional local thresholding while being
/// robust to lighting gradients and shadows.
class Binarizer {
  const Binarizer(this.source, {this.thresholdFactor = 0.875});

  final LuminanceSource source;
  final double thresholdFactor;

  // Block size for the window.
  // 1/8th of the image width is a reasonable heuristic for QR codes.
  static const int _minWindowSize = 40;

  BitMatrix getBlackMatrix() {
    final width = source.width;
    final height = source.height;

    // 2. Adaptive Thresholding Setup
    // Calculate window size based on image dimensions
    var windowSize = (width > height ? width : height) ~/ 32;
    if (windowSize < _minWindowSize) {
      windowSize = _minWindowSize;
    }
    // Safety: Clamp window to image dimensions
    if (windowSize > width) windowSize = width;
    if (windowSize > height) windowSize = height;

    final halfWindow = windowSize >> 1;

    // We need a rolling buffer for integral lines.
    // We need access to lines from (y - halfWindow - 1) up to (y + halfWindow).
    // Total lines needed = windowSize + 2 roughly.
    // Using a circular buffer (ring buffer).
    final bufferHeight = windowSize + 2;
    final integralBuffer = List<Int32List>.generate(
      bufferHeight,
      (_) => Int32List(width),
      growable: false,
    );

    // Buffer for luminance rows corresponding to the integral buffer.
    // This avoids re-fetching/re-calculating luminance for the target row.
    final lumBuffer = List<Uint8List>.generate(
      bufferHeight,
      (_) => Uint8List(width),
      growable: false,
    );

    final matrix = BitMatrix(width: width, height: height);
    final bits = matrix.bits;
    final rowStride = matrix.rowStride;

    // Boundary helpers
    final rightClamp = width - 1;

    // Pre-calculate integer threshold factor (scaled by 256)
    // Legacy 7/8 (0.875) becomes 224.
    // This allows using integer math for performance and keeping exact behavior for default.
    final scaledThreshold = (thresholdFactor * 256).round();

    // Loop controls
    final processLimit = height + halfWindow;

    for (var i = 0; i < processLimit; i++) {
      // 1. Ingest new row (if within image bounds)
      final writeIdx = i % bufferHeight; // Circular buffer index for row 'i'

      if (i < height) {
        // Calculate integral for row 'i'
        final lumRow = source.getRow(i, lumBuffer[writeIdx]);
        final integralRow = integralBuffer[writeIdx];
        final prevIntegralRow = (i > 0)
            ? integralBuffer[(i - 1) % bufferHeight]
            : null;

        var sum = 0;
        // 1. Horizontal Prefix Sum & Vertical Accumulation (Scalar is fastest for single pass)
        // Combining them into one loop avoids iterating twice.
        if (prevIntegralRow != null) {
          for (var x = 0; x < width; x++) {
            sum += lumRow[x];
            integralRow[x] = prevIntegralRow[x] + sum;
          }
        } else {
          for (var x = 0; x < width; x++) {
            sum += lumRow[x];
            integralRow[x] = sum;
          }
        }
      }

      // 2. Threshold row 'targetY'
      final targetY = i - halfWindow;

      if (targetY >= 0 && targetY < height) {
        // We have enough data now.
        final y1 = (targetY - halfWindow); // can be < 0
        final y2 = (targetY + halfWindow) >= height
            ? height - 1
            : (targetY + halfWindow);

        // Get buffers
        final rowY2 = integralBuffer[y2 % bufferHeight];
        final rowY1 = (y1 - 1 >= 0)
            ? integralBuffer[(y1 - 1) % bufferHeight]
            : null;

        final lumTarget = lumBuffer[targetY % bufferHeight];
        final bitsRowOffset = targetY * rowStride;

        // Optimization: Run SIMD in the safe core region where no x-clamping is needed.
        // Safe region: [halfWindow + 1, width - halfWindow - 4]
        // This avoids checking boundaries inside the loop.

        // 1. Left Boundary (Scalar)
        final safeStart = halfWindow + 1;
        // Ensure we can read up to x+3+halfWindow without going OOB.
        // max index accessed is x + 3 + halfWindow.
        // x + 3 + halfWindow < width  =>  x < width - halfWindow - 3
        final safeEnd = width - halfWindow - 4;

        var x = 0;
        // Only run scalar loop for left boundary
        for (; x < safeStart && x < width; x++) {
          _thresholdPixelScalar(
            x,
            width,
            rightClamp,
            halfWindow,
            y1,
            y2,
            lumTarget,
            rowY1,
            rowY2,
            bits,
            bitsRowOffset,
            scaledThreshold,
          );
        }

        // 2. Core Loop (Scalar Optimized)
        // We hoist boundary checks.
        if (x < safeEnd) {
          final offBR = halfWindow;
          final offBL = -halfWindow - 1;

          final yStart = (y1 < 0) ? 0 : y1;
          final h = (y2 - yStart + 1);
          final area = (2 * halfWindow + 1) * h;
          final areaShifted = area << 8;

          for (; x < safeEnd; x++) {
            final val = lumTarget[x];
            final br = rowY2[x + offBR];
            final bl = rowY2[x + offBL];

            var sumWindow = br - bl;
            if (rowY1 != null) {
              final tr = rowY1[x + offBR];
              final tl = rowY1[x + offBL];
              sumWindow -= (tr - tl);
            }

            // (val * area) * 256 <= sumWindow * scaledThreshold
            if (val * areaShifted <= sumWindow * scaledThreshold) {
              bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
            }
          }
        }

        // 3. Right Boundary (Scalar)
        for (; x < width; x++) {
          _thresholdPixelScalar(
            x,
            width,
            rightClamp,
            halfWindow,
            y1,
            y2,
            lumTarget,
            rowY1,
            rowY2,
            bits,
            bitsRowOffset,
            scaledThreshold,
          );
        }
      }
    }

    return matrix;
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  void _thresholdPixelScalar(
    int x,
    int width,
    int rightClamp,
    int halfWindow,
    int y1,
    int y2,
    Uint8List lumTarget,
    Int32List? rowY1,
    Int32List rowY2,
    Uint32List bits,
    int bitsRowOffset,
    int scaledThreshold,
  ) {
    final x1 = (x - halfWindow < 0) ? 0 : x - halfWindow;
    final x2 = (x + halfWindow > rightClamp) ? rightClamp : x + halfWindow;

    final br = rowY2[x2];
    final bl = (x1 > 0) ? rowY2[x1 - 1] : 0;

    final tr = (rowY1 != null) ? rowY1[x2] : 0;
    final tl = (rowY1 != null && x1 > 0) ? rowY1[x1 - 1] : 0;

    final sumWindow = br - bl - tr + tl;
    final area = (x2 - x1 + 1) * (y2 - ((y1 < 0) ? 0 : y1) + 1);

    if ((lumTarget[x] * area) << 8 <= sumWindow * scaledThreshold) {
      bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
    }
  }
}
