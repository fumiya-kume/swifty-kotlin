# Refactoring Metrics

Baseline refreshed on 2026-08-14 for the RF-GOV-002 state that publishes `Scripts/loc_report.sh` as a CI artifact.

## LoC Guard

Command:

```bash
bash Scripts/loc_report.sh
```

`loc_report.sh` itself is compatible with macOS's system Bash 3.2 and uses
Python 3 for the syntax-aware name-dispatch metrics. Other scripts under
`Scripts/` may require Bash 4+.

The KSP-691 task note captured `__kk_` 390 / `kk_` 1,770 on 2026-08-12;
this table is the current post-fetch baseline after subsequent master changes.

Output:

```tsv
metric	scope	value
loc_by_directory	.	862
loc_by_directory	.agents	167
loc_by_directory	.github	783
loc_by_directory	Scripts	28895
loc_by_directory	Sources	298413
loc_by_directory	Tests	250891
loc_by_directory	docs	3592
loc_by_path_prefix	Sources/CompilerCore/Sema/DataFlow	68998
loc_by_path_prefix	Sources/CompilerCore/Sema/TypeCheck	36986
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	50298
call_lowerer_legacy_total_lines	Sources/CompilerCore/KIR/CallLowerer+Legacy*.swift	3182
kir_lowering_todo_fixme_count	Sources/CompilerCore/{KIR,Lowering}/*.swift	0
kk_literal_count	Swift/Kotlin sources	9104
kk_cdecl_count	Sources/Runtime/@_cdecl("kk_*")	1582
__kk_cdecl_count	Sources/Runtime/@_cdecl("__kk_*")	463
interner_resolve_literal_comparison_count	Swift sources	728
typecheck_interner_resolve_literal_comparison_count	Sources/CompilerCore/Sema/TypeCheck	78
typecheck_string_literal_switch_case_count	Sources/CompilerCore/Sema/TypeCheck/*.swift	402
typecheck_inline_string_set_entry_count	Sources/CompilerCore/Sema/TypeCheck/*.swift	142
```

Notes:
- `loc_by_directory` counts physical lines in git-tracked files, grouped by top-level directory.
- `loc_by_path_prefix` tracks phase-specific line-count targets that are too coarse at top-level directory granularity.
- `kk_literal_count` counts Swift/Kotlin string literals beginning with `"kk_`.
- `kk_cdecl_count` counts distinct `@_cdecl("kk_...")` names in tracked Swift files under `Sources/Runtime/`.
- `__kk_cdecl_count` counts distinct `@_cdecl("__kk_...")` names in the same scope. These two metrics count bridge definitions only; they do not count references, `RuntimeABISpec` entries, generated files, fixtures, docs, or arbitrary string literals.
- `kir_lowering_todo_fixme_count` counts remaining `TODO` / `FIXME` markers in `Sources/CompilerCore/KIR/*.swift` and `Sources/CompilerCore/Lowering/*.swift`.
- `call_lowerer_legacy_total_lines` and `typecheck_interner_resolve_literal_comparison_count` track RF4 reduction goals directly.

## Name Dispatch Metrics

ARCH-022 adds two syntax-aware metrics for the remaining name-based Sema
dispatch surface. The scanner reads tracked Swift files under
`Sources/CompilerCore/Sema/TypeCheck/` and removes comments before tokenizing,
so examples in documentation or comments do not inflate the count.

| Metric | Definition | Baseline (2026-09-08) |
|---|---|---:|
| `typecheck_string_literal_switch_case_count` | `case` clauses whose first pattern token is a string literal; a clause with multiple comma-separated literals counts once | 402 |
| `typecheck_inline_string_set_entry_count` | Direct string literal elements in explicit `Set<String> = [...]` array literals; non-literal expressions and nested arrays are excluded | 142 |

The baseline was measured at base revision `a72cc373f859aaf408c6a4e9510404a1e21c92dc`
with:

```bash
bash Scripts/loc_report.sh
```

The scanner honors the hash count in extended string delimiters and skips
quoted strings nested inside interpolation expressions, so string contents do
not create false `case` or table-entry matches. The fixture is parsed with
`swiftc -parse` before its metric assertions run.

The scanner regression fixture covers nested comments, string contents,
multiline type formatting, inline comments, multiple table entries, and a
non-string switch case:

```bash
bash Scripts/test_loc_report.sh
```

If the Python scanner cannot run, `loc_report.sh` exits nonzero instead of
emitting a successful-looking metric row.

CI publishes the same TSV from the `refactoring-metrics` job as artifact `refactoring-metrics-${run_id}` and mirrors it into the job summary.

## KIR + Lowering TODO/FIXME Triage

RF3/RF4 後の `KIR + Lowering` 実測では、残存 marker は 4 件でした。RF-LOWER-002 の `CollectionLiteralLoweringPass+PreScan.swift` 単純名分類 TODO、RF-LOWER-003 の sequence plus/minus 共通化、DEBT-KIR-001 の safe-call virtual dispatch 再有効化は修正済みで、guard metric の現在値は 0 件です。

