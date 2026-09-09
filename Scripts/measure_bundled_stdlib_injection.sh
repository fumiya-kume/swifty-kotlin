#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
INJECTION_KT="${INJECTION_KT:-$ROOT_DIR/Scripts/measurement_cases/bundled_stdlib_injection.kt}"
HELLO_KT="${HELLO_KT:-$ROOT_DIR/Scripts/diff_cases/hello.kt}"

if [[ ! -x "$KSWIFTC" ]]; then
    echo "kswiftc not found or not executable: $KSWIFTC" >&2
    echo "Build kswiftc first or set KSWIFTC to an executable with the same source revision." >&2
    exit 1
fi

if [[ ! -f "$INJECTION_KT" ]]; then
    echo "bundled stdlib injection probe not found: $INJECTION_KT" >&2
    exit 1
fi

if [[ ! -f "$HELLO_KT" ]]; then
    echo "hello.kt not found: $HELLO_KT" >&2
    exit 1
fi

RUNS="${1:-5}"
if [[ ! "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
    echo "run count must be a positive integer: $RUNS" >&2
    exit 2
fi

# Keep the cache policy relative to the measured baseline.  The baseline is
# recorded in docs/refactoring-metrics.md and can be overridden for another
# compiler/input pair.
BASELINE_INJECTION_MEDIAN_MS="${BASELINE_INJECTION_MEDIAN_MS:-3472.27}"
CACHE_TRIGGER_DELTA_MS="${CACHE_TRIGGER_DELTA_MS:-100.00}"

TMPDIR="${TMPDIR:-/tmp}"
OUT_DIR="$(mktemp -d "$TMPDIR/kswiftk-bundled-injection.XXXXXX")"
ARTIFACT_DIR="$OUT_DIR/KSwiftKStdlib.kklib"
trap 'rm -rf "$OUT_DIR"' EXIT

clock_ns() {
    # Python's nanosecond wall clock is available on macOS and Linux; it does
    # not rely on a platform-specific date directive.
    python3 -c 'import time; print(time.time_ns())'
}

format_elapsed_ms() {
    awk -v start="$1" -v end="$2" 'BEGIN { printf "%.2f", (end - start) / 1000000 }'
}

print_failure() {
    local label="$1"
    local status="$2"
    local stdout_file="$3"
    local stderr_file="$4"

    printf 'Command failed (%s, exit %s)\n' "$label" "$status" >&2
    if [[ -s "$stdout_file" ]]; then
        printf '%s\n' "--- stdout ($label) ---" >&2
        cat "$stdout_file" >&2
    fi
    if [[ -s "$stderr_file" ]]; then
        printf '%s\n' "--- stderr ($label) ---" >&2
        cat "$stderr_file" >&2
    fi
}

run_compiler() {
    local label="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    shift 3

    local start end status
    start="$(clock_ns)"
    if "$KSWIFTC" "$@" >"$stdout_file" 2>"$stderr_file"; then
        end="$(clock_ns)"
    else
        status=$?
        print_failure "$label" "$status" "$stdout_file" "$stderr_file"
        return "$status"
    fi
    format_elapsed_ms "$start" "$end"
}

timed_run() {
    local label="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    shift 3

    local start end status
    start="$(clock_ns)"
    if "$@" >"$stdout_file" 2>"$stderr_file"; then
        end="$(clock_ns)"
    else
        status=$?
        print_failure "$label" "$status" "$stdout_file" "$stderr_file"
        return "$status"
    fi
    format_elapsed_ms "$start" "$end"
}

extract_total() {
    awk '$1 == "TOTAL" && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; exit }' "$1"
}

extract_phase() {
    local phase="$1"
    local file="$2"
    awk -v p="$phase" '$1 == p && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; exit }' "$file"
}

extract_subphase() {
    local phase="$1"
    local file="$2"
    awk -v p="$phase" '
        $0 ~ ("^" p "[[:space:]]") { want=1; next }
        want && /^  bundled-stdlib[[:space:]]/ { print $2; want=0; exit }
    ' "$file"
}

require_measurement() {
    local label="$1"
    local value="$2"
    local file="$3"
    if [[ -z "$value" || ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf 'Could not parse %s from compiler timing output: %s\n' "$label" "$file" >&2
        cat "$file" >&2
        exit 1
    fi
}

median() {
    if (( $# == 0 )); then
        echo 0
        return
    fi
    printf '%s\n' "$@" | sort -n | awk '
        { values[NR] = $1 }
        END {
            if (NR % 2) print values[(NR + 1) / 2]
            else printf "%.2f", (values[NR / 2] + values[NR / 2 + 1]) / 2
        }'
}

range() {
    printf '%s\n' "$@" | awk '
        NR == 1 { min = $1; max = $1; next }
        { if ($1 < min) min = $1; if ($1 > max) max = $1 }
        END { printf "%.2f..%.2f", min, max }
    '
}

common_args=(--emit kir -Xfrontend time-phases "$INJECTION_KT")
injection_cost_values=()
source_total_values=()
no_stdlib_total_values=()
source_lex_values=()
source_parse_values=()

for ((run = 1; run <= RUNS; run++)); do
    no_stdlib_stderr="$OUT_DIR/no-stdlib-$run.stderr"
    no_stdlib_stdout="$OUT_DIR/no-stdlib-$run.stdout"
    no_stdlib_output="$OUT_DIR/no-stdlib-$run.kir"
    source_stderr="$OUT_DIR/source-$run.stderr"
    source_stdout="$OUT_DIR/source-$run.stdout"
    source_output="$OUT_DIR/source-$run.kir"

    # Run the baseline first so it does not receive filesystem-cache warming
    # from the bundled source pass in the same pair.
    if no_stdlib_wall_ms="$(run_compiler "--no-stdlib run $run" "$no_stdlib_stdout" "$no_stdlib_stderr" --no-stdlib "${common_args[@]}" -o "$no_stdlib_output")"; then
        :
    else
        exit $?
    fi
    if source_wall_ms="$(run_compiler "source-injected run $run" "$source_stdout" "$source_stderr" --stdlib-from-source "${common_args[@]}" -o "$source_output")"; then
        :
    else
        exit $?
    fi

    no_stdlib_total="$(extract_total "$no_stdlib_stderr")"
    source_total="$(extract_total "$source_stderr")"
    require_measurement "--no-stdlib TOTAL (run $run)" "$no_stdlib_total" "$no_stdlib_stderr"
    require_measurement "source-injected TOTAL (run $run)" "$source_total" "$source_stderr"

    source_lex="$(extract_subphase Lex "$source_stderr")"
    source_parse="$(extract_subphase Parse "$source_stderr")"
    require_measurement "source-injected Lex bundled-stdlib (run $run)" "$source_lex" "$source_stderr"
    require_measurement "source-injected Parse bundled-stdlib (run $run)" "$source_parse" "$source_stderr"

    injection_cost="$(awk -v source="$source_total" -v baseline="$no_stdlib_total" 'BEGIN { printf "%.2f", source - baseline }')"
    source_total_values+=("$source_total")
    no_stdlib_total_values+=("$no_stdlib_total")
    injection_cost_values+=("$injection_cost")
    source_lex_values+=("$source_lex")
    source_parse_values+=("$source_parse")

    printf 'run %d: source-injected TOTAL = %s ms, --no-stdlib TOTAL = %s ms, injection difference = %s ms\n' \
        "$run" "$source_total" "$no_stdlib_total" "$injection_cost"
    printf '  wall clock: source-injected = %s ms, --no-stdlib = %s ms\n' "$source_wall_ms" "$no_stdlib_wall_ms"
    printf '  bundled subphases: Lex = %s ms, Parse = %s ms\n' "$source_lex" "$source_parse"

    # Confirm that both modes expose the same measured phase set.  The
    # per-phase values remain useful when a full-pipeline delta moves.
    for phase in LoadSources Lex Parse BuildAST Sema BuildKIR Lowerings; do
        source_phase="$(extract_phase "$phase" "$source_stderr")"
        no_stdlib_phase="$(extract_phase "$phase" "$no_stdlib_stderr")"
        require_measurement "source-injected $phase (run $run)" "$source_phase" "$source_stderr"
        require_measurement "--no-stdlib $phase (run $run)" "$no_stdlib_phase" "$no_stdlib_stderr"
        phase_delta="$(awk -v source="$source_phase" -v baseline="$no_stdlib_phase" 'BEGIN { printf "%.2f", source - baseline }')"
        printf '  phase %s: source-injected = %s ms, --no-stdlib = %s ms, difference = %s ms\n' \
            "$phase" "$source_phase" "$no_stdlib_phase" "$phase_delta"
    done
done

source_total_median="$(median "${source_total_values[@]}")"
no_stdlib_total_median="$(median "${no_stdlib_total_values[@]}")"
injection_cost_median="$(median "${injection_cost_values[@]}")"
source_lex_median="$(median "${source_lex_values[@]}")"
source_parse_median="$(median "${source_parse_values[@]}")"
injection_cost_range="$(range "${injection_cost_values[@]}")"

printf '\nMedian full-phase bundled stdlib injection cost over %d paired runs:\n' "$RUNS"
printf '  Source-injected TOTAL: %s ms\n' "$source_total_median"
printf '  --no-stdlib TOTAL:     %s ms\n' "$no_stdlib_total_median"
printf '  Injection difference:   %s ms\n' "$injection_cost_median"
printf '  Paired difference range: %s ms\n' "$injection_cost_range"
printf '\nSource-injected bundled subphase medians (diagnostic breakdown):\n'
printf '  Lex bundled-stdlib:  %s ms\n' "$source_lex_median"
printf '  Parse bundled-stdlib: %s ms\n' "$source_parse_median"

cache_trigger_ms="$(awk -v baseline="$BASELINE_INJECTION_MEDIAN_MS" -v delta="$CACHE_TRIGGER_DELTA_MS" 'BEGIN { printf "%.2f", baseline + delta }')"
if (( $(awk -v measured="$injection_cost_median" -v trigger="$cache_trigger_ms" 'BEGIN { print (measured >= trigger) ? 1 : 0 }') )); then
    printf 'Cache trigger (baseline %s ms + %s ms, >= %s ms): reached\n' \
        "$BASELINE_INJECTION_MEDIAN_MS" "$CACHE_TRIGGER_DELTA_MS" "$cache_trigger_ms" >&2
else
    printf 'Cache trigger (baseline %s ms + %s ms, >= %s ms): not reached\n' \
        "$BASELINE_INJECTION_MEDIAN_MS" "$CACHE_TRIGGER_DELTA_MS" "$cache_trigger_ms" >&2
fi

printf '\nShared stdlib artifact measurement (separate wall-clock check):\n'
artifact_build_ms="$(timed_run "stdlib-only artifact build" "$OUT_DIR/artifact_build.stdout" "$OUT_DIR/artifact_build.stderr" "$KSWIFTC" --stdlib-only --emit library -o "$ARTIFACT_DIR")"
printf '  Artifact build (stdlib-only .kklib): %s ms\n' "$artifact_build_ms"

shared_compile_ms="$(timed_run "shared candidate compile" "$OUT_DIR/shared.stdout" "$OUT_DIR/shared.stderr" "$KSWIFTC" --no-stdlib --stdlib-library "$ARTIFACT_DIR" "$HELLO_KT" -o "$OUT_DIR/shared.out")"
printf '  Shared candidate compile (hello.kt): %s ms\n' "$shared_compile_ms"
