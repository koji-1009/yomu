import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/image_data.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('Yomu Input Validation', () {
    test('decode throws ArgumentException on empty bytes', () {
      expect(
        () => Yomu.all.decode(
          YomuImage.rgba(width: 10, height: 10, bytes: Uint8List(0)),
        ),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('decode throws ArgumentException on size mismatch', () {
      expect(
        () => Yomu.all.decode(
          YomuImage.rgba(
            width: 10,
            height: 10,
            bytes: Uint8List(10), // 100 needed for grayscale, 400 for RGBA
          ),
        ),
        throwsA(isA<ArgumentException>()),
      );
    });
  });
}
