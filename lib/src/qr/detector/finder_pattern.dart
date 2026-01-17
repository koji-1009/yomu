class FinderPattern {
  const FinderPattern({
    required this.x,
    required this.y,
    required this.estimatedModuleSize,
    this.count = 1,
  });

  final double x;
  final double y;
  final double estimatedModuleSize;
  final int count;

  /// Combines this pattern with a new one (averaging).
  FinderPattern combineEstimate(double i, double j, double newModuleSize) {
    final combinedCount = count + 1;
    final combinedX = (count * x + j) / combinedCount;
    final combinedY = (count * y + i) / combinedCount;
    final combinedModuleSize =
        (count * estimatedModuleSize + newModuleSize) / combinedCount;
    return FinderPattern(
      x: combinedX,
      y: combinedY,
      estimatedModuleSize: combinedModuleSize,
      count: combinedCount,
    );
  }

  @override
  String toString() => '($x, $y) ~ $estimatedModuleSize';
}

class FinderPatternInfo {
  const FinderPatternInfo({
    required this.bottomLeft,
    required this.topLeft,
    required this.topRight,
  });

  final FinderPattern bottomLeft;
  final FinderPattern topLeft;
  final FinderPattern topRight;
}
