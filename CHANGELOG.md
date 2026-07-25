# CHANGELOG

## 1.2.0

The retry ladder becomes a three-level `DecodeEffort` axis instead of a boolean, the binarizer gets roughly twice as fast, and three previously undecodable image classes now decode.

### API

* **`DecodeEffort` replaces the `tryHarder` flag.** The ladder was a boolean: one fast point and one exhaustive point, with nothing between them and no way for a caller to see what the jump cost. It is now a three-level `effort` parameter, split where the cost actually jumps — between stages that **reuse** the binarized image and stages that **rebuild** it from the source pixels. Successful scans are unaffected at every level; the level trades detection on hard inputs against latency on inputs holding no code at all.
  | level                | retries                                  | detection      | blank Full HD frame | textured Full HD frame |
  | -------------------- | ---------------------------------------- | -------------- | ------------------- | ---------------------- |
  | `fast`               | none                                     | 167/201, 83.1% | 1.41ms              | 2.58ms                 |
  | `balanced`           | corner grid, despeckle, tolerant finder  | 188/201, 93.5% | 1.36ms              | 17.98ms                |
  | `thorough` (default) | + full-resolution retry, threshold sweep | 192/201, 95.5% | 7.89ms              | 51.30ms                |

  `balanced` recovers 21 of the 25 codes `thorough` adds over `fast`, for a third of the cost on a textured frame and a sixth on a blank one.
* **`Yomu.responsive` preset**: all formats at `DecodeEffort.balanced`, for streams that can afford more per frame than `Yomu.realtime`.
* **`tryHarder` is deprecated**, not removed. `tryHarder: false` still maps to `DecodeEffort.fast` and `true` to `DecodeEffort.thorough`, and `yomu.tryHarder` still reads back, so existing call sites keep compiling and keep their behaviour.
  ```dart
  // before                          // after
  Yomu(..., tryHarder: false)    ->  Yomu(..., effort: DecodeEffort.fast)
  Yomu(..., tryHarder: true)     ->  Yomu(..., effort: DecodeEffort.thorough)
  ```

### Performance

* **Block-averaged binarizer**: the adaptive threshold now comes from an integral image of per-block (4x4) mean luminance instead of a per-pixel integral image. The averaging window is at least 40px wide, so the threshold surface varies far more slowly than the block grid — quantizing it to blocks costs no meaningful accuracy while cutting the per-pixel work to one load and one compare, with the output word accumulated in a register and stored once per 32 pixels.
* **Branchless thresholding**: `luminance <= threshold` is now the sign bit of `luminance - (threshold + 1)` rather than an `if`. Binarizing a photograph otherwise means one data-dependent, unpredictable branch per pixel, and the misprediction dominated the compare; removing it cut the threshold pass by 3.4x on high-entropy input.
* **Whole-pixel image conversion**: RGBA/BGRA to luminance (and the fused downsample) reads one 32-bit word per pixel instead of three bounds-checked bytes, on little-endian hosts with a 4-aligned buffer. Falls back to per-byte access otherwise — unaligned camera buffers, or strides that are not a whole number of pixels.
* Binarization was ~65% of decode time and is now roughly the cost of one sequential pass over the image (1.3x a bare read loop, against 4.2x before). End-to-end on the fixture corpus (AOT, sequential min-of-25): standard QR **-30%**, high-version QR **-44%**, uneven lighting **-40%**, Full HD / 4K **-39%**, barcodes **-22%**. Per image: 4K 3.51ms -> 2.12ms, Full HD 1.99ms -> 1.24ms, version 7 2.70ms -> 1.57ms.

### Detection

* **Alternate-threshold retry sweep**: when every stage at the configured `binarizerThreshold` fails, `decode` re-binarizes at 0.6 / 1.0 / 1.1 and re-runs the ladder. Codes that fail by _shifting_ contrast rather than destroying it — screen moire, heavy low-light sensor noise, casual-scan blur — come out clean at a different factor. Three image classes that could not be decoded at all now decode: `gaussian_noise_120`, `moire_0.8` and `composite_scan_blur_5.5`.
* **`decodeAll` threshold sweep**: a sheet whose codes have differing contrast (one clean, one occluded) is re-scanned at the alternate factors when the first pass decodes fewer codes than it detected, and the best pass wins. Passes are compared rather than merged, so two codes carrying the same text on one sheet are both preserved.
* `TryHarderDecoder` (internal) accepts a `gridPointBudget`, letting the sweep run on a bounded fraction of the default budget instead of a fresh full allowance per attempt.

### Behaviour to be aware of

* **The deepest level is slower on inputs holding no code.** A heavily textured Full HD frame costs 51ms at `DecodeEffort.thorough`, against ~20ms for the old `tryHarder: true`; the extra work is the threshold sweep. This is exactly the cost `balanced` exists to let callers decline — the same frame is 18ms there and 2.6ms at `fast`. Per-frame scanning should already be on `Yomu.realtime`; `Yomu.responsive` is the new middle option.

### Test fixtures

