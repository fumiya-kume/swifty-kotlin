#!/usr/bin/env bash
set -euo pipefail

# Smoke-tests the mutation generator itself (determinism + operation
# coverage) plus the fuzz runner's timeout classification via a stub kswiftc.
# Compiling generated/corpus cases against a real kswiftc is the nightly
# workflow's job (nightly-mutation-fuzzer.yml) — its "Replay committed crash
# corpus" and "Run bounded mutation fuzzer" steps already cover that ground,
# so this script needs no real kswiftc/stdlib inputs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-mutation-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_generator() {
  local output_dir="$1"
  "$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
    --seed-dir "$SCRIPT_DIR/diff_cases" \
    --seed 23023 \
    --cases 24 \
    --duration-seconds 30 \
    --workers 1 \
    --generate-only \
    --output-dir "$output_dir"
}

run_generator "$TEMP_DIR/generated-a"
run_generator "$TEMP_DIR/generated-b"
diff -ru "$TEMP_DIR/generated-a" "$TEMP_DIR/generated-b"

"$PYTHON_BIN" - "$TEMP_DIR/generated-a/manifest.json" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
operations = {entry["mutation"]["operation"] for entry in manifest}
# Kept in sync by hand with the operations mutate_diff_cases.py can choose from.
expected = {"replace", "delete", "swap"}
missing = expected - operations
if missing:
    raise SystemExit(f"deterministic mutation smoke missed operations: {sorted(missing)}")
print(f"Deterministic mutation smoke: {len(manifest)} cases, operations={sorted(operations)}")
PY

# Regression: a timeout recorded under a truncated per-case budget (the
# --duration-seconds deadline shortening --timeout-seconds) must be reported
# as inconclusive, not counted as a finding. A stub kswiftc that always hangs
# keeps this test free of a real compiler/stdlib.
cat > "$TEMP_DIR/stub-kswiftc" <<'SH'
#!/usr/bin/env bash
sleep 30
SH
chmod +x "$TEMP_DIR/stub-kswiftc"

set +e
"$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
  --seed-dir "$SCRIPT_DIR/diff_cases" \
  --kswiftc "$TEMP_DIR/stub-kswiftc" \
  --seed 23023 \
  --cases 8 \
  --duration-seconds 3 \
  --timeout-seconds 2 \
  --workers 1 \
  --report "$TEMP_DIR/report.json" > "$TEMP_DIR/fuzz.out" 2>&1
fuzz_rc=$?
set -e

"$PYTHON_BIN" - "$TEMP_DIR/report.json" "$fuzz_rc" <<'PY'
import json
import sys

records = json.load(open(sys.argv[1], encoding="utf-8"))
rc = int(sys.argv[2])
full = [r for r in records if r["result"]["kind"] == "timeout" and r["finding"]]
truncated = [r for r in records if r["result"]["kind"] == "timeout" and not r["finding"]]
if not full:
    raise SystemExit("expected at least one full-budget timeout finding")
if not truncated:
    raise SystemExit("expected at least one budget-truncated timeout to be inconclusive")
if rc != 1:
    raise SystemExit(f"expected exit code 1 with findings, got {rc}")
print(f"Timeout budget regression: {len(full)} finding(s), {len(truncated)} inconclusive timeout(s)")
PY

echo "Mutation generator smoke test passed."
