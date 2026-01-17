import 'dart:js_interop';
import 'dart:typed_data';

import 'package:yomu/yomu.dart';

@JS('decodeQR')
external set _decodeQR(JSFunction fn);

void main() {
  const yomu = Yomu.all;

  _decodeQR = ((JSObject data, JSNumber width, JSNumber height) {
    try {
      final w = width.toDartInt;
      final h = height.toDartInt;
      // data is Uint8ClampedArray from canvas ImageData
      // Cast to JSUint8ClampedArray to use toDart
      final clamped = (data as JSUint8ClampedArray).toDart;
      // Efficiently convert to Uint8List without copying
      final bytes = Uint8List.view(clamped.buffer);
      final result = yomu.decode(bytes: bytes, width: w, height: h);

      return JSDecodeResult(
        success: true,
        text: result.text,
        format: 'QR Code',
      );
    } catch (e, stack) {
      console.error('Decode error: $e\n$stack'.toJS);
      return JSDecodeResult(success: false, text: '', format: '');
    }
  }).toJS;
}

@JS('console')
external JSConsole get console;

extension type JSConsole._(JSObject _) implements JSObject {
  external void error(JSAny? arg);
}

extension type JSDecodeResult._(JSObject _) implements JSObject {
  external factory JSDecodeResult({bool success, String text, String format});

  external bool get success;
  external String get text;
  external String get format;
}
