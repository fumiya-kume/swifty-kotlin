#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: diff_kotlinc_ci_summary.sh --report <path> [--summary <path>] [--format <tsv|json>] [--artifact-root <path>] [--diff-lines <n>]

Options:
  --report <path>        TSV report emitted by Scripts/diff_kotlinc.sh
  --summary <path>       Optional markdown output path
  --format <tsv|json>    Output format: tsv (default) or json
  --artifact-root <path> Root directory for failure artifacts (used for detailed diffs)
  --diff-lines <n>       Max diff lines to embed per case (default: 30, 0 = unlimited)
  -h, --help             Show this help
USAGE
}

REPORT_PATH=""
SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"
OUTPUT_FORMAT="tsv"
ARTIFACT_ROOT="${DIFF_ARTIFACT_ROOT:-}"
DIFF_MAX_LINES=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      shift
      REPORT_PATH="${1:-}"
      ;;
    --summary)
      shift
      SUMMARY_PATH="${1:-}"
      ;;
    --format)
      shift
      OUTPUT_FORMAT="${1:-tsv}"
      ;;
    --artifact-root)
      shift
      ARTIFACT_ROOT="${1:-}"
      ;;
    --diff-lines)
      shift
      DIFF_MAX_LINES="${1:-30}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$REPORT_PATH" ]]; then
  echo "--report is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Report file not found: $REPORT_PATH" >&2
  exit 1
fi

if [[ "$OUTPUT_FORMAT" != "tsv" && "$OUTPUT_FORMAT" != "json" ]]; then
  echo "Invalid format: $OUTPUT_FORMAT (must be tsv or json)" >&2
  usage
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: read a file and optionally truncate to DIFF_MAX_LINES lines
# ---------------------------------------------------------------------------
read_limited() {
  local file="$1"
  local max="${2:-$DIFF_MAX_LINES}"
  if [[ ! -f "$file" ]]; then
    return
  fi
  if [[ "$max" -le 0 ]]; then
    cat "$file"
    return
  fi
  local total
  total="$(wc -l < "$file" | tr -d ' ')"
  # Use cat + head to avoid printf issues with lines starting with '-'
  cat "$file" | head -n "$max"
  if (( total > max )); then
    printf '%s\n' "... ($(( total - max )) more lines)"
  fi
}

# ---------------------------------------------------------------------------
# Helper: escape a string for JSON
# ---------------------------------------------------------------------------
json_escape() {
  local s="$1"
  # Escape backslash, double-quote, newline, carriage-return, tab
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Helper: detect golden test update candidates for an artifact dir
# ---------------------------------------------------------------------------
detect_golden_candidates() {
  local artifact_dir="$1"
  local candidates=""

  if [[ -f "$artifact_dir/stdout.diff" && -s "$artifact_dir/stdout.diff" ]]; then
    candidates="${candidates:+$candidates,}stdout"
  fi
  if [[ -f "$artifact_dir/compile_stderr.diff" && -s "$artifact_dir/compile_stderr.diff" ]]; then
    candidates="${candidates:+$candidates,}compile_stderr"
  fi
  printf '%s' "$candidates"
}

# ---------------------------------------------------------------------------
# Helper: resolve artifact directory for a failed case
# Accepts the artifact_dir from the TSV, falling back to ARTIFACT_ROOT lookup.
# ---------------------------------------------------------------------------
resolve_artifact_dir() {
  local test_case="$1"
  local tsv_artifact_dir="$2"

  if [[ -n "$tsv_artifact_dir" && -d "$tsv_artifact_dir" ]]; then
    printf '%s' "$tsv_artifact_dir"
    return
  fi

  if [[ -n "$ARTIFACT_ROOT" ]]; then
    local sanitized="${test_case##*/}"
    sanitized="${sanitized%.kt}"
    sanitized="${sanitized//[^A-Za-z0-9._-]/_}"
    local candidate="$ARTIFACT_ROOT/$sanitized"
    if [[ -d "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  fi

  printf ''
}

# ---------------------------------------------------------------------------
# Parse the TSV report into parallel arrays (bash 3.2 compatible)
# ---------------------------------------------------------------------------
total=0
passed=0
failed=0
skipped=0
failed_cases=()
failed_adirs=()

while IFS=$'\t' read -r test_case status artifact_dir; do
  [[ -n "${test_case:-}" ]] || continue
  total=$((total + 1))
  case "${status:-}" in
    PASS)
      passed=$((passed + 1))
      ;;
    FAIL)
      failed=$((failed + 1))
      adir="$(resolve_artifact_dir "$test_case" "${artifact_dir:-}")"
      failed_cases+=("$test_case")
      failed_adirs+=("$adir")
      if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # Workflow commands must be a single line on stdout for GitHub Actions.
        printf '::error file=%s,title=kotlinc diff::diff regression failed for this case\n' "$test_case"
      fi
      ;;
    SKIP)
      skipped=$((skipped + 1))
      ;;
    *)
      failed=$((failed + 1))
      adir="$(resolve_artifact_dir "$test_case" "${artifact_dir:-}")"
      failed_cases+=("$test_case")
      failed_adirs+=("$adir")
      if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        printf '::warning file=%s,title=kotlinc diff::unknown status %s\n' "$test_case" "${status:-UNKNOWN}"
      fi
      ;;
  esac
