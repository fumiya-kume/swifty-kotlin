#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "swiftlint is not installed. Install version 0.63.2 or newer." >&2
    exit 127
fi

config_path=".swiftlint.yml"
baseline_path=".swiftlint.baseline.json"

usage() {
    echo "Usage: bash Scripts/swift_lint.sh [--update-baseline]" >&2
}

if [[ "${1:-}" == "--update-baseline" ]]; then
    shift
    if [[ $# -ne 0 ]]; then
        usage
        exit 2
    fi

    swiftlint lint \
        --config "$config_path" \
        --force-exclude \
        --lenient \
        --write-baseline "$baseline_path"
    exit 0
fi

if [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

swiftlint lint \
    --config "$config_path" \
    --force-exclude \
    --baseline "$baseline_path" \
    --strict
