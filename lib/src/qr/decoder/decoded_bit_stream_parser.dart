import 'dart:convert';
import 'dart:typed_data';

import '../../common/bit_source.dart';
import '../../yomu_exception.dart';
import '../mode.dart';
import '../version.dart';

/// The result of a successful QR code decode operation.
///
/// Contains the decoded text content along with metadata about the
/// decoding process.
///
/// ## Properties
///
/// - [text]: The primary decoded string content
/// - [byteSegments]: Raw byte data for each byte-mode segment (useful for binary data)
/// - [ecLevel]: The error correction level used (L, M, Q, or H)
///
/// ## Example
///
/// ```dart
/// final result = yomu.decode(imageBytes, width, height);
/// print('Content: ${result.text}');
/// print('EC Level: ${result.ecLevel}');
/// for (final segment in result.byteSegments) {
///   print('Raw bytes: $segment');
/// }
/// ```
class DecoderResult {
  /// Creates a new decoder result.
  const DecoderResult({
    required this.text,
    required this.byteSegments,
    this.ecLevel,
  });

  /// The decoded text content of the QR code.
  final String text;

  /// Raw byte segments from byte-mode encoded data.
  ///
  /// Each element corresponds to a contiguous byte-mode segment in the QR code.
  /// Useful when the QR code contains binary data that shouldn't be interpreted
  /// as text.
  final List<Uint8List> byteSegments;

  /// The error correction level used in the QR code.
  ///
  /// One of: "L" (7%), "M" (15%), "Q" (25%), "H" (30%).
  /// May be null if not determined.
  final String? ecLevel;
}

class DecodedBitStreamParser {
  static const _alphanumericChars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

  static DecoderResult decode({
    required Uint8List bytes,
    required Version version,
  }) {
    final source = BitSource(bytes.toList()); // BitSource expects List<int>
    final sb = StringBuffer();
    // byteSegments would be accumulated
    final byteSegments = <Uint8List>[];

    Mode mode;
    do {
      if (source.available() < 4) {
        mode = Mode.terminator;
      } else {
        try {
          final modeBits = source.readBits(4);
          mode = Mode.forBits(modeBits);
        } catch (_) {
          mode = Mode.terminator; // End of stream or invalid
        }
      }

      if (mode != Mode.terminator) {
        final countBits = mode.getCharacterCountBits(version);
        final count = source.readBits(countBits);

        if (mode == Mode.numeric) {
          _decodeNumericSegment(source: source, sb: sb, count: count);
        } else if (mode == Mode.alphanumeric) {
          _decodeAlphanumericSegment(source: source, sb: sb, count: count);
        } else if (mode == Mode.byte) {
          _decodeByteSegment(
            source: source,
            sb: sb,
            count: count,
            segments: byteSegments,
          );
        } else if (mode == Mode.kanji) {
          _decodeKanjiSegment(source: source, sb: sb, count: count);
        } else {
          throw DecodeException('Unsupported mode: $mode');
        }
      }
    } while (mode != Mode.terminator);

    return DecoderResult(text: sb.toString(), byteSegments: byteSegments);
  }

  static void _decodeNumericSegment({
    required BitSource source,
    required StringBuffer sb,
    required int count,
  }) {
    // Read 3 chars (10 bits), 2 chars (7 bits), or 1 char (4 bits)
    while (count >= 3) {
      if (source.available() < 10) {
        throw const DecodeException('Not enough bits for numeric');
      }
      final bits = source.readBits(10);
      if (bits >= 1000) throw DecodeException('Illegal numeric value: $bits');
      sb.write(_formatNumeric(value: bits, digits: 3));
      count -= 3;
    }
    if (count == 2) {
      if (source.available() < 7) {
        throw const DecodeException('Not enough bits for numeric');
      }
      final bits = source.readBits(7);
      if (bits >= 100) throw DecodeException('Illegal numeric value: $bits');
      sb.write(_formatNumeric(value: bits, digits: 2));
      count = 0;
    } else if (count == 1) {
      if (source.available() < 4) {
        throw const DecodeException('Not enough bits for numeric');
      }
      final bits = source.readBits(4);
      if (bits >= 10) throw DecodeException('Illegal numeric value: $bits');
      sb.write(_formatNumeric(value: bits, digits: 1));
      count = 0;
    }
  }

  static String _formatNumeric({required int value, required int digits}) {
    final s = value.toString();
    if (s.length >= digits) return s;
    return s.padLeft(digits, '0');
  }

  static void _decodeAlphanumericSegment({
    required BitSource source,
    required StringBuffer sb,
    required int count,
  }) {
    // 2 chars encoded in 11 bits
    while (count >= 2) {
      if (source.available() < 11) {
        throw const DecodeException('Not enough bits for alphanumeric');
      }
      final bits = source.readBits(11); // val = first*45 + second
      final first = bits ~/ 45;
      final second = bits % 45;
      sb.write(_alphanumericChars[first]);
      sb.write(_alphanumericChars[second]);
      count -= 2;
    }
    if (count == 1) {
      if (source.available() < 6) {
        throw const DecodeException('Not enough bits for alphanumeric');
      }
      final bits = source.readBits(6);
      sb.write(_alphanumericChars[bits]);
      count = 0;
    }
  }

