#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Benchmark runner for yomu.

Compares performance between JIT execution (dart run) and AOT execution (compiled exe).
Parses output from benchmark/bench_compare.dart (or compatible scripts).

Usage:
    uv run scripts/benchmark_runner.py [benchmark_script]

    Example:
    uv run scripts/benchmark_runner.py benchmark/bench_compare.dart
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
    qr_baseline_ms: float  # Yomu.qrOnly (Standard)
    qr_all_ms: float  # Yomu.all (Standard)
    qr_overhead_ms: float
    qr_overhead_pct: float

    # QR Stress Section
    qr_stress_baseline_ms: float  # Yomu.qrOnly (Complex/Stress)
    qr_stress_all_ms: float  # Yomu.all (Complex/Stress)
    qr_stress_overhead_ms: float
    qr_stress_overhead_pct: float

    # Barcode Section
    barcode_baseline_ms: float  # Yomu.barcodeOnly
    barcode_all_ms: float  # Yomu.all
    barcode_overhead_ms: float
    barcode_overhead_pct: float

    passed: bool

    # Optional fields (must come last in dataclass)
    # Categories (Standard, Heavy, Edge) with avg/p95
    # Stored as tuple (AvgA, p95A, AvgB, p95B)
    qr_categories: dict[str, tuple[float, float, float, float]] = None
    barcode_categories: dict[str, tuple[float, float, float, float]] = None
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


