import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/decode_effort.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

import 'qr_render_helper.dart';

/// Every failure [Yomu] reports is a [YomuException]: the library throws
/// them where the failure happens and never converts other errors into one,
/// so anything else escaping is a defect in the library, not in the image.
void main() {
  group('Yomu throws only YomuException', () {
    // Images of no code, parts of codes and codes in unusual shapes, in
    // sizes from a single pixel up, so that every stage has something to
    // try and fail on.
    List<(String, YomuImage)> images() {
      final random = Random(18004);
      final out = <(String, YomuImage)>[];

      for (final (width, height) in [
        (1, 1),
        (1, 40),
        (40, 1),
        (7, 7),
        (21, 21),
        (64, 48),
        (200, 150),
        (400, 400),
      ]) {
        final noise = Uint8List(width * height);
        for (var i = 0; i < noise.length; i++) {
          noise[i] = random.nextInt(256);
        }
        out.add((
          'noise ${width}x$height',
          YomuImage.grayscale(bytes: noise, width: width, height: height),
        ));
      }

      // A code cut off by the frame, at several offsets, dark on light and
      // light on dark.
      for (final offset in [-60.0, 0.0, 60.0, 140.0]) {
        for (final lightOnDark in [false, true]) {
          const size = 200;
          final px = blankCanvas(size, value: lightOnDark ? 0 : 255);
          drawQrCode(
            px,
            width: size,
            text: 'https://example.com/$offset',
            cx: offset,
            cy: size / 2,
            module: 5,
            degrees: 17,
            dark: lightOnDark ? 255 : 0,
          );
          out.add((
            'cut code at $offset${lightOnDark ? ', light on dark' : ''}',
            YomuImage.grayscale(bytes: px, width: size, height: size),
          ));
        }
      }

      // A code with a band of noise across it.
      const size = 240;
      final px = blankCanvas(size);
      drawQrCode(
        px,
        width: size,
        text: 'banded',
        cx: size / 2,
        cy: size / 2,
        module: 6,
      );
      for (var y = 100; y < 140; y++) {
        for (var x = 0; x < size; x++) {
          px[y * size + x] = random.nextInt(256);
        }
      }
      out.add((
        'code under a noise band',
        YomuImage.grayscale(bytes: px, width: size, height: size),
      ));
      return out;
    }

    for (final effort in DecodeEffort.values) {
      final yomu = Yomu(
        enableQRCode: true,
        barcodeScanner: BarcodeScanner.all,
        effort: effort,
      );

      for (final (name, image) in images()) {
        test('${effort.name}: $name', () {
          // A result or a YomuException; anything else fails the test.
          try {
            yomu.decode(image);
          } on YomuException {
            // Reported as a failure to decode.
          }
          yomu.decodeAll(image);
        });
      }
    }
  });
}
