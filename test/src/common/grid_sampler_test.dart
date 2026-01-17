import 'package:test/test.dart';
import 'package:yomu/src/common/bit_matrix.dart';
import 'package:yomu/src/common/grid_sampler.dart';
import 'package:yomu/src/common/perspective_transform.dart';

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
              image.set(x: x, y: y);
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
            image.set(x: x, y: y);
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
            if (result.get(x: x, y: y)) setCount++;
          }
        }
        expect(setCount, greaterThan(80));
      });

      test('handles out-of-bounds sampling gracefully', () {
        // Small image
        final image = BitMatrix(width: 5, height: 5);
        image.set(x: 2, y: 2);

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
            image.set(x: x, y: y);
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
            if (result.get(x: x, y: y)) setCount++;
          }
        }
        expect(setCount, greaterThan(15)); // Most should be set
      });
    });
  });
}
