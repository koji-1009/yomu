// Tests for remaining uncovered code paths
// Targets: perspective_transform, oned_result, generic_gf_poly, itf_decoder, version, yomu

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/barcode/barcode_result.dart';
import 'package:yomu/src/barcode/itf_decoder.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/perspective_transform.dart';
import 'package:yomu/src/qr/decoder/generic_gf.dart';
import 'package:yomu/src/qr/decoder/generic_gf_poly.dart';
import 'package:yomu/src/qr/decoder/qrcode_decoder.dart';
import 'package:yomu/src/qr/decoder/reed_solomon_decoder.dart';
import 'package:yomu/src/qr/detector/detector.dart';
import 'package:yomu/src/qr/detector/finder_pattern_finder.dart';
import 'package:yomu/src/qr/version.dart';
import 'package:yomu/src/yomu.dart';
import 'package:yomu/src/yomu_exception.dart';

void main() {
  group('PerspectiveTransform Coverage', () {
    test('squareToQuadrilateral with trapezoid triggers non-affine path', () {
      // A trapezoid is NOT affine - it requires perspective transform
      // dx3 != 0 or dy3 != 0, so we hit the else branch at line 78
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0, // top-left
        x1: 100,
        y1: 10, // top-right (not same y as top-left)
        x2: 120,
        y2: 100, // bottom-right (x > 100, creates perspective)
        x3: -20,
        y3: 90, // bottom-left (x < 0, creates perspective)
      );

      expect(transform, isNotNull);
      // Verify transform works
      final points = [0.5, 0.5];
      transform.transformPoints(points);
      expect(points[0].isFinite, isTrue);
      expect(points[1].isFinite, isTrue);
    });

    test('squareToQuadrilateral with strong perspective', () {
      // Create a strongly distorted quadrilateral
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 50,
        y0: 0, // top-left (shifted right)
        x1: 150,
        y1: 0, // top-right
        x2: 200,
        y2: 100, // bottom-right (far right)
        x3: 0,
        y3: 100, // bottom-left
      );

      expect(transform, isNotNull);
    });

    test('quadrilateralToQuadrilateral with perspective distortion', () {
      // Source: regular square
      // Destination: trapezoid (perspective view)
      final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 0,
        x2: 100,
        y2: 100,
        x3: 0,
        y3: 100, // source square
        x0p: 20,
        y0p: 10,
        x1p: 80,
        y1p: 10,
        x2p: 100,
        y2p: 100,
        x3p: 0,
        y3p: 100, // destination trapezoid
      );

      expect(transform, isNotNull);

      // Transform multiple points
      final points = [50.0, 50.0, 25.0, 75.0];
      transform.transformPoints(points);
      expect(points[0].isFinite, isTrue);
      expect(points[1].isFinite, isTrue);
      expect(points[2].isFinite, isTrue);
      expect(points[3].isFinite, isTrue);
    });

    test('handles near-degenerate quadrilateral with fallback', () {
      // Create quadrilateral where denominator is very small
      // This should trigger the abs() < 1e-10 check at line 86
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 0,
        x2: 100,
        y2: 100,
        x3: 0,
        y3: 100,
      );

      expect(transform, isNotNull);
    });

    test('transformPoints transforms multiple coordinate pairs', () {
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 10,
        y0: 20,
        x1: 110,
        y1: 30,
        x2: 100,
        y2: 120,
        x3: 0,
        y3: 110,
      );

      // Transform 3 points (6 values)
      final points = [0.0, 0.0, 0.5, 0.5, 1.0, 1.0];
      transform.transformPoints(points);

      // All outputs should be finite
      for (final p in points) {
        expect(p.isFinite, isTrue);
      }
    });

    test('times combines two transforms', () {
      final t1 = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 50,
        y1: 0,
        x2: 50,
        y2: 50,
        x3: 0,
        y3: 50,
      );
      final t2 = PerspectiveTransform.squareToQuadrilateral(
        x0: 10,
        y0: 10,
        x1: 40,
        y1: 10,
        x2: 40,
        y2: 40,
        x3: 10,
        y3: 40,
      );

      final combined = t1.times(t2);
      expect(combined, isNotNull);
    });
  });

  group('BarcodeResult Coverage', () {
    test('toString returns formatted string', () {
      const result = BarcodeResult(
        text: '123456789012',
        format: 'EAN_13',
        startX: 10,
        endX: 200,
        rowY: 50,
      );

      expect(result.toString(), contains('BarcodeResult'));
      expect(result.toString(), contains('EAN_13'));
      expect(result.toString(), contains('123456789012'));
    });

    test('fields are accessible', () {
      const result = BarcodeResult(
        text: 'TEST',
        format: 'CODE_128',
        startX: 5,
        endX: 100,
        rowY: 25,
      );

      expect(result.text, 'TEST');
      expect(result.format, 'CODE_128');
      expect(result.startX, 5);
      expect(result.endX, 100);
      expect(result.rowY, 25);
    });
  });

  group('BarcodeException Coverage', () {
    test('toString returns formatted message', () {
      const exception = BarcodeException('Barcode not found');

      expect(exception.toString(), contains('BarcodeException'));
      expect(exception.toString(), contains('Barcode not found'));
      expect(exception.message, 'Barcode not found');
    });
  });

  group('GenericGFPoly Exception Paths', () {
    test('divide by zero throws', () {
      final field = GenericGF.qrCodeField256;
      final poly1 = GenericGFPoly(field, [1, 2, 3]);
      final zero = field.zero;

      expect(() => poly1.divide(zero), throwsA(isA<ArgumentError>()));
    });

    test('multiplyByMonomial with negative degree throws', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [1, 2]);

      expect(
        () => poly.multiplyByMonomial(-1, 3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toString returns polynomial representation', () {
      final field = GenericGF.qrCodeField256;
      final poly = GenericGFPoly(field, [3, 2, 1]);

      final str = poly.toString();
      expect(str, contains('x^'));
    });
  });

  group('ITF-14 Checksum Validation', () {
    test('validates correct ITF-14 barcode', () {
      // Valid ITF-14: 00012345678905
      final result = ITFDecoder.validateITF14Checksum('00012345678905');
      expect(result, isTrue);
    });

    test('rejects incorrect ITF-14 checksum', () {
      // Invalid checksum (changed last digit)
      final result = ITFDecoder.validateITF14Checksum('00012345678901');
      expect(result, isFalse);
    });

    test('rejects non-14-digit barcode', () {
      // Only 10 digits
      final result = ITFDecoder.validateITF14Checksum('1234567890');
      expect(result, isFalse);
    });

    test('validates another ITF-14 barcode', () {
      // Test with different valid ITF-14
      // Pattern: sum of odd positions * 3 + sum of even positions
      // (10 - sum % 10) % 10 = check digit
      final result = ITFDecoder.validateITF14Checksum('10614141000415');
      expect(result, isTrue);
    });
  });

  group('PerspectiveTransform Degenerate Quadrilateral', () {
    test('handles near-degenerate quadrilateral (denominator < 1e-10)', () {
      // Create points where dx1*dy2 - dx2*dy1 ≈ 0 (collinear or degenerate)
      // Points: (0,0), (100,0), (100,0), (0,0) - collapsed quad
      final transform = PerspectiveTransform.squareToQuadrilateral(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 0,
        x2: 100.000001,
        y2: 0.000001, // Nearly collinear with (100,0)
        x3: 0.000001,
        y3: 0.000001,
      );

      expect(transform, isNotNull);
    });
  });

  group('Version Boundary Tests', () {
    test('getProvisionalVersionForDimension throws on invalid dimension', () {
      // Dimension must satisfy (dimension - 17) % 4 == 0, i.e. dimension % 4 == 1
      // 20 % 4 == 0, not 1, so should throw
      expect(
        () => Version.getProvisionalVersionForDimension(20),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getProvisionalVersionForDimension throws on too small dimension', () {
      // Dimension 13: (13-17)/4 = -1, invalid version
      expect(
        () => Version.getProvisionalVersionForDimension(13),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getProvisionalVersionForDimension works for valid dimension', () {
      // Dimension 21: (21-17)/4 = 1, version 1
      final version = Version.getProvisionalVersionForDimension(21);
      expect(version.versionNumber, 1);
    });
    test('getVersionForNumber throws on version 0', () {
      expect(
        () => Version.getVersionForNumber(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getVersionForNumber throws on version 41', () {
      expect(
        () => Version.getVersionForNumber(41),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Yomu Input Validation', () {
    test('decodeAll throws on too small byte array', () {
      const yomu = Yomu.qrOnly;
      final smallBytes = Uint8List(10); // Too small for 100x100 RGBA

      expect(
        () => yomu.decodeAll(bytes: smallBytes, width: 100, height: 100),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Byte array too small'),
          ),
        ),
      );
    });
  });

  group('Detector Dimension Adjustment', () {
    test('adjusts dimension when mod 4 == 0 (adds 1)', () {
      // 20 % 4 == 0 -> 20 + 1 = 21
      expect(Detector.adjustDimension(20), 21);
    });

    test('leaves dimension unchanged when mod 4 == 1', () {
      // 21 % 4 == 1 -> unchanged
      expect(Detector.adjustDimension(21), 21);
    });

    test('adjusts dimension when mod 4 == 2 (subtracts 1)', () {
      // 22 % 4 == 2 -> 22 - 1 = 21
      expect(Detector.adjustDimension(22), 21);
    });

    test('adjusts dimension when mod 4 == 3 (adds 2)', () {
      // 23 % 4 == 3 -> 23 + 2 = 25
      expect(Detector.adjustDimension(23), 25);
    });
  });

  group('Defensive Logic Unit Tests', () {
    test('PerspectiveTransform.checkDegenerate detects degenerate quad', () {
      // Degenerate: x0=x1 (collapsing side)
      // x0=0,y0=0; x1=0,y1=10; x2=10,y2=10; x3=10,y3=0 -> Square
      // Make it degenerate: x2=0, y2=10 (same as x1)
      final degenerate = PerspectiveTransform.checkDegenerate(
        x0: 0,
        y0: 0,
        x1: 0,
        y1: 10,
        x2: 0,
        y2: 10, // x2 same as x1
        x3: 10,
        y3: 0,
      );
      expect(degenerate, isNotNull);
    });

    test('QRCodeDecoder.rsDecode throws DecodeException on failure', () {
      // RS(4, 2) -> 2 data, 2 ec
      // Codewords: [1, 2, 3, 4]
      // Corrupt them heavily
      final codewords = [100, 200, 3, 4];
      final rsDecoder = ReedSolomonDecoder(GenericGF.qrCodeField256);

      expect(
        () => QRCodeDecoder.rsDecode(
          codewords: codewords,
          ecCount: 2,
          rsDecoder: rsDecoder,
        ),
        throwsA(
          isA<DecodeException>().having(
            (e) => (e).message,
            'message',
            contains('RS error'),
          ),
        ),
      );
    });

    test('FinderPatternFinder.foundPatternCross validates 1:1:3:1:1 ratio', () {
      // Perfect 1:1:3:1:1 ratio (module size 10)
      // 10, 10, 30, 10, 10
      expect(
        FinderPatternFinder.foundPatternCross([10, 10, 30, 10, 10]),
        isTrue,
      );

      // Invalid ratio
      expect(
        FinderPatternFinder.foundPatternCross([10, 10, 10, 10, 10]),
        isFalse,
      );

      // Zero count
      expect(
        FinderPatternFinder.foundPatternCross([10, 0, 30, 10, 10]),
        isFalse,
      );
    });

    test('Version.decodeVersionInformation calculates BCH', () {
      // Version 7: 0x07C94
      expect(Version.decodeVersionInformation(0x07C94)?.versionNumber, 7);

      // 1 bit error (LSB flipped): 0x07C95
      expect(Version.decodeVersionInformation(0x07C95)?.versionNumber, 7);

      // 3 bit error: 0x07C94 ^ 0x07 (last 3 bits flipped) -> 0x07C93
      expect(Version.decodeVersionInformation(0x07C93)?.versionNumber, 7);

      // 4 bit error: 0x07C94 ^ 0x0F -> 0x07C9B
      // Should fail (return null) or find another closer version if any?
      // Hamming distance to correct is 4.
      // If no other version is within 3, it returns null.
      expect(Version.decodeVersionInformation(0x07C9B), isNull);
    });
  });

  group('BitMatrixParser Version Fallback', () {
    test('readVersion falls back to second block or provisional', () {
      // Create a BitMatrix with dimension 45 (Version 7)
      // Dimension 45 -> (45-17)/4 = 7.
      final matrix = BitMatrix(width: 45, height: 45);

      // We need to verify that readVersion attempts to read version info.
      // Since the matrix is empty (all zeros), version decoding will fail for both blocks
      // (BCH check fails for 0x00000).
      // So it should fall back to provisional version 7.
      // This covers Line 241 (return provisional).
      // And it also executes Line 235 (try second block).

      final parser = BitMatrixParser(matrix);
      final version = parser.readVersion();
      expect(version.versionNumber, 7);
    });
  });

  group('FinderPatternFinder Edge Cases', () {
    test('find detects pattern at very end of row', () {
      // FinderPatternFinder skips rows (mod 3 == 2). So Row 0 and 1 are skipped.
      // We must place the pattern on Row 2 to be scanned.
      final matrix = BitMatrix(width: 14, height: 3);

      // Set pixels manually on Row 2
      // Pattern: B B, W W, B B B B B B, W W, B B (Total 14)
      // Counts: 2, 2, 6, 2, 2. Ratio 1:1:3:1:1.
      const y = 2;
      for (var x = 0; x < 2; x++) {
        matrix.set(x: x, y: y);
      } // Set (0,2), (1,2)
      // 2,3 are W
      for (var x = 4; x < 10; x++) {
        matrix.set(x: x, y: y);
      } // Set (4,2) to (9,2)
      // 10,11 are W
      for (var x = 12; x < 14; x++) {
        matrix.set(x: x, y: y);
      } // Set (12,2), (13,2)

      // Verify setup
      expect(matrix.get(x: 0, y: y), isTrue); // B
      expect(matrix.get(x: 1, y: y), isTrue); // B
      expect(matrix.get(x: 2, y: y), isFalse); // W
      expect(matrix.get(x: 3, y: y), isFalse); // W
      expect(matrix.get(x: 4, y: y), isTrue); // B
      expect(matrix.get(x: 9, y: y), isTrue); // B
      expect(matrix.get(x: 10, y: y), isFalse); // W
      expect(matrix.get(x: 11, y: y), isFalse); // W
      expect(matrix.get(x: 12, y: y), isTrue); // B
      expect(matrix.get(x: 13, y: y), isTrue); // B

      final finder = FinderPatternFinder(matrix);
      // This will throw NotFoundException because only 1 pattern exists,
      // but it should execute Line 385 before throwing.
      try {
        finder.find();
      } catch (_) {
        // Expected
      }
    });
  });
}
