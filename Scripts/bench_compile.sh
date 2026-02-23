#!/usr/bin/env bash
# bench_compile.sh — Compile-performance benchmark harness for KSwiftK.
#
# Usage:
#   bash Scripts/bench_compile.sh [options]
#
# Options:
#   --input <file|dir>   Input file or directory (default: Scripts/diff_cases)
#   --runs <N>           Number of runs per configuration (default: 3)
#   --output <path>      Output directory for results (default: .bench_results)
#   --format <tsv|json|both>  Output format (default: both)
#   --baseline <path>    Path to baseline JSON for regression comparison
#   --help               Show this help message
#
# Each configuration is a combination of:
#   --emit kir | object | executable
#   -Xir backend=synthetic-c | backend=llvm-c-api
#
# Results are saved as TSV and/or JSON in the output directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
INPUT="${REPO_ROOT}/Scripts/diff_cases"
RUNS=3
OUTPUT_DIR="${REPO_ROOT}/.bench_results"
FORMAT="both"
BASELINE=""
KSWIFTC="${REPO_ROOT}/.build/release/kswiftc"

print_usage() {
    sed -n '2,/^$/s/^# //p' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)   INPUT="$2";      shift 2 ;;
        --runs)    RUNS="$2";       shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --format)  FORMAT="$2";     shift 2 ;;
        --baseline) BASELINE="$2";  shift 2 ;;
        --help)    print_usage;     exit 0 ;;
        *)         echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# Build release binary if it doesn't exist.
if [[ ! -x "$KSWIFTC" ]]; then
    echo "Building release binary..."
    (cd "$REPO_ROOT" && swift build -c release 2>&1 | tail -1)
fi

# Collect input files.
declare -a INPUT_FILES=()
if [[ -d "$INPUT" ]]; then
    while IFS= read -r f; do
        INPUT_FILES+=("$f")
    done < <(find "$INPUT" -name '*.kt' -type f | sort)
else
    INPUT_FILES+=("$INPUT")
fi

if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
    echo "Error: No .kt files found in $INPUT" >&2
    exit 1
fi

echo "Benchmark configuration:"
echo "  Input files:  ${#INPUT_FILES[@]}"
echo "  Runs:         $RUNS"
echo "  Output:       $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

EMIT_MODES=(kir object executable)
BACKENDS=(synthetic-c llvm-c-api)

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
GIT_HASH=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Temporary directory for compiler output.
TMPDIR_BENCH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BENCH"' EXIT

# TSV header
TSV_FILE="${OUTPUT_DIR}/bench_${TIMESTAMP}.tsv"
JSON_FILE="${OUTPUT_DIR}/bench_${TIMESTAMP}.json"

write_tsv_header() {
    printf "timestamp\tgit_hash\tinput_mode\tinput_files\temit\tbackend\trun\ttotal_ms\tLoadSources\tLex\tParse\tBuildAST\tSemaPasses\tBuildKIR\tLowerings\tCodegen\tLink\n" > "$TSV_FILE"
}

# JSON accumulator
declare -a JSON_RECORDS=()

# Determine input mode label
if [[ -d "$INPUT" ]]; then
    INPUT_LABEL="multi(${#INPUT_FILES[@]})"
else
    INPUT_LABEL="single($(basename "$INPUT"))"
fi

