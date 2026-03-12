#!/bin/bash
# PostToolUse hook: Run SwiftFormat + SwiftLint lint checks after editing .swift files
# Receives tool input/output as JSON on stdin

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

# Only process .swift files under Sources/ or Tests/
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *.swift ]]; then
    exit 0
fi

# Resolve project root (git root) and relative path
PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || exit 0)
REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"

# Only lint Sources/ and Tests/ (matching .swiftlint.yml included paths)
if [[ "$REL_PATH" != Sources/* ]] && [[ "$REL_PATH" != Tests/* ]]; then
    exit 0
fi

ERRORS=""

# Run SwiftFormat (lint mode, no auto-fix)
FORMAT_OUTPUT=$(swiftformat --lint "$FILE_PATH" 2>&1) || true
FORMAT_ISSUES=$(echo "$FORMAT_OUTPUT" | grep -v '^$' | grep -v 'Running SwiftFormat' || true)
if [[ -n "$FORMAT_ISSUES" ]]; then
    ERRORS+="[SwiftFormat] $REL_PATH:"$'\n'"$FORMAT_ISSUES"$'\n'
fi

# Run SwiftLint with baseline
LINT_OUTPUT=$(swiftlint lint --path "$FILE_PATH" --config "$PROJECT_ROOT/.swiftlint.yml" --baseline "$PROJECT_ROOT/.swiftlint.baseline.json" 2>&1) || true

# Filter for warnings and errors only
LINT_ISSUES=$(echo "$LINT_OUTPUT" | grep -E '(warning:|error:)' || true)

if [[ -n "$LINT_ISSUES" ]]; then
    ERRORS+="[SwiftLint] Issues found:"$'\n'"$LINT_ISSUES"$'\n'
fi

if [[ -n "$ERRORS" ]]; then
    echo "$ERRORS"
    echo "Please fix the above lint issues in $REL_PATH"
    exit 1
fi
