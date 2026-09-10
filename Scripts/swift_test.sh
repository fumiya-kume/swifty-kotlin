#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

parallel_mode="${SWIFT_TEST_PARALLEL:-}"
workers_override="${SWIFT_TEST_WORKERS:-}"
build_jobs_override="${SWIFT_TEST_BUILD_JOBS:-}"

# XCTest ships with full Xcode and with Linux Swift toolchains, but NOT with
# the macOS Command Line Tools. On a CLT-only toolchain 'swift test' fails in
# confusing ways: the auto-added --num-workers below is rejected up front with
# "'--num-workers' is only supported when testing with XCTest" (regardless of
# what --filter selects), and even without that flag any test file importing
# XCTest cannot build. Probe the repo (not just the toolchain) here so we can
# fail fast with an actionable message instead, and skip --num-workers once
# the repo is fully migrated to Swift Testing (the flag stays unsupported
# without XCTest).
tests_use_xctest=false
grep -rq --include='*.swift' "import XCTest" "$SCRIPT_DIR/../Tests" && tests_use_xctest=true

if [[ "$tests_use_xctest" == true ]] && [[ "$(uname -s)" == "Darwin" ]] && ! xcrun --find xctest >/dev/null 2>&1; then
    {
        echo "error: the active Swift toolchain has no XCTest (xcrun --find xctest failed),"
        echo "but Tests/ still contains XCTest-based tests, so 'swift test' cannot build or run them."
        echo "On macOS this usually means xcode-select points at the Command Line Tools."
        echo "Select a full Xcode:"
        echo "  sudo xcode-select -s /Applications/Xcode.app"
        echo "or prefix the command with:"
        echo "  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
    } >&2
    exit 1
fi

xctest_available="$tests_use_xctest"

has_parallel_flag=false
has_workers_flag=false
has_jobs_flag=false
has_swift_testing_width_flag=false
supports_parallel_flags=true
for arg in "$@"; do
    case "$arg" in
        --parallel|--no-parallel)
            has_parallel_flag=true
            ;;
        --num-workers|--num-workers=*)
            has_workers_flag=true
            ;;
        -j|--jobs|--jobs=*)
            has_jobs_flag=true
            ;;
        --experimental-maximum-parallelization-width|--experimental-maximum-parallelization-width=*)
            has_swift_testing_width_flag=true
            ;;
        --list-tests|-l|list|last)
            supports_parallel_flags=false
            ;;
    esac
done

declare -a command=(swift test)

# Select the same build system used by build_swift_tests.sh so per-test-target
# products (swiftbuild) and their compilation cache are reused.
kswiftk_append_build_system_flag command

# When running a single test target product (required with swiftbuild's
# per-test-target products), tell `swift test` which product to load. Without
# this `swift test --skip-build` looks for the all-in-one PackageTests bundle.
test_product="${SWIFT_TEST_PRODUCT:-}"
if [[ -n "$test_product" ]]; then
    command+=(--test-product "$test_product")
fi

# Enable swiftbuild's integrated compilation cache if requested.
kswiftk_setup_compile_cache_env

# Append compilation-caching flags if enabled so `swift test --skip-build`
# uses the same -Xswiftc flags as the preceding build_swift_tests.sh call.
# Without identical flags SwiftPM may invalidate the incremental cache and
# rebuild from scratch.
kswiftk_append_compile_cache_flags command

# -j and --num-workers both fall back to the same autodetected core count;
# detect_workers forks nproc/sysctl, so cache its result across both callers
# instead of probing twice. Assigns through a nameref (not a command
# substitution) so the cache actually persists across calls: `$(...)` runs in
# a subshell and would discard the "already detected" flag on return.
default_workers=""
default_workers_detected=false
resolve_worker_count() {
    local -n __out="$1"
    local override="$2"
    if [[ -n "$override" ]]; then
        __out="$override"
        return
    fi
    if [[ "$default_workers_detected" == false ]]; then
        default_workers="$(detect_workers)"
        default_workers_detected=true
    fi
    __out="$default_workers"
}

if [[ "$has_jobs_flag" == false ]]; then
    resolve_worker_count build_jobs "$build_jobs_override"
    if [[ -n "$build_jobs" ]]; then
        command+=(-j "$build_jobs")
    fi
fi

if [[ "$supports_parallel_flags" == true ]]; then
    # --num-workers only controls XCTest. Swift Testing (including Golden)
    # needs its own width, even when the repo has no XCTest imports at all.
    # Preserve explicit Swift Testing CLI/environment overrides and let
    # --no-parallel disable parallelization in the runner as usual.
    if [[ -n "$workers_override" && "$has_swift_testing_width_flag" == false \
        && -z "${SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH:-}" ]]; then
        if ! [[ "$workers_override" =~ ^[1-9][0-9]*$ ]]; then
            echo "error: SWIFT_TEST_WORKERS must be a positive integer" >&2
            exit 1
        fi
        export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH="$workers_override"
    fi

    if [[ "$parallel_mode" == "0" || "$parallel_mode" == "false" ]]; then
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--no-parallel)
        fi
    else
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--parallel)
        fi

        if [[ "$has_workers_flag" == false && "$xctest_available" == true ]]; then
            resolve_worker_count workers "$workers_override"
            if [[ -n "$workers" ]]; then
                command+=(--num-workers "$workers")
            fi
        fi
    fi
fi

command+=("$@")

