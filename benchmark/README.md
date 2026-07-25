# Yomu Benchmark Suite

This directory contains performance benchmarks and profiling tools for the Yomu library.

## Prerequisites

Before running benchmarks, you must generate the test fixtures:

```bash
# Generate basic QR tests
uv run scripts/generate_test_qr.py

# Generate performance test set (noise, rotation, etc.)
uv run scripts/generate_performance_test_images.py
```

## Running Benchmarks

It is recommended to run benchmarks using **AOT compilation** or `dart run -O4` (release mode) to get realistic results, as JIT execution can be significantly slower and misleading for low-latency code.

### 1. Main Benchmark (`bench_compare.dart`)

Runs a comprehensive performance test across various categories (Standard, HiRes, Distorted, etc.) and compares overhead between different configurations.

```bash
dart run benchmark/bench_compare.dart
```

### 2. Sequential Benchmark (`tool_bench_seq.dart`)

`bench_compare.dart` runs images in parallel isolates, which is fast but sensitive to scheduler noise — a poor instrument for A/B comparing an optimization. This tool runs every image on the main isolate and reports the **minimum** of N iterations per image, which is stable to well under 1% run to run. Use it when you need to attribute a change to the code rather than to the machine.

```bash
dart compile exe benchmark/tool_bench_seq.dart -o /tmp/bench && /tmp/bench --stages
```

`--stages` adds a per-stage breakdown (process / binarize / find / total) on a handful of representative images, which is how you find out where the time actually goes before optimizing.

`--matrix` reports average latency per fixture directory across every `DecodeEffort` level. A single-level number cannot tell "this got slower" apart from "this now decodes, and decoding it costs a full retry ladder"; the three columns side by side can. CI posts this on each pull request.

### 3. Micro-Benchmarks

Targeted benchmarks for specific components.

* **Binarizer**: `dart run benchmark/bench_binarizer.dart`

### 4. Detection Rate (`tool_detection_rate.dart`)

Measures the decode success rate across every fixture directory (including `fixtures/unsupported_images`). Use this to track detection capability alongside performance.

```bash
dart run benchmark/tool_detection_rate.dart [--verbose]
```

## Profiling

To identify performance bottlenecks, use the profiling tool which breaks down execution time by stage (Load, Convert, Binarize, Detect, Decode).

```bash
dart run benchmark/tool_profiling.dart
```

## Tips for Accurate Benchmarking

* **Use AOT**: `dart compile exe benchmark/bench_compare.dart -o bench && ./bench`
* **Warmup**: Most scripts include a warmup phase, but multiple runs are recommended.
* **Power Mode**: Ensure your laptop is plugged in and not in "Low Power Mode".
