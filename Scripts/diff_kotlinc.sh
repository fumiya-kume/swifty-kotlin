#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
KOTLINC="${KOTLINC:-kotlinc}"
KOTLINC_CLASSPATH="${KOTLINC_CLASSPATH:-${KOTLINC_CP:-}}"
JAVA_BIN="${JAVA_BIN:-java}"
KOTLINC_COROUTINES_VERSION="${KOTLINC_COROUTINES_VERSION:-${KOTLINX_COROUTINES_VERSION:-1.10.2}}"
KOTLINC_DEP_DIR="${KOTLINC_DEP_DIR:-$ROOT_DIR/.runtime-build/deps}"
KOTLINC_COROUTINES_JAR="${KOTLINC_COROUTINES_JAR:-$KOTLINC_DEP_DIR/kotlinx-coroutines-core-jvm-$KOTLINC_COROUTINES_VERSION.jar}"
KEEP_TEMP=0
REPORT_PATH=""
DIFF_PARALLEL="${DIFF_PARALLEL:-1}"
DIFF_WORKERS="${DIFF_WORKERS:-4}"
LAST_ARTIFACT_DIR=""
COMPILE_TIMEOUT="${DIFF_COMPILE_TIMEOUT:-120}"
RUN_TIMEOUT="${DIFF_RUN_TIMEOUT:-30}"
TIMEOUT_CMD="${TIMEOUT:-timeout}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <file-or-dir>

Options:
  --kswiftc <path>   Path to kswiftc binary (default: .build/debug/kswiftc)
  --kotlinc <path>   Path to kotlinc command (default: kotlinc)
  --kotlinc-classpath <path>
                     Additional classpath for kotlinc and java (default: \$KOTLINC_CLASSPATH)
  --java <path>      Path to java command (default: java)
  --parallel [0|1]   Enable (or disable) parallel execution (default: env DIFF_PARALLEL)
  --no-parallel      Disable parallel execution
  --jobs <n>         Number of parallel workers (default: env DIFF_WORKERS, default: 4, clipped by CPU)
  --compile-timeout <seconds>
                     Per-compiler timeout (default: \$DIFF_COMPILE_TIMEOUT or 120)
  --run-timeout <seconds>
                     Per-program timeout (default: \$DIFF_RUN_TIMEOUT or 30)
  --keep-temp        Keep per-test temporary directories
  --report <path>    Write TSV report (case, status, artifact_dir)
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
    --kotlinc-classpath)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --kotlinc-classpath" >&2
        exit 1
      fi
      KOTLINC_CLASSPATH="$1"
      ;;
    --kotlinc-classpath=*)
      KOTLINC_CLASSPATH="${1#*=}"
      ;;
    --java)
      shift
      JAVA_BIN="$1"
      ;;
    --parallel)
      if [[ $# -gt 1 && ( "$2" == "0" || "$2" == "1" ) ]]; then
        DIFF_PARALLEL="$2"
        shift
      else
        DIFF_PARALLEL=1
      fi
      ;;
    --no-parallel)
      DIFF_PARALLEL=0
      ;;
    --jobs)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--jobs requires an argument" >&2
        exit 1
      fi
      DIFF_WORKERS="$1"
      ;;
    --jobs=*)
      DIFF_WORKERS="${1#*=}"
      ;;
    --compile-timeout)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--compile-timeout requires an argument" >&2
        exit 1
      fi
      COMPILE_TIMEOUT="$1"
      ;;
    --run-timeout)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--run-timeout requires an argument" >&2
        exit 1
      fi
      RUN_TIMEOUT="$1"
      ;;
    --keep-temp)
      KEEP_TEMP=1
      ;;
    --report)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--report requires an argument" >&2
        exit 1
      fi
      REPORT_PATH="$1"
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

requires_kotlinx_coroutines() {
  local target="$1"
  if [[ -f "$target" ]]; then
    rg -q 'import[[:space:]]+kotlinx\.coroutines' "$target"
    return $?
  fi
  if [[ -d "$target" ]]; then
    rg -q 'import[[:space:]]+kotlinx\.coroutines' --glob '*.kt' "$target"
    return $?
  fi
  return 1
}

