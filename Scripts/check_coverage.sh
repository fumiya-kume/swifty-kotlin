#!/usr/bin/env bash
set -euo pipefail

threshold="${COVERAGE_THRESHOLD:-97}"

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

readonly profile=".build/debug/codecov/default.profdata"
readonly tests_binary=".build/debug/KSwiftKPackageTests.xctest/Contents/MacOS/KSwiftKPackageTests"
readonly json_output=".build/debug/codecov/KSwiftK.json"

xcrun llvm-cov export "$tests_binary" -instr-profile "$profile" > "$json_output"

echo "Coverage threshold: ${threshold}%"

declare -a failed=()
for target in "${targets[@]}"; do
  percent="$(jq -r --arg target "$target" '
    .data[0].files[]
    | select(.filename | endswith($target))
    | .summary.lines.percent
  ' "$json_output")"

  if [[ -z "$percent" || "$percent" == "null" ]]; then
    failed+=("$target (missing)")
    printf "%-52s %s\n" "$target" "missing"
    continue
  fi

  formatted="$(awk -v value="$percent" 'BEGIN { printf "%.2f", value }')"
  printf "%-52s %s%%\n" "$target" "$formatted"

  if ! awk -v value="$percent" -v min="$threshold" 'BEGIN { exit (value + 0 >= min + 0 ? 0 : 1) }'; then
    failed+=("$target (${formatted}%)")
  fi
done

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
