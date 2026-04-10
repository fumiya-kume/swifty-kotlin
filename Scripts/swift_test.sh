#!/usr/bin/env bash
set -euo pipefail

parallel_mode="${SWIFT_TEST_PARALLEL:-1}"
workers_override="${SWIFT_TEST_WORKERS:-}"
build_jobs_override="${SWIFT_TEST_BUILD_JOBS:-}"

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
"${command[@]}"
