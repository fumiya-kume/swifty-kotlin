#!/usr/bin/env bash
set -euo pipefail

threshold="${COVERAGE_THRESHOLD:-80}"
readonly report_file="${COVERAGE_REPORT_MD:-}"

readonly targets=(
  "Sources/CompilerCore/Lexer/TokenStream.swift"
  "Sources/CompilerCore/Driver/SourceManager.swift"
  "Sources/CompilerCore/Sema/ConstraintSolver.swift"
  "Sources/CompilerCore/Sema/OverloadResolver.swift"
  "Sources/CompilerCore/Parser/SyntaxArena.swift"
  "Sources/CompilerCore/Sema/CompilerTypes.swift"
  "Sources/CompilerCore/Lexer/TokenModel.swift"
  "Sources/CompilerCore/AST/ASTModels.swift"
)

bash Scripts/swift_test.sh --enable-code-coverage

if [[ "$(uname)" == "Linux" ]]; then
  profile_candidate="$(
    find .build -type f -path '*/debug/codecov/default.profdata' 2>/dev/null \
      | sort \
      | head -1
  )"
  readonly profile="${profile_candidate:-.build/debug/codecov/default.profdata}"
  build_dir="$(dirname "$(dirname "$profile")")"
  readonly tests_binary="${build_dir}/KSwiftKPackageTests.xctest"
  readonly json_output="${build_dir}/codecov/KSwiftK.json"
else
  readonly profile=".build/debug/codecov/default.profdata"
  readonly tests_binary=".build/debug/KSwiftKPackageTests.xctest/Contents/MacOS/KSwiftKPackageTests"
  readonly json_output=".build/debug/codecov/KSwiftK.json"
fi

if [[ "$(uname)" == "Linux" ]]; then
  llvm-cov export "$tests_binary" -instr-profile "$profile" > "$json_output"
else
  xcrun llvm-cov export "$tests_binary" -instr-profile "$profile" > "$json_output"
fi

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