class BenchmarkParser:
    """Stateful parser for benchmark output."""

    def __init__(self):
        # Data storage
        self.qr_standard_stats = None
        self.qr_stress_stats = None
        self.barcode_stats = None

        # State
        self.current_section = None
        self.section_avgs = []
        self.section_overhead = None

        # Additional data
        self.params = {}  # For categories, etc
        self.qr_cats = {}
        self.bc_cats = {}
        self.details = []

    def parse(self, output: str) -> Optional[ComparativeBenchmarkResult]:
        lines = output.splitlines()

        for line in lines:
            self._process_line(line)

        self._commit_section()

        return self._build_result(output)

    def _process_line(self, line: str):
        line = line.strip()
        if not line:
            return

        # Section headers
        sec_match = re.search(r"^---\s+(.+)\s+---", line)
        if sec_match:
            header = sec_match.group(1)
            # Ignore sub-headers for categories
            if "Metrics" in header:
                return

            self._commit_section()
            self.current_section = header
            return

        # Stats
        if "Yomu." in line:
            stats_match = re.search(r"Avg:\s+([\d.]+)ms.*p95:\s+([\d.]+)ms", line)
            if stats_match:
                avg = float(stats_match.group(1))
                p95 = float(stats_match.group(2))
                self.section_avgs.append((avg, p95))

        # Overhead
        oh_match = re.search(
            r"Overhead:\s+([+\-]?[\d.]+)ms\s+\(([+\-]?[\d.]+)%\)", line
        )
        if oh_match:
            ms = float(oh_match.group(1))
            pct = float(oh_match.group(2))
            self.section_overhead = (ms, pct)

    def _commit_section(self):
        if not self.current_section or not self.section_avgs:
            return

        # Expecting at least 2 avgs (Baseline, All) and 1 overhead
        if len(self.section_avgs) >= 2 and self.section_overhead:
            stats = {
                "baseline": self.section_avgs[0],
                "all": self.section_avgs[1],
                "overhead": self.section_overhead,
            }

            if "QR Code Standard" in self.current_section:
                self.qr_standard_stats = stats
            elif "QR Code Stress" in self.current_section:
                self.qr_stress_stats = stats
            elif "Barcode" in self.current_section:
                self.barcode_stats = stats

        # Reset
        self.section_avgs = []
        self.section_overhead = None

    def _build_result(self, output: str) -> Optional[ComparativeBenchmarkResult]:
        if not self.qr_standard_stats and not self.barcode_stats:
            # Fallback if absolutely nothing is found (unlikely in valid run)
            # But the caller checks for None return
            if not self.qr_stress_stats:
                return None

        # Helper to get stat safe
        def get_stat(stats_dict, key, idx=0):
            if not stats_dict:
                return 0.0
            return stats_dict[key][idx]

        qr_base = get_stat(self.qr_standard_stats, "baseline", 0)
        qr_all = get_stat(self.qr_standard_stats, "all", 0)
        qr_ohm = get_stat(self.qr_standard_stats, "overhead", 0)
        qr_ohp = get_stat(self.qr_standard_stats, "overhead", 1)

        qr_stress_base = get_stat(self.qr_stress_stats, "baseline", 0)
        qr_stress_all = get_stat(self.qr_stress_stats, "all", 0)
        qr_stress_ohm = get_stat(self.qr_stress_stats, "overhead", 0)
        qr_stress_ohp = get_stat(self.qr_stress_stats, "overhead", 1)

        bc_base = get_stat(self.barcode_stats, "baseline", 0)
        bc_all = get_stat(self.barcode_stats, "all", 0)
        bc_ohm = get_stat(self.barcode_stats, "overhead", 0)
        bc_ohp = get_stat(self.barcode_stats, "overhead", 1)

        # Parse Categories (Best effort regex over full output)
        self._parse_categories(output)

        # Parse Details
        self._parse_details(output)

        # Pass logic
        passed = qr_ohp < 15.0

        return ComparativeBenchmarkResult(
            mode="",
            qr_baseline_ms=qr_base,
            qr_all_ms=qr_all,
            qr_overhead_ms=qr_ohm,
            qr_overhead_pct=qr_ohp,
            qr_stress_baseline_ms=qr_stress_base,
            qr_stress_all_ms=qr_stress_all,
            qr_stress_overhead_ms=qr_stress_ohm,
            qr_stress_overhead_pct=qr_stress_ohp,
            qr_categories=self.qr_cats,
            barcode_categories=self.bc_cats,
            barcode_baseline_ms=bc_base,
            barcode_all_ms=bc_all,
            barcode_overhead_ms=bc_ohm,
            barcode_overhead_pct=bc_ohp,
            passed=passed,
            details=self.details,
        )

    def _parse_categories(self, output: str):
        for cat in ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]:
            matches = re.findall(rf"{cat}\s+: Avg ([\d.]+)ms, p95 ([\d.]+)ms", output)
            if len(matches) >= 2:
                self.qr_cats[cat] = (
                    float(matches[0][0]),
                    float(matches[0][1]),
                    float(matches[1][0]),
                    float(matches[1][1]),
                )
            if len(matches) >= 4:
                self.bc_cats[cat] = (
                    float(matches[2][0]),
                    float(matches[2][1]),
                    float(matches[3][0]),
                    float(matches[3][1]),
                )

    def _parse_details(self, output: str):
        details = re.findall(r"DETAILS:(.+)\|(.+)\|(.+)\|(.+)", output)
        for d in details:
            image = d[0].strip()
            time_a = float(d[1].strip())
            time_b = float(d[2].strip())
            diff_str = d[3].strip()
            self.details.append((image, time_a, time_b, diff_str))


def _parse_comparative(output: str) -> Optional[ComparativeBenchmarkResult]:
    return BenchmarkParser().parse(output)


