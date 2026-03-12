#!/usr/bin/env bash
set -euo pipefail

REPORT_PATH=""
SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"
MAX_SECTION_LINES="${DIFF_SUMMARY_MAX_LINES:-80}"

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

if ! [[ "$MAX_SECTION_LINES" =~ ^[1-9][0-9]*$ ]]; then
  echo "DIFF_SUMMARY_MAX_LINES must be a positive integer: $MAX_SECTION_LINES" >&2
  exit 1
fi

emit_output() {
  local line="$1"
  if [[ -n "$SUMMARY_PATH" ]]; then
    printf '%s\n' "$line" >>"$SUMMARY_PATH"
  else
    printf '%s\n' "$line"
  fi
}

emit_block_from_file() {
  local title="$1"
  local file_path="$2"
  local limit="$3"

  [[ -f "$file_path" ]] || return 1
  [[ -s "$file_path" ]] || return 1

  emit_output "#### ${title}"
  emit_output ""
  emit_output '```text'
  sed -n "1,${limit}p" "$file_path" | while IFS= read -r line || [[ -n "$line" ]]; do
    emit_output "$line"
  done
  local total_lines
  total_lines="$(wc -l <"$file_path" | tr -d '[:space:]')"
  if [[ -n "$total_lines" && "$total_lines" -gt "$limit" ]]; then
    emit_output "... (truncated, showing first ${limit} of ${total_lines} lines)"
  fi
  emit_output '```'
  emit_output ""
}

emit_stdout_diff_block() {
  local artifact_dir="$1"
  local limit="$2"
  local ref_file="$artifact_dir/ref_run_stdout.norm"
  local cand_file="$artifact_dir/cand_run_stdout.norm"
  local diff_file

  [[ -f "$ref_file" && -f "$cand_file" ]] || return 1

  diff_file="$(mktemp -t kswiftk-diff-summary-diff-XXXXXX)"
  if diff -u "$ref_file" "$cand_file" >"$diff_file"; then
    rm -f "$diff_file"
    return 1
  fi

  emit_output "#### Stdout diff"
  emit_output ""
  emit_output '```diff'
  sed -n "1,${limit}p" "$diff_file" | while IFS= read -r line || [[ -n "$line" ]]; do
    emit_output "$line"
  done
  local total_lines
  total_lines="$(wc -l <"$diff_file" | tr -d '[:space:]')"
  if [[ -n "$total_lines" && "$total_lines" -gt "$limit" ]]; then
    emit_output "... (truncated, showing first ${limit} of ${total_lines} lines)"
  fi
  emit_output '```'
  emit_output ""

  rm -f "$diff_file"
}

print_console_excerpt() {
  local label="$1"
  local file_path="$2"
  local limit="$3"

  [[ -f "$file_path" ]] || return 1
  [[ -s "$file_path" ]] || return 1

  echo "$label"
  sed -n "1,${limit}p" "$file_path"
  local total_lines
  total_lines="$(wc -l <"$file_path" | tr -d '[:space:]')"
  if [[ -n "$total_lines" && "$total_lines" -gt "$limit" ]]; then
    echo "... (truncated, showing first ${limit} of ${total_lines} lines)"
  fi
}

print_console_failure_detail() {
  local case_path="$1"
  local artifact_dir="$2"
  local limit="$3"
  local diff_file=""

  echo "::group::kotlinc diff failure: ${case_path}"
  echo "Case: ${case_path}"
  echo "Artifacts: ${artifact_dir:-"-"}"

  if [[ -n "$artifact_dir" && -d "$artifact_dir" ]]; then
    diff_file="$(mktemp -t kswiftk-diff-console-diff-XXXXXX)"
    if [[ -f "$artifact_dir/ref_run_stdout.norm" && -f "$artifact_dir/cand_run_stdout.norm" ]] \
      && ! diff -u "$artifact_dir/ref_run_stdout.norm" "$artifact_dir/cand_run_stdout.norm" >"$diff_file"; then
      print_console_excerpt "Stdout diff:" "$diff_file" "$limit" || true
    fi
    print_console_excerpt "Reference compile stderr:" "$artifact_dir/ref_compile_stderr.norm" "$limit" || true
    print_console_excerpt "Candidate compile stderr:" "$artifact_dir/cand_compile_stderr.norm" "$limit" || true
    print_console_excerpt "Reference run stderr:" "$artifact_dir/ref_run_stderr" "$limit" || true
    print_console_excerpt "Candidate run stderr:" "$artifact_dir/cand_run_stderr" "$limit" || true
    rm -f "$diff_file"
  else
    echo "Artifact directory is unavailable."
  fi

  echo "::endgroup::"
}

