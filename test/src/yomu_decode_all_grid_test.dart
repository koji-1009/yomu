import 'package:test/test.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';

import 'qr_render_helper.dart';

void main() {
  group('decodeAll on a rotated 2x2 grid', () {
    // Corresponding finder patterns of neighbouring codes form right
    // isosceles triangles too, so a grid of codes offers cross-code
    // triplets alongside the real ones.
    YomuImage grid(double degrees) {
      const size = 1200;
      final px = blankCanvas(size);
      for (var i = 0; i < 4; i++) {
        drawQrCode(
          px,
          width: size,
          text: 'https://example.com/$i',
          cx: 300.0 + (i % 2) * 600,
          cy: 300.0 + (i ~/ 2) * 600,
          module: 6,
          degrees: degrees,
        );
      }
      return YomuImage.grayscale(bytes: px, width: size, height: size);
    }

    for (final degrees in [0.0, 5.0, 20.0, -10.0]) {
      for (final (name, yomu) in [
        ('realtime', Yomu.realtime),
        ('responsive', Yomu.responsive),
        ('qrOnly', Yomu.qrOnly),
      ]) {
        test('$name finds all four codes at $degrees deg', () {
          expect(
            yomu.decodeAll(grid(degrees)).map((r) => r.text),
            unorderedEquals([
              for (var i = 0; i < 4; i++) 'https://example.com/$i',
            ]),
          );
        });
      }
    }
  });
}
