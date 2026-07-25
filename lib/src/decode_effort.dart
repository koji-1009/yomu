/// How much work [Yomu.decode] may spend on an image the fast path cannot
/// decode.
///
/// The levels are not an arbitrary scale. Every retry stage falls into one of
/// two classes, and the boundary between them is where the cost cliff is:
///
/// * stages that **reuse** the binarized image already in hand (corner grid
///   search, despeckle, tolerant finder) - bounded, incremental work;
/// * stages that **rebuild** the image from the source pixels (full-resolution
///   conversion, alternate binarization thresholds) - each one re-runs the
///   front of the pipeline, which is the expensive part.
///
/// Successful scans are unaffected by this setting: every stage past the first
/// only runs on an image the previous stage failed on. What it buys is
/// detection on hard inputs; what it costs is latency on inputs holding no
/// code at all, which is exactly the case a camera preview hits every frame.
///
/// Measured on the fixture corpus (201 images) and on a Full HD frame holding
/// no code, AOT on an M-class laptop:
///
/// | level      | detection      | blank frame | textured frame |
/// | ---------- | -------------- | ----------- | -------------- |
/// | [fast]     | 167/201, 83.1% | 1.41ms      | 2.58ms         |
/// | [balanced] | 188/201, 93.5% | 1.36ms      | 17.98ms        |
/// | [thorough] | 192/201, 95.5% | 7.89ms      | 51.30ms        |
///
/// [balanced] is where the trade sits best for a stream: it recovers 21 of
/// the 25 codes [thorough] adds over [fast], for a third of the cost on a
/// textured frame and a sixth on a blank one.
///
/// The jump to [thorough] is the cost of rebuilding the image: the
/// full-resolution pass binarizes four times as many pixels, and the
/// threshold sweep binarizes three more times.
///
/// `benchmark/tool_detection_rate.dart --matrix` reproduces the detection
/// column, and CI posts it on every pull request so this table cannot drift
/// away from the code.
///
/// A textured frame costs more than a blank one at every level because noise
/// produces false finder patterns: each stage has candidates to rule out
/// rather than nothing to look at.
enum DecodeEffort {
  /// One binarization, one detection attempt, no retries.
  ///
  /// The right choice for per-frame camera scanning, where a code missed on
  /// one frame is caught on the next and a slow frame is worse than a missed
  /// one.
  fast,

  /// [fast] plus every retry that reuses the binarized image: dimension and
  /// corner-grid candidates, a despeckle pass, and the tolerant finder.
  ///
  /// Recovers noisy, dirty and perspective-distorted codes. Bounded by a
  /// deterministic work budget, and it never rebuilds the image, so the
  /// failure path stays within a few times the fast path.
  balanced,

  /// [balanced] plus the stages that rebuild the image: a full-resolution
  /// retry for codes too small to survive downsampling, and a sweep of
  /// alternate binarization thresholds for codes whose contrast sits away
  /// from the default.
  ///
  /// The default, and the right choice for still images, where a slower
  /// failure is better than a missed code.
  thorough,
}
