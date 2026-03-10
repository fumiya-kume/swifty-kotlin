#!/bin/bash
# PreToolUse hook: Block git commit if SwiftLint/SwiftFormat issues exist
# Receives tool input as JSON on stdin

set -euo pipefail

INPUT=$(cat)

# Only intercept git commit commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Check if this is a git commit command (not git add, git status, etc.)
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
    exit 0
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || exit 0)
cd "$PROJECT_ROOT"

# Get staged .swift files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.swift' 2>/dev/null || true)

if [[ -z "$STAGED_FILES" ]]; then
    exit 0
fi

ERRORS=""

while IFS= read -r FILE; do
    # Only check files in Sources/ or Tests/
    if [[ "$FILE" != Sources/* ]] && [[ "$FILE" != Tests/* ]]; then
        continue
    fi

    FULL_PATH="${PROJECT_ROOT}/${FILE}"
    if [[ ! -f "$FULL_PATH" ]]; then
        continue
    fi

    # Check SwiftFormat (lint mode, no auto-fix)
    FORMAT_OUTPUT=$(swiftformat --lint "$FULL_PATH" 2>&1) || true
    FORMAT_ISSUES=$(echo "$FORMAT_OUTPUT" | grep -v '^$' | grep -v 'Running SwiftFormat' || true)
    if [[ -n "$FORMAT_ISSUES" ]]; then
        ERRORS+="[SwiftFormat] $FILE:"$'\n'"$FORMAT_ISSUES"$'\n'
    fi

    # Check SwiftLint
    LINT_OUTPUT=$(swiftlint lint --path "$FULL_PATH" --config "$PROJECT_ROOT/.swiftlint.yml" --baseline "$PROJECT_ROOT/.swiftlint.baseline.json" 2>&1) || true
    LINT_ISSUES=$(echo "$LINT_OUTPUT" | grep -E '(warning:|error:)' || true)
    if [[ -n "$LINT_ISSUES" ]]; then
        ERRORS+="[SwiftLint] $FILE:"$'\n'"$LINT_ISSUES"$'\n'
    fi
done <<< "$STAGED_FILES"

if [[ -n "$ERRORS" ]]; then
    echo "Lint check failed for staged files:"
    echo "$ERRORS"
    echo "Fix the issues above before committing."
    exit 1
fi
