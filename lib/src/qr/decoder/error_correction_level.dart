/// QR Code Error Correction Levels.
///
/// The bits encoding in QR format information is:
/// - M = 00 (0)
/// - L = 01 (1)
/// - H = 10 (2)
/// - Q = 11 (3)
enum ErrorCorrectionLevel {
  L,
  M,
  Q,
  H;

  /// Decodes the error correction level from the 2-bit format info field.
  static ErrorCorrectionLevel forBits(int bits) => switch (bits) {
    0 => M,
    1 => L,
    2 => H,
    3 => Q,
    _ => throw ArgumentError('Invalid EC bits: $bits'),
  };
}
