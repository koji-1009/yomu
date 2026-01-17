import 'dart:js_interop';

import 'package:yomu/yomu.dart';

@JS('decodeQR')
external set _decodeQR(JSFunction fn);

void main() {
  const yomu = Yomu.qrOnly;

  _decodeQR = ((JSUint8Array data, JSNumber width, JSNumber height) {
    try {
      final w = width.toDartInt;
      final h = height.toDartInt;
      // data is already RGBA bytes from canvas ImageData
      final bytes = data.toDart;

      final result = yomu.decode(bytes: bytes, width: w, height: h);

      return DecodeResultJS(
        success: true.toJS,
        text: result.text.toJS,
        format: 'QR Code'.toJS,
      );
    } catch (e) {
      return DecodeResultJS(
        success: false.toJS,
        text: ''.toJS,
        format: ''.toJS,
      );
    }
  }).toJS;
}

extension type DecodeResultJS._(JSObject _) implements JSObject {
  external factory DecodeResultJS({
    JSBoolean success,
    JSString text,
    JSString format,
  });

  external JSBoolean get success;
  external JSString get text;
  external JSString get format;
}
