import XCTest
@testable import Runtime

final class NumericBitCountTests: XCTestCase {

    // MARK: - Int Bit Count Tests (32-bit semantics)

    func testIntCountOneBitsBasicValues() {
        // Test basic values
        XCTAssertEqual(kk_int_countOneBits(0), 0, "Zero should have 0 bits set")
        XCTAssertEqual(kk_int_countOneBits(1), 1, "1 should have 1 bit set")
        XCTAssertEqual(kk_int_countOneBits(2), 1, "2 should have 1 bit set")
        XCTAssertEqual(kk_int_countOneBits(3), 2, "3 should have 2 bits set")
        XCTAssertEqual(kk_int_countOneBits(0xFFFFFFFF), 32, "All 32 bits set should return 32")
    }

    func testIntCountOneBitsNegativeValues() {
        // Test negative values (32-bit two's complement)
        XCTAssertEqual(kk_int_countOneBits(-1), 32, "-1 (0xFFFFFFFF) should have 32 bits set")
        XCTAssertEqual(kk_int_countOneBits(-2), 31, "-2 (0xFFFFFFFE) should have 31 bits set")
        XCTAssertEqual(kk_int_countOneBits(Int(Int32.min)), 1, "Int32.min (0x80000000) should have 1 bit set")
    }

    func testIntCountLeadingZeroBitsBasicValues() {
        // Test basic values
        XCTAssertEqual(kk_int_countLeadingZeroBits(0), 32, "Zero should have 32 leading zeros")
        XCTAssertEqual(kk_int_countLeadingZeroBits(1), 31, "1 should have 31 leading zeros")
        XCTAssertEqual(kk_int_countLeadingZeroBits(0x80000000), 0, "MSB set should have 0 leading zeros")
        XCTAssertEqual(kk_int_countLeadingZeroBits(0x7FFFFFFF), 1, "All bits except MSB should have 1 leading zero")
    }

    func testIntCountLeadingZeroBitsNegativeValues() {
        // Test negative values (32-bit two's complement)
        XCTAssertEqual(kk_int_countLeadingZeroBits(-1), 0, "-1 (all bits set) should have 0 leading zeros")
        XCTAssertEqual(kk_int_countLeadingZeroBits(Int(Int32.min)), 0, "Int32.min (MSB set) should have 0 leading zeros")
    }

