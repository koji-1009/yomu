import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/grid_sampler.dart';
import 'package:yomu/src/common/perspective_transform.dart';

/// Samples exactly like [GridSampler.sampleGrid], but by staging a row of
/// points through [PerspectiveTransform.transformPoints].
///
/// This is the shape [GridSampler] had before the transform was applied
/// inline; the equivalence test below pins the two together.
BitMatrix sampleViaTransformPoints(
  BitMatrix image,
  int dimensionX,
  int dimensionY,
  PerspectiveTransform transform,
) {
  final result = BitMatrix(width: dimensionX, height: dimensionY);
  final points = Float64List(2 * dimensionX);

  for (var y = 0; y < dimensionY; y++) {
    final max = points.length;
    final iValue = y + 0.5;
    for (var x = 0; x < max; x += 2) {
      points[x] = (x >> 1) + 0.5;
      points[x + 1] = iValue;
    }

    transform.transformPoints(points);

    for (var x = 0; x < max; x += 2) {
      final px = points[x].toInt();
      final py = points[x + 1].toInt();
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        if (image.get(px, py)) {
          result.set(x >> 1, y);
        }
      }
    }
  }
  return result;
}

void main() {
  group('GridSampler', () {
    late GridSampler sampler;

    setUp(() {
      sampler = const GridSampler();
    });

    group('sampleGrid', () {
      test('throws on zero or negative dimensions', () {
        final image = BitMatrix(width: 10, height: 10);
        final transform = PerspectiveTransform.squareToQuadrilateral(
          x0: 0,
          y0: 0,
          x1: 10,
          y1: 0,
          x2: 10,
          y2: 10,
          x3: 0,
          y3: 10,
        );

        expect(
          () => sampler.sampleGrid(image, 0, 5, transform),
          throwsArgumentError,
        );
        expect(
          () => sampler.sampleGrid(image, 5, 0, transform),
          throwsArgumentError,
        );
        expect(
          () => sampler.sampleGrid(image, -1, 5, transform),
          throwsArgumentError,
        );
      });

      test('identity transform samples correctly', () {
        // Create a 10x10 image with checkerboard pattern
        final image = BitMatrix(width: 10, height: 10);
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            if ((x + y) % 2 == 0) {
              image.set(x, y);
            }
          }
        }

        // Identity-like transform (maps 0-5 to 0-10)
        final transform = PerspectiveTransform.squareToQuadrilateral(
          x0: 0,
          y0: 0,
          x1: 10,
          y1: 0,
          x2: 10,
          y2: 10,
          x3: 0,
          y3: 10,
        );

        final result = sampler.sampleGrid(image, 5, 5, transform);

        expect(result.width, 5);
        expect(result.height, 5);
      });

      test('samples from scaled source correctly', () {
        // 20x20 source image, all black
        final image = BitMatrix(width: 20, height: 20);
        for (var y = 0; y < 20; y++) {
          for (var x = 0; x < 20; x++) {
            image.set(x, y);
          }
        }

        // Map sample grid (0-10) to source (0-20)
        final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
          x0: 0,
          y0: 0,
          x1: 10,
          y1: 0,
          x2: 10,
          y2: 10,
          x3: 0,
          y3: 10,
          x0p: 0,
          y0p: 0,
          x1p: 20,
          y1p: 0,
          x2p: 20,
          y2p: 20,
          x3p: 0,
          y3p: 20,
        );

        final result = sampler.sampleGrid(image, 10, 10, transform);

        // Most sampled bits should be set (center sampling may miss edges)
        var setCount = 0;
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            if (result.get(x, y)) setCount++;
          }
        }
        expect(setCount, greaterThan(80));
      });

      test('handles out-of-bounds sampling gracefully', () {
        // Small image
        final image = BitMatrix(width: 5, height: 5);
        image.set(2, 2);

        // Transform that maps beyond image bounds
        final transform = PerspectiveTransform.squareToQuadrilateral(
          x0: -5,
          y0: -5,
          x1: 15,
          y1: -5,
          x2: 15,
          y2: 15,
          x3: -5,
          y3: 15,
        );

        // Should not throw, just return partial results
        final result = sampler.sampleGrid(image, 5, 5, transform);
        expect(result.width, 5);
        expect(result.height, 5);
      });

      test('samples specific region correctly', () {
        // 20x20 image with a 5x5 black square at (5,5)
        final image = BitMatrix(width: 20, height: 20);
        for (var y = 5; y < 10; y++) {
          for (var x = 5; x < 10; x++) {
            image.set(x, y);
          }
        }

        // Transform that samples just the black square region
        final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
          x0: 0,
          y0: 0,
          x1: 5,
          y1: 0,
          x2: 5,
          y2: 5,
          x3: 0,
          y3: 5,
          x0p: 5,
          y0p: 5,
          x1p: 10,
          y1p: 5,
          x2p: 10,
          y2p: 10,
          x3p: 5,
          y3p: 10,
        );

        final result = sampler.sampleGrid(image, 5, 5, transform);

        // Most of the sampled area should be set
        var setCount = 0;
        for (var y = 0; y < 5; y++) {
          for (var x = 0; x < 5; x++) {
            if (result.get(x, y)) setCount++;
          }
        }
        expect(setCount, greaterThan(15)); // Most should be set
      });

      test('leaves a point at infinity untransformed', () {
        // a31 * x + a32 * y + a33 == 0 at x == 0.5, i.e. the first column of
        // every row, so the degenerate branch is taken there. Such a point
        // keeps its grid coordinates, which land on (0, y) of the source.
        final image = BitMatrix(width: 8, height: 8);
        for (var y = 0; y < 8; y++) {
          image.set(0, y);
        }

        const transform = PerspectiveTransform(
          a11: 1.0,
          a12: 0.0,
          a13: 0.0,
          a21: 0.0,
          a22: 1.0,
          a23: 0.0,
          a31: 1.0,
          a32: 0.0,
          a33: -0.5,
        );

        final result = const GridSampler().sampleGrid(image, 4, 4, transform);

        for (var y = 0; y < 4; y++) {
          expect(
            result.get(0, y),
            isTrue,
            reason: 'column 0 of row $y samples the untransformed point',
          );
        }
      });

      test('matches sampling through transformPoints', () {
        final random = Random(20240607);
        final image = BitMatrix(width: 200, height: 160);
        for (var y = 0; y < 160; y++) {
          for (var x = 0; x < 200; x++) {
            if (random.nextBool()) {
              image.set(x, y);
            }
          }
        }

        const sampler = GridSampler();
        const dimension = 33;

        for (var trial = 0; trial < 200; trial++) {
          // A spread of quadrilaterals: mostly well behaved, some skewed
          // enough to exercise the perspective (non-affine) path.
          final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
            x0: 0,
            y0: 0,
            x1: dimension.toDouble(),
            y1: 0,
            x2: dimension.toDouble(),
            y2: dimension.toDouble(),
            x3: 0,
            y3: dimension.toDouble(),
            x0p: random.nextDouble() * 40,
            y0p: random.nextDouble() * 40,
            x1p: 120 + random.nextDouble() * 60,
            y1p: random.nextDouble() * 40,
            x2p: 120 + random.nextDouble() * 60,
            y2p: 110 + random.nextDouble() * 40,
            x3p: random.nextDouble() * 40,
            y3p: 110 + random.nextDouble() * 40,
          );

          final fused = sampler.sampleGrid(
            image,
            dimension,
            dimension,
            transform,
          );
          final staged = sampleViaTransformPoints(
            image,
            dimension,
            dimension,
            transform,
          );

          expect(
            fused.bits,
            orderedEquals(staged.bits),
            reason: 'trial $trial produced different samples',
          );
        }
      });

      test(
        'matches sampling through transformPoints for affine transforms',
        () {
          final random = Random(981);
          final image = BitMatrix(width: 120, height: 120);
          for (var y = 0; y < 120; y++) {
            for (var x = 0; x < 120; x++) {
              if ((x * 7 + y * 3) % 5 == 0) {
                image.set(x, y);
              }
            }
          }

          const sampler = GridSampler();
          const dimension = 21;

          for (var trial = 0; trial < 50; trial++) {
            // A parallelogram maps square -> quad with a31 == a32 == 0, but
            // only if the corners cancel exactly: quarters are exact in
            // binary floating point, arbitrary doubles are not.
            final ox = random.nextInt(80) / 4;
            final oy = random.nextInt(80) / 4;
            final ux = 3 + random.nextInt(8) / 4;
            final uy = (random.nextInt(4) - 2) / 4;
            final vx = (random.nextInt(4) - 2) / 4;
            final vy = 3 + random.nextInt(8) / 4;

            // The unit square maps to one grid step, so (ux, uy) and (vx, vy)
            // are the per-module step vectors of the sampled grid.
            final transform = PerspectiveTransform.squareToQuadrilateral(
              x0: ox,
              y0: oy,
              x1: ox + ux,
              y1: oy + uy,
              x2: ox + ux + vx,
              y2: oy + uy + vy,
              x3: ox + vx,
              y3: oy + vy,
            );
            expect(transform.a31, 0.0);

            final fused = sampler.sampleGrid(
              image,
              dimension,
              dimension,
              transform,
            );
            final staged = sampleViaTransformPoints(
              image,
              dimension,
              dimension,
              transform,
            );

            expect(
              fused.bits,
              orderedEquals(staged.bits),
              reason: 'trial $trial produced different samples',
            );
          }
        },
      );
    });
  });
}
