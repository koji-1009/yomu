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
    final luminances = source.luminances;

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

    // Ring buffer for integral image only (luminance read directly from source)
    final bufferHeight = windowSize + 2;
    final integralBuffer = Int32List(bufferHeight * width);

    final matrix = BitMatrix(width: width, height: height);
    final bits = matrix.bits;
    final rowStride = matrix.rowStride;

    // Boundary helpers
    final rightClamp = width - 1;

    // Pre-calculate integer threshold factor (scaled by 256)
    final scaledThreshold = (thresholdFactor * 256).round();

    // Loop controls
    final processLimit = height + halfWindow;

    for (var i = 0; i < processLimit; i++) {
      // 1. Ingest new row (if within image bounds)
      if (i < height) {
        // Calculate integral for row 'i' reading directly from source
        final writeIdx = i % bufferHeight;
        final integralRowOffset = writeIdx * width;
        final srcRowOffset = i * width;
        final prevIntegralRowOffset =
            ((i > 0) ? (i - 1) % bufferHeight : -1) * width;

        var sum = 0;
        if (prevIntegralRowOffset >= 0) {
          for (var x = 0; x < width; x++) {
            sum += luminances[srcRowOffset + x];
            integralBuffer[integralRowOffset + x] =
                integralBuffer[prevIntegralRowOffset + x] + sum;
          }
        } else {
          for (var x = 0; x < width; x++) {
            sum += luminances[srcRowOffset + x];
            integralBuffer[integralRowOffset + x] = sum;
          }
        }
      }

      // 2. Threshold row 'targetY'
      final targetY = i - halfWindow;

      if (targetY >= 0 && targetY < height) {
        final y1 = (targetY - halfWindow);
        final y2 = (targetY + halfWindow) >= height
            ? height - 1
            : (targetY + halfWindow);

        final rowY2Offset = (y2 % bufferHeight) * width;
        final rowY1Offset = (y1 - 1 >= 0)
            ? ((y1 - 1) % bufferHeight) * width
            : -1;

        // Read luminance directly from source (no ring buffer copy)
        final lumTargetOffset = targetY * width;
        final bitsRowOffset = targetY * rowStride;

        final safeStart = halfWindow + 1;
        final safeEnd = width - halfWindow - 4;

        var x = 0;
        // 1. Left Boundary (Scalar)
        for (; x < safeStart && x < width; x++) {
          _thresholdPixelScalar(
            x,
            width,
            rightClamp,
            halfWindow,
            y1,
            y2,
            luminances,
            lumTargetOffset,
            rowY1Offset,
            rowY2Offset,
            integralBuffer,
            bits,
            bitsRowOffset,
            scaledThreshold,
          );
        }

        // 2. Core Loop (Scalar Optimized)
        if (x < safeEnd) {
          final offBR = halfWindow;
          final offBL = -halfWindow - 1;

          final yStart = (y1 < 0) ? 0 : y1;
          final area = (2 * halfWindow + 1) * (y2 - yStart + 1);
          final areaShifted = area << 8;

          // Split loop to eliminate per-pixel branch on rowY1Offset
          if (rowY1Offset >= 0) {
            for (; x < safeEnd; x++) {
              final val = luminances[lumTargetOffset + x];
              final sumWindow =
                  integralBuffer[rowY2Offset + x + offBR] -
                  integralBuffer[rowY2Offset + x + offBL] -
                  integralBuffer[rowY1Offset + x + offBR] +
                  integralBuffer[rowY1Offset + x + offBL];

              if (val * areaShifted <= sumWindow * scaledThreshold) {
                bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
              }
            }
          } else {
            for (; x < safeEnd; x++) {
              final val = luminances[lumTargetOffset + x];
              final sumWindow =
                  integralBuffer[rowY2Offset + x + offBR] -
                  integralBuffer[rowY2Offset + x + offBL];

              if (val * areaShifted <= sumWindow * scaledThreshold) {
                bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
              }
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
            luminances,
            lumTargetOffset,
            rowY1Offset,
            rowY2Offset,
            integralBuffer,
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
    Uint8List luminances,
    int lumTargetOffset,
    int rowY1Offset,
    int rowY2Offset,
    Int32List integralBuffer,
    Uint32List bits,
    int bitsRowOffset,
    int scaledThreshold,
  ) {
    final x1 = (x - halfWindow < 0) ? 0 : x - halfWindow;
    final x2 = (x + halfWindow > rightClamp) ? rightClamp : x + halfWindow;

    final br = integralBuffer[rowY2Offset + x2];
    final bl = (x1 > 0) ? integralBuffer[rowY2Offset + x1 - 1] : 0;

    final tr = (rowY1Offset >= 0) ? integralBuffer[rowY1Offset + x2] : 0;
    final tl = (rowY1Offset >= 0 && x1 > 0)
        ? integralBuffer[rowY1Offset + x1 - 1]
        : 0;

    final sumWindow = br - bl - tr + tl;
    final area = (x2 - x1 + 1) * (y2 - ((y1 < 0) ? 0 : y1) + 1);

    if ((luminances[lumTargetOffset + x] * area) << 8 <=
        sumWindow * scaledThreshold) {
      bits[bitsRowOffset + (x >> 5)] |= (1 << (x & 31));
    }
  }
}
