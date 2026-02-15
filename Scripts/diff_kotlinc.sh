#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
KOTLINC="${KOTLINC:-kotlinc}"
JAVA_BIN="${JAVA_BIN:-java}"
KEEP_TEMP=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <file-or-dir>

Options:
  --kswiftc <path>   Path to kswiftc binary (default: .build/debug/kswiftc)
  --kotlinc <path>   Path to kotlinc command (default: kotlinc)
  --java <path>      Path to java command (default: java)
  --keep-temp        Keep per-test temporary directories
  -h, --help         Show this help

Examples:
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases
  bash Scripts/diff_kotlinc.sh path/to/program.kt
USAGE
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kswiftc)
      shift
      KSWIFTC="$1"
      ;;
    --kotlinc)
      shift
      KOTLINC="$1"
      ;;
    --java)
      shift
      JAVA_BIN="$1"
      ;;
    --keep-temp)
      KEEP_TEMP=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo "Only one file-or-dir argument is supported." >&2
        exit 1
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ ! -x "$KSWIFTC" ]]; then
  echo "kswiftc not found or not executable: $KSWIFTC" >&2
  exit 1
fi

if ! command -v "$KOTLINC" >/dev/null 2>&1; then
  echo "kotlinc command not found: $KOTLINC" >&2
  exit 1
fi

if ! command -v "$JAVA_BIN" >/dev/null 2>&1; then
  echo "java command not found: $JAVA_BIN" >&2
  exit 1
fi

collect_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
    return
  fi
  if [[ ! -d "$path" ]]; then
    echo "Target does not exist: $path" >&2
    exit 1
  fi
  find "$path" -type f -name '*.kt' | sort
}

normalize_text() {
  tr -d '\r'
}

run_case() {
  local kt_file="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d -t kswiftk-diff-XXXXXX)"

  local ref_jar="$tmp_dir/ref.jar"
  local ref_compile_stdout="$tmp_dir/ref_compile.stdout"
  local ref_compile_stderr="$tmp_dir/ref_compile.stderr"
  local ref_run_stdout="$tmp_dir/ref_run.stdout"
  local ref_run_stderr="$tmp_dir/ref_run.stderr"

  local cand_bin="$tmp_dir/candidate.out"
  local cand_compile_stdout="$tmp_dir/cand_compile.stdout"
  local cand_compile_stderr="$tmp_dir/cand_compile.stderr"
  local cand_run_stdout="$tmp_dir/cand_run.stdout"
  local cand_run_stderr="$tmp_dir/cand_run.stderr"

  : >"$ref_run_stdout"
  : >"$ref_run_stderr"
  : >"$cand_run_stdout"
  : >"$cand_run_stderr"

  local ref_compile_exit=0
  local ref_run_exit=0
  local cand_compile_exit=0
  local cand_run_exit=0

  "$KOTLINC" "$kt_file" -include-runtime -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
  if [[ $ref_compile_exit -eq 0 ]]; then
    "$JAVA_BIN" -jar "$ref_jar" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
  fi

  "$KSWIFTC" "$kt_file" -o "$cand_bin" >"$cand_compile_stdout" 2>"$cand_compile_stderr" || cand_compile_exit=$?
  if [[ $cand_compile_exit -eq 0 ]]; then
    "$cand_bin" >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
  fi

  normalize_text <"$ref_compile_stderr" >"$tmp_dir/ref_compile_stderr.norm"
  normalize_text <"$cand_compile_stderr" >"$tmp_dir/cand_compile_stderr.norm"
  normalize_text <"$ref_run_stdout" >"$tmp_dir/ref_run_stdout.norm" || true
  normalize_text <"$cand_run_stdout" >"$tmp_dir/cand_run_stdout.norm" || true

  local ok=1

  if [[ $ref_compile_exit -ne $cand_compile_exit ]]; then
    ok=0
    echo "  compile exit mismatch: ref=$ref_compile_exit candidate=$cand_compile_exit"
  fi

  if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
    if [[ $ref_run_exit -ne $cand_run_exit ]]; then
      ok=0
      echo "  run exit mismatch: ref=$ref_run_exit candidate=$cand_run_exit"
    fi
    if ! diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" >/dev/null; then
      ok=0
      echo "  stdout mismatch:"
      diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" || true
    fi
  fi

  if [[ $ok -eq 1 ]]; then
    echo "PASS $kt_file"
  else
    echo "FAIL $kt_file"
    echo "  ref compile stderr:"
    sed -n '1,120p' "$tmp_dir/ref_compile_stderr.norm"
    echo "  candidate compile stderr:"
    sed -n '1,120p' "$tmp_dir/cand_compile_stderr.norm"
    if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
      echo "  ref run stderr:"
      sed -n '1,120p' "$ref_run_stderr"
      echo "  candidate run stderr:"
      sed -n '1,120p' "$cand_run_stderr"
    fi
  fi

  if [[ $KEEP_TEMP -eq 0 && $ok -eq 1 ]]; then
    rm -rf "$tmp_dir"
  else
    echo "  artifacts: $tmp_dir"
  fi

  return $((1 - ok))
}

TOTAL=0
FAILED=0
while IFS= read -r test_case; do
  [[ -z "$test_case" ]] && continue
  TOTAL=$((TOTAL + 1))
  if ! run_case "$test_case"; then
    FAILED=$((FAILED + 1))
  fi
done < <(collect_cases "$TARGET")

if [[ $TOTAL -eq 0 ]]; then
  echo "No .kt files found." >&2
  exit 1
fi

echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED))"
if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
