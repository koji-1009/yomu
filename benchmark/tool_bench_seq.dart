import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:yomu/src/common/binarizer/binarizer.dart';
import 'package:yomu/src/common/binarizer/luminance_source.dart';
import 'package:yomu/src/common/image_processor.dart';
import 'package:yomu/src/qr/detector/finder_pattern_finder.dart';
import 'package:yomu/yomu.dart';

/// Sequential (single-isolate) benchmark harness.
///
/// Unlike `bench_compare.dart` (which runs images in parallel isolates and is
/// therefore sensitive to scheduler noise), this tool runs every image on the
/// main isolate and reports the **minimum** and **median** of N iterations.
/// The minimum is the most stable statistic for A/B comparing optimizations.
///
/// Usage:
///   dart compile exe benchmark/tool_bench_seq.dart -o bench && ./bench
///   ./bench --iters=50 --stages
///
/// Options:
///   --iters=N   Iterations per image (default 30).
///   --warmup=N  Warmup iterations per image (default 10).
///   --stages    Also report a per-stage breakdown (convert/binarize/find).
void main(List<String> args) {
  final iters = _intArg(args, '--iters=', 30);
  final warmup = _intArg(args, '--warmup=', 10);
  final withStages = args.contains('--stages');

  const qrDirs = [
    'fixtures/qr_images',
    'fixtures/qr_complex_images',
    'fixtures/distorted_images',
    'fixtures/uneven_lighting',
    'fixtures/performance_test_images',
    'fixtures/unsupported_images',
  ];
  const barcodeDir = 'fixtures/barcode_images';

  print('================================================');
  print('📊 YOMU SEQUENTIAL BENCHMARK (iters=$iters, warmup=$warmup)');
  print('================================================\n');

  var grandMin = 0.0;
  var grandMedian = 0.0;
  var grandImages = 0;

  final rows = <(String, double, double, int)>[];

  for (final dir in [...qrDirs, barcodeDir]) {
    final isBarcodeDir = dir == barcodeDir;
    final decoder = isBarcodeDir ? Yomu.barcodeOnly : Yomu.qrOnly;
    final images = _load(dir);
    if (images.isEmpty) {
      continue;
    }

    var sumMin = 0.0;
    var sumMedian = 0.0;
    final details = <(String, double)>[];

    for (final (name, image) in images) {
      final (best, median) = _time(
        iterations: iters,
        warmup: warmup,
        body: () {
          try {
            decoder.decode(image);
          } catch (_) {}
        },
      );
      sumMin += best;
      sumMedian += median;
      details.add((name, best));
    }

    rows.add((dir, sumMin, sumMedian, images.length));
    grandMin += sumMin;
    grandMedian += sumMedian;
    grandImages += images.length;

    details.sort((a, b) => b.$2.compareTo(a.$2));
    print('--- $dir (${images.length} images) ---');
    print(
      '  total(min) ${sumMin.toStringAsFixed(2)}ms  '
      'avg(min) ${(sumMin / images.length).toStringAsFixed(3)}ms  '
      'avg(median) ${(sumMedian / images.length).toStringAsFixed(3)}ms',
    );
    for (final (name, ms) in details.take(5)) {
      print('  SLOW: ${name.padRight(42)} ${ms.toStringAsFixed(3)}ms');
    }
    print('');
  }

  print('================================================');
  print('SUMMARY (lower is better)');
  print('================================================');
  for (final (dir, sumMin, sumMedian, count) in rows) {
    print(
      'BENCH:${dir.padRight(38)} | '
      'min ${sumMin.toStringAsFixed(2).padLeft(9)}ms | '
      'med ${sumMedian.toStringAsFixed(2).padLeft(9)}ms | '
      'avg ${(sumMin / count).toStringAsFixed(3).padLeft(7)}ms',
    );
  }
  print(
    'BENCH:${'TOTAL'.padRight(38)} | '
    'min ${grandMin.toStringAsFixed(2).padLeft(9)}ms | '
    'med ${grandMedian.toStringAsFixed(2).padLeft(9)}ms | '
    'avg ${(grandMin / grandImages).toStringAsFixed(3).padLeft(7)}ms',
  );

  if (withStages) {
    _reportStages(iters: iters, warmup: warmup);
  }
}

/// Per-stage breakdown on a representative subset, using the same
/// min-of-N statistic as the end-to-end numbers.
void _reportStages({required int iters, required int warmup}) {
  const samples = [
    'fixtures/performance_test_images/4k_gradient_center_300px.png',
    'fixtures/performance_test_images/fullhd_noise_center_200px.png',
    'fixtures/qr_complex_images/qr_version_7.png',
    'fixtures/qr_images/byte_url.png',
  ];

  print('\n================================================');
  print('STAGE BREAKDOWN (min of $iters)');
  print('================================================');
  print(
    '${'Image'.padRight(34)} | ${'process'.padLeft(8)} | '
    '${'binarize'.padLeft(8)} | ${'find'.padLeft(8)} | ${'total'.padLeft(8)}',
  );

  for (final path in samples) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final image = _toYomuImage(file);

    final (process, _) = _time(
      iterations: iters,
      warmup: warmup,
      body: () => ImageProcessor.process(image),
    );

    final (pixels, w, h) = ImageProcessor.process(image);
    final source = LuminanceSource(width: w, height: h, luminances: pixels);
    final (binarize, _) = _time(
      iterations: iters,
      warmup: warmup,
      body: () => Binarizer(source).getBlackMatrix(),
    );

    final matrix = Binarizer(source).getBlackMatrix();
    final (find, _) = _time(
      iterations: iters,
      warmup: warmup,
      body: () {
        try {
          FinderPatternFinder(matrix).find();
        } catch (_) {}
      },
    );

    final (total, _) = _time(
      iterations: iters,
      warmup: warmup,
      body: () {
        try {
          Yomu.qrOnly.decode(image);
        } catch (_) {}
      },
    );

    print(
      '${path.split('/').last.padRight(34)} | '
      '${process.toStringAsFixed(3).padLeft(8)} | '
      '${binarize.toStringAsFixed(3).padLeft(8)} | '
      '${find.toStringAsFixed(3).padLeft(8)} | '
      '${total.toStringAsFixed(3).padLeft(8)}',
    );
  }
}

/// Runs [body] and returns (min, median) elapsed milliseconds.
(double, double) _time({
  required int iterations,
  required int warmup,
  required void Function() body,
}) {
  for (var i = 0; i < warmup; i++) {
    body();
  }

  final times = List<double>.filled(iterations, 0);
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    times[i] = sw.elapsedMicroseconds / 1000.0;
  }
  times.sort();
  return (times.first, times[iterations >> 1]);
}

List<(String, YomuImage)> _load(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    return [];
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return [
    for (final file in files) (file.path.split('/').last, _toYomuImage(file)),
  ];
}

YomuImage _toYomuImage(File file) {
  final decoded = img.decodePng(file.readAsBytesSync())!;
  final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
  return YomuImage.rgba(
    bytes: rgba.buffer.asUint8List(),
    width: decoded.width,
    height: decoded.height,
  );
}

int _intArg(List<String> args, String prefix, int fallback) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return int.tryParse(arg.substring(prefix.length)) ?? fallback;
    }
  }
  return fallback;
}
