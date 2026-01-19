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

### 1. Latency Benchmark (`bench_latency.dart`)

**Goal**: Verify ultra-low latency (<1ms) for standard QR codes.

```bash
dart run benchmark/bench_latency.dart
```

### 2. Throughput Benchmark (`bench_throughput.dart`)

**Goal**: Verify system stability and FPS (Target > 120fps / < 8.3ms) on realistic workloads using `fixtures/performance_test_images`.

```bash
dart run benchmark/bench_throughput.dart
```

### 3. Micro-Benchmarks

Targeted benchmarks for specific components.

* **Binarizer**: `dart run benchmark/bench_binarizer.dart`

### 4. Comparative Benchmark (`bench_compare.dart`)

Compares overhead of different detector configurations (e.g., `qrOnly` vs `all`).

```bash
dart run benchmark/bench_compare.dart
```

## Profiling

To identify performance bottlenecks, use the profiling tool which breaks down execution time by stage (Load, Convert, Binarize, Detect, Decode).

```bash
dart run benchmark/tool_profiling.dart
```

## Tips for Accurate Benchmarking

* **Use AOT**: `dart compile exe benchmark/bench_throughput.dart -o bench && ./bench`
* **Warmup**: Most scripts include a warmup phase, but multiple runs are recommended.
* **Power Mode**: Ensure your laptop is plugged in and not in "Low Power Mode".
