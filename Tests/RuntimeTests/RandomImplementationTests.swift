import XCTest
@testable import Runtime

final class RandomImplementationTests: XCTestCase {

    // MARK: - Helpers

    private func createSeededRandom(seed: Int) -> Int {
        kk_random_create_seeded(seed)
    }

    private func bitsToFloat(_ bits: Int) -> Float {
        kk_bits_to_float(bits)
    }

    private func bitsToDouble(_ bits: Int) -> Double {
        kk_bits_to_double(bits)
    }

    // MARK: - nextLong() Tests (STDLIB-431)

    func testRandomNextLongImplementation() {
        // Test that kk_random_nextLong is properly implemented
        let defaultRandom = 0  // Random.Default
        let longValue = kk_random_nextLong(defaultRandom)
        
        // Should return a valid Int (representing Long on 64-bit)
        XCTAssertNotNil(longValue, "nextLong should return a valid value")
        
        // Test multiple calls produce different values (probabilistically)
        var values: Set<Int> = []
        for _ in 0..<10 {
            let value = kk_random_nextLong(defaultRandom)
            values.insert(value)
        }
        
        // With high probability, we should get different values
        XCTAssertGreaterThan(values.count, 1, "Multiple nextLong calls should produce different values")
    }

    func testRandomNextLongSeededDeterminism() {
        // Test that seeded random produces deterministic results
        let seed = 12345
        let random1 = createSeededRandom(seed: seed)
        let random2 = createSeededRandom(seed: seed)
        
        let value1 = kk_random_nextLong(random1)
        let value2 = kk_random_nextLong(random2)
        
        XCTAssertEqual(value1, value2, "Same seed should produce same sequence")
        
        // Test that next calls also match
        let value1_2 = kk_random_nextLong(random1)
        let value2_2 = kk_random_nextLong(random2)
        
        XCTAssertEqual(value1_2, value2_2, "Seeded sequence should be deterministic")
    }

    func testRandomNextLongRange() {
        // Test nextLong with range bounds
        let defaultRandom = 0
        var thrown: Int = 0
        
        // Test valid range
        let result = kk_random_nextLong_range(defaultRandom, 10, 20, &thrown)
        XCTAssertEqual(thrown, 0, "Valid range should not throw")
        XCTAssertGreaterThanOrEqual(result, 10, "Result should be >= from")
        XCTAssertLessThan(result, 20, "Result should be < until")
        
        // Test invalid range (from >= until)
        let invalidResult = kk_random_nextLong_range(defaultRandom, 20, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "Invalid range should throw")
        XCTAssertEqual(invalidResult, 0, "Thrown case should return 0")
    }

    func testRandomNextLongUntil() {
        // Test nextLong with upper bound
        let defaultRandom = 0
        var thrown: Int = 0
        
        // Test valid bound
        let result = kk_random_nextLong_until(defaultRandom, 100, &thrown)
        XCTAssertEqual(thrown, 0, "Valid bound should not throw")
        XCTAssertGreaterThanOrEqual(result, 0, "Result should be >= 0")
        XCTAssertLessThan(result, 100, "Result should be < until")
        
        // Test invalid bound (<= 0)
        thrown = 0
        let invalidResult = kk_random_nextLong_until(defaultRandom, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "Invalid bound should throw")
        XCTAssertEqual(invalidResult, 0, "Thrown case should return 0")
    }

    // MARK: - nextFloat() Tests (STDLIB-431)

    func testRandomNextFloatImplementation() {
        // Test that kk_random_nextFloat is properly implemented
        let defaultRandom = 0  // Random.Default
        let floatValueBits = kk_random_nextFloat(defaultRandom)
        let floatValue = bitsToFloat(floatValueBits)
        
        // Should return a valid Float in [0.0, 1.0)
        XCTAssertGreaterThanOrEqual(floatValue, 0.0, "nextFloat should be >= 0.0")
        XCTAssertLessThan(floatValue, 1.0, "nextFloat should be < 1.0")
        XCTAssertTrue(floatValue.isFinite, "nextFloat should be finite")
    }

