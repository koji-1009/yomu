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

    test('is on by default', () {
      expect(Yomu.all.readLightOnDark, isTrue);
      expect(
        const Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
        ).readLightOnDark,
        isTrue,
      );
    });

    group('with readLightOnDark off', () {
      YomuImage normal() {
        const size = 264;
        final px = blankCanvas(size);
        drawQrCode(
          px,
          width: size,
          text: 'https://example.com/',
          cx: size / 2,
          cy: size / 2,
          module: 8,
        );
        return YomuImage.grayscale(bytes: px, width: size, height: size);
      }

      for (final effort in DecodeEffort.values) {
        final yomu = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.all,
          effort: effort,
          readLightOnDark: false,
        );

        test('${effort.name} does not read a reversed code', () {
          expect(
            () => yomu.decode(inverted()),
            throwsA(isA<DetectionException>()),
          );
          expect(yomu.decodeAll(inverted()), isEmpty);
        });

        test('${effort.name} still reads a normal code', () {
          expect(yomu.decode(normal()).text, 'https://example.com/');
          expect(yomu.decodeAll(normal()).map((r) => r.text), [
            'https://example.com/',
          ]);
        });
      }
    });

    group('in the retry stages', () {
      // A fixture with its colours inverted, and the text its original
      // decodes to.
      (YomuImage, String) invertedFixture(String path) {
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
        for (var i = 0; i < bytes.length; i += 4) {
          bytes[i] = 255 - bytes[i];
          bytes[i + 1] = 255 - bytes[i + 1];
          bytes[i + 2] = 255 - bytes[i + 2];
        }
        final image = YomuImage.rgba(
          bytes: bytes,
          width: decoded.width,
          height: decoded.height,
        );
        return (image, text);
      }

      Yomu yomuAt(DecodeEffort effort, {bool readLightOnDark = true}) => Yomu(
        enableQRCode: true,
        barcodeScanner: BarcodeScanner.none,
        effort: effort,
        readLightOnDark: readLightOnDark,
      );

      test('fast reads a light-on-dark code past a false dark-on-light '
          'triplet', () {
        // The dark-on-light scan of this image finds a triplet that does not
        // decode: with light-on-dark reading off, fast ends in its
        // DecodeException.
        final (image, text) = invertedFixture(
          'fixtures/qr_complex_images/version_10.png',
        );

        expect(
          () => yomuAt(DecodeEffort.fast, readLightOnDark: false).decode(image),
          throwsA(isA<DecodeException>()),
        );
        expect(yomuAt(DecodeEffort.fast).decode(image).text, text);
      });

      test('despeckle reads a noisy light-on-dark code', () {
        // Salt & pepper noise: only the despeckle stage recovers it.
        final (image, text) = invertedFixture(
          'fixtures/distorted_images/damaged_noise_0.10.png',
        );

        expect(
          () => yomuAt(DecodeEffort.fast).decode(image),
          throwsA(isA<YomuException>()),
        );
        expect(yomuAt(DecodeEffort.balanced).decode(image).text, text);
        expect(
          () => yomuAt(
            DecodeEffort.balanced,
            readLightOnDark: false,
          ).decode(image),
          throwsA(isA<DetectionException>()),
        );
      });

      test('the threshold sweep reads a blurred light-on-dark code', () {
        // Blur: only a stage that rebuilds the image recovers it.
        final (image, text) = invertedFixture(
          'fixtures/distorted_images/blur_radius_5.0.png',
        );

        expect(
          () => yomuAt(DecodeEffort.balanced).decode(image),
          throwsA(isA<DetectionException>()),
        );
        expect(yomuAt(DecodeEffort.thorough).decode(image).text, text);
        expect(
          () => yomuAt(
            DecodeEffort.thorough,
            readLightOnDark: false,
          ).decode(image),
          throwsA(isA<DetectionException>()),
        );
      });
    });

    group('decodeAll on a mixed sheet', () {
      // Left half: a dark-on-light code. Right half: a light-on-dark one.
      YomuImage mixed() {
        const width = 600;
        const height = 300;
        final px = Uint8List(width * height);
        for (var y = 0; y < height; y++) {
          px.fillRange(y * width, y * width + width ~/ 2, 255);
        }
        drawQrCode(
          px,
          width: width,
          text: 'dark on light',
          cx: 150,
          cy: 150,
          module: 6,
        );
        drawQrCode(
          px,
          width: width,
          text: 'light on dark',
          cx: 450,
          cy: 150,
          module: 6,
          dark: 255,
        );
        return YomuImage.grayscale(bytes: px, width: width, height: height);
      }

      for (final effort in DecodeEffort.values) {
        test('${effort.name} returns both codes', () {
          final yomu = Yomu(
            enableQRCode: true,
            barcodeScanner: BarcodeScanner.none,
            effort: effort,
          );
          expect(
            yomu.decodeAll(mixed()).map((r) => r.text),
            unorderedEquals(['dark on light', 'light on dark']),
          );
        });

        test('${effort.name} with readLightOnDark off returns one', () {
          final yomu = Yomu(
            enableQRCode: true,
            barcodeScanner: BarcodeScanner.none,
            effort: effort,
            readLightOnDark: false,
          );
          expect(yomu.decodeAll(mixed()).map((r) => r.text), ['dark on light']);
        });
      }
    });
  });
}
