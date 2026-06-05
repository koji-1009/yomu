import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/yomu.dart';

YomuImage _loadRgba(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final converted = image.convert(format: img.Format.uint8, numChannels: 4);
  return YomuImage.rgba(
    bytes: converted.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
}

YomuImage _loadGrayscale(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final converted = image.convert(format: img.Format.uint8, numChannels: 4);
  final gray = rgbaToGrayscale(
    converted.buffer.asUint8List(),
    image.width,
    image.height,
  );
  return YomuImage.grayscale(
    bytes: gray,
    width: image.width,
    height: image.height,
  );
}

void main() {
  group('Yomu tryHarder integration', () {
    setUpAll(() {
      expect(
        Directory('fixtures/unsupported_images').existsSync(),
        isTrue,
        reason: 'fixtures/unsupported_images is required for these tests',
      );
    });

    group('rescued by retry stages (previously unsupported)', () {
      for (final name in [
        'damaged_noise_0.01',
        'damaged_noise_0.05',
        'damaged_noise_0.10',
        'damaged_noise_0.20',
        'damaged_dirt_0.30',
        'perspective_y_0.2',
        'perspective_y_0.3',
      ]) {
        test('decodes $name', () {
          final result = Yomu.qrOnly.decode(
            _loadRgba('fixtures/distorted_images/$name.png'),
          );
          expect(result.text, 'Hello World');
        });
      }
    });

    group('small codes rescued by the full-resolution retry', () {
      test('decodes a 200px code centered in a Full HD frame', () {
        final result = Yomu.qrOnly.decode(
          _loadRgba(
            'fixtures/performance_test_images/fullhd_white_center_200px.png',
          ),
        );
        expect(result.text, 'PerfTest_fullhd_center_200');
      });

      test('decodes a 250px code in a large square frame', () {
        final result = Yomu.qrOnly.decode(
          _loadRgba(
            'fixtures/performance_test_images/square_gray_top_right_250px.png',
          ),
        );
        expect(result.text, 'PerfTest_square_top_right_250');
      });

      test('decodes a downsampled grayscale input at full resolution', () {
        final result = Yomu.qrOnly.decode(
          _loadGrayscale(
            'fixtures/performance_test_images/fullhd_white_center_200px.png',
          ),
        );
        expect(result.text, 'PerfTest_fullhd_center_200');
      });

      test(
        'rescues a tiny code in a 4K frame via the full-resolution retry',
        () {
          // A ~150px code in a 4K frame shrinks to ~1.5px modules after
          // downsampling, which breaks even the finder. Only the
          // full-resolution retry can decode it.
          final qr = img.decodePng(
            File('fixtures/qr_images/alphanumeric_hello.png').readAsBytesSync(),
          )!;
          final small = img
              .copyResize(
                qr,
                width: 150,
                interpolation: img.Interpolation.average,
              )
              .convert(format: img.Format.uint8, numChannels: 4);
          final smallBytes = small.buffer.asUint8List();

          const canvasW = 3840;
          const canvasH = 2160;
          final canvas = Uint8List(canvasW * canvasH * 4);
          for (var i = 0; i < canvas.length; i++) {
            canvas[i] = 255;
          }
          // Paste the code at (120, 120) by direct row copies.
          for (var y = 0; y < small.height; y++) {
            final srcStart = y * small.width * 4;
            final dstStart = ((y + 120) * canvasW + 120) * 4;
            canvas.setRange(
              dstStart,
              dstStart + small.width * 4,
              smallBytes,
              srcStart,
            );
          }

          final result = Yomu.qrOnly.decode(
            YomuImage.rgba(bytes: canvas, width: canvasW, height: canvasH),
          );
          expect(result.text, 'HELLO WORLD');
        },
      );
    });

    group('detection boundary (fixtures bracket the capability limit)', () {
      // Passing side of each distortion axis. The failing side below pins
      // the boundary from above: if a future improvement rescues one of
      // those, the test fails and the fixture should move to
      // fixtures/distorted_images.
      for (final name in [
        // Legacy axes
        'damaged_noise_0.25',
        'perspective_x_0.3',
        'perspective_y_0.4',
        'perspective_y_0.6',
        // Modern imaging pipeline axes
        'gaussian_noise_110',
        'jpeg_q1',
        'glare_1.0',
        'moire_0.7',
        'composite_scan_blur_5.0',
      ]) {
        test('decodes $name (within the boundary)', () {
          final result = Yomu.qrOnly.decode(
            _loadRgba('fixtures/distorted_images/$name.png'),
          );
          expect(result.text, 'Hello World');
        });
      }

      for (final name in [
        // Legacy axes
        'damaged_noise_0.30',
        'damaged_dirt_0.35',
        'blur_radius_6.0',
        'perspective_x_0.4',
        // Modern imaging pipeline axes
        'gaussian_noise_120',
        'moire_0.8',
        'composite_scan_blur_5.5',
      ]) {
        test('does not decode $name (beyond the boundary)', () {
          expect(
            () => Yomu.qrOnly.decode(
              _loadRgba('fixtures/unsupported_images/$name.png'),
            ),
            throwsA(isA<YomuException>()),
          );
        });
      }
    });

    group('Yomu.all ordering', () {
      test('still decodes barcodes (QR retries do not interfere)', () {
        final result = Yomu.all.decode(
          _loadRgba('fixtures/barcode_images/ean13_product.png'),
        );
        expect(result.text, isNotEmpty);
      });

      test('rescues noisy QR through the post-barcode deep retries', () {
        final result = Yomu.all.decode(
          _loadRgba('fixtures/distorted_images/damaged_noise_0.10.png'),
        );
        expect(result.text, 'Hello World');
      });
    });

    group('decodeAll retry passes', () {
      test('rescues a noisy multi-code sheet via the despeckle pass', () {
        final results = Yomu.qrOnly.decodeAll(
          _loadRgba('fixtures/qr_images/multi_qr_3_noise.png'),
        );
        expect(results.map((r) => r.text).toSet(), {
          'Noise A',
          'Noise B',
          'Noise C',
        });
      });

      test(
        'rescues small codes in a 4K sheet via the full-resolution pass',
        () {
          final results = Yomu.qrOnly.decodeAll(
            _loadRgba('fixtures/qr_images/multi_qr_2_small_4k.png'),
          );
          expect(results.map((r) => r.text).toSet(), {'Small A', 'Small B'});
        },
      );

      test('rescues a detected-but-undecodable code on a mixed sheet', () {
        // A clean code next to a dirt-occluded one: the clean code decodes
        // on the fast pass while the dirty one is detected but needs the
        // in-pass corner-grid rescue.
        final clean = img
            .decodePng(
              File(
                'fixtures/qr_images/alphanumeric_hello.png',
              ).readAsBytesSync(),
            )!
            .convert(format: img.Format.uint8, numChannels: 4);
        final dirty = img
            .decodePng(
              File(
                'fixtures/distorted_images/damaged_dirt_0.30.png',
              ).readAsBytesSync(),
            )!
            .convert(format: img.Format.uint8, numChannels: 4);

        const canvasW = 760;
        const canvasH = 460;
        final canvas = Uint8List(canvasW * canvasH * 4);
        for (var i = 0; i < canvas.length; i++) {
          canvas[i] = 255;
        }
        void paste(img.Image source, int dstX, int dstY) {
          final bytes = source.buffer.asUint8List();
          for (var y = 0; y < source.height; y++) {
            final srcStart = y * source.width * 4;
            final dstStart = ((y + dstY) * canvasW + dstX) * 4;
            canvas.setRange(
              dstStart,
              dstStart + source.width * 4,
              bytes,
              srcStart,
            );
          }
        }

        paste(dirty, 10, 10);
        paste(clean, 440, 10);

        final results = Yomu.qrOnly.decodeAll(
          YomuImage.rgba(bytes: canvas, width: canvasW, height: canvasH),
        );
        expect(results.map((r) => r.text).toSet(), {
          'Hello World',
          'HELLO WORLD',
        });
      });

      test('tryHarder=false finds nothing on the degraded sheets', () {
        const fastOnly = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
          tryHarder: false,
        );
        expect(
          fastOnly.decodeAll(
            _loadRgba('fixtures/qr_images/multi_qr_3_noise.png'),
          ),
          isEmpty,
        );
        // Clean sheets still decode on the fast-only path.
        expect(
          fastOnly
              .decodeAll(
                _loadRgba('fixtures/qr_images/multi_qr_3_vertical.png'),
              )
              .map((r) => r.text)
              .toSet(),
          {'Code A', 'Code B', 'Code C'},
        );
      });

      test('returns empty when nothing is found', () {
        final blankSmall = Uint8List(200 * 200 * 4);
        for (var i = 0; i < blankSmall.length; i++) {
          blankSmall[i] = 255;
        }
        expect(
          Yomu.qrOnly.decodeAll(
            YomuImage.rgba(bytes: blankSmall, width: 200, height: 200),
          ),
          isEmpty,
        );

        // Downsampled blank: the full-resolution pass also runs and finds
        // nothing.
        final blankLarge = Uint8List(1920 * 1080 * 4);
        for (var i = 0; i < blankLarge.length; i++) {
          blankLarge[i] = 255;
        }
        expect(
          Yomu.qrOnly.decodeAll(
            YomuImage.rgba(bytes: blankLarge, width: 1920, height: 1080),
          ),
          isEmpty,
        );

        // QR scanning disabled short-circuits to an empty list.
        expect(
          Yomu.barcodeOnly.decodeAll(
            YomuImage.rgba(bytes: blankSmall, width: 200, height: 200),
          ),
          isEmpty,
        );
      });
    });

    group('exception semantics', () {
      test('detected-but-undecodable code throws DetectionException '
          '(falls through all retries)', () {
        expect(
          () => Yomu.all.decode(
            _loadRgba('fixtures/unsupported_images/curved_wavy_6.0.png'),
          ),
          throwsA(isA<DetectionException>()),
        );
      });

      test('tryHarder=false preserves the DecodeException fast path', () {
        const fastOnly = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.all,
          tryHarder: false,
        );
        expect(
          () => fastOnly.decode(
            _loadRgba('fixtures/unsupported_images/curved_wavy_6.0.png'),
          ),
          throwsA(isA<DecodeException>()),
        );
      });
    });

    group('tryHarder=false (fast-only mode)', () {
      const fastOnly = Yomu(
        enableQRCode: true,
        barcodeScanner: BarcodeScanner.none,
        tryHarder: false,
      );

      test('still decodes clean codes', () {
        final result = fastOnly.decode(
          _loadRgba('fixtures/qr_images/alphanumeric_hello.png'),
        );
        expect(result.text, 'HELLO WORLD');
      });

      test('still decodes barcodes', () {
        const fastAll = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.all,
          tryHarder: false,
        );
        final result = fastAll.decode(
          _loadRgba('fixtures/barcode_images/ean13_product.png'),
        );
        expect(result.text, isNotEmpty);
      });

      test('Yomu.realtime decodes clean codes without retries', () {
        expect(Yomu.realtime.tryHarder, isFalse);
        final result = Yomu.realtime.decode(
          _loadRgba('fixtures/qr_images/alphanumeric_hello.png'),
        );
        expect(result.text, 'HELLO WORLD');
        expect(
          () => Yomu.realtime.decode(
            _loadRgba('fixtures/distorted_images/damaged_noise_0.10.png'),
          ),
          throwsA(isA<YomuException>()),
        );
      });

      test('does not rescue noisy codes', () {
        expect(
          () => fastOnly.decode(
            _loadRgba('fixtures/distorted_images/damaged_noise_0.10.png'),
          ),
          throwsA(isA<DetectionException>()),
        );
      });
    });

    group('configuration variants', () {
      test('decodes with a tight alignment allowance configuration', () {
        const tight = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
          alignmentAreaAllowance: 5,
        );
        final result = tight.decode(
          _loadRgba('fixtures/qr_images/alphanumeric_hello.png'),
        );
        expect(result.text, 'HELLO WORLD');
      });

      test('decodeAll with a tight allowance uses the expanded search', () {
        // Fast-only path with alignmentAreaAllowance == 5: the tight
        // pre-pass is skipped, so the fallback expanded multi-search
        // decodes the codes.
        const tight = Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
          alignmentAreaAllowance: 5,
          tryHarder: false,
        );
        final results = tight.decodeAll(
          _loadRgba('fixtures/qr_images/multi_qr_3_vertical.png'),
        );
        expect(results, hasLength(3));
      });

      test('barcode-only configuration ignores QR codes', () {
        expect(
          () => Yomu.barcodeOnly.decode(
            _loadRgba('fixtures/qr_images/alphanumeric_hello.png'),
          ),
          throwsA(isA<DetectionException>()),
        );
      });

      test('throws DetectionException when nothing is found', () {
        final blank = Uint8List(200 * 200 * 4);
        for (var i = 0; i < blank.length; i++) {
          blank[i] = 255;
        }
        expect(
          () => Yomu.all.decode(
            YomuImage.rgba(bytes: blank, width: 200, height: 200),
          ),
          throwsA(isA<DetectionException>()),
        );
      });

      test(
        'skips the full-resolution retry once the work budget is exhausted',
        () {
          // An upscaled undecodable code in a downsampled-size frame: the
          // grid searches burn the whole budget on a code that cannot
          // decode, so the full-resolution retry is skipped.
          final wavy = img.decodePng(
            File(
              'fixtures/unsupported_images/curved_wavy_6.0.png',
            ).readAsBytesSync(),
          )!;
          final big = img
              .copyResize(
                wavy,
                width: 1640,
                interpolation: img.Interpolation.average,
              )
              .convert(format: img.Format.uint8, numChannels: 4);

          expect(
            () => Yomu.qrOnly.decode(
              YomuImage.rgba(
                bytes: big.buffer.asUint8List(),
                width: big.width,
                height: big.height,
              ),
            ),
            throwsA(isA<DetectionException>()),
          );
        },
      );
    });
  });
}