| Classification | Count | Items |
|---|---:|---|
| Resolved | 4 | `CollectionLiteralLoweringPass+PreScan.swift` の stdlib type 判定を FQN ベースへ変更、RF-LOWER-003 の sequence plus/minus 共通化 2 件、DEBT-KIR-001 の safe-call virtual dispatch 再有効化 1 件 |
| Taskized | 0 | なし |
| Delete | 0 | 削除のみで閉じられる marker はなし |

## jscpd Guard

Report-only command used for the combined `.jscpd.json` baseline:

```bash
jscpd --config .jscpd.json --silent --reporters json --output /tmp/kswiftk-jscpd-report --exitCode 0
```

Combined `Sources/` + `Tests/` result:

| Metric | Value |
|---|---:|
| Files | 1522 |
| Lines | 329178 |
| Clones | 3516 |
| Duplicated lines | 40795 |
| Duplicated line % | 12.39% |
| Duplicated tokens | 441450 |
| Duplicated token % | 14.30% |

Tests-only observation with the same `minLines=5` / `minTokens=50` settings:

| Metric | Value |
|---|---:|
| Files | 999 |
| Lines | 159829 |
| Clones | 2089 |
| Duplicated lines | 22163 |
| Duplicated line % | 13.87% |
| Duplicated tokens | 254999 |
| Duplicated token % | 16.55% |

The CI observation step is report-only. Set a Tests-specific threshold after enough runs confirm a stable target.

## Bundled Stdlib Injection Cost

The injection cost is the paired full-phase difference, not one bundled-source
subtotal:

```text
source-injected TOTAL - --no-stdlib TOTAL
```

Both commands use the same compiler binary, input, `--emit kir` mode, and
`-Xfrontend time-phases` flag. `TOTAL` is the sum of the `PhaseTimer` phase
records for that mode. The script computes one difference per pair and uses the
median of those differences as the baseline. The `Lex`/`Parse`
`bundled-stdlib` subrecords remain in the report as a diagnostic breakdown; they
are not the injection-cost definition. The probe is the stdlib-independent
[`Scripts/measurement_cases/bundled_stdlib_injection.kt`](../Scripts/measurement_cases/bundled_stdlib_injection.kt),
so the same source can complete under plain `--no-stdlib`.

Controlled baseline captured on 2026-09-08 from base
`a72cc373f859aaf408c6a4e9510404a1e21c92dc`:

```bash
KSWIFTC=/private/tmp/swifty-todo-state001-base/.build/debug/kswiftc \
  /opt/homebrew/bin/bash Scripts/measure_bundled_stdlib_injection.sh 5
```

The exact-base debug compiler is SHA-256
`ab80c404d9a82f2b63df4b6659984995bd5d80ac187df8f238847038441ae54b`. The
measurement ran on macOS 27.0 (Darwin 27.0, arm64), Apple Swift 6.4, and GNU
Bash 5.3. The script's portable wall-clock helper used `/usr/bin/python3`
3.9.6; the exclusive batch coordinator used `/opt/homebrew/bin/python3`
3.14.7. The five paired runs were executed baseline first and source-injected
second under the batch's exclusive benchmark lock.

| Run | Source-injected TOTAL (ms) | `--no-stdlib` TOTAL (ms) | Difference (ms) | Lex bundled-stdlib (ms) | Parse bundled-stdlib (ms) |
|---:|---:|---:|---:|---:|---:|
| 1 | 3700.97 | 216.39 | 3484.58 | 178.30 | 24.35 |
| 2 | 3661.40 | 206.19 | 3455.21 | 179.30 | 22.63 |
| 3 | 3674.87 | 202.60 | 3472.27 | 176.72 | 22.56 |
| 4 | 3682.46 | 202.35 | 3480.11 | 183.46 | 21.28 |
| 5 | 3648.78 | 200.28 | 3448.50 | 169.18 | 21.12 |

The full-phase injection baseline is **3472.27 ms** (paired-difference range
**3448.50–3484.58 ms**). The cache work trigger remains a regression of
**+100.00 ms** or more from this baseline, so the trigger for this matched
compiler/input/options tuple is median paired difference **≥ 3572.27 ms**.
Re-measure the baseline when the compiler binary, input, emit mode, or frontend
flags change; the absolute threshold is not portable across those changes.

The same script also reports the stdlib-only `.kklib` build time and the shared
candidate compile time for `hello.kt` with
`--no-stdlib --stdlib-library <artifact>`. Those are a separate wall-clock
check for the shared diff path and do not enter the injection-cost baseline.

## Migration API Runtime Benchmark

KSP-INF-007 baseline captured on 2026-07-23 with a debug `kswiftc` build on Linux (x86_64).

Command:

```bash
bash Scripts/benchmark_stdlib_hof.sh
```

The harness compiles each Kotlin source in `Scripts/benchmark_cases/` with `kswiftc` and reports the median wall-clock execution time over 7 runs.

| Case | Workload | Median (ms) |
|---|---|---:|
| filter | `(1..100000).filter { it > 50000 }.sum()` | 63 |
| map | `(1..100000).map { it * 2 }.sum()` | 111 |
| sort | `(1..100000).toList().sorted().first()` | 94 |
| for_in_range | `for (i in 1..1000000) sum += i` | 1236 |

These numbers are the reference for "performance reasons to keep Swift residuals". Any migration of stdlib internals to Swift must beat the relevant baseline.