  static void _decodeByteSegment({
    required BitSource source,
    required StringBuffer sb,
    required int count,
    required List<Uint8List> segments,
  }) {
    // 8 bits per char
    if (source.available() < 8 * count) {
      throw const DecodeException('Not enough bits for byte mode');
    }

    final readBytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      readBytes[i] = source.readBits(8);
    }
    segments.add(readBytes);

    // Default encoding is Latin-1 per spec, but UTF-8 is commonly used.
    // We try UTF-8 first, then fallback to Latin-1.
    try {
      sb.write(utf8.decode(readBytes));
    } catch (_) {
      // Fallback to latin1
      sb.write(latin1.decode(readBytes));
    }
  }

  /// Decodes a Kanji mode segment.
  ///
  /// Kanji characters are encoded as 13-bit values representing
  /// Shift JIS double-byte characters with a compact encoding.
  static void _decodeKanjiSegment({
    required BitSource source,
    required StringBuffer sb,
    required int count,
  }) {
    // Each Kanji character is 13 bits
    if (source.available() < 13 * count) {
      throw const DecodeException('Not enough bits for Kanji mode');
    }

    final shiftJisBytes = <int>[];

    for (var i = 0; i < count; i++) {
      final twoBytes = source.readBits(13);

      // Reverse the compact encoding
      // If value is in range 0x8140-0x9FFC, subtract 0x8140 and encode
      // If value is in range 0xE040-0xEBBF, subtract 0xC140 and encode
      var assembledValue = ((twoBytes ~/ 0x0C0) << 8) | (twoBytes % 0x0C0);

      if (assembledValue < 0x01F00) {
        // Range 0x8140 - 0x9FFC
        assembledValue += 0x08140;
      } else {
        // Range 0xE040 - 0xEBBF
        assembledValue += 0x0C140;
      }

      // Extract the two Shift JIS bytes
      shiftJisBytes.add((assembledValue >> 8) & 0xFF);
      shiftJisBytes.add(assembledValue & 0xFF);
    }

    // Convert Shift JIS to Unicode
    // a Shift JIS codec would be needed.
    sb.write(decodeShiftJis(shiftJisBytes));
  }

  /// Converts Shift JIS bytes to a Unicode string.
  ///
  /// This is a simplified implementation that handles common JIS X 0208
  /// characters. For full Shift JIS support, consider using a dedicated
  /// codec package.
  static String decodeShiftJis(List<int> bytes) {
    final result = StringBuffer();
    var i = 0;

    while (i < bytes.length) {
      final b1 = bytes[i];

      if (b1 < 0x80) {
        // ASCII
        result.writeCharCode(b1);
        i++;
      } else if (b1 >= 0xA1 && b1 <= 0xDF) {
        // Half-width katakana (JIS X 0201)
        // Map to Unicode half-width katakana block (0xFF61-0xFF9F)
        result.writeCharCode(0xFF61 + (b1 - 0xA1));
        i++;
      } else if (i + 1 < bytes.length) {
        // Double-byte character
        final b2 = bytes[i + 1];

        // Convert Shift JIS to JIS X 0208 row/cell
        int row;
        int cell;

        if (b1 >= 0x81 && b1 <= 0x9F) {
          row = (b1 - 0x81) * 2 + 1;
        } else if (b1 >= 0xE0 && b1 <= 0xEF) {
          row = (b1 - 0xE0) * 2 + 63;
        } else {
          // Unknown lead byte, skip
          result.write('\uFFFD');
          i += 2;
          continue;
        }

        if (b2 >= 0x40 && b2 <= 0x7E) {
          cell = b2 - 0x40 + 1;
        } else if (b2 >= 0x80 && b2 <= 0x9E) {
          cell = b2 - 0x80 + 64;
        } else if (b2 >= 0x9F && b2 <= 0xFC) {
          cell = b2 - 0x9F + 1;
          row++;
        } else {
          // Unknown trail byte
          result.write('\uFFFD');
          i += 2;
          continue;
        }

        // Lookup in JIS X 0208 to Unicode table
        // For now, use a simplified approach - emit the raw bytes as
        // placeholder. A full implementation would use a lookup table.
        final codePoint = jisToUnicode(row: row, cell: cell);
        if (codePoint != null) {
          result.writeCharCode(codePoint);
        } else {
          // Fallback: output replacement character
          result.write('\uFFFD');
        }

        i += 2;
      } else {
        // Incomplete double-byte sequence
        result.write('\uFFFD');
        i++;
      }
    }

    return result.toString();
  }

  /// Maps JIS X 0208 row/cell to Unicode code point.
  ///
  /// This is a minimal implementation covering common characters.
  /// A complete implementation would include the full JIS X 0208 table.
  static int? jisToUnicode({required int row, required int cell}) {
    // Row 1-8: Symbols and punctuation
    // Row 16-47: Level 1 Kanji
    // Row 48-84: Level 2 Kanji

    // Simplified mapping. Complete implementation requires full JIS X 0208 table.
    // Here we provide a simplified mapping for demonstration.

    // Hiragana (row 4)
    if (row == 4 && cell >= 1 && cell <= 83) {
      return 0x3041 + cell - 1; // Hiragana block starts at U+3041
    }

    // Katakana (row 5)
    if (row == 5 && cell >= 1 && cell <= 86) {
      return 0x30A1 + cell - 1; // Katakana block starts at U+30A1
    }

    // For other characters, we'd need a full JIS X 0208 table
    // Return null to indicate unmapped character
    return null;
  }
}
