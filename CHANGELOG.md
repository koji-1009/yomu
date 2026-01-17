## 0.1.0

Initial release.

### Features

* **QR Code Decoding**
  * Versions 1-40
  * Encoding modes: Numeric, Alphanumeric, Byte, Kanji
  * Error correction levels: L, M, Q, H
  * Multi-QR detection
* **1D Barcode Decoding**
  * EAN-13, EAN-8, UPC-A
  * Code 128, Code 39
  * ITF (Interleaved 2 of 5)
  * Codabar
* **Core**
  * Zero external dependencies
  * Pure Dart implementation
  * Reed-Solomon error correction
  * Automatic downsampling for large images

### Performance

* < 1.5ms average decode time (AOT)
* < 2ms average decode time (JIT)
* 120fps capable for all resolutions up to 4K

### Limitations

* Micro QR not supported
* ECI (Extended Channel Interpretation) not supported