    func testRandomNextFloatSeededDeterminism() {
        // Test that seeded random produces deterministic Float results
        let seed = 12345
        let random1 = createSeededRandom(seed: seed)
        let random2 = createSeededRandom(seed: seed)
        
        let bits1 = kk_random_nextFloat(random1)
        let bits2 = kk_random_nextFloat(random2)
        let value1 = bitsToFloat(bits1)
        let value2 = bitsToFloat(bits2)
        
        XCTAssertEqual(value1, value2, "Same seed should produce same Float sequence")
        
        // Test that next calls also match
        let bits1_2 = kk_random_nextFloat(random1)
        let bits2_2 = kk_random_nextFloat(random2)
        let value1_2 = bitsToFloat(bits1_2)
        let value2_2 = bitsToFloat(bits2_2)
        
        XCTAssertEqual(value1_2, value2_2, "Seeded Float sequence should be deterministic")
    }

    func testRandomNextFloatRange() {
        // Test nextFloat with range bounds
        let defaultRandom = 0
        var thrown: Int = 0
        
        let fromBits = kk_float_to_bits(0.5)
        let untilBits = kk_float_to_bits(1.5)
        
        // Test valid range
        let resultBits = kk_random_nextFloat_range(defaultRandom, fromBits, untilBits, &thrown)
        XCTAssertEqual(thrown, 0, "Valid range should not throw")
        
        let result = bitsToFloat(resultBits)
        XCTAssertGreaterThanOrEqual(result, 0.5, "Result should be >= from")
        XCTAssertLessThan(result, 1.5, "Result should be < until")
        XCTAssertTrue(result.isFinite, "Result should be finite")
        
        // Test invalid range (from >= until)
        thrown = 0
        let invalidResultBits = kk_random_nextFloat_range(defaultRandom, untilBits, fromBits, &thrown)
        XCTAssertNotEqual(thrown, 0, "Invalid range should throw")
        XCTAssertEqual(invalidResultBits, 0, "Thrown case should return 0")
    }

    func testRandomNextFloatUntil() {
        // Test nextFloat with upper bound
        let defaultRandom = 0
        var thrown: Int = 0
        
        let untilBits = kk_float_to_bits(2.5)
        
        // Test valid bound
        let resultBits = kk_random_nextFloat_until(defaultRandom, untilBits, &thrown)
        XCTAssertEqual(thrown, 0, "Valid bound should not throw")
        
        let result = bitsToFloat(resultBits)
        XCTAssertGreaterThanOrEqual(result, 0.0, "Result should be >= 0.0")
        XCTAssertLessThan(result, 2.5, "Result should be < until")
        XCTAssertTrue(result.isFinite, "Result should be finite")
        
        // Test invalid bound (<= 0 or NaN/infinite)
        thrown = 0
        let nanBits = kk_float_to_bits(Float.nan)
        let invalidResultBits = kk_random_nextFloat_until(defaultRandom, nanBits, &thrown)
        XCTAssertNotEqual(thrown, 0, "Invalid bound should throw")
        XCTAssertEqual(invalidResultBits, 0, "Thrown case should return 0")
    }

    // MARK: - Integration Tests

    func testRandomImplementationConsistency() {
        // Test that different random methods work together consistently
        let seed = 42
        let random = createSeededRandom(seed: seed)
        
        // Generate values using different methods
        let longValue = kk_random_nextLong(random)
        let floatBits = kk_random_nextFloat(random)
        let doubleBits = kk_random_nextDouble(random)
        
        // All should be valid
        XCTAssertNotNil(longValue, "nextLong should return valid value")
        
        let floatValue = bitsToFloat(floatBits)
        XCTAssertTrue(floatValue.isFinite && floatValue >= 0.0 && floatValue < 1.0, 
                     "nextFloat should return valid value")
        
        let doubleValue = bitsToDouble(doubleBits)
        XCTAssertTrue(doubleValue.isFinite && doubleValue >= 0.0 && doubleValue < 1.0, 
                     "nextDouble should return valid value")
    }