def run_jit_benchmark(
    script_path: str = "benchmark/bench_compare.dart",
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
    script_path: str = "benchmark/bench_compare.dart",
) -> Optional[BenchmarkResult]:
    """Run benchmark in AOT mode (compiled executable)."""
    exe_name = Path(script_path).stem + "_exe"
    exe_path = Path("benchmark") / exe_name
    exe_path = Path(exe_path)  # correct path usage

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
    md.append(f"| **QR Standard** | `qr -> all` | {jit_qr} | {aot_qr} |")

    jit_stress = f"{jit.qr_stress_baseline_ms:.2f}ms -> {jit.qr_stress_all_ms:.2f}ms ({jit.qr_stress_overhead_pct:+.1f}%)"
    aot_stress = f"{aot.qr_stress_baseline_ms:.2f}ms -> {aot.qr_stress_all_ms:.2f}ms ({aot.qr_stress_overhead_pct:+.1f}%)"
    md.append(f"| **QR Stress** | `qr -> all` | {jit_stress} | {aot_stress} |")

    jit_bc = f"{jit.barcode_baseline_ms:.2f}ms -> {jit.barcode_all_ms:.2f}ms ({jit.barcode_overhead_pct:+.1f}%)"
    aot_bc = f"{aot.barcode_baseline_ms:.2f}ms -> {aot.barcode_all_ms:.2f}ms ({aot.barcode_overhead_pct:+.1f}%)"
    md.append(f"| **Barcode** | `bar -> all` | {jit_bc} | {aot_bc} |")

    jit_status = "✅ PASS" if jit.passed else "⚠️ WARN"
    aot_status = "✅ PASS" if aot.passed else "⚠️ WARN"
    md.append(f"| **Status** | | {jit_status} | {aot_status} |")

    # QR Category Breakdown (AOT)
    if aot.qr_categories:
        md.append("")
        md.append("## 📈 QR Code Performance (AOT)")
        md.append("| Category | Average (ms) | p95 (ms) | Notes |")
        md.append("| :--- | :--- | :--- | :--- |")

        cats = aot.qr_categories
        for cat in ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]:
            if cat in cats:
                c = cats[cat]
                note = ""
                if cat == "Standard":
                    note = "Version 1-4, Alphanumeric"
                elif cat == "Complex":
                    note = "High Versions (V5+)"
                elif cat == "HiRes":
                    note = "4K / Large images"
                elif cat == "Distorted":
                    note = "Rotated / Tilted / Skewed"
                elif cat == "Noise":
                    note = "Noisy background"
                elif cat == "Edge":
                    note = "Tiny, uniform, error cases"

                md.append(f"| **{cat}** | {c[2]:.2f}ms | {c[3]:.2f}ms | {note} |")

    # Barcode Category Breakdown (AOT)
    if aot.barcode_categories and len(aot.barcode_categories) > 0:
        md.append("")
        md.append("## 📈 Barcode Performance (AOT)")
        md.append("| Category | Average (ms) | p95 (ms) | Notes |")
        md.append("| :--- | :--- | :--- | :--- |")

        cats = aot.barcode_categories
        for cat in ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]:
            if cat in cats:
                c = cats[cat]
                md.append(f"| **{cat}** | {c[2]:.2f}ms | {c[3]:.2f}ms | |")

    # Detailed Table
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
    print(f"{'QR Standard':<20} | {'qr -> all':<12} | {jit_qr_str:<30} | {aot_qr_str:<30}")

    # QR Stress Row
    jit_stress_str = _format_time_cell(
        jit.qr_stress_baseline_ms, jit.qr_stress_all_ms, jit.qr_stress_overhead_pct
    )
    aot_stress_str = _format_time_cell(
        aot.qr_stress_baseline_ms, aot.qr_stress_all_ms, aot.qr_stress_overhead_pct
    )
    print(
        f"{'QR Stress':<20} | {'qr -> all':<12} | {jit_stress_str:<30} | {aot_stress_str:<30}"
    )

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

    # Print Categories (AOT)
    if aot.qr_categories:
        print("\n📈 QR Performance by Category (AOT - Yomu.all):")
        print(f"{'Category':<15} | {'Average':<15} | {'p95':<15}")
        print("-" * 50)
        cats = aot.qr_categories
        for cat in ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]:
            if cat in cats:
                c = cats[cat]
                print(f"{cat:<15} | {c[2]:.3f}ms        | {c[3]:.3f}ms")

    if aot.barcode_categories and len(aot.barcode_categories) > 0:
        print("\n📈 Barcode Performance by Category (AOT - Yomu.all):")
        print(f"{'Category':<15} | {'Average':<15} | {'p95':<15}")
        print("-" * 50)
        cats = aot.barcode_categories
        for cat in ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]:
            if cat in cats:
                c = cats[cat]
                print(f"{cat:<15} | {c[2]:.3f}ms        | {c[3]:.3f}ms")

    print("=" * 100)


