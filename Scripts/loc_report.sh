#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Emit refactoring guard metrics as TSV:
  metric<TAB>scope<TAB>value

Metrics:
  loc_by_directory                         Physical lines in tracked files, grouped by top-level directory
  loc_by_path_prefix                       Physical lines in tracked Swift files under a refactor target path
  header_helpers_synthetic_total_lines     Physical lines in HeaderHelpers+Synthetic*.swift files
  call_lowerer_legacy_total_lines          Physical lines in CallLowerer+Legacy*.swift files
  kir_lowering_todo_fixme_count            TODO/FIXME markers remaining in KIR and Lowering Swift sources
  kk_literal_count                         Occurrences of string literals beginning with "kk_ in Swift/Kotlin sources
  kk_cdecl_count                            Distinct Runtime @_cdecl("kk_*") bridge definitions
  __kk_cdecl_count                          Distinct Runtime @_cdecl("__kk_*") bridge definitions
  interner_resolve_literal_comparison_count Occurrences of interner.resolve(...) == "..." in Swift sources
  typecheck_interner_resolve_literal_comparison_count
                                            Same as above, scoped to Sources/CompilerCore/Sema/TypeCheck
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$ROOT_DIR"

# File lists are fed to xargs as NUL-separated stdin (printf is a builtin, so
# no exec() argument limit applies); xargs may split them across several tool
# invocations, so per-invocation counts are summed afterwards.
count_lines() {
  local existing_files=()
  for file in "$@"; do
    # `git ls-files` also returns paths deleted in the working tree. Ignore
    # those paths so refactor metrics remain usable during file migrations.
    [[ -f "$file" ]] && existing_files+=("$file")
  done

  if [[ ${#existing_files[@]} -eq 0 ]]; then
    printf '0\n'
    return
  fi

  printf '%s\0' "${existing_files[@]}" \
    | xargs -0 awk 'END { print NR + 0 }' \
    | awk '{ total += $1 } END { print total + 0 }'
}

# `|| true` tolerates grep's exit 1 on zero matches under `set -e`.
grep_matches() {
  local pattern="$1"
  shift

  printf '%s\0' "$@" | xargs -0 grep -hEo "$pattern" || true
}

count_regex_occurrences() {
  local pattern="$1"
  shift

  local existing_files=()
  for file in "$@"; do
    [[ -f "$file" ]] && existing_files+=("$file")
  done

  if [[ ${#existing_files[@]} -eq 0 ]]; then
    printf '0\n'
    return
  fi

  { printf '%s\0' "${existing_files[@]}" | xargs -0 grep -hEo "$pattern" || true; } \
    | awk 'END { print NR + 0 }'
}

count_unique_regex_matches() {
  local pattern="$1"
  shift

  if [[ $# -eq 0 ]]; then
    printf '0\n'
    return
  fi

  grep_matches "$pattern" "$@" | LC_ALL=C sort -u | awk 'END { print NR + 0 }'
}

emit_directory_loc() {
  git ls-files -z \
    | while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
          printf '%s\0' "$file"
        fi
      done \
    | xargs -0 awk '
        FNR == 1 {
          dir = FILENAME
          if (index(dir, "/") > 0) {
            sub(/\/.*/, "", dir)
          } else {
            dir = "."
          }
        }
        { totals[dir] += 1 }
        END {
          for (dir in totals) {
            printf "%s\t%d\n", dir, totals[dir]
          }
        }
      ' \
    | awk -F '\t' '
        { totals[$1] += $2 }
        END {
          for (dir in totals) {
            printf "%s\t%d\n", dir, totals[dir]
          }
        }
      ' \
    | LC_ALL=C sort \
    | awk -F '\t' '{ printf "loc_by_directory\t%s\t%s\n", $1, $2 }'
}

SYNTHETIC_HEADER_FILES=()
while IFS= read -r file; do
  SYNTHETIC_HEADER_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift' | LC_ALL=C sort)

SWIFT_AND_KOTLIN_FILES=()
while IFS= read -r file; do
  SWIFT_AND_KOTLIN_FILES+=("$file")
done < <(git ls-files '*.swift' '*.kt' | LC_ALL=C sort)

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(git ls-files '*.swift' | LC_ALL=C sort)

KIR_LOWERING_FILES=()
while IFS= read -r file; do
  KIR_LOWERING_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/KIR/*.swift' 'Sources/CompilerCore/Lowering/*.swift' | LC_ALL=C sort)

SEMA_DATAFLOW_FILES=()
while IFS= read -r file; do
  SEMA_DATAFLOW_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/Sema/DataFlow/*.swift' | LC_ALL=C sort)

SEMA_TYPECHECK_FILES=()
while IFS= read -r file; do
  SEMA_TYPECHECK_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/Sema/TypeCheck/*.swift' | LC_ALL=C sort)

RUNTIME_SWIFT_FILES=()
while IFS= read -r file; do
  RUNTIME_SWIFT_FILES+=("$file")
done < <(git ls-files 'Sources/Runtime' | awk '/\.swift$/ { print }' | LC_ALL=C sort)

CALL_LOWERER_LEGACY_FILES=()
while IFS= read -r file; do
  CALL_LOWERER_LEGACY_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/KIR/CallLowerer+Legacy*.swift' | LC_ALL=C sort)

printf 'metric\tscope\tvalue\n'
emit_directory_loc
printf 'loc_by_path_prefix\tSources/CompilerCore/Sema/DataFlow\t%s\n' \
  "$(count_lines "${SEMA_DATAFLOW_FILES[@]}")"
printf 'loc_by_path_prefix\tSources/CompilerCore/Sema/TypeCheck\t%s\n' \
  "$(count_lines "${SEMA_TYPECHECK_FILES[@]}")"
printf 'header_helpers_synthetic_total_lines\tSources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift\t%s\n' \
  "$(count_lines "${SYNTHETIC_HEADER_FILES[@]}")"
printf 'call_lowerer_legacy_total_lines\tSources/CompilerCore/KIR/CallLowerer+Legacy*.swift\t%s\n' \
  "$(count_lines "${CALL_LOWERER_LEGACY_FILES[@]}")"
printf 'kir_lowering_todo_fixme_count\tSources/CompilerCore/{KIR,Lowering}/*.swift\t%s\n' \
  "$(count_regex_occurrences 'TODO|FIXME' "${KIR_LOWERING_FILES[@]}")"
printf 'kk_literal_count\tSwift/Kotlin sources\t%s\n' \
  "$(count_regex_occurrences '"kk_[^"]*"' "${SWIFT_AND_KOTLIN_FILES[@]}")"
printf 'kk_cdecl_count\tSources/Runtime/@_cdecl("kk_*")\t%s\n' \
  "$(count_unique_regex_matches '@_cdecl\("kk_[A-Za-z0-9_]+"\)' "${RUNTIME_SWIFT_FILES[@]}")"
printf '__kk_cdecl_count\tSources/Runtime/@_cdecl("__kk_*")\t%s\n' \
  "$(count_unique_regex_matches '@_cdecl\("__kk_[A-Za-z0-9_]+"\)' "${RUNTIME_SWIFT_FILES[@]}")"
printf 'interner_resolve_literal_comparison_count\tSwift sources\t%s\n' \
  "$(count_regex_occurrences 'interner\.resolve[^=]*==[[:space:]]*"[^"]+"' "${SWIFT_FILES[@]}")"
printf 'typecheck_interner_resolve_literal_comparison_count\tSources/CompilerCore/Sema/TypeCheck\t%s\n' \
  "$(count_regex_occurrences 'interner\.resolve[^=]*==[[:space:]]*"[^"]+"' "${SEMA_TYPECHECK_FILES[@]}")"
