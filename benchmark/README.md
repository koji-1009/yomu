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

### 2. Micro-Benchmarks

Targeted benchmarks for specific components.

* **Binarizer**: `dart run benchmark/bench_binarizer.dart`

## Profiling

To identify performance bottlenecks, use the profiling tool which breaks down execution time by stage (Load, Convert, Binarize, Detect, Decode).

```bash
dart run benchmark/tool_profiling.dart
```

## Tips for Accurate Benchmarking

* **Use AOT**: `dart compile exe benchmark/bench_compare.dart -o bench && ./bench`
* **Warmup**: Most scripts include a warmup phase, but multiple runs are recommended.
* **Power Mode**: Ensure your laptop is plugged in and not in "Low Power Mode".