ensure_kotlinc_classpath() {
  if [[ -n "$KOTLINC_CLASSPATH" ]]; then
    return 0
  fi

  if ! requires_kotlinx_coroutines "$TARGET"; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download kotlinx-coroutines dependency" >&2
    return 1
  fi

  mkdir -p "$KOTLINC_DEP_DIR"
  if [[ ! -s "$KOTLINC_COROUTINES_JAR" ]]; then
    local download_url
    download_url="https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/${KOTLINC_COROUTINES_VERSION}/kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar"
    echo "Downloading kotlinx-coroutines-core-jvm ${KOTLINC_COROUTINES_VERSION}..."
    curl -fSL -o "$KOTLINC_COROUTINES_JAR" "$download_url"
    
    local expected_sha256="5ca175b38df331fd64155b35cd8cae1251fa9ee369709b36d42e0a288ccce3fd"
    local actual_sha256
    if command -v shasum >/dev/null 2>&1; then
      actual_sha256="$(shasum -a 256 "$KOTLINC_COROUTINES_JAR" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
      actual_sha256="$(sha256sum "$KOTLINC_COROUTINES_JAR" | awk '{print $1}')"
    else
      echo "Warning: shasum or sha256sum not found, skipping checksum verification" >&2
      actual_sha256="$expected_sha256"
    fi
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
      echo "Error: checksum mismatch for kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar" >&2
      echo "Expected: $expected_sha256" >&2
      echo "Actual:   $actual_sha256" >&2
      rm -f "$KOTLINC_COROUTINES_JAR"
      return 1
    fi
  fi
  KOTLINC_CLASSPATH="$KOTLINC_COROUTINES_JAR"
}

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

ensure_kotlinc_classpath

if ! [[ "$DIFF_PARALLEL" =~ ^[01]$ ]]; then
  echo "DIFF_PARALLEL must be 0 or 1: $DIFF_PARALLEL" >&2
  exit 1
fi

