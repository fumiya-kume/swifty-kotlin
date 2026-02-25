#!/usr/bin/env bash
set -euo pipefail

parallel_mode="${SWIFT_TEST_PARALLEL:-1}"
workers_override="${SWIFT_TEST_WORKERS:-}"

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
supports_parallel_flags=true
for arg in "$@"; do
    case "$arg" in
        --parallel|--no-parallel)
            has_parallel_flag=true
            ;;
        --num-workers|--num-workers=*)
            has_workers_flag=true
            ;;
        --list-tests|-l|list|last)
            supports_parallel_flags=false
            ;;
    esac
done

declare -a command=(swift test)

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
"${command[@]}"
