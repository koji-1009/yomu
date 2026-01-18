#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Benchmark runner for yomu.

Compares performance between JIT execution (dart run) and AOT execution (compiled exe).
Parses output from benchmark/decoding_benchmark.dart (or compatible scripts).

Usage:
    uv run scripts/benchmark_runner.py [benchmark_script]

    Example:
    uv run scripts/benchmark_runner.py benchmark/decoding.dart
    uv run scripts/benchmark_runner.py benchmark/small.dart
"""

import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union


@dataclass
class LegacyBenchmarkResult:
    """Results from a standard benchmark run."""

    mode: str
    total_images: int
    success_count: int
    total_time_us: int
    avg_time_ms: float
    passed: bool


@dataclass
class ComparativeBenchmarkResult:
    """Results from a comparative benchmark run (e.g. Mode A vs Mode B)."""

    mode: str
    # QR Section
    qr_baseline_ms: float  # Yomu.qrOnly
    qr_all_ms: float  # Yomu.all
    qr_overhead_ms: float
    qr_overhead_pct: float

    # Barcode Section
    barcode_baseline_ms: float  # Yomu.barcodeOnly
    barcode_all_ms: float  # Yomu.all
    barcode_overhead_ms: float
    barcode_overhead_pct: float

    passed: bool
    details: list[tuple[str, float, float, str]] = None


BenchmarkResult = Union[LegacyBenchmarkResult, ComparativeBenchmarkResult]


def run_command(cmd: list[str], cwd: str = ".") -> tuple[int, str, str]:
    """Run a command and return exit code, stdout, stderr."""
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except FileNotFoundError:
        return 1, "", f"Command not found: {cmd[0]}"


def parse_benchmark_output(output: str) -> Optional[BenchmarkResult]:
    """Parse benchmark output to extract metrics."""

    # Check for Comparative Benchmark
    if "COMPARATIVE BENCHMARK" in output:
        return _parse_comparative(output)

    # Fallback to Legacy Benchmark
    return _parse_legacy(output)


def _parse_legacy(output: str) -> Optional[LegacyBenchmarkResult]:
    # Look for the summary lines
    total_match = re.search(r"Total processed: (\d+) images \((\d+) success\)", output)
    time_match = re.search(r"Total decode time: (\d+)µs", output)
    avg_match = re.search(r"Average decode time: ([\d.]+)ms", output)

    # Some benchmarks output BENCHMARK_PASS explicitly
    passed_explicit = "BENCHMARK_PASS" in output

    if not all([total_match, time_match, avg_match]):
        return None

    total = int(total_match.group(1))  # type: ignore
    success = int(total_match.group(2))  # type: ignore
    total_us = int(time_match.group(1))  # type: ignore
    avg_ms = float(avg_match.group(1))  # type: ignore

    # Pass if < 5ms (JIT dev target) or explicitly passed
    passed = passed_explicit or avg_ms < 5.0

    return LegacyBenchmarkResult(
        mode="",
        total_images=total,
        success_count=success,
        total_time_us=total_us,
        avg_time_ms=avg_ms,
        passed=passed,
    )


def _parse_comparative(output: str) -> Optional[ComparativeBenchmarkResult]:
    # Parse overheads
    # Expect output like: Overhead: +0.024ms (+1.7%) or -0.019ms (-1.1%)
    # Parse details
    # Expect: DETAILS:image.png | 1.234 | 1.567 | +0.333
    details = re.findall(r"DETAILS:(.+)\|(.+)\|(.+)\|(.+)", output)

    detail_rows = []
    for d in details:
        image = d[0].strip()
        time_a = float(d[1].strip())
        time_b = float(d[2].strip())
        diff_str = d[3].strip()
        detail_rows.append((image, time_a, time_b, diff_str))

    # Parse overheads (Restored)
    # Expect output like: Overhead: +0.024ms (+1.7%) or -0.019ms (-1.1%)
    overheads = re.findall(r"Overhead: ([+\-]?[\d.]+)ms \(([+\-]?[\d.]+)%\)", output)

    # Parse absolute times (Restored)
    # Expect: Yomu.qrOnly          | Avg: 1.454ms | Total: 46.5ms
    # Capture 'Avg:' value
    avgs = re.findall(r"Avg: ([\d.]+)ms", output)

    # We expect 4 averages (A, B for QR, then A, B for Barcode) and 2 overheads
    if len(overheads) < 2 or len(avgs) < 4:
        # Might be partial result or failed
        return None

    # QR Metrics
    qr_base = float(avgs[0])
    qr_all = float(avgs[1])
    qr_ohm = float(overheads[0][0])
    qr_ohp = float(overheads[0][1])

    # Barcode Metrics
    bc_base = float(avgs[2])
    bc_all = float(avgs[3])
    bc_ohm = float(overheads[1][0])
    bc_ohp = float(overheads[1][1])

    # Pass logic: QR overhead should be small (< 15%), Barcode overhead logic is just info
    passed = qr_ohp < 15.0

    return ComparativeBenchmarkResult(
        mode="",
        qr_baseline_ms=qr_base,
        qr_all_ms=qr_all,
        qr_overhead_ms=qr_ohm,
        qr_overhead_pct=qr_ohp,
        barcode_baseline_ms=bc_base,
        barcode_all_ms=bc_all,
        barcode_overhead_ms=bc_ohm,
        barcode_overhead_pct=bc_ohp,
        passed=passed,
        details=detail_rows,
    )


def run_jit_benchmark(
    script_path: str = "benchmark/decoding.dart",
) -> Optional[BenchmarkResult]:
    """Run benchmark in JIT mode (dart run)."""
    print(f"🔄 Running JIT benchmark ({script_path})...")
    code, stdout, stderr = run_command(["dart", "run", script_path])

    if code != 0:
        print(f"❌ JIT benchmark failed: {stderr}")
        return None

    result = parse_benchmark_output(stdout)
    if result:
        result.mode = "JIT"
    return result


def run_aot_benchmark(
    script_path: str = "benchmark/decoding.dart",
) -> Optional[BenchmarkResult]:
    """Run benchmark in AOT mode (compiled executable)."""
    exe_name = Path(script_path).stem + "_exe"
    exe_path = Path("benchmark") / exe_name

    # Compile if needed
    print("🔨 Compiling AOT executable...")
    code, stdout, stderr = run_command(
        ["dart", "compile", "exe", script_path, "-o", str(exe_path)]
    )

    if code != 0:
        print(f"❌ Compilation failed: {stderr}")
        return None

    # Run compiled executable
    print("🔄 Running AOT benchmark (compiled)...")
    code, stdout, stderr = run_command([str(exe_path)])

    # Clean up executable
    if exe_path.exists():
        exe_path.unlink()

    if code != 0:
        print(f"❌ AOT benchmark failed: {stderr}")
        return None

    result = parse_benchmark_output(stdout)
    if result:
        result.mode = "AOT"
    return result


def generate_markdown_report(
    jit: ComparativeBenchmarkResult, aot: ComparativeBenchmarkResult
) -> str:
    """Generate a Markdown report for GitHub Summary / PR Comment."""
    md = []
    md.append("# 📊 Benchmark Report")
    md.append("")

    # Overview Table
    md.append("## Overview")
    md.append("| Metric | Mode | JIT (dart run) | AOT (compiled) |")
    md.append("| :--- | :--- | :--- | :--- |")

    jit_qr = f"{jit.qr_baseline_ms:.2f}ms -> {jit.qr_all_ms:.2f}ms ({jit.qr_overhead_pct:+.1f}%)"
    aot_qr = f"{aot.qr_baseline_ms:.2f}ms -> {aot.qr_all_ms:.2f}ms ({aot.qr_overhead_pct:+.1f}%)"
    md.append(f"| **QR Code** | `qr -> all` | {jit_qr} | {aot_qr} |")

    jit_bc = f"{jit.barcode_baseline_ms:.2f}ms -> {jit.barcode_all_ms:.2f}ms ({jit.barcode_overhead_pct:+.1f}%)"
    aot_bc = f"{aot.barcode_baseline_ms:.2f}ms -> {aot.barcode_all_ms:.2f}ms ({aot.barcode_overhead_pct:+.1f}%)"
    md.append(f"| **Barcode** | `bar -> all` | {jit_bc} | {aot_bc} |")

    jit_status = "✅ PASS" if jit.passed else "⚠️ WARN"
    aot_status = "✅ PASS" if aot.passed else "⚠️ WARN"
    md.append(f"| **Status** | | {jit_status} | {aot_status} |")

    # Detailed Table (AOT only usually matters for prod, but we show both or just AOT. Let's show AOT details)
    if aot.details:
        md.append("")
        md.append("## 🔍 Detailed Performance (AOT)")
        md.append("<details>")
        md.append("<summary>Click to view per-image breakdown</summary>")
        md.append("")
        md.append("| Image | Baseline (ms) | All (ms) | Diff (ms) |")
        md.append("| :--- | :---: | :---: | :---: |")

        for img, t1, t2, diff in aot.details:
            md.append(f"| {img} | {t1:.3f} | {t2:.3f} | {diff} |")

        md.append("</details>")

    return "\n".join(md)


def print_comparison(jit: BenchmarkResult, aot: BenchmarkResult):
    """Print a comparison table of JIT vs AOT results."""

    print("\n" + "=" * 80)
    print("📊 BENCHMARK COMPARISON")
    print("=" * 80)

    if isinstance(jit, LegacyBenchmarkResult) and isinstance(
        aot, LegacyBenchmarkResult
    ):
        _print_legacy_comparison(jit, aot)
    elif isinstance(jit, ComparativeBenchmarkResult) and isinstance(
        aot, ComparativeBenchmarkResult
    ):
        _print_comparative_comparison(jit, aot)

        # Generate and save report
        report = generate_markdown_report(jit, aot)
        with open("benchmark_summary.md", "w") as f:
            f.write(report)
        print("\n📝 Report saved to benchmark_summary.md")
        print("   (See benchmark_summary.md for detailed per-image breakdown)")

    else:
        print("❌ Error: Mixed benchmark results (Legacy vs Comparative)")


def _print_legacy_comparison(jit: LegacyBenchmarkResult, aot: LegacyBenchmarkResult):
    speedup = jit.avg_time_ms / aot.avg_time_ms if aot.avg_time_ms > 0 else 0

    print(f"{'Metric':<25} | {'JIT (dart run)':<18} | {'AOT (compiled)':<18}")
    print("-" * 80)
    print(f"{'Images Processed':<25} | {jit.total_images:<18} | {aot.total_images:<18}")
    print(f"{'Success Count':<25} | {jit.success_count:<18} | {aot.success_count:<18}")
    print(
        f"{'Total Time (µs)':<25} | {jit.total_time_us:<18} | {aot.total_time_us:<18}"
    )
    print(
        f"{'Average Time (ms)':<25} | {jit.avg_time_ms:<18.3f} | {aot.avg_time_ms:<18.3f}"
    )
    print(
        f"{'Status':<25} | {'✅ PASS' if jit.passed else '⚠️ WARN':<18} | {'✅ PASS' if aot.passed else '⚠️ WARN':<18}"
    )
    print("-" * 80)
    print(f"{'AOT Speedup':<25} | {speedup:.2f}x faster")
    print("=" * 80)

    # Performance assessment
    print("\n📈 PERFORMANCE ASSESSMENT:")
    if aot.avg_time_ms < 2.0:
        print("   ✅ AOT meets target (<2ms average decode time)")
    else:
        print(f"   ⚠️ AOT above target (target: <2ms, actual: {aot.avg_time_ms:.3f}ms)")

    if jit.avg_time_ms < 5.0:
        print("   ✅ JIT acceptable for development (<5ms)")
    else:
        print(f"   ⚠️ JIT slower than expected ({jit.avg_time_ms:.3f}ms)")


def _format_time_cell(baseline: float, all_mode: float, overhead_pct: float) -> str:
    # Format: "1.45ms -> 1.48ms (+1.7%)"
    return f"{baseline:.2f}ms -> {all_mode:.2f}ms ({overhead_pct:+.1f}%)"


def _print_comparative_comparison(
    jit: ComparativeBenchmarkResult, aot: ComparativeBenchmarkResult
):
    # Print JIT Table
    print(
        f"{'METRIC':<20} | {'MODE':<12} | {'JIT (dart run)':<30} | {'AOT (compiled)':<30}"
    )
    print("-" * 100)

    # QR Row
    jit_qr_str = _format_time_cell(
        jit.qr_baseline_ms, jit.qr_all_ms, jit.qr_overhead_pct
    )
    aot_qr_str = _format_time_cell(
        aot.qr_baseline_ms, aot.qr_all_ms, aot.qr_overhead_pct
    )
    print(f"{'QR Code':<20} | {'qr -> all':<12} | {jit_qr_str:<30} | {aot_qr_str:<30}")

    # Barcode Row
    jit_bc_str = _format_time_cell(
        jit.barcode_baseline_ms, jit.barcode_all_ms, jit.barcode_overhead_pct
    )
    aot_bc_str = _format_time_cell(
        aot.barcode_baseline_ms, aot.barcode_all_ms, aot.barcode_overhead_pct
    )
    print(f"{'Barcode':<20} | {'bar -> all':<12} | {jit_bc_str:<30} | {aot_bc_str:<30}")

    print("-" * 100)
    print(
        f"{'Status':<35} | {'✅ PASS' if jit.passed else '⚠️ WARN':<30} | {'✅ PASS' if aot.passed else '⚠️ WARN':<30}"
    )
    print("=" * 100)


def main():
    """Main execution entry point."""
    # Parse args
    target_script = "benchmark/decoding.dart"
    if len(sys.argv) > 1:
        target_script = sys.argv[1]

    # Check we're in the right directory
    if not Path(target_script).exists():
        print(f"❌ Error: Benchmark script not found: {target_script}")
        sys.exit(1)

    if not Path("fixtures/qr_images").exists():
        print(
            "❌ Error: Test images not found. Run: uv run scripts/generate_test_qr.py"
        )
        sys.exit(1)

    print("=" * 80)
    print("🚀 QYUTO BENCHMARK RUNNER")
    print("=" * 80)
    print()

    start_time = time.time()

    # Run JIT benchmark
    jit_result = run_jit_benchmark(target_script)
    if not jit_result:
        print("❌ JIT benchmark failed")
        sys.exit(1)

    print()

    # Run AOT benchmark
    aot_result = run_aot_benchmark(target_script)
    if not aot_result:
        print("❌ AOT benchmark failed")
        sys.exit(1)

    # Print comparison
    print_comparison(jit_result, aot_result)

    elapsed = time.time() - start_time
    print(f"\n⏱️ Total benchmark time: {elapsed:.1f}s")

    # Final status
    if aot_result.passed and jit_result.passed:
        print("\n✅ ALL BENCHMARKS PASSED")
        sys.exit(0)
    else:
        print("\n⚠️ SOME BENCHMARKS NEED ATTENTION")
        # Don't fail the script, just warn
        sys.exit(0)


if __name__ == "__main__":
    main()