import argparse
import json
from dataclasses import asdict, is_dataclass

# ... (Existing imports)


def save_results(
    path: str, jit: Optional[BenchmarkResult], aot: Optional[BenchmarkResult]
):
    """Save benchmark results to a JSON file."""
    data = {
        "jit": asdict(jit) if jit and is_dataclass(jit) else None,
        "aot": asdict(aot) if aot and is_dataclass(aot) else None,
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"\n💾 Results saved to {path}")


def load_results(path: str) -> dict:
    """Load benchmark results from a JSON file."""
    with open(path, "r") as f:
        return json.load(f)


def generate_comparison_report(base_data: dict, target_data: dict) -> str:
    """Generate a Markdown report comparing Base vs Target (HEAD)."""
    md = []
    md.append("# 🚀 Benchmark Comparison Report")
    md.append("")

    # We focus deeply on AOT results for the comparison as it is the prod target
    base_aot = base_data.get("aot")
    target_aot = target_data.get("aot")

    if not base_aot or not target_aot:
        md.append(
            "> ⚠️ Missing AOT data in one or both reports. Comparing JIT if available."
        )
        # Fallback logic could go here, but let's stick to AOT for now or show error

    # Helper to extract metric
    def get_metric(data, key, nested_key=None):
        if not data:
            return 0.0
        val = data.get(key, 0.0)
        if nested_key and isinstance(val, dict):
            return val.get(nested_key, 0.0)
        return val

    # QR Comparison
    base_qr_avg = get_metric(base_aot, "qr_all_ms")
    target_qr_avg = get_metric(target_aot, "qr_all_ms")

    md.append("## 🏁 Main Metrics (AOT)")
    md.append("| Metric | Base (main) | Target (PR) | Diff | State |")
    md.append("| :--- | :--- | :--- | :--- | :--- |")

    def row(label, base, target):
        diff = target - base
        pct = (diff / base * 100) if base > 0 else 0
        icon = "🟢" if diff <= 0 else "🔴"
        if abs(diff) < 0.05:
            icon = "⚪"  # Noise threshold
        return f"| **{label}** | {base:.3f}ms | {target:.3f}ms | {diff:+.3f}ms ({pct:+.1f}%) | {icon} |"

    md.append(row("QR Code Avg", base_qr_avg, target_qr_avg))

    base_bar_avg = get_metric(base_aot, "barcode_all_ms")
    target_bar_avg = get_metric(target_aot, "barcode_all_ms")
    md.append(row("Barcode Avg", base_bar_avg, target_bar_avg))

    # Category Comparison
    base_cats = base_aot.get("qr_categories", {}) if base_aot else {}
    target_cats = target_aot.get("qr_categories", {}) if target_aot else {}

    if base_cats or target_cats:
        md.append("")
        md.append("## 📊 QR Category Breakdown")
        md.append("| Category | Base Avg | Target Avg | Diff |")
        md.append("| :--- | :--- | :--- | :--- |")

        all_cats = set(list(base_cats.keys()) + list(target_cats.keys()))
        # Define sort order
        cat_order = ["Standard", "Complex", "HiRes", "Distorted", "Noise", "Edge"]

        all_cats = set(list(base_cats.keys()) + list(target_cats.keys()))

        # Sort based on defined order, put undefined ones at the end
        def sort_key(k):
            try:
                return cat_order.index(k)
            except ValueError:
                return 999

        for cat in sorted(all_cats, key=sort_key):
            # Format is [base_base, base_all, base_all, base_all]?
            # No, dict value is [base_avg, base_p95, all_avg, all_p95]
            # We want index 2 (all_avg)
            b_val = base_cats.get(cat, [0, 0, 0, 0])[2] if cat in base_cats else 0
            t_val = target_cats.get(cat, [0, 0, 0, 0])[2] if cat in target_cats else 0

            diff = t_val - b_val
            pct = (diff / b_val * 100) if b_val > 0 else 0
            md.append(
                f"| {cat} | {b_val:.3f}ms | {t_val:.3f}ms | {diff:+.3f}ms ({pct:+.1f}%) |"
            )

    return "\n".join(md)


