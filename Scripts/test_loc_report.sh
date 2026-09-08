#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SCANNER="$SCRIPT_DIR/loc_report_metrics.py"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-loc-report.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FIXTURE="$TEMP_DIR/dispatch_metrics.swift"
cat >"$FIXTURE" <<'SWIFT'
/*
    /* nested comment with case "alsoCommentedOut" */
    case "commentedOut"
    let ignored: Set<String> = ["commentedOut"]
*/
let prose = "case \"inside a string\""

private let names: Set<
    String
> = [
    "alpha", // a real table entry
    // "commentedOut"
    "beta",
]

private let otherNames: Set<String> = ["gamma"]

func classify(_ name: String) -> Int {
    switch name {
    case
        "alpha",
        "beta":
        return 1
    case "gamma": // a real string-literal case
        return 2
    case .fallback:
        return 3
    }
}
SWIFT

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $description (expected $expected, got $actual)" >&2
    exit 1
  fi
}

assert_equal 2 \
  "$("$PYTHON_BIN" "$SCANNER" string-switch-cases "$FIXTURE")" \
  "string-literal switch clauses ignore comments and string contents"
assert_equal 3 \
  "$("$PYTHON_BIN" "$SCANNER" inline-string-set-entries "$FIXTURE")" \
  "Set<String> entries handle multiline formatting and comments"

REPORT="$($SCRIPT_DIR/loc_report.sh)"
for metric in \
  typecheck_string_literal_switch_case_count \
  typecheck_inline_string_set_entry_count; do
  value="$(printf '%s\n' "$REPORT" | awk -F '\t' -v metric="$metric" '$1 == metric { print $3 }')"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "FAIL: loc_report.sh did not emit a numeric $metric value" >&2
    exit 1
  fi
done

echo "OK: loc_report.sh dispatch metrics scan Swift syntax and emit numeric repository values"
