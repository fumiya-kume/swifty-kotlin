# Scripts workflow

## Golden update workflow

1. Run golden tests without updating fixtures:

```bash
swift test --filter GoldenHarnessTests
```

2. Review differences:

```bash
git diff -- Tests/CompilerCoreTests/GoldenCases
```

3. If the parser/sema/lowering change is intentional, update fixtures:

```bash
UPDATE_GOLDEN=1 swift test --filter GoldenHarnessTests
```

4. Re-review fixture changes and ensure only intended files changed:

```bash
git status --short
git diff -- Tests/CompilerCoreTests/GoldenCases
```

5. Validate before commit:

```bash
swift test
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
