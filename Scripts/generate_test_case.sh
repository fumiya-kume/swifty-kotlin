#!/usr/bin/env bash
# generate_test_case.sh - Scaffold golden / diff test cases for swifty-kotlin
#
# Usage:
#   bash Scripts/generate_test_case.sh --type <golden-sema|golden-parser|golden-lexer|diff> \
#       --name <test_name> [--source <inline_kotlin>] [--from-file <path.kt>] [--task <TASK-ID>]
#
#   bash Scripts/generate_test_case.sh --from-registry <registry.json> [--task <TASK-ID>] [--category <cat>]
#
# Examples:
#   # Scaffold a single golden-sema test with inline source:
#   bash Scripts/generate_test_case.sh --type golden-sema --name variance_out \
#       --source 'class Box<out T>(val value: T)\nfun main() { val b: Box<Any> = Box(42) }'
#
#   # Scaffold from a template file:
#   bash Scripts/generate_test_case.sh --type diff --name abstract_class \
#       --from-file Scripts/test_templates/diff/abstract_class.kt
#
#   # Generate all pending tests for a specific task from the registry:
#   bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-001
#
#   # Generate all pending tests for a category:
#   bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --category expressions
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN_DIR="$ROOT_DIR/Tests/CompilerCoreTests/GoldenCases"
DIFF_DIR="$ROOT_DIR/Scripts/diff_cases"

TYPE=""
NAME=""
SOURCE=""
FROM_FILE=""
TASK=""
CATEGORY=""
FROM_REGISTRY=""
DRY_RUN=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [options]

Single test mode:
  --type <type>         Test type: golden-sema, golden-parser, golden-lexer, diff
  --name <name>         Test file name (without extension)
  --source <kotlin>     Inline Kotlin source (use \\n for newlines)
  --from-file <path>    Path to a .kt template file to copy
  --task <TASK-ID>      (optional) Associated task ID for documentation

Registry mode:
  --from-registry <path>  Path to test_case_registry.json
  --task <TASK-ID>        Generate tests for a specific task
  --category <cat>        Generate tests for a category

Options:
  --dry-run             Print what would be created without writing files
  -h, --help            Show this help
USAGE
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

resolve_target_dir() {
    local type="$1"
    case "$type" in
        golden-sema)   echo "$GOLDEN_DIR/Sema" ;;
        golden-parser) echo "$GOLDEN_DIR/Parser" ;;
        golden-lexer)  echo "$GOLDEN_DIR/Lexer" ;;
        diff)          echo "$DIFF_DIR" ;;
        *)
            log_error "Unknown test type: $type"
            exit 1
            ;;
    esac
}

# Add package declaration for golden-sema tests (matching existing convention)
maybe_add_package() {
    local type="$1"
    local source="$2"
    if [[ "$type" == "golden-sema" ]] && ! echo "$source" | grep -q '^package '; then
        echo "package golden.sema"
        echo ""
        echo "$source"
    else
        echo "$source"
    fi
}

scaffold_single() {
    local type="$1"
    local name="$2"
    local source="$3"
    local task="${4:-}"

    local target_dir
    target_dir="$(resolve_target_dir "$type")"
    local target_file="$target_dir/${name}.kt"

    if [[ -f "$target_file" ]]; then
        log_warn "File already exists: $target_file (skipping)"
        return 0
    fi

    local final_source
    final_source="$(maybe_add_package "$type" "$source")"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would create: $target_file"
        if [[ -n "$task" ]]; then
            log_info "  Task: $task"
        fi
        return 0
    fi

    mkdir -p "$target_dir"
    printf '%s\n' "$final_source" > "$target_file"
    log_info "Created: $target_file"

    if [[ -n "$task" ]]; then
        log_info "  Associated task: $task"
    fi

    # For diff cases, suggest updating README.md
    if [[ "$type" == "diff" ]]; then
        log_info "  Remember to add an entry to $DIFF_DIR/README.md"
    fi

    # For golden cases, remind about UPDATE_GOLDEN=1
    if [[ "$type" == golden-* ]]; then
        log_info "  Run tests with UPDATE_GOLDEN=1 to generate .golden file:"
        log_info "    UPDATE_GOLDEN=1 swift test --filter GoldenHarnessTests 2>&1 | tail -5"
    fi
}

scaffold_from_registry() {
    local registry_path="$1"
    local filter_task="${2:-}"
    local filter_category="${3:-}"

    if [[ ! -f "$registry_path" ]]; then
        log_error "Registry file not found: $registry_path"
        exit 1
    fi

    # Use python3 to parse JSON and emit lines: type|name|task|source_file
    local entries
    entries=$(python3 - "$registry_path" "$filter_task" "$filter_category" <<'PYEOF'
import json, sys, os

registry_path = sys.argv[1]
filter_task = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
filter_category = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

with open(registry_path) as f:
    registry = json.load(f)

for entry in registry.get("test_cases", []):
    task = entry.get("task", "")
    category = entry.get("category", "")
    if filter_task and task != filter_task:
        continue
    if filter_category and category != filter_category:
        continue
    for tc in entry.get("cases", []):
        test_type = tc.get("type", "")
        name = tc.get("name", "")
        source_file = tc.get("template", "")
        print(f"{test_type}|{name}|{task}|{source_file}")
PYEOF
    )

    if [[ -z "$entries" ]]; then
        log_warn "No matching test cases found in registry."
        return 0
    fi

    local count=0
    while IFS='|' read -r tc_type tc_name tc_task tc_template; do
        [[ -z "$tc_type" || -z "$tc_name" ]] && continue

        local source=""
        if [[ -n "$tc_template" && -f "$ROOT_DIR/$tc_template" ]]; then
            source="$(cat "$ROOT_DIR/$tc_template")"
        elif [[ -n "$tc_template" && -f "$tc_template" ]]; then
            source="$(cat "$tc_template")"
        else
            # Generate a minimal placeholder
            source="// TODO: Implement test case for $tc_task ($tc_name)"
            source="$source"$'\n'"fun main() {"$'\n'"    // Add test code here"$'\n'"}"
        fi

        scaffold_single "$tc_type" "$tc_name" "$source" "$tc_task"
        count=$((count + 1))
    done <<< "$entries"

    log_info "Processed $count test case(s)."
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)        shift; TYPE="$1" ;;
        --name)        shift; NAME="$1" ;;
        --source)      shift; SOURCE="$(printf '%b' "$1")" ;;
        --from-file)   shift; FROM_FILE="$1" ;;
        --task)        shift; TASK="$1" ;;
        --category)    shift; CATEGORY="$1" ;;
        --from-registry) shift; FROM_REGISTRY="$1" ;;
        --dry-run)     DRY_RUN=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Dispatch ---
if [[ -n "$FROM_REGISTRY" ]]; then
    scaffold_from_registry "$FROM_REGISTRY" "$TASK" "$CATEGORY"
elif [[ -n "$TYPE" && -n "$NAME" ]]; then
    if [[ -n "$FROM_FILE" ]]; then
        if [[ ! -f "$FROM_FILE" ]]; then
            log_error "Template file not found: $FROM_FILE"
            exit 1
        fi
        SOURCE="$(cat "$FROM_FILE")"
    fi
    if [[ -z "$SOURCE" ]]; then
        log_error "Either --source or --from-file is required in single test mode."
        usage
        exit 1
    fi
    scaffold_single "$TYPE" "$NAME" "$SOURCE" "$TASK"
else
    log_error "Either provide --type + --name, or --from-registry."
    usage
    exit 1
fi