* `gaussian_noise_120`, `moire_0.8` and `composite_scan_blur_5.5` moved from `fixtures/unsupported_images` to `fixtures/distorted_images`, and the stress generator gained the next rung on each axis so the boundary is pinned from above again (moire 0.9, composite scan blur 6.0, low-light noise σ=170).
* **Low-light noise rungs re-derived from a measured curve.** This axis is the only probabilistic one — each σ draws a single noise field — so a fixture near the transition asserts its own draw rather than the decoder's limit. Decode rate over 20 independent draws per σ: 110→100%, 120→100%, 130→75%, 140→70%, 150→50%, 160→40%, 170→5%, 180→5%. The rungs are now taken from the flat ends (σ=120 decodes, σ=170 does not) instead of the 130-160 band, where a single fixture is a coin flip.
* Net effect on the corpus: of the 198 images that existed before, three more decode (189 -> 192); the corpus is now 201 images as the ladders were extended.

### Tooling

* `benchmark/tool_bench_seq.dart`: sequential, single-isolate benchmark reporting the minimum of N iterations per image, stable to well under 1% run to run — the instrument for A/B comparing an optimization, where the isolate-parallel `bench_compare.dart` is too noisy. `--stages` adds a process / binarize / find breakdown.
* `benchmark/tool_detection_rate.dart --effort=LEVEL` and `--matrix`. CI now posts the detection matrix for the PR and for `main` alongside the latency comparison: the latency job alone cannot see a change that buys speed by giving up detection, which is precisely the trade `DecodeEffort` exposes.

## 1.1.0

### Features

* **Try-Harder Mode (default on)**: `Yomu.decode` now runs escalating retry strategies when the fast path fails, significantly improving the detection rate (fixture corpus: 84.3% -> 95.5%, 167/198 -> 189/198). Successful scans are unaffected; retries only run on images the fast path cannot decode.
  * **Corner grid search**: per-axis dimension candidates plus a grid search of the bottom-right corner rescue perspective-distorted codes.
  * **Despeckle retry**: a word-parallel 3x3 majority filter (`BitMatrix.majority3x3`) recovers codes under salt & pepper noise (validated up to 20% pixel noise).
  * **Tolerant finder**: clusters raw row-scan hits without the strict vertical cross-check, recovering slanted finder patterns under strong perspective.
  * **Full-resolution retry**: re-runs detection without downsampling when a downsampled pass fails, recovering small codes in high-resolution frames.
  * Retries are bounded by a deterministic work budget and grid-search deduplication, so undecodable inputs cannot make the failure path pathologically slow.
  * Set `tryHarder: false` for the previous fast-only behavior (latency-critical per-frame scanning).
* **`decodeAll` retry passes**: multi-code scanning applies the same strategy. Detected-but-undecodable codes get the corner-grid rescue, and a pass that finds nothing escalates to despeckle and a full-resolution pass (a noisy 3-code sheet and two 90px codes in a 4K frame go from 0 to fully decoded).
* **`Yomu.realtime` preset**: all formats with `tryHarder` disabled, tuned for per-frame camera scanning where a missed frame is cheaper than a slower failure path.
* With `tryHarder` enabled, a detected-but-undecodable QR code now falls through to barcode scanning instead of propagating a `DecodeException`.

### Test fixtures

* Fixture ladders now bracket the current capability boundary on both sides, with boundary-pinning tests on each side (see the Supported Image Classes table in the README).
* New distortion axes derived from the modern imaging pipeline: low-light Gaussian noise, JPEG quantization artifacts, specular glare, screen moire, and a composite casual-scan recipe (mild perspective + lighting gradient + blur) that demonstrates composition lowering the single-axis boundary.
* The legacy `perspective_{x,y}` fixtures above 0.2 cropped the finder patterns out of the canvas (invalid test images); they are replaced by a padded transform that keeps the code fully visible.
* `fixtures/unsupported_images` now contains only images beyond the capability boundary; everything rescued by the retry strategies moved to `fixtures/distorted_images`.

## 1.0.0

Initial stable release.

### Features

* **Pure Dart Implementation**: A zero-dependency QR code and barcode reader library. No native code required, making it highly portable across Flutter, Web, and Server-side Dart.
* **QR Code Support**:
  * Full support for QR Code versions 1 to 40.
  * Supports all error correction levels (L, M, Q, H).
  * Robust multi-QR detection and decoding in a single image.
  * High resilience against perspective distortion, rotation, and uneven lighting.
* **1D Barcode Support**:
  * Retail: EAN-13 (including JAN), EAN-8, UPC-A.
  * Industrial: Code 128, Code 39, ITF (Interleaved 2 of 5), Codabar.
* **High Performance**:
  * Specifically optimized for AOT compilation and performance.
  * Efficiently handles high-resolution images (> 1MP) using internal fused downsampling and conversion.
  * Capable of real-time decoding on mobile and desktop platforms.
* **Flexible Image API**: Platform-agnostic `YomuImage` container supporting various pixel formats including RGBA, BGRA, Grayscale, and YUV420 (camera stream Y-plane).