done < "$REPORT_PATH"

# ---------------------------------------------------------------------------
# Emit JSON output
# ---------------------------------------------------------------------------
emit_json() {
  local i
  local first_case=1
  local case_count="${#failed_cases[@]}"

  printf '{\n'
  printf '  "summary": {\n'
  printf '    "total": %d,\n' "$total"
  printf '    "passed": %d,\n' "$passed"
  printf '    "failed": %d,\n' "$failed"
  printf '    "skipped": %d\n' "$skipped"
  printf '  },\n'
  printf '  "failed_cases": [\n'

  for (( i = 0; i < case_count; i++ )); do
    local test_case="${failed_cases[$i]}"
    local adir="${failed_adirs[$i]}"

    if [[ "$first_case" -eq 0 ]]; then
      printf ',\n'
    fi
    first_case=0

    local stdout_diff=""
    local compile_diff=""
    local summary_info=""
    local golden_candidates=""

    if [[ -n "$adir" && -d "$adir" ]]; then
      stdout_diff="$(read_limited "$adir/stdout.diff")"
      compile_diff="$(read_limited "$adir/compile_stderr.diff")"
      if [[ -f "$adir/summary.txt" ]]; then
        summary_info="$(cat "$adir/summary.txt")"
      fi
      golden_candidates="$(detect_golden_candidates "$adir")"
    fi

    printf '    {\n'
    printf '      "case": "%s",\n' "$(json_escape "$test_case")"
    printf '      "artifact_dir": "%s",\n' "$(json_escape "$adir")"
    printf '      "golden_update_candidates": "%s",\n' "$(json_escape "$golden_candidates")"
    printf '      "summary": "%s",\n' "$(json_escape "$summary_info")"
    printf '      "stdout_diff": "%s",\n' "$(json_escape "$stdout_diff")"
    printf '      "compile_stderr_diff": "%s"\n' "$(json_escape "$compile_diff")"
    printf '    }'
  done

  if [[ "$case_count" -gt 0 ]]; then
    printf '\n'
  fi
  printf '  ]\n'
  printf '}\n'
}

# ---------------------------------------------------------------------------
# Emit Markdown (for GitHub Step Summary / console)
# ---------------------------------------------------------------------------
emit_markdown() {
  printf '%s\n' "## kotlinc Diff Regression Summary"
  printf '\n'
  printf '%s\n' "| Metric | Count |"
  printf '%s\n' "|--------|-------|"
  printf '| Total   | %d |\n' "$total"
  printf '| Passed  | %d |\n' "$passed"
  printf '| Failed  | %d |\n' "$failed"
  printf '| Skipped | %d |\n' "$skipped"

  if (( failed > 0 )); then
    local i
    local case_count="${#failed_cases[@]}"

    printf '\n'
    printf '%s\n' "### Failed Cases"
    printf '\n'

    for (( i = 0; i < case_count; i++ )); do
      local test_case="${failed_cases[$i]}"
      local adir="${failed_adirs[$i]}"

      printf '#### `%s`\n' "$test_case"
      if [[ -n "$adir" ]]; then
        printf '%s\n' "- Artifacts: \`${adir}\`"
      fi

      # Embed stdout diff if available
      if [[ -n "$adir" && -f "$adir/stdout.diff" && -s "$adir/stdout.diff" ]]; then
        printf '\n'
        printf '%s\n' '<details><summary>stdout diff</summary>'
        printf '\n'
        printf '%s\n' '```diff'
        read_limited "$adir/stdout.diff"
        printf '%s\n' '```'
        printf '\n'
        printf '%s\n' '</details>'
        printf '\n'
        printf '%s\n' '> **Golden update candidate**: stdout mismatch detected.'
        printf '%s\n' '> To regenerate: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden`'
      fi

      # Embed compile stderr diff if available
      if [[ -n "$adir" && -f "$adir/compile_stderr.diff" && -s "$adir/compile_stderr.diff" ]]; then
        printf '\n'
        printf '%s\n' '<details><summary>compile stderr diff</summary>'
        printf '\n'
        printf '%s\n' '```diff'
        read_limited "$adir/compile_stderr.diff"
        printf '%s\n' '```'
        printf '\n'
        printf '%s\n' '</details>'
      fi

      # Embed summary.txt if available
      if [[ -n "$adir" && -f "$adir/summary.txt" ]]; then
        printf '\n'
        printf '%s\n' '<details><summary>case summary</summary>'
        printf '\n'
        printf '%s\n' '```'
        cat "$adir/summary.txt"
        printf '%s\n' '```'
        printf '\n'
        printf '%s\n' '</details>'
      fi

      printf '\n'
    done
  fi
}

# ---------------------------------------------------------------------------
# Main output dispatch
# ---------------------------------------------------------------------------
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  emit_json
else
  # TSV/default mode: emit markdown (backward-compatible)
  if [[ -n "$SUMMARY_PATH" ]]; then
    emit_markdown | tee -a "$SUMMARY_PATH"
  else
    emit_markdown
  fi
fi
