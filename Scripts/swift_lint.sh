#!/usr/bin/env bash
set -euo pipefail

repo_root="$PWD"
if [[ ! -f "$repo_root/.swiftlint.yml" || ! -d "$repo_root/Scripts" ]]; then
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
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

normalize_baseline_paths() {
    local input_path="$1"
    local output_path="$2"
    local mode="$3"

    python3 - "$input_path" "$output_path" "$repo_root" "$mode" <<'PY'
import json
import os
import sys

input_path, output_path, repo_root, mode = sys.argv[1:5]

with open(input_path, "r", encoding="utf-8") as f:
    baseline = json.load(f)

def relativize(path: str) -> str:
    for marker in ("Sources/", "Tests/", "Scripts/"):
        index = path.find(marker)
        if index != -1:
            return path[index:]
    if os.path.isabs(path):
        try:
            return os.path.relpath(path, repo_root)
        except ValueError:
            return path
    return path

for entry in baseline:
    location = entry.get("violation", {}).get("location", {})
    file_path = location.get("file")
    if not file_path:
        continue
    relative_path = relativize(file_path)
    if mode == "relative":
        location["file"] = relative_path
    else:
        location["file"] = os.path.join(repo_root, relative_path)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(baseline, f, separators=(",", ":"))
PY
}

if [[ "${1:-}" == "--update-baseline" ]]; then
    shift
    if [[ $# -ne 0 ]]; then
        usage
        exit 2
    fi

    raw_baseline="$(mktemp)"
    swiftlint lint \
        --config "$config_path" \
        --force-exclude \
        --lenient \
        --write-baseline "$raw_baseline"
    normalize_baseline_paths "$raw_baseline" "$baseline_path" "relative"
    rm -f "$raw_baseline"
    exit 0
fi

if [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

runtime_baseline="$(mktemp)"
trap 'rm -f "$runtime_baseline"' EXIT
normalize_baseline_paths "$baseline_path" "$runtime_baseline" "absolute"
swiftlint lint \
    --config "$config_path" \
    --force-exclude \
    --baseline "$runtime_baseline" \
    --strict
