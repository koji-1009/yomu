import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_result.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('YomuException.toString', () {
    // Each name is spelled out rather than taken from runtimeType, which
    // minified (dart2js -O2) and obfuscated (--obfuscate) builds rename:
    // there a BarcodeException printed as "minified:W: ..." or "Ji: ...".
    for (final (exception, expected) in <(YomuException, String)>[
      (const DetectionException('m'), 'DetectionException: m'),
      (const DecodeException('m'), 'DecodeException: m'),
      (const ReedSolomonException('m'), 'ReedSolomonException: m'),
      (const ArgumentException('m'), 'ArgumentException: m'),
      // ignore: deprecated_member_use_from_same_package
      (const ImageProcessingException('m'), 'ImageProcessingException: m'),
      (const BarcodeException('m'), 'BarcodeException: m'),
    ]) {
      test(expected, () {
        expect(exception.toString(), expected);
      });
    }

    test('names a subclass that does not spell out its own', () {
      expect(const _Custom('m').toString(), '_Custom: m');
    });
  });
}

class _Custom extends YomuException {
  const _Custom(super.message);
}