if ! [[ "$DIFF_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  echo "DIFF_WORKERS must be a positive integer: $DIFF_WORKERS" >&2
  exit 1
fi

if ! [[ "$COMPILE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "compile timeout must be a positive integer: $COMPILE_TIMEOUT" >&2
  exit 1
fi

if ! [[ "$RUN_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "run timeout must be a positive integer: $RUN_TIMEOUT" >&2
  exit 1
fi

if [[ -n "$REPORT_PATH" ]]; then
  : >"$REPORT_PATH"
fi

if ! [[ -x "$KSWIFTC" ]]; then
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

if [[ -n "$KOTLINC_CLASSPATH" ]] && ! command -v unzip >/dev/null 2>&1; then
  echo "unzip command not found: unzip" >&2
  exit 1
fi

detect_workers() {
  local detected

  if detected="$(nproc 2>/dev/null)" \
    && [[ "$detected" =~ ^[0-9]+$ ]] \
    && (( detected > 0 )); then
    printf "%s" "$detected"
    return
  fi

  if detected="$(sysctl -n hw.logicalcpu 2>/dev/null)" \
    && [[ "$detected" =~ ^[0-9]+$ ]] \
    && (( detected > 0 )); then
    printf "%s" "$detected"
    return
  fi

  if detected="$(sysctl -n hw.physicalcpu 2>/dev/null)" \
    && [[ "$detected" =~ ^[0-9]+$ ]] \
    && (( detected > 0 )); then
    printf "%s" "$detected"
    return
  fi

  printf "" 
}

jar_main_class() {
  local jar_path="$1"
  unzip -p "$jar_path" META-INF/MANIFEST.MF 2>/dev/null \
    | tr -d '\r' \
    | awk -F': ' '/^Main-Class:/ { print $2; exit }'
}

WORKER_COUNT="$DIFF_WORKERS"
if [[ "$DIFF_PARALLEL" -eq 1 ]]; then
  CPU_LIMIT="$(detect_workers)"
  if [[ -n "$CPU_LIMIT" && "$WORKER_COUNT" -gt "$CPU_LIMIT" ]]; then
    WORKER_COUNT="$CPU_LIMIT"
  fi
else
  WORKER_COUNT=1
fi

if [[ "$WORKER_COUNT" -lt 1 ]]; then
  WORKER_COUNT=1
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

should_skip_case() {
  local kt_file="$1"
  grep -Eq '^[[:space:]]*//[[:space:]]*(KSWIFTK_DIFF_IGNORE|SKIP-DIFF)\b' "$kt_file"
}

run_case() {
  local kt_file="$1"
  local artifact_file="${2:-}"
  local tmp_dir
  tmp_dir="$(mktemp -d -t kswiftk-diff-XXXXXX)"
  LAST_ARTIFACT_DIR="$tmp_dir"

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

  : >"$ref_compile_stdout"
  : >"$ref_compile_stderr"
  : >"$ref_run_stdout"
  : >"$ref_run_stderr"
  : >"$cand_run_stdout"
  : >"$cand_run_stderr"

  local ref_compile_exit=0
  local ref_run_exit=0
  local cand_compile_exit=0
  local cand_run_exit=0

  local basename
  basename="$(basename "$kt_file")"
  local is_script=0
  if [[ "$basename" == script_* ]]; then
    is_script=1
  fi

  if [[ $is_script -eq 1 ]]; then
    local kts_tmp="$tmp_dir/${basename%.kt}.kts"
    cp "$kt_file" "$kts_tmp"
    local script_exit=0
    if [[ -n "$KOTLINC_CLASSPATH" ]]; then
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$KOTLINC" -Xcontext-parameters -classpath "$KOTLINC_CLASSPATH" -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || script_exit=$?
    else
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$KOTLINC" -Xcontext-parameters -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || script_exit=$?
    fi
    if [[ $script_exit -eq 124 ]]; then
      # Timeout in script mode is a runtime timeout, not a compile timeout
      ref_run_exit=124
    elif [[ $script_exit -ne 0 ]] && [[ ! -s "$ref_run_stdout" ]]; then
      ref_compile_exit=$script_exit
    else
      ref_run_exit=$script_exit
    fi
  else
    if [[ -n "$KOTLINC_CLASSPATH" ]]; then
      "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters -classpath "$KOTLINC_CLASSPATH" "$kt_file" -include-runtime -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
    else
      "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters "$kt_file" -include-runtime -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
    fi
    if [[ $ref_compile_exit -eq 0 ]]; then
      if [[ -n "$KOTLINC_CLASSPATH" ]]; then
        local main_class
        main_class="$(jar_main_class "$ref_jar")"
        if [[ -z "$main_class" ]]; then
          ref_run_exit=1
          echo "Missing Main-Class in reference jar manifest." >"$ref_run_stderr"
        else
          "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" -cp "$ref_jar:$KOTLINC_CLASSPATH" "$main_class" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
        fi
      else
        "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" -jar "$ref_jar" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
      fi
    fi
  fi

  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" "$kt_file" -o "$cand_bin" >"$cand_compile_stdout" 2>"$cand_compile_stderr" || cand_compile_exit=$?
  if [[ $cand_compile_exit -eq 0 ]]; then
    "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$cand_bin" >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
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
  if [[ $ref_compile_exit -eq 124 ]]; then
    ok=0
    echo "  ref compile timed out after ${COMPILE_TIMEOUT}s"
  fi
  if [[ $cand_compile_exit -eq 124 ]]; then
    ok=0
    echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
  fi

  if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
    if [[ $ref_run_exit -ne $cand_run_exit ]]; then
      ok=0
      echo "  run exit mismatch: ref=$ref_run_exit candidate=$cand_run_exit"
    fi
    if [[ $ref_run_exit -eq 124 ]]; then
      ok=0
      echo "  ref run timed out after ${RUN_TIMEOUT}s"
    fi
    if [[ $cand_run_exit -eq 124 ]]; then
      ok=0
      echo "  candidate run timed out after ${RUN_TIMEOUT}s"
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
    LAST_ARTIFACT_DIR=""
  else
    echo "  artifacts: $tmp_dir"
  fi

  if [[ -n "$artifact_file" ]]; then
    printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
  fi

  return $((1 - ok))
}

run_case_worker() {
  local kt_file="$1"
  local log_path="$2"
  local status_path="$3"
  local artifact_file="$4"

  local case_exit=0
  local status="PASS"
  local artifact=""

  run_case "$kt_file" "$artifact_file" >"$log_path" 2>&1 || case_exit=$?

  if [[ $case_exit -ne 0 ]]; then
    status="FAIL"
  fi

  artifact="$(cat "$artifact_file" 2>/dev/null || true)"
  printf '%s\t%s\n' "$status" "$artifact" >"$status_path"
}

TOTAL=0
FAILED=0
SKIPPED=0
if [[ "$DIFF_PARALLEL" -eq 0 || "$WORKER_COUNT" -le 1 ]]; then
  while IFS= read -r test_case; do
    [[ -z "$test_case" ]] && continue
    if should_skip_case "$test_case"; then
      echo "SKIP $test_case (// SKIP-DIFF)"
      SKIPPED=$((SKIPPED + 1))
      if [[ -n "$REPORT_PATH" ]]; then
        printf '%s\tSKIP\t\n' "$test_case" >>"$REPORT_PATH"
      fi
      continue
    fi
    TOTAL=$((TOTAL + 1))
    echo "CASE $TOTAL: $test_case"
    status="PASS"
    if ! run_case "$test_case"; then
      FAILED=$((FAILED + 1))
      status="FAIL"
    fi
    if [[ -n "$REPORT_PATH" ]]; then
      printf '%s\t%s\t%s\n' "$test_case" "$status" "$LAST_ARTIFACT_DIR" >>"$REPORT_PATH"
    fi
  done < <(collect_cases "$TARGET")
else
  declare -a TEST_CASES=()
  declare -a CASE_KIND=()
  declare -a CASE_NUM=()
  declare -a RUN_INPUT_INDEXES=()
  while IFS= read -r test_case; do
    [[ -z "$test_case" ]] && continue
    TEST_CASES+=("$test_case")
  done < <(collect_cases "$TARGET")

  if [[ ${#TEST_CASES[@]} -eq 0 ]]; then
    echo "No .kt files found." >&2
    exit 1
  fi
  for i in "${!TEST_CASES[@]}"; do
    test_case="${TEST_CASES[$i]}"
    if should_skip_case "$test_case"; then
      CASE_KIND[$i]="SKIP"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    TOTAL=$((TOTAL + 1))
    CASE_KIND[$i]="RUN"
    CASE_NUM[$i]="$TOTAL"
    RUN_INPUT_INDEXES+=("$i")
  done

  RUN_DIR="$(mktemp -d -t kswiftk-diff-run-XXXXXX)"
  declare -a RUNNING_PIDS=()

  for input_index in "${RUN_INPUT_INDEXES[@]}"; do
    test_case="${TEST_CASES[$input_index]}"
    log_path="$RUN_DIR/case_${input_index}.log"
    status_path="$RUN_DIR/case_${input_index}.status"
    artifact_path="$RUN_DIR/case_${input_index}.artifact"

    run_case_worker "$test_case" "$log_path" "$status_path" "$artifact_path" &
    RUNNING_PIDS+=("$!")

    if (( ${#RUNNING_PIDS[@]} >= WORKER_COUNT )); then
      for pid in "${RUNNING_PIDS[@]}"; do
        wait "$pid" || true
      done
      RUNNING_PIDS=()
    fi
  done

  for pid in "${RUNNING_PIDS[@]}"; do
    wait "$pid" || true
  done

  for i in "${!TEST_CASES[@]}"; do
    test_case="${TEST_CASES[$i]}"
    if [[ "${CASE_KIND[$i]:-}" == "SKIP" ]]; then
      echo "SKIP $test_case (// SKIP-DIFF)"
      if [[ -n "$REPORT_PATH" ]]; then
        printf '%s\tSKIP\t\n' "$test_case" >>"$REPORT_PATH"
      fi
      continue
    fi
    case_number="${CASE_NUM[$i]:-0}"
    log_path="$RUN_DIR/case_${i}.log"
    status_path="$RUN_DIR/case_${i}.status"
    status="FAIL"
    artifact_dir=""

    if [[ -f "$status_path" ]]; then
      IFS=$'\t' read -r status artifact_dir < "$status_path" || true
    fi

    if [[ "$status" != "PASS" && "$status" != "FAIL" ]]; then
      status="FAIL"
    fi

    echo "CASE $case_number: $test_case"
    if [[ -f "$log_path" ]]; then
      cat "$log_path"
    else
      echo "FAIL $test_case"
      echo "  parallel worker output missing: $log_path"
      status="FAIL"
    fi

    if [[ "$status" == "FAIL" ]]; then
      FAILED=$((FAILED + 1))
    fi

    if [[ -n "$REPORT_PATH" ]]; then
      printf '%s\t%s\t%s\n' "$test_case" "$status" "$artifact_dir" >>"$REPORT_PATH"
    fi
  done

  rm -rf "$RUN_DIR"
fi

if [[ $TOTAL -eq 0 && $SKIPPED -eq 0 ]]; then
  echo "No .kt files found." >&2
  exit 1
fi

echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED)) skipped=$SKIPPED"
if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
