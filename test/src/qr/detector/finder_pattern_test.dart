import 'package:test/test.dart';
import 'package:yomu/src/qr/detector/finder_pattern.dart';

void main() {
  group('FinderPattern', () {
    test('creates pattern with correct properties', () {
      const pattern = FinderPattern(x: 10.0, y: 20.0, estimatedModuleSize: 3.0);
      expect(pattern.x, 10.0);
      expect(pattern.y, 20.0);
      expect(pattern.estimatedModuleSize, 3.0);
      expect(pattern.count, 1);
    });

    test('creates pattern with custom count', () {
      const pattern = FinderPattern(
        x: 10.0,
        y: 20.0,
        estimatedModuleSize: 3.0,
        count: 5,
      );
      expect(pattern.count, 5);
    });

    test('combineEstimate averages values', () {
      const pattern = FinderPattern(
        x: 10.0,
        y: 20.0,
        estimatedModuleSize: 3.0,
        count: 2,
      );
      final combined = pattern.combineEstimate(22.0, 12.0, 4.0);

      // New count = 3
      // New x = (2*10 + 12) / 3 = 10.67
      // New y = (2*20 + 22) / 3 = 20.67
      // New module = (2*3 + 4) / 3 = 3.33
      expect(combined.count, 3);
      expect(combined.x, closeTo(10.67, 0.1));
      expect(combined.y, closeTo(20.67, 0.1));
      expect(combined.estimatedModuleSize, closeTo(3.33, 0.1));
    });

    test('toString returns readable format', () {
      const pattern = FinderPattern(x: 10.0, y: 20.0, estimatedModuleSize: 3.0);
      final str = pattern.toString();
      expect(str, contains('10'));
      expect(str, contains('20'));
    });
  });

  group('FinderPatternInfo', () {
    test('holds three patterns', () {
      const bl = FinderPattern(x: 0, y: 100, estimatedModuleSize: 3.0);
      const tl = FinderPattern(x: 0, y: 0, estimatedModuleSize: 3.0);
      const tr = FinderPattern(x: 100, y: 0, estimatedModuleSize: 3.0);

      const info = FinderPatternInfo(bottomLeft: bl, topLeft: tl, topRight: tr);

      expect(info.bottomLeft, bl);
      expect(info.topLeft, tl);
      expect(info.topRight, tr);
    });
  });
}
