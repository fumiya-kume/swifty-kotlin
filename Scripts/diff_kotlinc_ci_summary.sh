#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: diff_kotlinc_ci_summary.sh --report <path> [--summary <path>]

Options:
  --report <path>   TSV report emitted by Scripts/diff_kotlinc.sh
  --summary <path>  Optional markdown output path
  -h, --help        Show this help
USAGE
}

REPORT_PATH=""
SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"

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

total=0
passed=0
failed=0
skipped=0
declare -a failed_cases=()

while IFS=$'\t' read -r test_case status artifact_dir; do
  [[ -n "${test_case:-}" ]] || continue
  total=$((total + 1))
  case "${status:-}" in
    PASS)
      passed=$((passed + 1))
      ;;
    FAIL)
      failed=$((failed + 1))
      if [[ -n "${artifact_dir:-}" ]]; then
        failed_cases+=("- \`${test_case}\` artifacts: \`${artifact_dir}\`")
      else
        failed_cases+=("- \`${test_case}\`")
      fi
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
      failed_cases+=("- \`${test_case}\` had unknown status \`${status:-UNKNOWN}\`")
      ;;
  esac
done < "$REPORT_PATH"

summary_lines=()
summary_lines+=("## kotlinc Diff Regression Summary")
summary_lines+=("")
summary_lines+=("- Total: ${total}")
summary_lines+=("- Passed: ${passed}")
summary_lines+=("- Failed: ${failed}")
summary_lines+=("- Skipped: ${skipped}")

if (( failed > 0 )); then
  summary_lines+=("")
  summary_lines+=("### Failed Cases")
  summary_lines+=("${failed_cases[@]}")
fi

if [[ -n "$SUMMARY_PATH" ]]; then
  {
    for line in "${summary_lines[@]}"; do
      printf '%s\n' "$line"
    done
  } >> "$SUMMARY_PATH"
fi

for line in "${summary_lines[@]}"; do
  printf '%s\n' "$line"
done
