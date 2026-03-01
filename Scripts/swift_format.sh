#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "swiftformat is not installed. Install version 0.59.1 or newer." >&2
    exit 127
fi

usage() {
    echo "Usage: bash Scripts/swift_format.sh [--lint]" >&2
}

mode="format"
if [[ "${1:-}" == "--lint" ]]; then
    mode="lint"
    shift
fi

if [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

if [[ "$mode" == "lint" ]]; then
    swiftformat --lint --config .swiftformat Sources Tests
else
    swiftformat --config .swiftformat Sources Tests
fi
