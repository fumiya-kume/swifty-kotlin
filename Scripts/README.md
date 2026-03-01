# Scripts workflow

`Scripts/swift_test.sh` wraps `swift test` with parallel execution enabled by default.

- Tune workers: `SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh`
- Disable parallel mode: `SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh`

## Style workflow

Format all Swift sources and tests:

```bash
bash Scripts/swift_format.sh
```

Lint formatting without modifying files:

```bash
bash Scripts/swift_format.sh --lint
```

Run SwiftLint with strict mode and baseline filtering:

```bash
bash Scripts/swift_lint.sh
```

Update SwiftLint baseline intentionally after reviewing violations:

```bash
bash Scripts/swift_lint.sh --update-baseline
```

## Golden update workflow

1. Run golden tests without updating fixtures:

```bash
bash Scripts/swift_test.sh --filter GoldenHarnessTests
```

2. Review differences:

```bash
git diff -- Tests/CompilerCoreTests/GoldenCases
```

3. If the parser/sema/lowering change is intentional, update fixtures:

```bash
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter GoldenHarnessTests
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

## kotlinc diff workflow

Run one case:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

Run all tracked regression cases:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

Emit a machine-readable report (TSV) for CI tooling:

```bash
bash Scripts/diff_kotlinc.sh --report /tmp/diff_report.tsv Scripts/diff_cases
```

Render a markdown summary from that report:

```bash
bash Scripts/diff_kotlinc_ci_summary.sh --report /tmp/diff_report.tsv --summary /tmp/step_summary.md
```