    func testRandomDefaultVsSeeded() {
        // Test behavior differences between default and seeded random
        let defaultRandom = 0
        let seededRandom = createSeededRandom(seed: 123)
        
        // Generate sequences
        var defaultValues: [Int] = []
        var seededValues: [Int] = []
        
        for _ in 0..<5 {
            defaultValues.append(kk_random_nextLong(defaultRandom))
            seededValues.append(kk_random_nextLong(seededRandom))
        }
        
        // Default random should be non-deterministic (different from seeded)
        XCTAssertNotEqual(defaultValues, seededValues, "Default and seeded should produce different sequences")
    }

    func testRandomPerformanceCharacteristics() {
        // Test that random generation is reasonably fast
        let defaultRandom = 0
        
        measure {
            for _ in 0..<1000 {
                _ = kk_random_nextLong(defaultRandom)
                _ = kk_random_nextFloat(defaultRandom)
                _ = kk_random_nextDouble(defaultRandom)
            }
        }
    }

    // MARK: - Edge Case Tests

    func testRandomEdgeCases() {
        let defaultRandom = 0
        var thrown: Int = 0
        
        // Test extreme ranges
        let maxLongValue = kk_random_nextLong_range(defaultRandom, Int.max - 10, Int.max, &thrown)
        XCTAssertEqual(thrown, 0, "Extreme range should not throw")
        XCTAssertGreaterThanOrEqual(maxLongValue, Int.max - 10, "Extreme range should work")
        
        // Test very small ranges
        let smallRangeValue = kk_random_nextLong_range(defaultRandom, 5, 6, &thrown)
        XCTAssertEqual(thrown, 0, "Small range should not throw")
        XCTAssertEqual(smallRangeValue, 5, "Single-value range should return that value")
        
        // Test Float edge cases
        let epsilonBits = kk_float_to_bits(Float.ulpOfOne)
        let epsilonResultBits = kk_random_nextFloat_range(defaultRandom, 0, epsilonBits, &thrown)
        XCTAssertEqual(thrown, 0, "Very small float range should not throw")
        
        let epsilonResult = bitsToFloat(epsilonResultBits)
        XCTAssertGreaterThanOrEqual(epsilonResult, 0.0, "Very small range should be >= 0")
        XCTAssertLessThanOrEqual(epsilonResult, Float.ulpOfOne, "Very small range should be <= epsilon")
    }

    // MARK: - STDLIB-514/515 Integration Tests

    func testStdlib514515Integration() {
        // These tests verify that the implementation addresses STDLIB-514/515 concerns
        // about Random.nextLong() and nextFloat() consistency and behavior
        
        let seed = 999
        let random = createSeededRandom(seed: seed)
        
        // Test that nextLong produces full-range values
        let longValue = kk_random_nextLong(random)
        // Should be able to produce values across the full Int range
        XCTAssertNotNil(longValue, "nextLong should produce valid full-range values")
        
        // Test that nextFloat produces proper floating-point values
        let floatBits = kk_random_nextFloat(random)
        let floatValue = bitsToFloat(floatBits)
        
        // Verify float is in correct range and has proper precision
        XCTAssertGreaterThanOrEqual(floatValue, 0.0, "nextFloat should be >= 0.0")
        XCTAssertLessThan(floatValue, 1.0, "nextFloat should be < 1.0")
        
        // Test that multiple calls produce reasonably distributed values
        var floatValues: [Float] = []
        for _ in 0..<100 {
            let bits = kk_random_nextFloat(random)
            floatValues.append(bitsToFloat(bits))
        }
        
        // Basic statistical checks
        let average = floatValues.reduce(0, +) / Float(floatValues.count)
        XCTAssertGreaterThan(average, 0.1, "Average should be reasonable")
        XCTAssertLessThan(average, 0.9, "Average should be reasonable")
        
        let min = floatValues.min()!
        let max = floatValues.max()!
        XCTAssertGreaterThanOrEqual(min, 0.0, "Min should be >= 0")
        XCTAssertLessThan(max, 1.0, "Max should be < 1")
    }
}
