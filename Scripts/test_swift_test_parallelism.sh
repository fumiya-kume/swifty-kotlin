#!/usr/bin/env bash
# Exercise the real wrapper against a stub runner, without building Swift tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-test-parallelism.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/repo/Scripts/lib" "$TEST_DIR/repo/Tests" "$TEST_DIR/bin"
cp "$SCRIPT_DIR/swift_test.sh" "$TEST_DIR/repo/Scripts/"
cp "$SCRIPT_DIR/lib/common.sh" "$TEST_DIR/repo/Scripts/lib/"

cat > "$TEST_DIR/bin/swift" <<'EOF'
#!/usr/bin/env bash
printf 'width=%s\n' "${SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH-unset}"
printf 'arg=%s\n' "$@"
EOF
cat > "$TEST_DIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo Linux
EOF
chmod +x "$TEST_DIR/bin/swift" "$TEST_DIR/bin/uname"

run_wrapper() {
    env -u SWIFT_TEST_WORKERS -u SWIFT_TEST_PARALLEL \
        -u SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH \
        -u SWIFT_ENABLE_COMPILE_CACHE -u SWIFT_ENABLE_CACHE_REMARKS \
        -u GITHUB_ACTIONS -u SWIFT_TEST_PRODUCT -u SWIFT_BUILD_SYSTEM \
        PATH="$TEST_DIR/bin:$PATH" SWIFT_TEST_BUILD_JOBS=2 \
        "$@" > "$TEST_DIR/output" 2>&1
}

expect_line() {
    if ! grep -qxF -- "$1" "$TEST_DIR/output"; then
        cat "$TEST_DIR/output" >&2
        echo "FAIL: expected $1" >&2
        exit 1
    fi
}

reject_line() {
    if grep -qxF -- "$1" "$TEST_DIR/output"; then
        cat "$TEST_DIR/output" >&2
        echo "FAIL: unexpected $1" >&2
        exit 1
    fi
}

wrapper="$TEST_DIR/repo/Scripts/swift_test.sh"

# Swift Testing-only repositories must receive the override without XCTest flags.
run_wrapper SWIFT_TEST_WORKERS=3 bash "$wrapper" --filter Golden
expect_line width=3
reject_line arg=--num-workers

# Preserve explicit Swift Testing settings, including both CLI spellings.
run_wrapper SWIFT_TEST_WORKERS=3 SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=5 bash "$wrapper"
expect_line width=5
run_wrapper SWIFT_TEST_WORKERS=3 bash "$wrapper" --experimental-maximum-parallelization-width 2
expect_line width=unset
expect_line arg=--experimental-maximum-parallelization-width
expect_line arg=2
run_wrapper SWIFT_TEST_WORKERS=3 bash "$wrapper" --experimental-maximum-parallelization-width=6
expect_line width=unset
expect_line arg=--experimental-maximum-parallelization-width=6

# Keep default and discovery behavior, and pass serialization to the runner.
run_wrapper bash "$wrapper"
expect_line width=unset
run_wrapper SWIFT_TEST_WORKERS=3 bash "$wrapper" list
expect_line width=unset
reject_line arg=--parallel
run_wrapper SWIFT_TEST_WORKERS=3 SWIFT_TEST_PARALLEL=0 bash "$wrapper"
expect_line arg=--no-parallel
reject_line arg=--parallel
run_wrapper SWIFT_TEST_WORKERS=3 SWIFT_TEST_PARALLEL=0 bash "$wrapper" --parallel
expect_line arg=--parallel
reject_line arg=--no-parallel

# Invalid widths must not silently fall back to unrestricted parallelism.
if run_wrapper SWIFT_TEST_WORKERS=0 bash "$wrapper"; then
    echo "FAIL: accepted an invalid worker count" >&2
    exit 1
fi
expect_line 'error: SWIFT_TEST_WORKERS must be a positive integer'

# Mixed suites retain XCTest's worker flag as well as Swift Testing's width.
printf 'import XCTest\n' > "$TEST_DIR/repo/Tests/Example.swift"
run_wrapper SWIFT_TEST_WORKERS=3 bash "$wrapper"
expect_line width=3
expect_line arg=--num-workers
expect_line arg=3

echo 'PASS: Swift test parallelism overrides'
