import 'dart:typed_data';

/// Reads bits sequentially from a byte array, maintaining a cursor position.
///
/// Used by the QR code decoded bit stream parser to extract mode indicators,
/// character counts, and data segments from the raw codeword bytes.
class BitSource {
  BitSource(this._bytes) : _byteOffset = 0, _bitOffset = 0;
  final Uint8List _bytes;
  int _byteOffset;
  int _bitOffset;

  int get byteOffset => _byteOffset;
  int get bitOffset => _bitOffset;

  /// Returns the number of bits still available to read.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int available() {
    return 8 * (_bytes.length - _byteOffset) - _bitOffset;
  }

  /// Reads [numBits] bits from the source, advancing the cursor.
  ///
  /// Returns the bits as the least significant bits of the result.
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int readBits(int numBits) {
    var result = 0;
    var bitsLeft = numBits;

    while (bitsLeft > 0) {
      if (_bitOffset == 8) {
        _byteOffset++;
        _bitOffset = 0;
      }

      var bitsToRead = 8 - _bitOffset;
      if (bitsToRead > bitsLeft) {
        bitsToRead = bitsLeft;
      }

      final shift = 8 - _bitOffset - bitsToRead;
      final bits = (_bytes[_byteOffset] >> shift) & ((1 << bitsToRead) - 1);

      result = (result << bitsToRead) | bits;

      _bitOffset += bitsToRead;
      bitsLeft -= bitsToRead;
    }
    return result;
  }
}
