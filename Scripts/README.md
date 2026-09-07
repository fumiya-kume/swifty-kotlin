# Scripts workflow

## Inventory

| Script | CI | Purpose |
|---|---|---|
| `swift_test.sh` | ✓ | `swift test` wrapper: parallel defaults, grouped failure summary, golden-update hint, GitHub annotations, crash-signal retry |
| `shard_swift_tests.sh` | ✓ | Split one slow test target across CI jobs (`--mode dynamic` per-test / `--mode static` per-suite) |
| `diff_kotlinc.sh` | ✓ | Behavioral diff of `kswiftc` vs `kotlinc` over `diff_cases/`; persists failure artifacts |
| `diff_diagnostics.sh` | ✓ | Diagnostic differential over `diagnostic_cases/`: compile acceptance and normalized error line sets |
| `diff_kotlinc_ci_summary.sh` | ✓ | Render the diff TSV report as a markdown step summary with embedded diffs |
| `loc_report.sh` | – | Refactoring guard metrics as TSV (LoC by directory, `kk_` literals, TODO/FIXME counts) |
| `dead_code_audit.sh` | – | Audit `@_cdecl kk_*` runtime symbols unreachable from the compiler |
| `check_todo_ids.sh` | ✓ | Detect duplicate task IDs in `TODO.md` |
| `check_mutation_fuzzer_keywords.sh` | ✓ | Verify `mutate_diff_cases.py`'s `IDENTIFIER_KEYWORDS` matches the lexer's `Keyword` enum |
| `validate_runtime_abi_links.sh` | – | Shorthand for the `RuntimeABIExternalLinkValidationTests` filter |
| `lib/common.sh` | (sourced) | Shared helpers: worker detection, interleaved sharding, filter chunking, case-name sanitizing, diff-tooling preflight, case-directive parsing, artifact-collision avoidance |

## swift_test.sh

`Scripts/swift_test.sh` wraps `swift test` with parallel execution enabled by default.

- Tune XCTest and Swift Testing workers (including Golden): `SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh`
- Tune build jobs: `SWIFT_TEST_BUILD_JOBS=4 bash Scripts/swift_test.sh`
- Disable parallel mode: `SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh`

`SWIFT_TEST_WORKERS` must be a positive integer. Explicit Swift Testing
`--experimental-maximum-parallelization-width` or
`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` settings take precedence for
Swift Testing. Without a worker override, the runner keeps its default width.
Limiting workers reduces concurrent CPU load; it does not skip test cases.

If a run crashes with a signal (e.g. `*** Signal 11: ...` / `exited with
unexpected signal code`) and no per-test failure line was parsed, the whole
`swift test` invocation is retried up to 3 times before failing the step.
This targets swift-corelibs-foundation's Linux `Process.run()` races that
`CommandRunner.processLaunchLock` cannot fully close (unrelated threads in
the same xctest process can still mutate the fd table mid-spawn); genuine
test failures are never retried, since they always produce a parsed failure.

When you are iterating on test failures after a successful build, you can also
reuse the existing build products:

```bash
bash Scripts/swift_test.sh --skip-build
```

### macOS toolchain requirement (XCTest)

Testing requires a toolchain that ships XCTest: full Xcode on macOS, or any
Linux Swift toolchain. The macOS **Command Line Tools alone are not enough** —
with `xcode-select` pointing at them, `swift test` first rejects the
auto-added `--num-workers` with a misleading `'--num-workers' is only
supported when testing with XCTest` (independent of `--filter`), and test
files importing XCTest cannot build at all. `swift_test.sh` probes the active
toolchain (`xcrun --find xctest`) and fails fast with instructions. Fix
either way:

```bash
sudo xcode-select -s /Applications/Xcode.app
# or per-invocation:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/swift_test.sh ...
```

## Runtime ABI link validation

Validate compiler runtime link names against `RuntimeABISpec`:

```bash
bash Scripts/validate_runtime_abi_links.sh
```

## TODO hygiene

Detect duplicate task IDs in `TODO.md`:

```bash
bash Scripts/check_todo_ids.sh
```

## Mutation fuzzer keyword drift check

`Scripts/mutate_diff_cases.py` classifies scanned tokens as `keyword` vs.
`identifier` using its own `IDENTIFIER_KEYWORDS` set, kept independent of the
Swift lexer for simplicity. Verify it still matches the hard-keyword
`Keyword` enum in `Sources/CompilerCore/Lexer/TokenModel.swift`:

```bash
bash Scripts/check_mutation_fuzzer_keywords.sh
```

Soft keywords (`SoftKeyword` enum, e.g. `by`, `get`, `value`) are
deliberately excluded from this comparison — they are valid identifiers in
most contexts, so treating them as keywords would misclassify real
identifier usages in the seed corpus.

