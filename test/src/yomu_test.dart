import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('Yomu Input Validation', () {
    test('decode throws ArgumentError on empty bytes', () {
      expect(
        () => Yomu.all.decode(width: 10, height: 10, bytes: Uint8List(0)),
        throwsA(isA<ArgumentException>()),
      );
    });

    test('decode throws ArgumentError on size mismatch', () {
      expect(
        () => Yomu.all.decode(
          width: 10,
          height: 10,
          bytes: Uint8List(10),
        ), // 100 needed
        throwsA(isA<ArgumentException>()),
      );
    });
  });
}
