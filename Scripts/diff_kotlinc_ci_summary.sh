#!/usr/bin/env bash
set -euo pipefail

REPORT_PATH=""
SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --report <path> [--summary <path>]

Options:
  --report <path>   TSV report emitted by Scripts/diff_kotlinc.sh --report
  --summary <path>  Markdown summary output path (default: \$GITHUB_STEP_SUMMARY)
  -h, --help        Show this help
USAGE
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      shift
      REPORT_PATH="$1"
      ;;
    --summary)
      shift
      SUMMARY_PATH="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$REPORT_PATH" ]]; then
  echo "--report is required." >&2
  usage
  exit 1
fi

emit_summary() {
  local total="$1"
  local failed="$2"
  local body_file="$3"

  local passed=$((total - failed))
  {
    echo "## kotlinc diff regression"
    echo
    echo "- Total: $total"
    echo "- Passed: $passed"
    echo "- Failed: $failed"
    if [[ $failed -gt 0 ]]; then
      echo
      echo "### Failed cases"
      echo
      echo "| Case | Artifact dir |"
      echo "| --- | --- |"
      cat "$body_file"
    fi
    echo
  } >>"${SUMMARY_PATH:-/dev/stdout}"
}

if [[ ! -f "$REPORT_PATH" ]]; then
  tmp_body="$(mktemp -t kswiftk-diff-summary-empty-XXXXXX)"
  trap 'rm -f "$tmp_body"' EXIT
  emit_summary 0 0 "$tmp_body"
  exit 0
fi

tmp_body="$(mktemp -t kswiftk-diff-summary-XXXXXX)"
trap 'rm -f "$tmp_body"' EXIT

total=0
failed=0
while IFS=$'\t' read -r case_path status artifact_dir; do
  [[ -z "$case_path" ]] && continue
  total=$((total + 1))
  if [[ "$status" == "FAIL" ]]; then
    failed=$((failed + 1))
    display_artifact="$artifact_dir"
    if [[ -z "$display_artifact" ]]; then
      display_artifact="-"
    fi
    printf '| `%s` | `%s` |\n' "$case_path" "$display_artifact" >>"$tmp_body"
  fi
done <"$REPORT_PATH"

emit_summary "$total" "$failed" "$tmp_body"
