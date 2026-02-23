#!/usr/bin/env bash
# save_baseline.sh — Save a benchmark baseline for regression comparison.
#
# Usage:
#   bash Scripts/save_baseline.sh [--dir <bench_results_dir>]
#
# Copies the latest bench JSON result into Scripts/baselines/ with a
# descriptive name so it can be committed and used for future comparisons.
#
# Example workflow:
#   bash Scripts/bench_compile.sh
#   bash Scripts/save_baseline.sh
#   # Later, compare against baseline:
#   bash Scripts/bench_compile.sh --baseline Scripts/baselines/baseline_latest.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_DIR="${REPO_ROOT}/.bench_results"
BASELINES_DIR="${SCRIPT_DIR}/baselines"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) BENCH_DIR="$2"; shift 2 ;;
        *)     echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Find the latest JSON result.
LATEST_JSON=$(ls -t "$BENCH_DIR"/bench_*.json 2>/dev/null | head -1)

if [[ -z "$LATEST_JSON" ]]; then
    echo "Error: No benchmark JSON results found in $BENCH_DIR" >&2
    echo "Run 'bash Scripts/bench_compile.sh' first." >&2
    exit 1
fi

mkdir -p "$BASELINES_DIR"

GIT_HASH=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

BASELINE_NAME="baseline_${TIMESTAMP}_${GIT_HASH}.json"
cp "$LATEST_JSON" "${BASELINES_DIR}/${BASELINE_NAME}"

# Also maintain a "latest" symlink / copy.
cp "$LATEST_JSON" "${BASELINES_DIR}/baseline_latest.json"

echo "Baseline saved:"
echo "  ${BASELINES_DIR}/${BASELINE_NAME}"
echo "  ${BASELINES_DIR}/baseline_latest.json (copy)"
echo ""
echo "To compare future runs against this baseline:"
echo "  bash Scripts/bench_compile.sh --baseline Scripts/baselines/baseline_latest.json"