# ---------------------------------------------------------------------------
# Color helpers (disabled in CI unless NO_COLOR is unset and terminal present)
# ---------------------------------------------------------------------------
if [[ -t 2 && "${NO_COLOR:-}" == "" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

# ---------------------------------------------------------------------------
# Run swift test, capturing output while streaming it to the terminal.
# Parse failure lines to build a grouped summary.
#
# swift-corelibs-foundation's Process.run() is not fully race-free on Linux
# even with CommandRunner's launch-window lock (Sources/CompilerCore/Driver/
# CommandRunner.swift): that lock only serializes CommandRunner's own spawns
# against each other, but unrelated threads in the same test process (pipe
# drain threads, other tests' file I/O) can still mutate the fd table while a
# spawn's /proc/self/fd scan is in flight, occasionally SIGSEGV-ing the whole
# xctest process. SwiftPM reports that as a generic "exited with unexpected
# signal code" error with exit code 1 - indistinguishable from a real failure
# by exit code alone, but no per-test failure line is ever printed for it. So
# retry only when a crash signature is present AND no test failure was
# parsed, to avoid ever masking a genuine regression.
# ---------------------------------------------------------------------------

# Parse failed test names out of swift test's output, deduplicated in order.
# XCTest lines:        "Test Case '-[Suite.Class method]' failed"
# Swift Testing lines:  "FAILED: Suite/test"  or  "✗ Suite.test"
# A cheap substring check gates each regex so the (vast majority of) lines
# that can't match skip the more expensive pattern match entirely.
parse_failed_tests() {
    local -n __out="$1"
    local line match
    local -A seen=()
    while IFS= read -r line; do
        match=""
        if [[ "$line" == *"Test Case '-["* ]] && [[ "$line" =~ "Test Case '-["([^]]+)"]' failed" ]]; then
            match="${BASH_REMATCH[1]}"
        elif [[ "$line" == *FAILED:* ]] && [[ "$line" =~ ^[[:space:]]*FAILED:[[:space:]]*(.+)$ ]]; then
            match="${BASH_REMATCH[1]}"
        elif [[ "$line" == *[✗✖]* ]] && [[ "$line" =~ [✗✖][[:space:]]+([A-Za-z0-9_.]+[A-Za-z0-9_/.:]+) ]]; then
            match="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$match" && -z "${seen[$match]:-}" ]]; then
            seen[$match]=1
            __out+=("$match")
        fi
    done < "$tmpout"
}

max_attempts=3
attempt=0

while true; do
    attempt=$(( attempt + 1 ))
    tmpout="$(mktemp "${TMPDIR:-/tmp}/swift_test_out.XXXXXX")"
    trap 'rm -f "$tmpout"' EXIT

    test_exit=0
    "${command[@]}" 2>&1 | tee "$tmpout" || test_exit=$?

    declare -a unique_failures=()
    parse_failed_tests unique_failures

    if (( test_exit != 0 )) && (( ${#unique_failures[@]} == 0 )) \
        && grep -qE '\*\*\* Signal [0-9]+:|Program crashed:|exited with unexpected signal code' "$tmpout"; then
        # Surface an annotation (not just a stderr line) so recurrence of this
        # infra flake is countable from the Actions UI across runs/jobs.
        if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
            printf '::warning title=Test process crash (retried)::attempt %d/%d crashed with a signal; no test failure was reported\n' "$attempt" "$max_attempts"
        fi
        if (( attempt < max_attempts )); then
            echo "swift_test.sh: test process crashed with a signal (attempt $attempt/$max_attempts, no test failure was reported); retrying..." >&2
            rm -f "$tmpout"
            continue
        fi
        echo "swift_test.sh: test process crashed with a signal on all $attempt attempts; giving up." >&2
    fi
    break
done

# ---------------------------------------------------------------------------
# Emit grouped failure summary
# ---------------------------------------------------------------------------
emit_failure_summary() {
    local count="${#unique_failures[@]}"
    if (( count == 0 )); then
        if (( test_exit == 0 )); then
            printf >&2 "\n${GREEN}${BOLD}All tests passed.${RESET}\n"
        fi
        return
    fi

    printf >&2 "\n${RED}${BOLD}── Test Failures (%d) ──────────────────────────────────────────${RESET}\n" "$count"

    # Group by suite prefix (first component before '.' or '/'); suite_of_test
    # keeps each test's suite in unique_failures order for reuse below.
    local suite
    local -a suite_order=()
    local -A suite_entries=()
    local -a suite_of_test=()
    for t in "${unique_failures[@]}"; do
        suite="${t%%[./]*}"
        suite_of_test+=("$suite")
        if [[ -z "${suite_entries[$suite]:-}" ]]; then
            suite_order+=("$suite")
        fi
        suite_entries[$suite]+="${t}"$'\n'
    done

    for suite in "${suite_order[@]}"; do
        printf >&2 "\n${YELLOW}${BOLD}[%s]${RESET}\n" "$suite"
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            printf >&2 "  ${RED}✗${RESET} %s\n" "$entry"
            # Emit GitHub Actions error annotation (one per failure)
            if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
                printf '::error title=Test Failure::%s\n' "$entry"
            fi
        done <<< "${suite_entries[$suite]}"
    done

    printf >&2 "\n${RED}${BOLD}%d test(s) failed.${RESET}\n" "$count"

    # Hint for golden test failures
    for t in "${unique_failures[@]}"; do
        if [[ "$t" == *Golden* || "$t" == *golden* ]]; then
            printf >&2 "\n${YELLOW}Hint: golden mismatch detected — regenerate with:${RESET}\n"
            printf >&2 "  %s\n" "$GOLDEN_UPDATE_CMD"
            break
        fi
    done

    # Emit GitHub Actions step summary table
    if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            printf '## Swift Test Failures (%d)\n\n' "$count"
            printf '| Suite | Test |\n'
            printf '|-------|------|\n'
            for i in "${!unique_failures[@]}"; do
                printf '| `%s` | `%s` |\n' "${suite_of_test[$i]}" "${unique_failures[$i]}"
            done
            printf '\n'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}

emit_failure_summary

exit "$test_exit"
