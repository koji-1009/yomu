import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:yomu/yomu.dart';

/// Detection rate measurement tool.
///
/// Runs `Yomu.qrOnly` (QR fixtures) / `Yomu.barcodeOnly` (barcode fixtures)
/// against every fixture image and reports the per-directory detection rate.
/// Use this to track detection capability (検出力) regressions/improvements.
///
/// Usage:
///   dart run benchmark/tool_detection_rate.dart [--verbose] [--fast-only]
///
/// `--fast-only` disables the try-harder retries (tryHarder: false),
/// which measures the fast-path-only baseline on the same corpus.
void main(List<String> args) {
  final verbose = args.contains('--verbose');
  final fastOnly = args.contains('--fast-only');
  final qrDecoder = fastOnly
      ? const Yomu(
          enableQRCode: true,
          barcodeScanner: BarcodeScanner.none,
          tryHarder: false,
        )
      : Yomu.qrOnly;
  final barcodeDecoder = fastOnly
      ? const Yomu(
          enableQRCode: false,
          barcodeScanner: BarcodeScanner.all,
          tryHarder: false,
        )
      : Yomu.barcodeOnly;

  final qrDirs = [
    'fixtures/qr_images',
    'fixtures/qr_complex_images',
    'fixtures/distorted_images',
    'fixtures/uneven_lighting',
    'fixtures/performance_test_images',
    'fixtures/unsupported_images',
  ];
  const barcodeDir = 'fixtures/barcode_images';

  var totalImages = 0;
  var totalSuccess = 0;

  print('================================================');
  print('🎯 YOMU DETECTION RATE');
  print('================================================\n');

  for (final dirPath in qrDirs) {
    final (success, total) = _measureDirectory(
      dirPath: dirPath,
      decoder: qrDecoder,
      verbose: verbose,
    );
    totalSuccess += success;
    totalImages += total;
  }

  final (success, total) = _measureDirectory(
    dirPath: barcodeDir,
    decoder: barcodeDecoder,
    verbose: verbose,
  );
  totalSuccess += success;
  totalImages += total;

  final totalRate = (totalSuccess / totalImages * 100).toStringAsFixed(1);
  print('\nTOTAL: $totalSuccess/$totalImages ($totalRate%)');
}

/// Decodes every fixture in [dirPath] with [decoder], prints the directory's
/// rate line (and failures when [verbose]), and returns (success, total).
(int, int) _measureDirectory({
  required String dirPath,
  required Yomu decoder,
  required bool verbose,
}) {
  final files = _getFiles(dirPath);
  if (files.isEmpty) {
    return (0, 0);
  }

  var success = 0;
  final failures = <String>[];
  for (final file in files) {
    try {
      decoder.decode(_loadImage(file));
      success++;
    } catch (_) {
      failures.add(file.uri.pathSegments.last);
    }
  }

  final rate = (success / files.length * 100).toStringAsFixed(1);
  print('RATE:${dirPath.padRight(40)} | $success/${files.length} ($rate%)');
  if (verbose && failures.isNotEmpty) {
    for (final f in failures) {
      print('  FAIL: $f');
    }
  }
  return (success, files.length);
}

List<File> _getFiles(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .where((f) => !f.path.contains('multi_qr'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

YomuImage _loadImage(File file) {
  final bytes = file.readAsBytesSync();
  final image = img.decodePng(bytes)!;
  final converted = image.convert(format: img.Format.uint8, numChannels: 4);
  return YomuImage.rgba(
    bytes: converted.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
}
