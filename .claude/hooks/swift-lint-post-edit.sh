#!/bin/bash
# PostToolUse hook: Run SwiftFormat + SwiftLint after editing .swift files
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

# Run SwiftFormat (auto-fix in place)
FORMAT_OUTPUT=$(swiftformat "$FILE_PATH" 2>&1) || true
# Check if swiftformat actually changed the file
FORMAT_CHANGES=$(echo "$FORMAT_OUTPUT" | grep -v '^$' | grep -v 'Running SwiftFormat' | grep -v 'Reading config' | grep -v 'SwiftFormat completed' | grep -v '0/[0-9]* files formatted' || true)
if echo "$FORMAT_OUTPUT" | grep -qE '[1-9][0-9]*/[0-9]+ files formatted'; then
    ERRORS+="[SwiftFormat] Auto-fixed formatting in $REL_PATH. The file has been updated."$'\n'
fi
if [[ -n "$FORMAT_CHANGES" ]]; then
    ERRORS+="[SwiftFormat] $FORMAT_CHANGES"$'\n'
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
