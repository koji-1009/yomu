import 'package:test/test.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';

import 'qr_render_helper.dart';

void main() {
  group('Reflectance reversal', () {
    // Light modules on a dark background (ISO/IEC 18004:2015, 6.2).
    YomuImage inverted() {
      const size = 264;
      final px = blankCanvas(size, value: 0);
      drawQrCode(
        px,
        width: size,
        text: 'https://example.com/',
        cx: size / 2,
        cy: size / 2,
        module: 8,
        dark: 255,
      );
      return YomuImage.grayscale(bytes: px, width: size, height: size);
    }

    for (final (name, yomu) in [
      ('realtime', Yomu.realtime),
      ('responsive', Yomu.responsive),
      ('qrOnly', Yomu.qrOnly),
      ('all', Yomu.all),
    ]) {
      test('$name.decode reads a reversed code', () {
        expect(yomu.decode(inverted()).text, 'https://example.com/');
      });

      test('$name.decodeAll reads a reversed code', () {
        expect(yomu.decodeAll(inverted()).map((r) => r.text), [
          'https://example.com/',
        ]);
      });
    }
  });
}
