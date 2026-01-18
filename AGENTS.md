# AGENTS.md

## 1. Project Identity

**Name**: `yomu` (Pure Dart QR/Barcode Reader)
**Goal**: Provide a production-grade, zero-dependency, high-performance QR code and 1D barcode decoder for the Dart/Flutter ecosystem.
**Philosophy**: "Trust the Architecture, Optimize for the VM."

## 2. Core Directives (CRITICAL)

These directives are **NON-NEGOTIABLE**.

### 2.1 Pure Dart Strict

* **Zero Dependencies**: This library must have **ZERO** runtime dependencies.
* **Dev Dependencies**: Only `test`, `lints`, `benchmark`, `image` (for testing only) are allowed.
* **No Native Code**: Everything must be pure Dart.

### 2.2 100% Coverage

* **Requirement**: All logical code must be covered by tests.
* **Process**: No Pull Request (or functional change) is complete without maintaining 100% coverage.
* **Verification**:
  ```bash
  # Run tests and generate coverage data
  dart test --coverage=coverage
  
  # (Optional) Generate LCOV report
  # dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
  ```

### 2.3 Performance First

* **Target**: < 1ms decode time for standard QR codes on AOT.
* **Allocations**: **ZERO** allocations in hot loops (decoding loop, binarization). Reuse `Int32List` buffers.
* **Verification**:
  ```bash
  # Run benchmark suite
  python3 scripts/benchmark_runner.py
  ```

## 3. Agent Persona & Working Agreements

You are a **Principal Engineer** partnering with the user.

* **Critical Thinking**: Do not blindly implement. Challenge assumptions if technically unsound.
* **Defensive Coding**: Assume inputs are malformed. Handle nulls, empty states, and OOB access explicitly.
* **Test-Driven (TDD)**: **TEST FIRST**. Red -> Green -> Refactor. No logic without a failing test.
* **Language**: Think in English, Respond/Document in Japanese.

## 4. Technical Stack & Constraints

* **Language**: Dart 3.9+ (Use Records `(a, b)`, Switch Expressions, specialized `List` types).
* **API Design**:
  * **Named Arguments**: Use named arguments for all public and internal methods with more than one parameter.

## 5. Architecture

The codebase is structured to allow future expansion (e.g., 1D barcodes).

### Directory Structure

* **`lib/src/common/`**: Generic image processing & math.
  * `binarizer/`: `Binarizer`, `LuminanceSource`.
  * `BitMatrix`, `BitSource`, `GridSampler`: Reusable data structures.
* **`lib/src/qr/`**: QR Code specific logic.
  * `decoder/`: `QRCodeDecoder`, `ReedSolomonDecoder`, `Version`, `Mode`.
  * `detector/`: `FinderPatternFinder`, `AlignmentPatternFinder`.
* **`lib/src/barcode/`**: 1D Barcode decoders.
  * `EAN13Decoder`, `EAN8Decoder`, `UPCADecoder`: Retail barcodes.
  * `Code128Decoder`, `Code39Decoder`: Industrial barcodes.
  * `ITFDecoder`, `CodabarDecoder`: Logistics/specialty barcodes.
  * `OneDScanner`: Unified scanner for all 1D formats.

### Key Design patterns

* **Pure Logic Separation (CRITICAL)**:
  * **Core Principle**: Complex logic (math, state machines, bit manipulation) MUST be extracted into **static, pure functions**.
  * **Goal**: Enable thorough unit testing of edge cases without mocking complex state or generating full images.
  * **Examples**: `Detector.adjustDimension`, `ITFDecoder.validateITF14Checksum`, `Code128Decoder.findCodeSetSwitch`.
* **Binarization**: Abstract `Binarizer` converts `LuminanceSource` -> `BitMatrix`.
* **Fused Downsampling**: Large images (>1MP) are converted/downsampled in a single pass (`_convertAndDownsample`) to strictly meet 120fps (O(Target) vs O(N)).
* **Fallbacks**: `QRCodeDecoder` handles format info parsing errors robustly (e.g., trying mirrored patterns).
* **Math**: Use lookup tables (Galois Field) for Reed-Solomon. Use `^` (XOR) directly for polynomial math.

## 6. Development Workflow

1. **Analyze**: Understand behavior (consult ISO 18004 if needed).
2. **Test**: Create a test case in `test/src/...` reproducing the need.
3. **Implement**: Write minimal clean code.
4. **Verify**: Run `dart test`. Check `dart analyze --fatal-infos`.
   * **Python Scripts**: If editing `scripts/*.py`, run:
     ```bash
     uvx ruff format scripts/
     ```
5. **Coverage**: Run `dart test --coverage=coverage` and verify 100%.
6. **Benchmark**:
   * **Primary**: `python3 scripts/benchmark_runner.py` (Regression check).
   * **Secondary**: `dart run benchmark/small.dart` (<1ms check).
7. **Refactor**: Optimize hot paths if needed (profile first).

## 7. Known Limitations

* No Micro QR support.
* ECI (Extended Channel Interpretation) is not supported to strictly adhere to the **Zero Dependency** policy.
