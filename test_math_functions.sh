#!/bin/bash

# Test all math function implementations
echo "=== Testing Kotlin Math Functions ==="

tests=(
    "math_constants.kt"
    "math_basic.kt" 
    "math_advanced.kt"
    "math_extended.kt"
    "math_exp_log_functions.kt"
    "math_float_overloads.kt"
    "math_float_overloads_edge.kt"
)

passed=0
failed=0

for test in "${tests[@]}"; do
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
    echo "All math function tests passed! ✓"
    exit 0
else
    echo "Some tests failed. See details above."
    exit 1
fi
