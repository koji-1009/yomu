import 'version.dart';

/// Represents the encoding mode used in a QR code segment.
///
/// QR codes can encode data using different modes, each optimized for
/// specific types of content:
///
/// | Mode | Use Case | Efficiency |
/// |------|----------|------------|
/// | [numeric] | Digits 0-9 | 3.3 bits/char |
/// | [alphanumeric] | A-Z, 0-9, special | 5.5 bits/char |
/// | [byte] | Any byte value | 8 bits/char |
/// | [kanji] | Japanese characters | 13 bits/char |
///
/// ## Mode Indicators
///
/// Each mode is identified by a 4-bit indicator in the QR data stream.
/// Use [forBits] to convert from the bit pattern to a [Mode] instance.
///
/// ## Character Count
///
/// The number of bits used to encode the character count varies by
/// QR code version. Use [getCharacterCountBits] to get the correct
/// bit length for a specific version.
class Mode {
  /// Creates a new Mode with the specified character count bits and identifier.
  const Mode(this._characterCountBitsForVersions, this.bits, this.name);

  /// End of data indicator.
  static const Mode terminator = Mode([0, 0, 0], 0x00, 'TERMINATOR');

  /// Numeric mode: digits 0-9 only.
  static const Mode numeric = Mode([10, 12, 14], 0x01, 'NUMERIC');

  /// Alphanumeric mode: A-Z, 0-9, space, $%*+-./:
  static const Mode alphanumeric = Mode([9, 11, 13], 0x02, 'ALPHANUMERIC');

  /// Structured append mode for splitting data across multiple QR codes.
  static const Mode structuredAppend = Mode(
    [0, 0, 0],
    0x03,
    'STRUCTURED_APPEND',
  );

  /// Byte mode: any 8-bit value (typically ISO-8859-1 or UTF-8).
  static const Mode byte = Mode([8, 16, 16], 0x04, 'BYTE');

  /// Extended Channel Interpretation mode for character set switching.
  static const Mode eci = Mode([0, 0, 0], 0x07, 'ECI');

  /// Kanji mode for Japanese characters (Shift JIS encoding).
  static const Mode kanji = Mode([8, 10, 12], 0x08, 'KANJI');

  /// FNC1 in first position (GS1 barcodes).
  static const Mode fnc1FirstPosition = Mode([0, 0, 0], 0x05, 'FNC1_FIRST');

  /// FNC1 in second position (AIM application).
  static const Mode fnc1SecondPosition = Mode([0, 0, 0], 0x09, 'FNC1_SECOND');

  /// Hanzi mode for Simplified Chinese characters.
  static const Mode hanzi = Mode([8, 10, 12], 0x0D, 'HANZI');

  final List<int> _characterCountBitsForVersions;

  /// The 4-bit mode indicator value.
  final int bits;

  /// Human-readable name of the mode.
  final String name;

  static Mode forBits(int bits) => switch (bits) {
    0x00 => terminator,
    0x01 => numeric,
    0x02 => alphanumeric,
    0x03 => structuredAppend,
    0x04 => byte,
    0x05 => fnc1FirstPosition,
    0x07 => eci,
    0x08 => kanji,
    0x09 => fnc1SecondPosition,
    0x0D => hanzi,
    _ => throw ArgumentError('Invalid mode bits: $bits'),
  };

  /// Returns the number of bits used for character count in this mode for [version].
  int getCharacterCountBits(Version version) {
    final number = version.versionNumber; // 1 to 40
    int offset;
    if (number <= 9) {
      offset = 0;
    } else if (number <= 26) {
      offset = 1;
    } else {
      offset = 2;
    }
    return _characterCountBitsForVersions[offset];
  }

  @override
  String toString() => name;
}