emit_failed_case_detail() {
  local case_path="$1"
  local artifact_dir="$2"
  local limit="$3"

  emit_output "<details>"
  emit_output "<summary><code>${case_path}</code></summary>"
  emit_output ""
  emit_output "- Artifact dir: \`${artifact_dir:-"-"}\`"
  emit_output ""

  if [[ -n "$artifact_dir" && -d "$artifact_dir" ]]; then
    emit_stdout_diff_block "$artifact_dir" "$limit" || true
    emit_block_from_file "Reference compile stderr" "$artifact_dir/ref_compile_stderr.norm" "$limit" || true
    emit_block_from_file "Candidate compile stderr" "$artifact_dir/cand_compile_stderr.norm" "$limit" || true
    emit_block_from_file "Reference run stderr" "$artifact_dir/ref_run_stderr" "$limit" || true
    emit_block_from_file "Candidate run stderr" "$artifact_dir/cand_run_stderr" "$limit" || true
  else
    emit_output "_Artifact directory is unavailable on this runner._"
    emit_output ""
  fi

  emit_output "</details>"
  emit_output ""
}

emit_summary() {
  local total="$1"
  local failed="$2"
  local skipped="$3"
  local body_file="$4"
  local details_file="$5"

  local passed=$((total - failed - skipped))
  emit_output "## kotlinc diff regression"
  emit_output ""
  emit_output "- Total: $total"
  emit_output "- Passed: $passed"
  emit_output "- Skipped: $skipped"
  emit_output "- Failed: $failed"
  if [[ $failed -gt 0 ]]; then
    emit_output ""
    emit_output "### Failed cases"
    emit_output ""
    emit_output "| Case | Artifact dir |"
    emit_output "| --- | --- |"
    while IFS= read -r line || [[ -n "$line" ]]; do
      emit_output "$line"
    done <"$body_file"
    emit_output ""
    emit_output "### Failure details"
    emit_output ""
    while IFS= read -r line || [[ -n "$line" ]]; do
      emit_output "$line"
    done <"$details_file"
  fi
  emit_output ""
}

if [[ ! -f "$REPORT_PATH" ]]; then
  tmp_body="$(mktemp -t kswiftk-diff-summary-empty-XXXXXX)"
  trap 'rm -f "$tmp_body"' EXIT
  emit_summary 0 0 0 "$tmp_body"
  exit 0
fi

tmp_body="$(mktemp -t kswiftk-diff-summary-XXXXXX)"
tmp_details="$(mktemp -t kswiftk-diff-summary-details-XXXXXX)"
trap 'rm -f "$tmp_body" "$tmp_details"' EXIT

total=0
failed=0
skipped=0
while IFS=$'\t' read -r case_path status artifact_dir; do
  [[ -z "$case_path" ]] && continue
  total=$((total + 1))
  if [[ "$status" == "SKIP" ]]; then
    skipped=$((skipped + 1))
  elif [[ "$status" == "FAIL" ]]; then
    failed=$((failed + 1))
    display_artifact="$artifact_dir"
    if [[ -z "$display_artifact" ]]; then
      display_artifact="-"
    fi
    printf '| `%s` | `%s` |\n' "$case_path" "$display_artifact" >>"$tmp_body"
    print_console_failure_detail "$case_path" "$artifact_dir" "$MAX_SECTION_LINES"
    current_summary_path="$SUMMARY_PATH"
    SUMMARY_PATH="$tmp_details"
    emit_failed_case_detail "$case_path" "$artifact_dir" "$MAX_SECTION_LINES"
    SUMMARY_PATH="$current_summary_path"
  fi
done <"$REPORT_PATH"

emit_summary "$total" "$failed" "$skipped" "$tmp_body" "$tmp_details"