## Golden update workflow

1. Run golden tests without updating fixtures:

```bash
bash Scripts/swift_test.sh --filter Golden
```

2. Review differences:

```bash
git diff -- Tests/CompilerCoreTests/GoldenCases
```

3. If the parser/sema/lowering change is intentional, update fixtures
   (the `-swift-version` flags match the CI language mode):

```bash
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6
```

4. Re-review fixture changes and ensure only intended files changed:

```bash
git status --short
git diff -- Tests/CompilerCoreTests/GoldenCases
```

5. Validate before commit:

```bash
bash Scripts/swift_test.sh
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

### Golden stability (after harness / concurrency changes)

Golden tests run each case in a dedicated worker process so `swift test --parallel` can fan them out safely. To sanity-check flakiness after harness changes, run the filter twice (or more):

```bash
bash Scripts/swift_test.sh --filter Golden
bash Scripts/swift_test.sh --filter Golden
```

## kotlinc diff workflow

Run one case:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

Run all tracked regression cases:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

For coroutine/Flow cases, `diff_kotlinc.sh` can automatically download
`kotlinx-coroutines-core-jvm` when needed (if no `--kotlinc-classpath` is
set).  
You can control the cached path and version with:

```bash
export KOTLINC_COROUTINES_VERSION=1.10.2
export KOTLINC_DEP_DIR=/path/to/.runtime-build/deps
```

Downloads are checksum-verified. For versions without a checksum baked into
the script, also set:

```bash
export KOTLINC_COROUTINES_SHA256=<expected sha256 of the jar>
```

Successful non-script reference compilations are reused across runs via
`KOTLINC_REF_CACHE_DIR` (default: `.runtime-build/kotlinc-ref-cache`, so a
second full run skips the per-case kotlinc compile entirely). Set it to
another directory to relocate the cache, or to empty to disable:

```bash
KOTLINC_REF_CACHE_DIR=/tmp/kswiftk-kotlinc-refs \
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases   # relocate
KOTLINC_REF_CACHE_DIR= \
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases   # disable
```

Each cached jar is keyed by the source name and contents, extra compiler
flags, Kotlin compiler version, JDK version, and classpath contents.
Script-style cases still execute through `kotlinc -script` on every run.
Note that `--clean-runtime-cache` removes `.runtime-build` and therefore
also the default reference cache.

kotlinc invocations run with `-XX:TieredStopAtLevel=1` (C1-only JIT,
~15-20% faster for these short-lived compiles) prepended to `JAVA_OPTS`;
caller-provided `JAVA_OPTS` flags still win on conflict. Override or
disable with `DIFF_KOTLINC_JAVA_OPTS` (empty disables). The plain `java`
runs of reference jars are unaffected (`java` does not read `JAVA_OPTS`).
Reference `java` runs disable HotSpot perf-data collection by default with
`-XX:-UsePerfData`, preventing parallel CI workers from turning a locked
`hsperfdata` diagnostic into a false stdout mismatch. Override with
`DIFF_REFERENCE_JAVA_FLAGS` (set it empty to disable the default).

Emit a machine-readable report (TSV) for CI tooling:

```bash
bash Scripts/diff_kotlinc.sh --report /tmp/diff_report.tsv Scripts/diff_cases
```

Omit `PASS` lines in logs (CI uses `DIFF_LOG_PASS=0`):

```bash
DIFF_LOG_PASS=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

You can control parallel execution. The worker count is set by `--jobs <n>`
(or the equivalent `DIFF_WORKERS` env var); `0` means serial. By default the
script runs in parallel with one worker per CPU:

```bash
# Set the worker count explicitly (0 = serial)
bash Scripts/diff_kotlinc.sh --jobs 4 Scripts/diff_cases
DIFF_WORKERS=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Disable parallel execution
bash Scripts/diff_kotlinc.sh --no-parallel Scripts/diff_cases
DIFF_PARALLEL=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

`DIFF_PARALLEL` is a boolean toggle (`0` = serial, `1` = parallel, the
default). Setting it to a number greater than 1 is deprecated — it prints a
warning and is treated as `DIFF_WORKERS`.

`DIFF_WORKERS` parallelizes within one machine. To split the case
set across several machines (CI shards the regression this way; the current
shard count is the diff-regression matrix in `.github/workflows/ci.yml`),
use interleaved sharding — case `i` runs only when `i % count == index`:

```bash
# 4 shards; each prints/reports only its ~1/4 of the cases.
DIFF_SHARD_INDEX=0 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_SHARD_INDEX=1 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
# ...and shards 2, 3 on other machines. Combine with --jobs for per-machine parallelism.

