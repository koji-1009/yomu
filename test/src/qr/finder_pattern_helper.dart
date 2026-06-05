import 'package:yomu/src/common/bit_matrix.dart';

/// Draws a standard 7x7 finder pattern (ring plus 3x3 center) scaled by
/// [moduleSize], clipping to the matrix bounds (negative offsets simulate
/// cropped patterns).
void drawFinderPattern(
  BitMatrix matrix,
  int xStart,
  int yStart, {
  int moduleSize = 1,
}) {
  for (var my = 0; my < 7; my++) {
    for (var mx = 0; mx < 7; mx++) {
      final isDark =
          my == 0 ||
          my == 6 ||
          mx == 0 ||
          mx == 6 ||
          (my >= 2 && my <= 4 && mx >= 2 && mx <= 4);
      if (!isDark) continue;
      for (var py = 0; py < moduleSize; py++) {
        for (var px = 0; px < moduleSize; px++) {
          final x = xStart + mx * moduleSize + px;
          final y = yStart + my * moduleSize + py;
          if (x >= 0 && x < matrix.width && y >= 0 && y < matrix.height) {
            matrix.set(x, y);
          }
        }
      }
    }
  }
}
