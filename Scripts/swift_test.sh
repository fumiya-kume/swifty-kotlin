#!/usr/bin/env bash
set -euo pipefail

parallel_mode="${SWIFT_TEST_PARALLEL:-}"
workers_override="${SWIFT_TEST_WORKERS:-}"
build_jobs_override="${SWIFT_TEST_BUILD_JOBS:-}"
junit_xml_path="${SWIFT_TEST_JUNIT_XML:-}"

detect_workers() {
    local detected

    # Linux: use nproc if available.
    if detected="$(nproc 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
        return
    fi

    # macOS: use logical cores by default to maximize XCTest worker concurrency.
    if detected="$(sysctl -n hw.logicalcpu 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
        return
    fi

    if detected="$(sysctl -n hw.physicalcpu 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
    fi
}

has_parallel_flag=false
has_workers_flag=false
has_jobs_flag=false
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
        --list-tests|-l|list|last)
            supports_parallel_flags=false
            ;;
    esac
done

declare -a command=(swift test)

if [[ "$has_jobs_flag" == false ]]; then
    build_jobs="$build_jobs_override"
    if [[ -z "$build_jobs" ]]; then
        build_jobs="$(detect_workers)"
    fi
    if [[ -n "$build_jobs" ]]; then
        command+=(-j "$build_jobs")
    fi
fi

if [[ "$supports_parallel_flags" == true ]]; then
    if [[ "$parallel_mode" == "0" || "$parallel_mode" == "false" ]]; then
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--no-parallel)
        fi
    else
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--parallel)
        fi

        if [[ "$has_workers_flag" == false ]]; then
            workers="$workers_override"
            if [[ -z "$workers" ]]; then
                workers="$(detect_workers)"
            fi
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
# ---------------------------------------------------------------------------
tmpout="$(mktemp "${TMPDIR:-/tmp}/swift_test_out.XXXXXX")"
trap 'rm -f "$tmpout"' EXIT

test_exit=0
"${command[@]}" 2>&1 | tee "$tmpout" || test_exit=$?

# ---------------------------------------------------------------------------
# Parse failures from swift test output.
# XCTest lines: "Test Case '-[Suite.Class method]' failed"
# Swift Testing lines: "FAILED: Suite/test"  or  "✗ Suite.test"
# ---------------------------------------------------------------------------
declare -a failed_tests=()

while IFS= read -r line; do
    # XCTest: "Test Case '-[CompilerCoreTests.LexerTests testFoo]' failed (0.123 seconds)"
    if [[ "$line" =~ "Test Case '-["([^]]+)"]' failed" ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
    # Swift Testing: lines starting with "FAILED:" (uppercase)
    if [[ "$line" =~ ^[[:space:]]*FAILED:[[:space:]]*(.+)$ ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
    # Swift Testing: "✗ Suite.test" or "◇ ... ✗"
    if [[ "$line" =~ [✗✖][[:space:]]+([A-Za-z0-9_.]+[A-Za-z0-9_/.:]+) ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
done < "$tmpout"

# Deduplicate while preserving order (bash 3.2 compatible — no declare -A)
declare -a unique_failures=()
_dedup_seen=""
for t in "${failed_tests[@]+"${failed_tests[@]}"}"; do
    # Use a delimited sentinel so partial names don't accidentally match
    if [[ "$_dedup_seen" != *"|${t}|"* ]]; then
        _dedup_seen="${_dedup_seen}|${t}|"
        unique_failures+=("$t")
    fi
done
unset _dedup_seen

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

    # Group by suite prefix (first component before '.' or '/').
    # Use parallel arrays for bash 3.2 compatibility (no declare -A).
    declare -a suite_order=()
    declare -a suite_entries=()
    _suite_seen=""
    for t in "${unique_failures[@]}"; do
        local suite="${t%%[./]*}"
        if [[ "$_suite_seen" != *"|${suite}|"* ]]; then
            _suite_seen="${_suite_seen}|${suite}|"
            suite_order+=("$suite")
            suite_entries+=("${t}"$'\n')
        else
            # Append to existing entry for this suite
            local idx=0
            for (( idx=0; idx < ${#suite_order[@]}; idx++ )); do
                if [[ "${suite_order[$idx]}" == "$suite" ]]; then
                    suite_entries[$idx]+="${t}"$'\n'
                    break
                fi
            done
        fi
    done
    unset _suite_seen

    local idx=0
    for (( idx=0; idx < ${#suite_order[@]}; idx++ )); do
        local suite="${suite_order[$idx]}"
        printf >&2 "\n${YELLOW}${BOLD}[%s]${RESET}\n" "$suite"
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            printf >&2 "  ${RED}✗${RESET} %s\n" "$entry"
            # Emit GitHub Actions error annotation (one per failure)
            if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
                printf '::error title=Test Failure::%s\n' "$entry"
            fi
        done <<< "${suite_entries[$idx]}"
    done

    printf >&2 "\n${RED}${BOLD}%d test(s) failed.${RESET}\n" "$count"

    # Hint for golden test failures
    for t in "${unique_failures[@]}"; do
        if [[ "$t" == *Golden* || "$t" == *golden* || "$t" == *matchesGolden* ]]; then
            printf >&2 "\n${YELLOW}Hint: golden mismatch detected — regenerate with:${RESET}\n"
            printf >&2 "  UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden\n"
            break
        fi
    done

    # Emit GitHub Actions step summary table
    if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            printf '## Swift Test Failures (%d)\n\n' "$count"
            printf '| Suite | Test |\n'
            printf '|-------|------|\n'
            for t in "${unique_failures[@]}"; do
                local suite="${t%%[./]*}"
                printf '| `%s` | `%s` |\n' "$suite" "$t"
            done
            printf '\n'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}

# ---------------------------------------------------------------------------
# Optionally emit JUnit XML (set SWIFT_TEST_JUNIT_XML=/path/report.xml)
# ---------------------------------------------------------------------------
xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&apos;}"
    printf '%s' "$value"
}

emit_junit_xml() {
    [[ -z "$junit_xml_path" ]] && return
    local count="${#unique_failures[@]}"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"
    mkdir -p "$(dirname "$junit_xml_path")"

    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<testsuites tests="%d" failures="%d" errors="0" skipped="0" timestamp="%s">\n' \
            "$count" "$count" "$timestamp"
        printf '  <testsuite name="SwiftTests" tests="%d" failures="%d" errors="0" skipped="0">\n' \
            "$count" "$count"
        for t in "${unique_failures[@]}"; do
            local classname="${t%%[./]*}"
            local testname="${t}"
            local escaped_classname
            local escaped_testname
            escaped_classname="$(xml_escape "$classname")"
            escaped_testname="$(xml_escape "$testname")"
            printf '    <testcase classname="%s" name="%s">\n' "$escaped_classname" "$escaped_testname"
            printf '      <failure message="Test failed">%s</failure>\n' "$escaped_testname"
            printf '    </testcase>\n'
        done
        printf '  </testsuite>\n'
        printf '</testsuites>\n'
    } > "$junit_xml_path"
    printf >&2 "JUnit XML written to: %s\n" "$junit_xml_path"
}

emit_failure_summary
emit_junit_xml

exit "$test_exit"