# Equivalent flags
bash Scripts/diff_kotlinc.sh --shard-index 0 --shard-count 4 Scripts/diff_cases
```

Sharding and `DIFF_WORKERS` compose: a shard still runs its slice across the
configured workers. `DIFF_SHARD_COUNT=1` (the default) disables sharding.

Render a markdown summary from that report:

```bash
bash Scripts/diff_kotlinc_ci_summary.sh --report /tmp/diff_report.tsv --summary /tmp/step_summary.md
```

## Diagnostic differential workflow

`diff_diagnostics.sh` is the first-stage diagnostic oracle. It compares only
whether `kotlinc` and `kswiftc` accept the source and, when both reject it, the
normalized set of source line numbers containing an error diagnostic. Diagnostic
wording and diagnostic codes are deliberately outside this contract.

The dedicated `Scripts/diagnostic_cases/` directory keeps negative cases out of
the behavioral `diff_kotlinc.sh` run. Use `// EXPECT-REJECT` for a case that
must be rejected by both compilers; acceptance is the default and can be stated
explicitly with `// EXPECT-ACCEPT`.

```bash
bash Scripts/diff_diagnostics.sh Scripts/diagnostic_cases
bash Scripts/diff_diagnostics.sh --report /tmp/diagnostics.tsv Scripts/diagnostic_cases
bash Scripts/diff_diagnostics.sh --self-test
```

The harness requires JDK 21 or newer by default, matching the CI Kotlin 2.3.10
lane. For local toolchains that are intentionally different, set
`DIFF_REQUIRE_JDK21=0` and record that limitation with the result.

## Precompiled stdlib artifact for diff runs

`diff_kotlinc.sh` builds a shared stdlib `.kklib` once per shard and references it from
each candidate compile. The artifact is created under `DIFF_ARTIFACT_ROOT` (default
`.artifacts/diff_kotlinc/KSwiftKStdlib.kklib`) at runtime and is never committed.

```bash
# Default: build artifact automatically and use it for all cases
bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Reuse an existing artifact (useful for local debugging or repro scripts)
DIFF_STDLIB_LIBRARY=/path/to/KSwiftKStdlib.kklib bash Scripts/diff_kotlinc.sh Scripts/diff_cases
bash Scripts/diff_kotlinc.sh --stdlib-library /path/to/KSwiftKStdlib.kklib Scripts/diff_cases

# Build a stdlib artifact manually
.build/debug/kswiftc --stdlib-only --emit library -o /tmp/KSwiftKStdlib.kklib
# Then compile a user file against it
.build/debug/kswiftc --no-stdlib --stdlib-library /tmp/KSwiftKStdlib.kklib Scripts/diff_cases/hello.kt -o /tmp/hello
```

The artifact manifest records `libraryKind: stdlib` and `stdlibManifestHash` so
mismatched compiler/stdlib versions are rejected with `KSWIFTK-LIB-0021` / `KSWIFTK-LIB-0022`.

## CI test sharding

`shard_swift_tests.sh` splits one test target across several CI jobs using the
same interleaved rule as `diff_kotlinc.sh` sharding. XCTest and Swift Testing
targets can shard documented test specifiers per method (`--mode dynamic`,
backed by `swift test list`); targets that cannot be listed reliably can shard
per-suite with source-estimated test weights (`--mode static`, backed by source
scanning). Dynamic mode can exclude suites that need separate execution:

```bash
bash Scripts/shard_swift_tests.sh --mode dynamic --list-filter '^CompilerBackendTests\.' \
  --shard-index 0 --shard-count 6
bash Scripts/shard_swift_tests.sh --mode dynamic --list-filter '^CompilerCoreTests\.' \
  --list-exclude '^CompilerCoreTests\.(FrontendParallelBenchmarkTests|SmokeTests)/' \
  --target-prefix CompilerCoreTests \
  --shard-index 0 --shard-count 6
bash Scripts/shard_swift_tests.sh --mode static --tests-dir Tests/RuntimeTests \
  --target-prefix RuntimeTests
```

## Refactoring guard metrics

`loc_report.sh` emits the metrics used as the RF-series refactor gate,
including phase-target path counts for Sema/DataFlow, TypeCheck, and legacy
CallLowerer files (see `docs/refactoring-metrics.md` for the tracked baseline
and CI artifact name):

```bash
bash Scripts/loc_report.sh > after.tsv
```

## Dead-code audit

`dead_code_audit.sh` lists `@_cdecl kk_*` runtime symbols that no compiler
path can emit (see `docs/dead-code-audit.md` for the exclusion pipeline):

```bash
bash Scripts/dead_code_audit.sh --verbose
```

The `Quarterly Audits` workflow runs this audit with the fiction audit on the
first day of January, April, July, and October. Its summary and the intermediate
audit files are retained as a 90-day GitHub Actions artifact.
