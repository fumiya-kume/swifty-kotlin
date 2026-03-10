#!/usr/bin/env bash
set -euo pipefail

threshold="${COVERAGE_THRESHOLD:-80}"
readonly report_file="${COVERAGE_REPORT_MD:-}"
readonly skip_test_run="${COVERAGE_SKIP_TEST_RUN:-0}"
readonly profile_override="${COVERAGE_PROFILE_PATH:-}"
readonly tests_binary_override="${COVERAGE_TESTS_BINARY:-}"
readonly json_output_override="${COVERAGE_JSON_OUTPUT:-}"
readonly llvm_cov_override="${LLVM_COV_BIN:-}"

readonly targets=(
  "Sources/CompilerCore/Lexer/TokenStream.swift"
  "Sources/CompilerCore/Driver/SourceManager.swift"
  "Sources/CompilerCore/Sema/Resolution/ConstraintSolver.swift"
  "Sources/CompilerCore/Sema/Resolution/OverloadResolver.swift"
  "Sources/CompilerCore/Parser/SyntaxArena.swift"
  "Sources/CompilerCore/Sema/Models/CompilerTypes.swift"
  "Sources/CompilerCore/Lexer/TokenModel.swift"
  "Sources/CompilerCore/AST/ASTModels.swift"
)

run_tests=true
case "$skip_test_run" in
  1|true|TRUE|True|yes|YES|Yes)
    run_tests=false
    ;;
esac

if [[ "$run_tests" == true ]]; then
  bash Scripts/swift_test.sh --enable-code-coverage
fi

if [[ "$(uname)" == "Linux" ]]; then
  if [[ -n "$profile_override" ]]; then
    readonly profile="$profile_override"
  else
    profile_candidate="$(find .build -name "default.profdata" 2>/dev/null | head -1)"
    readonly profile="${profile_candidate:-.build/debug/codecov/default.profdata}"
  fi

  if [[ -n "$tests_binary_override" ]]; then
    readonly tests_binary="$tests_binary_override"
  else
    tests_binary_candidate="$(find .build -name "KSwiftKPackageTests.xctest" 2>/dev/null | head -1)"
    readonly tests_binary="${tests_binary_candidate:-.build/debug/KSwiftKPackageTests.xctest}"
  fi
else
  readonly profile="${profile_override:-.build/debug/codecov/default.profdata}"
  readonly tests_binary="${tests_binary_override:-.build/debug/KSwiftKPackageTests.xctest/Contents/MacOS/KSwiftKPackageTests}"
fi

if [[ -n "$json_output_override" ]]; then
  readonly json_output="$json_output_override"
else
  readonly json_output="$(dirname "$tests_binary")/codecov/KSwiftK.json"
fi

if [[ ! -f "$profile" ]]; then
  echo "Coverage profile not found: ${profile}" >&2
  exit 1
fi

if [[ ! -e "$tests_binary" ]]; then
  echo "Test binary not found: ${tests_binary}" >&2
  exit 1
fi

if [[ -n "$llvm_cov_override" ]]; then
  readonly llvm_cov_bin="$llvm_cov_override"
elif [[ "$(uname)" == "Linux" ]]; then
  llvm_cov_candidate="$(command -v llvm-cov 2>/dev/null || true)"
  readonly llvm_cov_bin="${llvm_cov_candidate:-}"
else
  llvm_cov_candidate="$(xcrun --find llvm-cov 2>/dev/null || true)"
  readonly llvm_cov_bin="${llvm_cov_candidate:-}"
fi

if [[ -z "$llvm_cov_bin" || ! -x "$llvm_cov_bin" ]]; then
  echo "llvm-cov binary not found: ${llvm_cov_bin:-<empty>}" >&2
  exit 1
fi

mkdir -p "$(dirname "$json_output")"

"$llvm_cov_bin" export "$tests_binary" -instr-profile "$profile" > "$json_output"

echo "Coverage threshold: ${threshold}%"

declare -a failed=()
declare -a report_lines=()
for target in "${targets[@]}"; do
  percent="$(jq -r --arg target "$target" '
    .data[0].files[]
    | select(.filename | endswith($target))
    | .summary.lines.percent
    | select(. != null)
  ' "$json_output" | head -1)"

  if [[ -z "$percent" || "$percent" == "null" ]]; then
    failed+=("$target (missing)")
    report_lines+=("| \`$target\` | - | ${threshold}% | :warning: missing |")
    printf "%-52s %s\n" "$target" "missing"
    continue
  fi

  formatted="$(awk -v value="$percent" 'BEGIN { printf "%.2f", value }')"
  printf "%-52s %s%%\n" "$target" "$formatted"

  if ! awk -v value="$percent" -v min="$threshold" 'BEGIN { exit (value + 0 >= min + 0 ? 0 : 1) }'; then
    failed+=("$target (${formatted}%)")
    report_lines+=("| \`$target\` | ${formatted}% | ${threshold}% | :x: |")
  else
    report_lines+=("| \`$target\` | ${formatted}% | ${threshold}% | :white_check_mark: |")
  fi
done

# Generate markdown report if requested
if [[ -n "$report_file" ]]; then
  {
    echo "<!-- coverage-gate-report -->"
    if (( ${#failed[@]} > 0 )); then
      echo "## :warning: Coverage Check Failed"
      echo ""
      echo "The following files are below the **${threshold}%** line coverage threshold."
    else
      echo "## :white_check_mark: Coverage Check Passed"
      echo ""
      echo "All tracked files meet the **${threshold}%** line coverage threshold."
    fi
    echo ""
    echo "| File | Coverage | Threshold | Status |"
    echo "|------|----------|-----------|--------|"
    for line in "${report_lines[@]}"; do
      echo "$line"
    done
    if (( ${#failed[@]} > 0 )); then
      echo ""
      echo "Please add tests to improve coverage for the files marked with :x:."
    fi
  } > "$report_file"
fi

if (( ${#failed[@]} > 0 )); then
  echo
  echo "Coverage check failed. Files below ${threshold}%:"
  for item in "${failed[@]}"; do
    echo "- ${item}"
  done
  exit 1
fi

echo

echo "Coverage check passed."