def main():
    """Main execution entry point."""
    parser = argparse.ArgumentParser(description="Qyuto Benchmark Runner")
    parser.add_argument(
        "script",
        nargs="?",
        default="benchmark/bench_compare.dart",
        help="Path to benchmark script",
    )
    parser.add_argument("--save", help="Save benchmark results to JSON file")
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("BASE", "TARGET"),
        help="Compare two JSON result files",
    )
    parser.add_argument(
        "--mode",
        choices=["jit", "aot", "all"],
        default="all",
        help="Benchmark mode (jit, aot, or all)",
    )

    args = parser.parse_args()

    # COMPARISON MODE
    if args.compare:
        base_path, target_path = args.compare
        print(f"🔍 Comparing {base_path} vs {target_path}...")
        try:
            base_data = load_results(base_path)
            target_data = load_results(target_path)
            report = generate_comparison_report(base_data, target_data)

            with open("benchmark_comparison.md", "w") as f:
                f.write(report)

            print(report)
            print("\n📝 Comparison saved to benchmark_comparison.md")
            sys.exit(0)
        except Exception as e:
            print(f"❌ Comparison failed: {e}")
            sys.exit(1)

    # NORMAL MODE
    target_script = args.script

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

    jit_result = None
    aot_result = None

    # Run JIT benchmark
    if args.mode in ["jit", "all"]:
        jit_result = run_jit_benchmark(target_script)
        if not jit_result:
            print("❌ JIT benchmark failed")
            if args.mode == "jit":
                sys.exit(1)
        print()

    # Run AOT benchmark
    if args.mode in ["aot", "all"]:
        aot_result = run_aot_benchmark(target_script)
        if not aot_result:
            print("❌ AOT benchmark failed")
            if args.mode == "aot":
                sys.exit(1)

    # Print comparison if both available, otherwise just print what we have
    if jit_result and aot_result:
        print_comparison(jit_result, aot_result)
    elif jit_result:
        print_single_result(jit_result, "JIT")
    elif aot_result:
        print_single_result(aot_result, "AOT")

    # Save Results if requested
    if args.save:
        save_results(args.save, jit_result, aot_result)

    elapsed = time.time() - start_time
    print(f"\n⏱️ Total benchmark time: {elapsed:.1f}s")

    success = True
    if args.mode in ["jit", "all"] and (not jit_result or not jit_result.passed):
        success = False
    if args.mode in ["aot", "all"] and (not aot_result or not aot_result.passed):
        success = False

    # Final status
    if success:
        print("\n✅ BENCHMARKS PASSED")
        sys.exit(0)
    else:
        print("\n⚠️ BENCHMARKS FAILED OR WARNED")
        sys.exit(0)


def print_single_result(result: BenchmarkResult, label: str):
    """Print results for a single mode (JIT or AOT)."""
    if isinstance(result, ComparativeBenchmarkResult):
        print(f"{label} Result (QR Standard): Avg {result.qr_all_ms:.3f}ms")
        print(f"{label} Result (QR Stress):   Avg {result.qr_stress_all_ms:.3f}ms")
        print(f"{label} Result (Barcode):     Avg {result.barcode_all_ms:.3f}ms")

        if result.qr_categories:
            print(f"\n📈 QR Performance ({label}):")
            for cat, val in sorted(result.qr_categories.items()):
                print(f"  {cat:<10}: Avg {val[2]:.3f}ms | p95 {val[3]:.3f}ms")

        if result.barcode_categories:
            print(f"\n📈 Barcode Performance ({label}):")
            for cat, val in sorted(result.barcode_categories.items()):
                print(f"  {cat:<10}: Avg {val[2]:.3f}ms | p95 {val[3]:.3f}ms")
    else:
        print(f"{label} Result: Avg {result.avg_time_ms:.3f}ms")



if __name__ == "__main__":
    main()
