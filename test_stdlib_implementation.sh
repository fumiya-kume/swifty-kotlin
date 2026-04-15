#!/bin/bash

# Test all Phase 1 & Phase 2 stdlib implementations
echo "=== Testing Kotlin Stdlib Implementation ==="

# Phase 1: Basic APIs (High Priority)
phase1_tests=(
    "math_constants.kt"
    "system_current_time_millis.kt"
    "measure_time_duration.kt"
    "experimental_time.kt"
    "uuid_basic.kt"
)

# Phase 2: Advanced APIs (Medium Priority)
phase2_tests=(
    "test_framework_basic.kt"
    "delegate_observable.kt"
    "delegate_vetoable.kt"
    "reflect_kclass_ktype.kt"
)

echo "--- Phase 1: Basic APIs ---"
passed=0
failed=0

for test in "${phase1_tests[@]}"; do
    echo "Testing $test..."
    if ./Scripts/diff_kotlinc.sh "Scripts/diff_cases/$test"; then
        echo "✓ PASS: $test"
        ((passed++))
    else
        echo "✗ FAIL: $test"
        ((failed++))
    fi
    echo ""
done

echo "--- Phase 2: Advanced APIs ---"
for test in "${phase2_tests[@]}"; do
    echo "Testing $test..."
    if ./Scripts/diff_kotlinc.sh "Scripts/diff_cases/$test"; then
        echo "✓ PASS: $test"
        ((passed++))
    else
        echo "✗ FAIL: $test"
        ((failed++))
    fi
    echo ""
done

echo "=== Summary ==="
echo "Passed: $passed"
echo "Failed: $failed"
echo "Total: $((passed + failed))"

if [ $failed -eq 0 ]; then
    echo "All stdlib implementation tests passed! ✓"
    echo "Kotlin stdlib Phase 1 & Phase 2 implementation is COMPLETE!"
    exit 0
else
    echo "Some tests failed. See details above."
    exit 1
fi
