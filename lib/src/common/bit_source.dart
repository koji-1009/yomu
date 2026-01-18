import 'dart:typed_data';

/// Helper to read bits from a byte array.
class BitSource {
  // 0 to 7
  BitSource(this._bytes) : _byteOffset = 0, _bitOffset = 0;
  final Uint8List _bytes;
  int _byteOffset;
  int _bitOffset;

  int get byteOffset => _byteOffset;
  int get bitOffset => _bitOffset;

  // Available bits
  @pragma('dart2js:prefer-inline')
  @pragma('vm:prefer-inline')
  int available() {
    return 8 * (_bytes.length - _byteOffset) - _bitOffset;
  }

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
