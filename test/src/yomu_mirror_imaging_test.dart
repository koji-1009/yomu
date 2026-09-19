import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_scanner.dart';
import 'package:yomu/src/decode_effort.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

import 'qr_render_helper.dart';

/// Mirrors the grayscale [pixels] left to right.
Uint8List _flipHorizontal(Uint8List pixels, {required int width}) {
  final height = pixels.length ~/ width;
  final out = Uint8List(pixels.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out[y * width + x] = pixels[y * width + width - 1 - x];
    }
  }
  return out;
}

/// Mirrors the grayscale [pixels] top to bottom.
Uint8List _flipVertical(Uint8List pixels, {required int width}) {
  final height = pixels.length ~/ width;
  final out = Uint8List(pixels.length);
  for (var y = 0; y < height; y++) {
    out.setRange(
      y * width,
      y * width + width,
      pixels,
      (height - 1 - y) * width,
    );
  }
  return out;
}

void main() {
  group('Mirror imaging', () {
    // ISO/IEC 18004:2015, 6.2: a symbol whose modules are laterally
    // transposed still decodes.
    const text = 'https://example.com/';

    YomuImage drawn({
      double degrees = 0,
      bool vertical = false,
      bool lightOnDark = false,
    }) {
      const size = 264;
      final px = blankCanvas(size, value: lightOnDark ? 0 : 255);
      drawQrCode(
        px,
        width: size,
        text: text,
        cx: size / 2,
        cy: size / 2,
        module: 8,
        degrees: degrees,
        dark: lightOnDark ? 255 : 0,
      );
      final mirrored = vertical
          ? _flipVertical(px, width: size)
          : _flipHorizontal(px, width: size);
      return YomuImage.grayscale(bytes: mirrored, width: size, height: size);
    }

    for (final (name, yomu) in [
      ('realtime', Yomu.realtime),
      ('responsive', Yomu.responsive),
      ('qrOnly', Yomu.qrOnly),
      ('all', Yomu.all),
    ]) {
      test('$name.decode reads a mirror-image code', () {
        expect(yomu.decode(drawn()).text, text);
      });

      test('$name.decodeAll reads a mirror-image code', () {
        expect(yomu.decodeAll(drawn()).map((r) => r.text), [text]);
      });
    }

    test('reads a code mirrored top to bottom and rotated', () {
      for (final degrees in [0.0, 30.0, 90.0, 200.0]) {
        expect(
          Yomu.realtime.decode(drawn(degrees: degrees, vertical: true)).text,
          text,
          reason: '$degrees degrees',
        );
      }
    });

    test('reads a mirror-image code with reflectance reversal', () {
      final image = drawn(lightOnDark: true);
      expect(Yomu.realtime.decode(image).text, text);
      expect(Yomu.realtime.decodeAll(image).map((r) => r.text), [text]);
      expect(
        () => const Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
          readLightOnDark: false,
        ).decode(image),
        throwsA(isA<DetectionException>()),
      );
    });

    group('from fixtures', () {
      // A fixture mirrored left to right, and the text its original decodes
      // to.
      (YomuImage, String) mirroredFixture(String path) {
        final decoded = img.decodePng(File(path).readAsBytesSync())!;
        final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
        final bytes = rgba.buffer.asUint8List();
        final text = Yomu.qrOnly
            .decode(
              YomuImage.rgba(
                bytes: Uint8List.fromList(bytes),
                width: decoded.width,
                height: decoded.height,
              ),
            )
            .text;
        final mirrored = Uint8List(bytes.length);
        final rowBytes = decoded.width * 4;
        for (var y = 0; y < decoded.height; y++) {
          for (var x = 0; x < decoded.width; x++) {
            final to = y * rowBytes + x * 4;
            final from = y * rowBytes + (decoded.width - 1 - x) * 4;
            mirrored.setRange(to, to + 4, bytes, from);
          }
        }
        final image = YomuImage.rgba(
          bytes: mirrored,
          width: decoded.width,
          height: decoded.height,
        );
        return (image, text);
      }

      test('reads version information of a mirror-image code', () {
        // Version 7 and up carry their version in two blocks, which mirror
        // imaging swaps.
        for (final path in [
          'fixtures/qr_complex_images/qr_version_7_with_version_info.png',
          'fixtures/qr_complex_images/version_10.png',
        ]) {
          final (image, text) = mirroredFixture(path);
          expect(
            yomuAt(DecodeEffort.fast).decode(image).text,
            text,
            reason: path,
          );
        }
      });

      test('despeckle reads a noisy mirror-image code', () {
        final (image, text) = mirroredFixture(
          'fixtures/distorted_images/damaged_noise_0.10.png',
        );

        expect(
          () => yomuAt(DecodeEffort.fast).decode(image),
          throwsA(isA<YomuException>()),
        );
        expect(yomuAt(DecodeEffort.balanced).decode(image).text, text);
      });

      test('thorough reads a mirror-image code under moire', () {
        // Screen moire: only a stage that rebuilds the image recovers it.
        final (image, text) = mirroredFixture(
          'fixtures/distorted_images/moire_0.7.png',
        );

        expect(
          () => yomuAt(DecodeEffort.balanced).decode(image),
          throwsA(isA<YomuException>()),
        );
        expect(yomuAt(DecodeEffort.thorough).decode(image).text, text);
      });
    });

    group('decodeAll on a mixed sheet', () {
      // Left half: a code in normal orientation. Right half: a mirror image.
      YomuImage mixed() {
        const width = 600;
        const height = 300;
        final left = Uint8List(width * height)
          ..fillRange(0, width * height, 255);
        drawQrCode(
          left,
          width: width,
          text: 'normal',
          cx: 150,
          cy: 150,
          module: 6,
        );
        // Drawn on the left, then flipped onto the right.
        final right = Uint8List(width * height)
          ..fillRange(0, width * height, 255);
        drawQrCode(
          right,
          width: width,
          text: 'mirror image',
          cx: 150,
          cy: 150,
          module: 6,
        );
        final flipped = _flipHorizontal(right, width: width);
        for (var y = 0; y < height; y++) {
          left.setRange(
            y * width + width ~/ 2,
            y * width + width,
            flipped,
            y * width + width ~/ 2,
          );
        }
        return YomuImage.grayscale(bytes: left, width: width, height: height);
      }

      for (final effort in DecodeEffort.values) {
        test('${effort.name} returns both codes', () {
          expect(
            yomuAt(effort).decodeAll(mixed()).map((r) => r.text),
            unorderedEquals(['normal', 'mirror image']),
          );
        });
      }
    });
  });
}

Yomu yomuAt(DecodeEffort effort) => Yomu(
  enableQRCode: true,
  barcodeScanner: BarcodeScanner.none,
  effort: effort,
);
