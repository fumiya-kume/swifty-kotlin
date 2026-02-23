# Compile Performance Baselines

This directory stores benchmark baseline JSON files for regression comparison.

## Workflow

1. Run benchmarks:
   ```bash
   bash Scripts/bench_compile.sh
   ```

2. Save the result as a baseline:
   ```bash
   bash Scripts/save_baseline.sh
   ```

3. Later, compare against the baseline:
   ```bash
   bash Scripts/bench_compile.sh --baseline Scripts/baselines/baseline_latest.json
   ```

## File Format

Baseline files are JSON arrays. Each entry contains:

| Field        | Description                                      |
|-------------|--------------------------------------------------|
| `timestamp`  | UTC timestamp of the run                         |
| `git_hash`   | Short git commit hash                            |
| `input_mode` | `single(file.kt)` or `multi(N)`                 |
| `input_files` | File name or count                              |
| `emit`       | Emit mode: `kir`, `object`, `executable`         |
| `backend`    | Backend: `synthetic-c`, `llvm-c-api`             |
| `run`        | Run number (1-based)                             |
| `total_ms`   | Total compilation time in milliseconds           |
| `phases`     | Object mapping phase name to duration in ms      |
| `exit_code`  | Compiler exit code (0 = success)                 |

### Phase Names

`LoadSources`, `Lex`, `Parse`, `BuildAST`, `SemaPasses`, `BuildKIR`, `Lowerings`, `Codegen`, `Link`
