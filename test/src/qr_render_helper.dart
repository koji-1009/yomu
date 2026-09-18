import 'dart:math';
import 'dart:typed_data';

import 'package:qr/qr.dart';

/// Draws [text] as a QR code (ECC M) onto the grayscale [pixels], [module]
/// pixels per module, centered on ([cx], [cy]) and rotated by [degrees].
///
/// Dark modules are drawn as [dark]; the pixels around them are untouched.
void drawQrCode(
  Uint8List pixels, {
  required int width,
  required String text,
  required double cx,
  required double cy,
  required int module,
  double degrees = 0,
  int dark = 0,
}) {
  final code = QrImage(
    QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = code.moduleCount;
  final half = n * module / 2;
  final angle = degrees * pi / 180;
  final c = cos(angle);
  final s = sin(angle);
  final r = (half * 1.5).ceil();
  final height = pixels.length ~/ width;
  for (var y = max(0, (cy - r).floor()); y <= min(height - 1, cy + r); y++) {
    for (var x = max(0, (cx - r).floor()); x <= min(width - 1, cx + r); x++) {
      final dx = x + 0.5 - cx;
      final dy = y + 0.5 - cy;
      final u = dx * c + dy * s + half;
      final v = -dx * s + dy * c + half;
      final mx = (u / module).floor();
      final my = (v / module).floor();
      if (mx < 0 || my < 0 || mx >= n || my >= n) continue;
      if (code.isDark(my, mx)) pixels[y * width + x] = dark;
    }
  }
}

/// A [size] x [size] grayscale canvas filled with [value].
Uint8List blankCanvas(int size, {int value = 255}) =>
    Uint8List(size * size)..fillRange(0, size * size, value);
