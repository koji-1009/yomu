import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('Robustness / Fuzz Tests', () {
    test('Yomu.all.decode handles random byte input gracefully', () {
      final random = Random(12345);
      // Run 50 iterations with random noise
      for (var i = 0; i < 50; i++) {
        final length = random.nextInt(1000) + 100;
        final bytes = Uint8List(length);
        for (var j = 0; j < length; j++) {
          bytes[j] = random.nextInt(256);
        }

        // Random dimensions that fit the bytes
        final width = sqrt(length ~/ 4).floor();
        final height = width;
        if (width < 5 || height < 5) continue;

        try {
          Yomu.all.decode(
            YomuImage.rgba(bytes: bytes, width: width, height: height),
          );
        } catch (e) {
          // Should throw typed exceptions, not crash with RangeError etc.
          expect(e, isA<YomuException>());
        }
      }
    });

    test('QRCodeDecoder handles random bit matrices', () {
      final random = Random(67890);
      final decoder = QRCodeDecoder();

      for (var i = 0; i < 20; i++) {
        final dimension = random.nextInt(50) + 21;
        final matrix = BitMatrix(width: dimension, height: dimension);
        // Fill with random bits
        for (var y = 0; y < dimension; y++) {
          for (var x = 0; x < dimension; x++) {
            if (random.nextBool()) {
              matrix.set(x, y);
            }
          }
        }

        try {
          decoder.decode(matrix);
        } catch (e) {
          // Should normally throw DecodeException, but ReaderException/ChecksumException base classes are also possible if they exist.
          // Yomu uses YomuException hierarchy.
          expect(e, isA<YomuException>());
        }
      }
    });

    test('FinderPatternFinder handles noise gracefully', () {
      // This is harder to unit test directly without exposing internals,
      // but we can test Detector with noisy matrix.
      final random = Random(13579);
      for (var i = 0; i < 20; i++) {
        const dimension = 100;
        final matrix = BitMatrix(width: dimension);
        // 50% noise
        for (var y = 0; y < dimension; y++) {
          for (var x = 0; x < dimension; x++) {
            if (random.nextBool()) {
              matrix.set(x, y);
            }
          }
        }

        final detector = Detector(matrix);
        try {
          detector.detect();
        } catch (e) {
          expect(e, isA<YomuException>());
        }
      }
    });
  });
}