    func testIntCountTrailingZeroBitsBasicValues() {
        // Test basic values
        XCTAssertEqual(kk_int_countTrailingZeroBits(0), 32, "Zero should have 32 trailing zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(1), 0, "1 should have 0 trailing zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(2), 1, "2 should have 1 trailing zero")
        XCTAssertEqual(kk_int_countTrailingZeroBits(4), 2, "4 should have 2 trailing zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(0x80000000), 31, "MSB set should have 31 trailing zeros")
    }

    func testIntCountTrailingZeroBitsNegativeValues() {
        // Test negative values (32-bit two's complement)
        XCTAssertEqual(kk_int_countTrailingZeroBits(-1), 0, "-1 (all bits set) should have 0 trailing zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(-2), 1, "-2 (all bits except LSB) should have 1 trailing zero")
        XCTAssertEqual(kk_int_countTrailingZeroBits(Int(Int32.min)), 31, "Int32.min should have 31 trailing zeros")
    }

    // MARK: - Host Int Truncation Behavior

    func testHighBitsAreIgnoredForIntBitCounts() {
        // kk_int_* helpers intentionally apply Kotlin Int (32-bit) semantics even on 64-bit hosts.
        XCTAssertEqual(kk_int_countOneBits(0), 0, "Zero should have 0 bits set")
        XCTAssertEqual(kk_int_countOneBits(1), 1, "1 should have 1 bit set")
        XCTAssertEqual(kk_int_countOneBits(-1), 32, "All low 32 bits set should return 32")
        XCTAssertEqual(kk_int_countOneBits(-2), 31, "Only low 32 bits should participate in the count")
        XCTAssertEqual(kk_int_countLeadingZeroBits(0), 32, "Zero should have 32 leading zeros")
        XCTAssertEqual(kk_int_countLeadingZeroBits(1), 31, "1 should have 31 leading zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(0), 32, "Zero should have 32 trailing zeros")
        XCTAssertEqual(kk_int_countTrailingZeroBits(1), 0, "1 should have 0 trailing zeros")
    }

    // MARK: - Edge Case and Optimization Tests

    func testBitCountSpecialValues() {
        // Test values that might trigger optimizations
        let specialValues: [Int] = [
            0, 1, -1, Int(Int32.max), Int(Int32.min),
            Int.max, Int.min,
            0x55555555, 0xAAAAAAAA,  // Alternating patterns
            0xFF00FF00, 0x00FF00FF,  // Byte patterns
            0xFFFF0000, 0x0000FFFF   // Word patterns
        ]

        for value in specialValues {
            let ones = kk_int_countOneBits(value)
            let leadingZeros = kk_int_countLeadingZeroBits(value)
            let trailingZeros = kk_int_countTrailingZeroBits(value)

            // Verify basic constraints
            XCTAssertGreaterThanOrEqual(ones, 0, "Count of ones should be non-negative")
            XCTAssertLessThanOrEqual(ones, 32, "Count of ones should not exceed 32 for Int")
            
            XCTAssertGreaterThanOrEqual(leadingZeros, 0, "Leading zeros should be non-negative")
            XCTAssertLessThanOrEqual(leadingZeros, 32, "Leading zeros should not exceed 32 for Int")
            
            XCTAssertGreaterThanOrEqual(trailingZeros, 0, "Trailing zeros should be non-negative")
            XCTAssertLessThanOrEqual(trailingZeros, 32, "Trailing zeros should not exceed 32 for Int")

            // Verify relationship: leadingZeros + trailingZeros + ones_in_between = 32
            // This is more complex due to potential gaps, so we just verify basic consistency
            if value != 0 && ones > 0 {
                XCTAssertLessThan(leadingZeros + trailingZeros, 32, "Non-zero value should have some bits set")
            }
        }
    }

    func testBitCountPowerOfTwoValues() {
        // Test powers of two (should have exactly one bit set)
        for i in 0..<31 {
            let powerOfTwo = 1 << i
            XCTAssertEqual(kk_int_countOneBits(powerOfTwo), 1, "2^\(i) should have exactly 1 bit set")
            XCTAssertEqual(kk_int_countTrailingZeroBits(powerOfTwo), i, "2^\(i) should have \(i) trailing zeros")
            XCTAssertEqual(kk_int_countLeadingZeroBits(powerOfTwo), 31 - i, "2^\(i) should have \(31-i) leading zeros")
        }
    }

    func testBitCountComplementaryValues() {
        // Test complementary relationships
        for i in 0..<16 {
            let value = 1 << i
            let complement = ~value & 0xFFFFFFFF  // Keep only 32 bits

            let onesInValue = kk_int_countOneBits(value)
            let onesInComplement = kk_int_countOneBits(complement)

            XCTAssertEqual(onesInValue + onesInComplement, 32, "Value and its complement should have 32 total bits set")
        }
    }

    func testBitCountConsistencyAcrossRange() {
        // Test consistency across a range of values
        for value in 0..<1000 {
            let ones = kk_int_countOneBits(value)
            let leadingZeros = kk_int_countLeadingZeroBits(value)
            let trailingZeros = kk_int_countTrailingZeroBits(value)

            // Basic sanity checks
            XCTAssertGreaterThanOrEqual(ones, 0, "Ones count should be non-negative for value \(value)")
            XCTAssertLessThanOrEqual(ones, 32, "Ones count should not exceed 32 for value \(value)")
            
            if value != 0 {
                XCTAssertLessThan(leadingZeros, 32, "Non-zero value should have less than 32 leading zeros")
                XCTAssertLessThan(trailingZeros, 32, "Non-zero value should have less than 32 trailing zeros")
            } else {
                XCTAssertEqual(leadingZeros, 32, "Zero should have exactly 32 leading zeros")
                XCTAssertEqual(trailingZeros, 32, "Zero should have exactly 32 trailing zeros")
            }
        }
    }

    // MARK: - Performance and Optimization Tests

    func testBitCountPerformanceCharacteristics() {
        // Test that bit count operations are reasonably fast
        let testValues: [Int] = Array(0..<10000)
        
        measure {
            for value in testValues {
                _ = kk_int_countOneBits(value)
                _ = kk_int_countLeadingZeroBits(value)
                _ = kk_int_countTrailingZeroBits(value)
            }
        }
    }

    func testBitManipulationPerformanceCharacteristics() {
        // Test performance of all bit manipulation functions
        let testValues: [Int] = Array(0..<1000)
        let distances: [Int] = [0, 1, 7, 15, 31]
        
        measure {
            for value in testValues {
                for distance in distances {
                    _ = kk_int_rotateLeft(value, distance)
                    _ = kk_int_rotateRight(value, distance)
                    _ = kk_int_highestOneBit(value)
                    _ = kk_int_lowestOneBit(value)
                    _ = kk_int_takeHighestOneBit(value)
                    _ = kk_int_takeLowestOneBit(value)
                }
            }
        }
    }

    func testLongBitManipulationPerformanceCharacteristics() {
        // Test performance of Long bit manipulation functions
        let testValues: [Int] = Array(0..<1000)
        let distances: [Int] = [0, 1, 31, 63]
        
        measure {
            for value in testValues {
                for distance in distances {
                    _ = kk_long_rotateLeft(value, distance)
                    _ = kk_long_rotateRight(value, distance)
                    _ = kk_long_highestOneBit(value)
                    _ = kk_long_lowestOneBit(value)
                    _ = kk_long_takeHighestOneBit(value)
                    _ = kk_long_takeLowestOneBit(value)
                }
            }
        }
    }

    func testBitCountLargeValues() {
        // Test with values near Int boundaries
        let largeValues: [Int] = [
            Int.max,
            Int.max - 1,
            Int.max / 2,
            Int.min,
            Int.min + 1,
            Int.min / 2
        ]

        for value in largeValues {
            let ones = kk_int_countOneBits(value)
            let leadingZeros = kk_int_countLeadingZeroBits(value)
            let trailingZeros = kk_int_countTrailingZeroBits(value)

            // Verify results are reasonable
            XCTAssertGreaterThanOrEqual(ones, 0, "Large value should have non-negative ones count")
            XCTAssertLessThanOrEqual(ones, 32, "Large value should not exceed 32 ones")
            
            XCTAssertGreaterThanOrEqual(leadingZeros, 0, "Large value should have non-negative leading zeros")
            XCTAssertLessThanOrEqual(leadingZeros, 32, "Large value should not exceed 32 leading zeros")
            
            XCTAssertGreaterThanOrEqual(trailingZeros, 0, "Large value should have non-negative trailing zeros")
            XCTAssertLessThanOrEqual(trailingZeros, 32, "Large value should not exceed 32 trailing zeros")
        }
    }

    // MARK: - Regression Tests

    func testBitCountRegressionForKnownValues() {
        // Test specific values that have caused issues in other implementations
        let knownValues: [(value: Int, expectedOnes: Int, expectedLeadingZeros: Int, expectedTrailingZeros: Int)] = [
            (0, 0, 32, 32),
            (1, 1, 31, 0),
            (-1, 32, 0, 0),
            (0x80000000, 1, 0, 31),
            (0x7FFFFFFF, 31, 1, 0),
            (0xFFFFFFFF, 32, 0, 0),
            (Int(Int32.min), 1, 0, 31),
            (Int(Int32.max), 31, 1, 0)
        ]

        for (value, expectedOnes, expectedLeadingZeros, expectedTrailingZeros) in knownValues {
            XCTAssertEqual(kk_int_countOneBits(value), expectedOnes, "Unexpected ones count for \(value)")
            XCTAssertEqual(kk_int_countLeadingZeroBits(value), expectedLeadingZeros, "Unexpected leading zeros for \(value)")
            XCTAssertEqual(kk_int_countTrailingZeroBits(value), expectedTrailingZeros, "Unexpected trailing zeros for \(value)")
        }
    }

    func testBitCountWithBitManipulation() {
        // Test bit count operations against manual bit manipulation
        for value in [0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 511, 512, 1023] {
            // Manual count of ones for verification
            var manualOnes = 0
            var tempValue = value & 0xFFFFFFFF  // Ensure 32-bit
            for _ in 0..<32 {
                if tempValue & 1 != 0 {
                    manualOnes += 1
                }
                tempValue >>= 1
            }

            XCTAssertEqual(kk_int_countOneBits(value), manualOnes, "Manual count should match for \(value)")
        }
    }

    func testOptimizedBitManipulationCorrectness() {
        // Test that optimized implementations produce correct results
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            0x7FFF_FFFF, Int(Int32.min), -2, -128,
            0x5555_5555, Int(Int32(bitPattern: 0xAAAA_AAAA)),
            0x0101_0101, 0x00FF_00FF, 0x8000_0000, 0x0000_0001
        ]

        func assertSingleBitSet(_ value: Int, file: StaticString = #filePath, line: UInt = #line) {
            let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
            XCTAssertNotEqual(bits, 0, file: file, line: line)
            XCTAssertEqual(bits & (bits &- 1), 0, file: file, line: line)
        }
        
        for value in testValues {
            // Test rotate functions
            for distance in [0, 1, 7, 15, 31] {
                let rotatedLeft = kk_int_rotateLeft(value, distance)
                let rotatedRight = kk_int_rotateRight(value, distance)
                
                // Verify rotation is reversible
                XCTAssertEqual(kk_int_rotateRight(rotatedLeft, distance) & 0xFFFFFFFF, value & 0xFFFFFFFF, 
                    "Rotate left then right should return original for value=\(value), distance=\(distance)")
                XCTAssertEqual(kk_int_rotateLeft(rotatedRight, distance) & 0xFFFFFFFF, value & 0xFFFFFFFF,
                    "Rotate right then left should return original for value=\(value), distance=\(distance)")
            }
            
            // Test highest/lowest one bit
            let highest = kk_int_highestOneBit(value)
            let lowest = kk_int_lowestOneBit(value)

            if value != 0 {
                assertSingleBitSet(highest)
                assertSingleBitSet(lowest)
            } else {
                XCTAssertEqual(highest, 0, "Highest one bit should be 0 for zero")
                XCTAssertEqual(lowest, 0, "Lowest one bit should be 0 for zero")
            }
            
            // Test take functions
            let takeHighest = kk_int_takeHighestOneBit(value)
            let takeLowest = kk_int_takeLowestOneBit(value)
            
            if value != 0 {
                XCTAssertNotEqual(takeHighest, 0, "Take highest should be non-zero for non-zero value \(value)")
                XCTAssertNotEqual(takeLowest, 0, "Take lowest should be non-zero for non-zero value \(value)")
                
                // Verify take functions preserve the corresponding bit
                XCTAssertEqual(takeHighest & highest, highest, "Take highest should preserve highest bit for \(value)")
                XCTAssertEqual(takeLowest & lowest, lowest, "Take lowest should preserve lowest bit for \(value)")
            } else {
                XCTAssertEqual(takeHighest, 0, "Take highest should be 0 for zero")
                XCTAssertEqual(takeLowest, 0, "Take lowest should be 0 for zero")
            }
        }
    }

    func testOptimizedLongBitManipulationCorrectness() {
        // Test that optimized Long implementations produce correct results
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            Int.max, Int.min, -2, -128,
            Int(bitPattern: 0x5555_5555_5555_5555), Int(bitPattern: 0xAAAA_AAAA_AAAA_AAAA),
            Int(bitPattern: 0x8000_0000_0000_0000), Int(bitPattern: 0x0000_0000_0000_0001)
        ]

        func assertSingleBitSet(_ value: Int, file: StaticString = #filePath, line: UInt = #line) {
            let bits = UInt(bitPattern: value)
            XCTAssertNotEqual(bits, 0, file: file, line: line)
            XCTAssertEqual(bits & (bits &- 1), 0, file: file, line: line)
        }
        
        for value in testValues {
            // Test rotate functions
            for distance in [0, 1, 31, 63] {
                let rotatedLeft = kk_long_rotateLeft(value, distance)
                let rotatedRight = kk_long_rotateRight(value, distance)
                
                // Verify rotation is reversible
                XCTAssertEqual(kk_long_rotateRight(rotatedLeft, distance), value,
                    "Long rotate left then right should return original for value=\(value), distance=\(distance)")
                XCTAssertEqual(kk_long_rotateLeft(rotatedRight, distance), value,
                    "Long rotate right then left should return original for value=\(value), distance=\(distance)")
            }
            
            // Test highest/lowest one bit
            let highest = kk_long_highestOneBit(value)
            let lowest = kk_long_lowestOneBit(value)
            
            if value != 0 {
                assertSingleBitSet(highest)
                assertSingleBitSet(lowest)
            } else {
                XCTAssertEqual(highest, 0, "Long highest one bit should be 0 for zero")
                XCTAssertEqual(lowest, 0, "Long lowest one bit should be 0 for zero")
            }
        }
    }

    func testLowestOneBitHandlesMinimumValues() {
        XCTAssertEqual(kk_int_lowestOneBit(Int(Int32.min)), Int(Int32.min))
        XCTAssertEqual(kk_int_takeLowestOneBit(Int(Int32.min)), Int(Int32.min))
        XCTAssertEqual(kk_long_lowestOneBit(Int.min), Int.min)
        XCTAssertEqual(kk_long_takeLowestOneBit(Int.min), Int.min)
    }
}
