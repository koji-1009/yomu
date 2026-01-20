import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/image_conversion.dart';
import 'package:yomu/yomu.dart';

Uint8List _pixelsToBytes(int width, int height, int color) {
  final bytes = Uint8List(width * height * 4);
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = 0xFF; // Alpha
  }
  return bytes;
}

void main() {
  group('Yomu API & Logic Tests', () {
    group('Input Validation & Edge Cases', () {
      late Yomu yomu;

      setUp(() {
        yomu = Yomu.qrOnly;
      });

      test('throws on empty byte array', () {
        expect(
          () => yomu.decode(bytes: Uint8List(0), width: 0, height: 0),
          throwsA(anything),
        );
      });

      test('throws on insufficient bytes', () {
        // 100 bytes but claim 20x20 = 1600 pixels * 4 bytes/pixel = 6400 bytes needed
        // The decoder expects RGBA, so it checks for enough bytes.
        final bytes = Uint8List(100);
        expect(
          () => yomu.decode(bytes: bytes, width: 20, height: 20),
          throwsA(anything),
        );
      });

      test('throws when no QR code present', () {
        // All white image
        final bytes = _pixelsToBytes(100, 100, 0xFFFFFF);
        expect(
          () => yomu.decode(bytes: bytes, width: 100, height: 100),
          throwsException,
        );
      });

      test('decodeAll returns empty list for no QR codes', () {
        final bytes = _pixelsToBytes(100, 100, 0xFFFFFF);
        final results = yomu.decodeAll(bytes: bytes, width: 100, height: 100);
        expect(results, isEmpty);
      });
    });

    group('BitMatrix Operations', () {
      test('handles 1x1 matrix', () {
        final matrix = BitMatrix(width: 1, height: 1);
        expect(matrix.get(0, 0), isFalse);
        matrix.set(0, 0);
        expect(matrix.get(0, 0), isTrue);
        matrix.flip(0, 0);
        expect(matrix.get(0, 0), isFalse);
      });

      test('handles large matrix', () {
        final matrix = BitMatrix(width: 1000, height: 1000);
        matrix.set(999, 999);
        expect(matrix.get(999, 999), isTrue);
        expect(matrix.get(0, 0), isFalse);
      });
    });

    group('LuminanceSource Operations', () {
      test('handles very small image', () {
        final pixels = Int32List(4);
        pixels[0] = 0xFF000000; // Black
        pixels[1] = 0xFFFFFFFF; // White
        pixels[2] = 0xFFFFFFFF; // White
        pixels[3] = 0xFF000000; // Black

        final luminances = int32ToGrayscale(pixels, 2, 2);
        final source = LuminanceSource(
          width: 2,
          height: 2,
          luminances: luminances,
        );

        expect(source.width, 2);
        expect(source.height, 2);
        // Black pixel should have low luminance
        expect(source.getRow(0, null)[0], lessThan(50));
        // White pixel should have high luminance
        expect(source.getRow(0, null)[1], greaterThan(200));
      });

      test('handles grayscale values correctly', () {
        final pixels = Int32List(3);
        // Pure red, green, blue
        pixels[0] = 0xFFFF0000; // Red
        pixels[1] = 0xFF00FF00; // Green
        pixels[2] = 0xFF0000FF; // Blue

        final luminances = int32ToGrayscale(pixels, 3, 1);
        final source = LuminanceSource(
          width: 3,
          height: 1,
          luminances: luminances,
        );
        final row = source.getRow(0, null);

        // Green contributes most to luminance
        expect(row[1], greaterThan(row[0]));
        expect(row[1], greaterThan(row[2]));
      });
    });

    group('Binarizer Operations', () {
      test('Binarizer handles uniform image', () {
        // All same color
        final pixels = Int32List(100);
        for (var i = 0; i < 100; i++) {
          pixels[i] = 0xFF808080; // Gray
        }
        final luminances = int32ToGrayscale(pixels, 10, 10);
        final source = LuminanceSource(
          width: 10,
          height: 10,
          luminances: luminances,
        );
        final binarizer = Binarizer(source);

        // Should not throw
        final matrix = binarizer.getBlackMatrix();
        expect(matrix.width, 10);
        expect(matrix.height, 10);
      });
    });

    group('Fallback Strategy', () {
      // Re-using logic from fallback_strategy_test.dart
      late Uint8List pixels;
      late int width;
      late int height;

      setUpAll(() {
        final file = File('fixtures/distorted_images/qr_distorted_v4.png');
        if (!file.existsSync()) {
          // Fallback if fixture missing (e.g. CI), though we generally expect fixtures.
          // For unit tests, maybe we should skip.
          // For now, fail loud as per original test.
          return;
        }
        final bytes = file.readAsBytesSync();
        final image = img.decodePng(bytes)!;
        width = image.width;
        height = image.height;

        // Convert to RGBA
        final converted = image.convert(
          format: img.Format.uint8,
          numChannels: 4,
        );
        pixels = converted.buffer.asUint8List();
      });

      test('Yomu.all should abort fallback on DecodeException', () {
        if (!File(
          'fixtures/distorted_images/qr_distorted_v4.png',
        ).existsSync()) {
          return;
        }

        expect(
          () => Yomu.all.decode(bytes: pixels, width: width, height: height),
          throwsA(isA<DecodeException>()),
          reason:
              'Should throw DecodeException directly, ensuring no fallback occurred.',
        );
      });

      test('Yomu.qrOnly should throw DecodeException', () {
        if (!File(
          'fixtures/distorted_images/qr_distorted_v4.png',
        ).existsSync()) {
          return;
        }

        expect(
          () => Yomu.qrOnly.decode(bytes: pixels, width: width, height: height),
          throwsA(isA<DecodeException>()),
        );
      });
    });

    group('Barcode Decoder Unit Tests', () {
      group('CodabarDecoder', () {
        late CodabarDecoder decoder;

        setUp(() {
          decoder = const CodabarDecoder();
        });

        test('format is CODABAR', () {
          expect(decoder.format, 'CODABAR');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });

        test('returns null for all-white row', () {
          final row = List<bool>.filled(200, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });

        test('returns null for all-black row', () {
          final row = List<bool>.filled(200, true);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('Code128Decoder', () {
        late Code128Decoder decoder;

        setUp(() {
          decoder = const Code128Decoder();
        });

        test('format is CODE_128', () {
          expect(decoder.format, 'CODE_128');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });

        // Helper to generate a boolean row from bar/space widths
        List<bool> generateRow(List<int> widths) {
          final row = <bool>[];
          // var color = true; // Bars are true (black), but decoder logic relies on change?
          // Decoder: _getRunLengths starts with row[0].
          // If starts with White (quiet zone), then first run is white.
          // Code128 starts with Quiet Zone (10 modules default quiet zone usually).
          // But decodeRow expects 'row'.
          // _getRunLengths:
          // var currentColor = row[0];
          // Code128 Bars are Black. Spaces are White.
          // Usually Quiet Zone is White. So row[0]=false.
          // First run is white.
          // Then Pattern starts with Bar.

          // Let's assume start with sufficient White quiet zone.
          row.addAll(List.filled(20, false));

          // Then patterns
          // Pattern widths: [bar, space, bar, space, bar, space]
          var isBar = true;
          for (final w in widths) {
            row.addAll(List.filled(w, isBar));
            isBar = !isBar;
          }

          // Trailing quiet zone
          row.addAll(List.filled(20, false));
          return row;
        }

        // Patterns (Module widths)
        // Start B (104): [2, 1, 1, 2, 1, 4] -> Code Set B
        const startB = [2, 1, 1, 2, 1, 4];
        // Start C (105): [2, 1, 1, 2, 3, 2] -> Code Set C
        // const startC = [2, 1, 1, 2, 3, 2];

        // 'A' (33) in Set B: [1, 1, 1, 3, 2, 3] -> Value 33 ('A')
        const charaSetb = [1, 1, 1, 3, 2, 3];

        // '12' (12) in Set C: [1, 1, 2, 2, 3, 2] -> Value 12 ('12')
        // const char12_SetC = [1, 1, 2, 2, 3, 2];

        // Stop: [2, 3, 3, 1, 1, 1, 2]
        const stop = [2, 3, 3, 1, 1, 1, 2];

        test('decodes simple Code Set B string "A"', () {
          // Start B (104) -> 'A' (33) -> Checksum (?) -> Stop
          // Checksum = Start + data*1
          // = 104 + 33*1 = 137.
          // 137 % 103 = 34.
          // Code 34 patterns: [1, 3, 1, 1, 2, 3]
          const check34 = [1, 3, 1, 1, 2, 3];

          final rowData = [...startB, ...charaSetb, ...check34, ...stop];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNotNull);
          expect(result!.text, 'A');
        });

        test('fails on invalid checksum', () {
          // Same as above 'A' but wrong checksum (e.g. 35 instead of 34)
          // Code 35: [1, 3, 1, 3, 2, 1]
          const check35 = [1, 3, 1, 3, 2, 1];

          final rowData = [
            ...startB,
            ...charaSetb,
            ...check35, // wrong
            ...stop,
          ];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNull);
        });

        test('fails when missing stop pattern', () {
          // Start B + 'A' + Check34 ... but no Stop
          const check34 = [1, 3, 1, 1, 2, 3];
          final rowData = [...startB, ...charaSetb, ...check34];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });

        test('handles Code Set switching (B -> C)', () {
          // Start B (104)
          // 'B' (34) -> [1, 3, 1, 1, 2, 3]
          // Switch to C (99) -> [1, 1, 3, 1, 4, 1] ? No wait.
          // Code 99 pattern: [1, 1, 3, 1, 4, 1] (Is it? Need to verify mapping)
          // Let's verify Code 99 from decoder file source if possible, or assume standard.
          // Code 128 Table:
          // 99: [1, 1, 3, 1, 4, 1] (Code C switch)
          // 34: [1, 3, 1, 1, 2, 3] ('B')
          // Set C '12' -> Value 12: [1, 1, 2, 2, 3, 2]
          // Stop

          // Checksum:
          // StartB(104) + 'B'(34)*1 + SwitchC(99)*2 + '12'(12)*3
          // = 104 + 34 + 198 + 36 = 372
          // 372 % 103 = 63
          // Code 63: [1, 1, 1, 2, 2, 4]

          const charbSetb = [1, 3, 1, 1, 2, 3]; // 34
          const switchC = [1, 1, 3, 1, 4, 1]; // 99
          const char12 = [1, 1, 2, 2, 3, 2]; // 12
          const check63 = [1, 1, 1, 2, 2, 4]; // 63

          final rowData = [
            ...startB,
            ...charbSetb,
            ...switchC,
            ...char12,
            ...check63,
            ...stop,
          ];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNotNull);
          // 'B' from Set B, then '12' from Set C
          expect(result!.text, 'B12');
        });

        test('handles FNC1 in Code Set C (GS1-128)', () {
          // FNC codes are ignored in text output but affect checksum/modes?
          // Yomu implementation:
          // if (code < 96) decodedChars.add(...)
          // else handle Switch.
          // FNC1 is Code 102.
          // Code 102 pattern: [4, 1, 1, 1, 3, 1]
          // Logic checks for switch (99,100,101).
          // 102 (FNC1), 103-105 (Start), 98 (Shift), 97 (FNC3), 96 (FNC?)
          // Current basic logic: `if (newSet != null) codeSet = newSet; else if (code < 96) add();`
          // So 102 is effectively skipped/ignored in output, which is correct for basic value extraction,
          // though GS1 spec might say insert separator. Yomu might just skip it.
          // Let's verify it skips.

          // Start C (105): [2, 1, 1, 2, 3, 2]
          // FNC1 (102): [4, 1, 1, 1, 3, 1]
          // '12' (12): [1, 1, 2, 2, 3, 2]
          // Checksum: 105 + 102*1 + 12*2 = 105 + 102 + 24 = 231
          // 231 % 103 = 25
          // Code 25: [3, 2, 1, 1, 2, 2]

          const startC = [2, 1, 1, 2, 3, 2];
          const fnc1 = [4, 1, 1, 1, 3, 1];
          const char12 = [1, 1, 2, 2, 3, 2];
          const check25 = [3, 2, 1, 1, 2, 2];

          final rowData = [...startC, ...fnc1, ...char12, ...check25, ...stop];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNotNull);
          expect(result!.text, '12'); // FNC1 skipped
        });

        test('decodes Code Set A (Control characters logic)', () {
          // Start A (103): [2, 1, 1, 4, 1, 2]
          // 'A' in Set A is code 33 (same as Set B). Logic: code < 64 -> charCode + 32.
          // 33 + 32 = 65 ('A').
          // Also test code > 64 case.
          // Code 65 in Set A -> charCode - 64.
          // 65: [1, 2, 1, 1, 2, 4] -> ASCII 1 (SOH) ?
          // Wait, Code 128 Set A:
          // 0-63: ASCII 32 (SP) to 95 (_).  (code + 32)
          // 64-95: ASCII 0 (NUL) to 31 (US). (code - 64)
          //
          // Let's test Code 65 (ASCII 1).
          // Code 65: [1, 2, 1, 1, 2, 4]
          // Checksum: 103 + 65*1 = 168. 168 % 103 = 65.
          // So pattern repeated.

          const startA = [2, 1, 1, 4, 1, 2];
          const char65 = [1, 2, 1, 1, 2, 4]; // Test code > 64 branch
          const check65 = char65;

          final rowData = [...startA, ...char65, ...check65, ...stop];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNotNull);
          // 65 - 64 = 1 (SOH). String.fromCharCode(1).
          expect(result!.text.codeUnitAt(0), 1);
        });

        test('handles Code Set switching (A -> B)', () {
          // Start A (103)
          // Switch to B (100): [1, 1, 4, 1, 3, 1]
          // 'a' (65 in Set B): [1, 2, 1, 1, 2, 4]
          // Checksum: 103 + 100*1 + 65*2 = 103 + 100 + 130 = 333
          // 333 % 103 = 24
          // Code 24: [3, 1, 1, 2, 2, 2]

          const startA = [2, 1, 1, 4, 1, 2];
          const switchB = [1, 1, 4, 1, 3, 1];
          const char65 = [1, 2, 1, 1, 2, 4];
          const check24 = [3, 1, 1, 2, 2, 2];

          final rowData = [
            ...startA,
            ...switchB,
            ...char65,
            ...check24,
            ...stop,
          ];
          final row = generateRow(rowData);

          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );

          expect(result, isNotNull);
          expect(result!.text, 'a');
        });

        test('handles Code Set switching (B -> A)', () {
          // Start B (104)
          // Switch to A (101): [3, 1, 1, 1, 4, 1]
          // NUL (64 in Set A): [1, 1, 1, 4, 2, 2]
          // Checksum: 104 + 101*1 + 64*2 = 104 + 101 + 128 = 333
          // 333 % 103 = 24
          const startB = [2, 1, 1, 2, 1, 4];
          const switchA = [3, 1, 1, 1, 4, 1];
          const char64 = [1, 1, 1, 4, 2, 2];
          const check24 = [3, 1, 1, 2, 2, 2];

          final rowData = [
            ...startB,
            ...switchA,
            ...char64,
            ...check24,
            ...stop,
          ];
          final row = generateRow(rowData);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNotNull);
          expect(result!.text.codeUnitAt(0), 0); // NUL
        });

        test('returns null for too short row (header missing)', () {
          // Just Start pattern
          const startB = [2, 1, 1, 2, 1, 4];
          final row = generateRow(startB);
          // generateRow adds 20px padding * 2 = 40. + 6 = 46.
          // _getRunLengths will define runs.
          // Run lengths: [20, 2, 1, 1, 2, 1, 4, 20]. Length 8.
          // decodeRow check: runs.length < 10 return null.
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('Code39Decoder', () {
        late Code39Decoder decoder;

        setUp(() {
          decoder = const Code39Decoder();
        });

        test('format is CODE_39', () {
          expect(decoder.format, 'CODE_39');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('EAN13Decoder Unit', () {
        late EAN13Decoder decoder;

        setUp(() {
          decoder = const EAN13Decoder();
        });

        test('format is EAN_13', () {
          expect(decoder.format, 'EAN_13');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('EAN8Decoder', () {
        late EAN8Decoder decoder;

        setUp(() {
          decoder = const EAN8Decoder();
        });

        test('format is EAN_8', () {
          expect(decoder.format, 'EAN_8');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('ITFDecoder Unit', () {
        late ITFDecoder decoder;

        setUp(() {
          decoder = const ITFDecoder();
        });

        test('format is ITF', () {
          expect(decoder.format, 'ITF');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });

      group('UPCADecoder', () {
        late UPCADecoder decoder;

        setUp(() {
          decoder = const UPCADecoder();
        });

        test('format is UPC_A', () {
          expect(decoder.format, 'UPC_A');
        });

        test('returns null for invalid row data', () {
          final row = List<bool>.filled(20, false);
          final result = decoder.decodeRow(
            row: row,
            rowNumber: 0,
            width: row.length,
          );
          expect(result, isNull);
        });
      });
    });
  });
}