run_single_bench() {
    local emit="$1"
    local backend="$2"
    local run_num="$3"
    local out_path="${TMPDIR_BENCH}/out_${emit}_${backend}_${run_num}"

    local -a cmd=("$KSWIFTC")
    for f in "${INPUT_FILES[@]}"; do
        cmd+=("$f")
    done
    cmd+=("--emit" "$emit")
    cmd+=("-Xir" "backend=${backend}")
    cmd+=("-Xfrontend" "time-phases")
    cmd+=("-o" "$out_path")

    # Capture stderr (where time-phases output goes)
    local stderr_file="${TMPDIR_BENCH}/stderr_${emit}_${backend}_${run_num}.txt"

    # Run and capture exit code; non-zero exits are tolerated for benchmarking
    local exit_code=0
    "${cmd[@]}" 2>"$stderr_file" || exit_code=$?

    # Parse phase timing from stderr
    local total_ms=0
    local -A phase_ms=()
    local phases=(LoadSources Lex Parse BuildAST SemaPasses BuildKIR Lowerings Codegen Link)
    for p in "${phases[@]}"; do
        phase_ms[$p]="0.00"
    done

    # Parse the timing table from stderr output
    while IFS= read -r line; do
        for p in "${phases[@]}"; do
            if echo "$line" | grep -q "^${p} "; then
                local ms
                ms=$(echo "$line" | awk '{print $2}')
                phase_ms[$p]="$ms"
            fi
        done
        if echo "$line" | grep -q "^TOTAL "; then
            total_ms=$(echo "$line" | awk '{print $2}')
        fi
    done < "$stderr_file"

    # Build file list for TSV
    local file_list
    if [[ ${#INPUT_FILES[@]} -eq 1 ]]; then
        file_list="$(basename "${INPUT_FILES[0]}")"
    else
        file_list="${#INPUT_FILES[@]}_files"
    fi

    # Write TSV row
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s" \
        "$TIMESTAMP" "$GIT_HASH" "$INPUT_LABEL" "$file_list" \
        "$emit" "$backend" "$run_num" "$total_ms" >> "$TSV_FILE"
    for p in "${phases[@]}"; do
        printf "\t%s" "${phase_ms[$p]}" >> "$TSV_FILE"
    done
    printf "\n" >> "$TSV_FILE"

    # Accumulate JSON record
    local json_phases=""
    for p in "${phases[@]}"; do
        if [[ -n "$json_phases" ]]; then json_phases+=", "; fi
        json_phases+="\"${p}\": ${phase_ms[$p]}"
    done

    JSON_RECORDS+=("{\"timestamp\": \"${TIMESTAMP}\", \"git_hash\": \"${GIT_HASH}\", \"input_mode\": \"${INPUT_LABEL}\", \"input_files\": \"${file_list}\", \"emit\": \"${emit}\", \"backend\": \"${backend}\", \"run\": ${run_num}, \"total_ms\": ${total_ms}, \"phases\": {${json_phases}}, \"exit_code\": ${exit_code}}")

    # Progress indicator
    if [[ $exit_code -eq 0 ]]; then
        printf "  emit=%-12s backend=%-14s run=%d  total=%s ms\n" "$emit" "$backend" "$run_num" "$total_ms"
    else
        printf "  emit=%-12s backend=%-14s run=%d  total=%s ms (exit=%d)\n" "$emit" "$backend" "$run_num" "$total_ms" "$exit_code"
    fi
}

# Run benchmarks
write_tsv_header

for emit in "${EMIT_MODES[@]}"; do
    for backend in "${BACKENDS[@]}"; do
        echo "--- emit=${emit} backend=${backend} ---"
        for run in $(seq 1 "$RUNS"); do
            run_single_bench "$emit" "$backend" "$run"
        done
    done
done

# Write JSON output
if [[ "$FORMAT" == "json" || "$FORMAT" == "both" ]]; then
    {
        echo "["
        for i in "${!JSON_RECORDS[@]}"; do
            if [[ $i -gt 0 ]]; then echo ","; fi
            echo "  ${JSON_RECORDS[$i]}"
        done
        echo "]"
    } > "$JSON_FILE"
fi

# Remove TSV if only JSON requested
if [[ "$FORMAT" == "json" ]]; then
    rm -f "$TSV_FILE"
fi

# Remove JSON if only TSV requested
if [[ "$FORMAT" == "tsv" ]]; then
    rm -f "$JSON_FILE"
fi

echo ""
echo "Results saved:"
if [[ "$FORMAT" != "json" ]]; then echo "  TSV:  $TSV_FILE"; fi
if [[ "$FORMAT" != "tsv" ]]; then echo "  JSON: $JSON_FILE"; fi

# Baseline comparison
if [[ -n "$BASELINE" && -f "$BASELINE" ]]; then
    echo ""
    echo "===== Regression Comparison (vs baseline) ====="
    echo ""

    # Simple comparison: show total_ms deltas per configuration
    # Requires python3 or jq for JSON parsing; fallback to basic approach
    if command -v python3 &>/dev/null && [[ -f "$JSON_FILE" ]]; then
        python3 - "$BASELINE" "$JSON_FILE" <<'PYEOF'
import json, sys

def load_results(path):
    with open(path) as f:
        data = json.load(f)
    # Group by (emit, backend) and compute median total_ms
    groups = {}
    for rec in data:
        key = (rec["emit"], rec["backend"])
        groups.setdefault(key, []).append(rec["total_ms"])
    medians = {}
    for key, vals in groups.items():
        vals.sort()
        mid = len(vals) // 2
        medians[key] = vals[mid] if len(vals) % 2 == 1 else (vals[mid - 1] + vals[mid]) / 2
    return medians

baseline = load_results(sys.argv[1])
current = load_results(sys.argv[2])

header = f"{'emit':<14} {'backend':<16} {'baseline_ms':>12} {'current_ms':>12} {'delta_ms':>10} {'delta_%':>8}"
print(header)
print("-" * len(header))

all_keys = sorted(set(list(baseline.keys()) + list(current.keys())))
for key in all_keys:
    emit, backend = key
    b = baseline.get(key, 0)
    c = current.get(key, 0)
    delta = c - b
    pct = (delta / b * 100) if b > 0 else 0
    marker = "  <<< REGRESSION" if pct > 10 else ""
    print(f"{emit:<14} {backend:<16} {b:>12.2f} {c:>12.2f} {delta:>+10.2f} {pct:>+7.1f}%{marker}")
PYEOF
    else
        echo "(python3 not available; skipping detailed comparison)"
        echo "Baseline: $BASELINE"
        echo "Current:  $JSON_FILE"
    fi
fi

echo ""
echo "Done."
