import XCTest
@testable import Runtime

final class CoercionRuntimeTests: XCTestCase {

    // MARK: - Helpers

    private func intToBits(_ value: Int) -> Int { value }
    private func longToBits(_ value: Int) -> Int { value }
    private func doubleToBits(_ value: Double) -> Int { kk_double_to_bits(value) }
    private func floatToBits(_ value: Float) -> Int { kk_float_to_bits(value) }
    private func bitsToDouble(_ bits: Int) -> Double { kk_bits_to_double(bits) }
    private func bitsToFloat(_ bits: Int) -> Float { kk_bits_to_float(bits) }

    // MARK: - Int Coercion Runtime Tests

    func testIntCoerceInRuntimeBehavior() {
        // Test normal coercion
        XCTAssertEqual(kk_int_coerceIn(5, 1, 10), 5, "Value within range should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn(0, 1, 10), 1, "Value below minimum should be clamped to minimum")
        XCTAssertEqual(kk_int_coerceIn(15, 1, 10), 10, "Value above maximum should be clamped to maximum")

        // Test boundary values
        XCTAssertEqual(kk_int_coerceIn(1, 1, 10), 1, "Value at minimum should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn(10, 1, 10), 10, "Value at maximum should remain unchanged")

        // Test negative values
        XCTAssertEqual(kk_int_coerceIn(-5, -10, -1), -5, "Negative value within range should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn(-15, -10, -1), -10, "Negative value below minimum should be clamped")
        XCTAssertEqual(kk_int_coerceIn(5, -10, -1), -1, "Positive value in negative range should be clamped to maximum")
    }

    func testIntCoerceAtLeastRuntimeBehavior() {
        XCTAssertEqual(kk_int_coerceAtLeast(5, 1), 5, "Value above minimum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtLeast(0, 1), 1, "Value below minimum should be clamped to minimum")
        XCTAssertEqual(kk_int_coerceAtLeast(1, 1), 1, "Value at minimum should remain unchanged")

        // Test with negative minimum
        XCTAssertEqual(kk_int_coerceAtLeast(-5, -10), -5, "Value above negative minimum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtLeast(-15, -10), -10, "Value below negative minimum should be clamped")
    }

    func testIntCoerceAtMostRuntimeBehavior() {
        XCTAssertEqual(kk_int_coerceAtMost(5, 10), 5, "Value below maximum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtMost(15, 10), 10, "Value above maximum should be clamped to maximum")
        XCTAssertEqual(kk_int_coerceAtMost(10, 10), 10, "Value at maximum should remain unchanged")

        // Test with negative values
        XCTAssertEqual(kk_int_coerceAtMost(-5, -1), -5, "Negative value below negative maximum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtMost(-15, -1), -15, "Negative value below negative maximum should remain unchanged")
    }

    // MARK: - Long Coercion Runtime Tests

    func testLongCoerceInRuntimeBehavior() {
        // Test normal coercion (Long uses same Int representation on 64-bit)
        XCTAssertEqual(kk_long_coerceIn(5000000000, 1000000000, 10000000000), 5000000000, "Long value within range should remain unchanged")
        XCTAssertEqual(kk_long_coerceIn(500000000, 1000000000, 10000000000), 1000000000, "Long value below minimum should be clamped")
        XCTAssertEqual(kk_long_coerceIn(15000000000, 1000000000, 10000000000), 10000000000, "Long value above maximum should be clamped")

        // Test boundary values
        XCTAssertEqual(kk_long_coerceIn(1000000000, 1000000000, 10000000000), 1000000000, "Long at minimum should remain unchanged")
        XCTAssertEqual(kk_long_coerceIn(10000000000, 1000000000, 10000000000), 10000000000, "Long at maximum should remain unchanged")
    }

    func testLongCoerceAtLeastRuntimeBehavior() {
        XCTAssertEqual(kk_long_coerceAtLeast(5000000000, 1000000000), 5000000000, "Long above minimum should remain unchanged")
        XCTAssertEqual(kk_long_coerceAtLeast(500000000, 1000000000), 1000000000, "Long below minimum should be clamped")
        XCTAssertEqual(kk_long_coerceAtLeast(1000000000, 1000000000), 1000000000, "Long at minimum should remain unchanged")
    }

    func testLongCoerceAtMostRuntimeBehavior() {
        XCTAssertEqual(kk_long_coerceAtMost(5000000000, 10000000000), 5000000000, "Long below maximum should remain unchanged")
        XCTAssertEqual(kk_long_coerceAtMost(15000000000, 10000000000), 10000000000, "Long above maximum should be clamped")
        XCTAssertEqual(kk_long_coerceAtMost(10000000000, 10000000000), 10000000000, "Long at maximum should remain unchanged")
    }

    // MARK: - Double Coercion Runtime Tests

    func testDoubleCoerceInRuntimeBehavior() {
        // Test normal coercion with bit encoding
        let valueBits = doubleToBits(5.5)
        let minBits = doubleToBits(1.0)
        let maxBits = doubleToBits(10.0)

        let resultBits = kk_double_coerceIn(valueBits, minBits, maxBits)
        let result = bitsToDouble(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-10, "Double value within range should remain unchanged")

        // Test value below minimum
        let belowBits = doubleToBits(0.5)
        let clampedBelowBits = kk_double_coerceIn(belowBits, minBits, maxBits)
        let clampedBelow = bitsToDouble(clampedBelowBits)
        XCTAssertEqual(clampedBelow, 1.0, accuracy: 1e-10, "Double value below minimum should be clamped to minimum")

        // Test value above maximum
        let aboveBits = doubleToBits(15.5)
        let clampedAboveBits = kk_double_coerceIn(aboveBits, minBits, maxBits)
        let clampedAbove = bitsToDouble(clampedAboveBits)
        XCTAssertEqual(clampedAbove, 10.0, accuracy: 1e-10, "Double value above maximum should be clamped to maximum")
    }

    func testDoubleCoerceAtLeastRuntimeBehavior() {
        let valueBits = doubleToBits(5.5)
        let minBits = doubleToBits(1.0)

        let resultBits = kk_double_coerceAtLeast(valueBits, minBits)
        let result = bitsToDouble(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-10, "Double above minimum should remain unchanged")

        let belowBits = doubleToBits(0.5)
        let clampedBits = kk_double_coerceAtLeast(belowBits, minBits)
        let clamped = bitsToDouble(clampedBits)
        XCTAssertEqual(clamped, 1.0, accuracy: 1e-10, "Double below minimum should be clamped")
    }

    func testDoubleCoerceAtMostRuntimeBehavior() {
        let valueBits = doubleToBits(5.5)
        let maxBits = doubleToBits(10.0)

        let resultBits = kk_double_coerceAtMost(valueBits, maxBits)
        let result = bitsToDouble(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-10, "Double below maximum should remain unchanged")

        let aboveBits = doubleToBits(15.5)
        let clampedBits = kk_double_coerceAtMost(aboveBits, maxBits)
        let clamped = bitsToDouble(clampedBits)
        XCTAssertEqual(clamped, 10.0, accuracy: 1e-10, "Double above maximum should be clamped")
    }

    // MARK: - Float Coercion Runtime Tests

    func testFloatCoerceInRuntimeBehavior() {
        // Test normal coercion with bit encoding
        let valueBits = floatToBits(5.5)
        let minBits = floatToBits(1.0)
        let maxBits = floatToBits(10.0)

        let resultBits = kk_float_coerceIn(valueBits, minBits, maxBits)
        let result = bitsToFloat(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-6, "Float value within range should remain unchanged")

        // Test value below minimum
        let belowBits = floatToBits(0.5)
        let clampedBelowBits = kk_float_coerceIn(belowBits, minBits, maxBits)
        let clampedBelow = bitsToFloat(clampedBelowBits)
        XCTAssertEqual(clampedBelow, 1.0, accuracy: 1e-6, "Float value below minimum should be clamped to minimum")

        // Test value above maximum
        let aboveBits = floatToBits(15.5)
        let clampedAboveBits = kk_float_coerceIn(aboveBits, minBits, maxBits)
        let clampedAbove = bitsToFloat(clampedAboveBits)
        XCTAssertEqual(clampedAbove, 10.0, accuracy: 1e-6, "Float value above maximum should be clamped to maximum")
    }

    func testFloatCoerceAtLeastRuntimeBehavior() {
        let valueBits = floatToBits(5.5)
        let minBits = floatToBits(1.0)

        let resultBits = kk_float_coerceAtLeast(valueBits, minBits)
        let result = bitsToFloat(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-6, "Float above minimum should remain unchanged")

        let belowBits = floatToBits(0.5)
        let clampedBits = kk_float_coerceAtLeast(belowBits, minBits)
        let clamped = bitsToFloat(clampedBits)
        XCTAssertEqual(clamped, 1.0, accuracy: 1e-6, "Float below minimum should be clamped")
    }

    func testFloatCoerceAtMostRuntimeBehavior() {
        let valueBits = floatToBits(5.5)
        let maxBits = floatToBits(10.0)

        let resultBits = kk_float_coerceAtMost(valueBits, maxBits)
        let result = bitsToFloat(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-6, "Float below maximum should remain unchanged")

        let aboveBits = floatToBits(15.5)
        let clampedBits = kk_float_coerceAtMost(aboveBits, maxBits)
        let clamped = bitsToFloat(clampedBits)
        XCTAssertEqual(clamped, 10.0, accuracy: 1e-6, "Float above maximum should be clamped")
    }

    // MARK: - Boundary Value Tests

    func testIntBoundaryValues() {
        // Test Int32 boundary values
        let int32Max = Int(Int32.max)
        let int32Min = Int(Int32.min)

        XCTAssertEqual(kk_int_coerceIn(int32Max, int32Max - 100, int32Max), int32Max, "Int32.max at upper bound")
        XCTAssertEqual(kk_int_coerceIn(int32Min, int32Min, int32Min + 100), int32Min, "Int32.min at lower bound")

        // Test extreme ranges
        XCTAssertEqual(kk_int_coerceIn(0, Int.min, Int.max), 0, "Zero in extreme range should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn(Int.min, Int.min, Int.max), Int.min, "Int.min in extreme range should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn(Int.max, Int.min, Int.max), Int.max, "Int.max in extreme range should remain unchanged")
    }

    func testDoubleSpecialValues() {
        // Test NaN behavior
        let nanBits = doubleToBits(Double.nan)
        let minBits = doubleToBits(0.0)
        let maxBits = doubleToBits(1.0)

        let nanResultBits = kk_double_coerceIn(nanBits, minBits, maxBits)
        let nanResult = bitsToDouble(nanResultBits)
        XCTAssertTrue(nanResult.isNaN, "NaN should be preserved in coercion")

        // Test infinity
        let posInfBits = doubleToBits(Double.infinity)
        let negInfBits = doubleToBits(-Double.infinity)

        let posInfResultBits = kk_double_coerceIn(posInfBits, minBits, maxBits)
        let posInfResult = bitsToDouble(posInfResultBits)
        XCTAssertEqual(posInfResult, 1.0, accuracy: 1e-10, "Positive infinity should be clamped to maximum")

        let negInfResultBits = kk_double_coerceIn(negInfBits, minBits, maxBits)
        let negInfResult = bitsToDouble(negInfResultBits)
        XCTAssertEqual(negInfResult, 0.0, accuracy: 1e-10, "Negative infinity should be clamped to minimum")
    }

    func testFloatSpecialValues() {
        // Test NaN behavior
        let nanBits = floatToBits(Float.nan)
        let minBits = floatToBits(0.0)
        let maxBits = floatToBits(1.0)

        let nanResultBits = kk_float_coerceIn(nanBits, minBits, maxBits)
        let nanResult = bitsToFloat(nanResultBits)
        XCTAssertTrue(nanResult.isNaN, "Float NaN should be preserved in coercion")

        // Test infinity
        let posInfBits = floatToBits(Float.infinity)
        let negInfBits = floatToBits(-Float.infinity)

        let posInfResultBits = kk_float_coerceIn(posInfBits, minBits, maxBits)
        let posInfResult = bitsToFloat(posInfResultBits)
        XCTAssertEqual(posInfResult, 1.0, accuracy: 1e-6, "Positive infinity should be clamped to maximum")

        let negInfResultBits = kk_float_coerceIn(negInfBits, minBits, maxBits)
        let negInfResult = bitsToFloat(negInfResultBits)
        XCTAssertEqual(negInfResult, 0.0, accuracy: 1e-6, "Negative infinity should be clamped to minimum")
    }

    // MARK: - Precision Tests

    func testFloatToDoublePrecision() {
        // Test precision loss when converting Double -> Float -> Double.
        let preciseDouble = 1.23456789012345
        let doubleBits = doubleToBits(preciseDouble)
        let floatBits = kk_double_to_float(doubleBits)
        let convertedBackBits = kk_float_to_double_bits(floatBits)
        let convertedBack = bitsToDouble(convertedBackBits)

        // Should lose some precision due to Float conversion
        XCTAssertNotEqual(convertedBack, preciseDouble, accuracy: 1e-15, "Precision should be lost in Float conversion")
        XCTAssertEqual(convertedBack, preciseDouble, accuracy: 1e-7, "But should be accurate within Float precision")
    }

    func testTypeConversionConsistency() {
        // Test that bit encoding/decoding is consistent
        let testDouble = 3.141592653589793
        let bits = doubleToBits(testDouble)
        let decoded = bitsToDouble(bits)
        XCTAssertEqual(decoded, testDouble, accuracy: 1e-15, "Double bit encoding/decoding should be lossless")

        let testFloat: Float = 3.1415927
        let floatBits = floatToBits(testFloat)
        let decodedFloat = bitsToFloat(floatBits)
        XCTAssertEqual(decodedFloat, testFloat, accuracy: 1e-7, "Float bit encoding/decoding should be lossless")
    }

    // MARK: - UByte and UShort Conversion Tests (STDLIB-PRIM-002)

    func testIntToUByteConversion() {
        XCTAssertEqual(kk_int_to_ubyte(100), 100, "Valid value should remain unchanged")
        XCTAssertEqual(kk_int_to_ubyte(-5), 251, "Negative value should truncate to the low 8 bits")
        XCTAssertEqual(kk_int_to_ubyte(300), 44, "Value above 255 should truncate to the low 8 bits")
        XCTAssertEqual(kk_int_to_ubyte(0), 0, "Minimum boundary should remain unchanged")
        XCTAssertEqual(kk_int_to_ubyte(255), 255, "Maximum boundary should remain unchanged")
    }

    func testIntToUShortConversion() {
        XCTAssertEqual(kk_int_to_ushort(1000), 1000, "Valid value should remain unchanged")
        XCTAssertEqual(kk_int_to_ushort(-5), 65531, "Negative value should truncate to the low 16 bits")
        XCTAssertEqual(kk_int_to_ushort(70000), 4464, "Value above 65535 should truncate to the low 16 bits")
        XCTAssertEqual(kk_int_to_ushort(0), 0, "Minimum boundary should remain unchanged")
        XCTAssertEqual(kk_int_to_ushort(65535), 65535, "Maximum boundary should remain unchanged")
    }

    func testLongToUByteConversion() {
        XCTAssertEqual(kk_long_to_ubyte(100), 100, "Valid value should remain unchanged")
        XCTAssertEqual(kk_long_to_ubyte(-5), 251, "Negative value should truncate to the low 8 bits")
        XCTAssertEqual(kk_long_to_ubyte(300), 44, "Value above 255 should truncate to the low 8 bits")
    }

    func testLongToUShortConversion() {
        XCTAssertEqual(kk_long_to_ushort(1000), 1000, "Valid value should remain unchanged")
        XCTAssertEqual(kk_long_to_ushort(-5), 65531, "Negative value should truncate to the low 16 bits")
        XCTAssertEqual(kk_long_to_ushort(70000), 4464, "Value above 65535 should truncate to the low 16 bits")
    }

    func testUIntToUByteConversion() {
        XCTAssertEqual(kk_uint_to_ubyte(100), 100, "Valid value should remain unchanged")
        XCTAssertEqual(kk_uint_to_ubyte(300), 44, "Value above 255 should truncate to the low 8 bits")
        XCTAssertEqual(kk_uint_to_ubyte(0), 0, "Minimum boundary should remain unchanged")
        XCTAssertEqual(kk_uint_to_ubyte(255), 255, "Maximum boundary should remain unchanged")
    }

    // MARK: - Range-based Coercion Tests (STDLIB-CONV-006)

    func testIntCoerceInRangeRuntimeBehavior() {
        // Create test range
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        // Test normal coercion
        XCTAssertEqual(kk_int_coerceIn_range(5, range), 5, "Value within range should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn_range(0, range), 1, "Value below minimum should be clamped to minimum")
        XCTAssertEqual(kk_int_coerceIn_range(15, range), 10, "Value above maximum should be clamped to maximum")

        // Test boundary values
        XCTAssertEqual(kk_int_coerceIn_range(1, range), 1, "Value at minimum should remain unchanged")
        XCTAssertEqual(kk_int_coerceIn_range(10, range), 10, "Value at maximum should remain unchanged")
    }

    func testIntCoerceAtLeastRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 3, last: 10, step: 1))

        XCTAssertEqual(kk_int_coerceAtLeast_range(5, range), 5, "Value above minimum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtLeast_range(1, range), 3, "Value below minimum should be clamped to minimum")
        XCTAssertEqual(kk_int_coerceAtLeast_range(3, range), 3, "Value at minimum should remain unchanged")
    }

    func testIntCoerceAtMostRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 7, step: 1))

        XCTAssertEqual(kk_int_coerceAtMost_range(5, range), 5, "Value below maximum should remain unchanged")
        XCTAssertEqual(kk_int_coerceAtMost_range(10, range), 7, "Value above maximum should be clamped to maximum")
        XCTAssertEqual(kk_int_coerceAtMost_range(7, range), 7, "Value at maximum should remain unchanged")
    }

    func testDoubleCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        let valueBits = doubleToBits(5.5)
        let belowBits = doubleToBits(0.5)
        let aboveBits = doubleToBits(15.5)

        let resultBits = kk_double_coerceIn_range(valueBits, range)
        let result = bitsToDouble(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-10, "Double value within range should remain unchanged")

        let clampedBelowBits = kk_double_coerceIn_range(belowBits, range)
        let clampedBelow = bitsToDouble(clampedBelowBits)
        XCTAssertEqual(clampedBelow, 1.0, accuracy: 1e-10, "Double value below minimum should be clamped to minimum")

        let clampedAboveBits = kk_double_coerceIn_range(aboveBits, range)
        let clampedAbove = bitsToDouble(clampedAboveBits)
        XCTAssertEqual(clampedAbove, 10.0, accuracy: 1e-10, "Double value above maximum should be clamped to maximum")
    }

    func testFloatCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        let valueBits = floatToBits(5.5)
        let belowBits = floatToBits(0.5)
        let aboveBits = floatToBits(15.5)

        let resultBits = kk_float_coerceIn_range(valueBits, range)
        let result = bitsToFloat(resultBits)
        XCTAssertEqual(result, 5.5, accuracy: 1e-6, "Float value within range should remain unchanged")

        let clampedBelowBits = kk_float_coerceIn_range(belowBits, range)
        let clampedBelow = bitsToFloat(clampedBelowBits)
        XCTAssertEqual(clampedBelow, 1.0, accuracy: 1e-6, "Float value below minimum should be clamped to minimum")

        let clampedAboveBits = kk_float_coerceIn_range(aboveBits, range)
        let clampedAbove = bitsToFloat(clampedAboveBits)
        XCTAssertEqual(clampedAbove, 10.0, accuracy: 1e-6, "Float value above maximum should be clamped to maximum")
    }

    func testLongCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1000000000, last: 10000000000, step: 1))

        XCTAssertEqual(kk_long_coerceIn_range(5000000000, range), 5000000000, "Long value within range should remain unchanged")
        XCTAssertEqual(kk_long_coerceIn_range(500000000, range), 1000000000, "Long value below minimum should be clamped")
        XCTAssertEqual(kk_long_coerceIn_range(15000000000, range), 10000000000, "Long value above maximum should be clamped")
    }

    func testRangeCoercionConsistency() {
        // Test that range-based coercion produces same results as min/max coercion
        let range = registerRuntimeObject(RuntimeRangeBox(first: 2, last: 8, step: 1))

        let testValues = [1, 3, 5, 10]
        for value in testValues {
            let rangeResult = kk_int_coerceIn_range(value, range)
            let minMaxResult = kk_int_coerceIn(value, 2, 8)
            XCTAssertEqual(rangeResult, minMaxResult, "Range-based coercion should match min/max coercion for value \(value)")

            let rangeAtLeastResult = kk_int_coerceAtLeast_range(value, range)
            let minAtLeastResult = kk_int_coerceAtLeast(value, 2)
            XCTAssertEqual(rangeAtLeastResult, minAtLeastResult, "Range-based coerceAtLeast should match min coercion for value \(value)")

            let rangeAtMostResult = kk_int_coerceAtMost_range(value, range)
            let maxAtMostResult = kk_int_coerceAtMost(value, 8)
            XCTAssertEqual(rangeAtMostResult, maxAtMostResult, "Range-based coerceAtMost should match max coercion for value \(value)")
        }
    }

    func testUIntToUShortConversion() {
        XCTAssertEqual(kk_uint_to_ushort(1000), 1000, "Valid value should remain unchanged")
        XCTAssertEqual(kk_uint_to_ushort(70000), 4464, "Value above 65535 should truncate to the low 16 bits")
        XCTAssertEqual(kk_uint_to_ushort(0), 0, "Minimum boundary should remain unchanged")
        XCTAssertEqual(kk_uint_to_ushort(65535), 65535, "Maximum boundary should remain unchanged")
    }

    func testUByteToIntConversion() {
        XCTAssertEqual(kk_ubyte_to_int(100), 100, "UByte to Int should be identity")
        XCTAssertEqual(kk_ubyte_to_int(0), 0, "Zero should remain unchanged")
        XCTAssertEqual(kk_ubyte_to_int(255), 255, "Maximum UByte should remain unchanged")
    }

    func testUShortToIntConversion() {
        XCTAssertEqual(kk_ushort_to_int(1000), 1000, "UShort to Int should be identity")
        XCTAssertEqual(kk_ushort_to_int(0), 0, "Zero should remain unchanged")
        XCTAssertEqual(kk_ushort_to_int(65535), 65535, "Maximum UShort should remain unchanged")
    }

    func testUByteToLongConversion() {
        XCTAssertEqual(kk_ubyte_to_long(100), 100, "UByte to Long should be identity")
        XCTAssertEqual(kk_ubyte_to_long(0), 0, "Zero should remain unchanged")
        XCTAssertEqual(kk_ubyte_to_long(255), 255, "Maximum UByte should remain unchanged")
    }

    func testUShortToLongConversion() {
        XCTAssertEqual(kk_ushort_to_long(1000), 1000, "UShort to Long should be identity")
        XCTAssertEqual(kk_ushort_to_long(0), 0, "Zero should remain unchanged")
        XCTAssertEqual(kk_ushort_to_long(65535), 65535, "Maximum UShort should remain unchanged")
    }

    // MARK: - Char Conversion Tests (STDLIB-PRIM-002)

    func testIntToCharConversion() {
        XCTAssertEqual(kk_int_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_int_to_char(0x1F600), 0xF600, "Values should truncate to the low 16 bits")
        XCTAssertEqual(kk_int_to_char(-5), 0xFFFB, "Negative value should truncate to the low 16 bits")
        XCTAssertEqual(kk_int_to_char(0x110000), 0, "Value above 16 bits should truncate to 0")
        XCTAssertEqual(kk_int_to_char(0), 0, "Minimum boundary should remain unchanged")
        XCTAssertEqual(kk_int_to_char(0x10FFFF), 0xFFFF, "Maximum input should truncate to the low 16 bits")
    }

    func testLongToCharConversion() {
        XCTAssertEqual(kk_long_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_long_to_char(0x1F600), 0xF600, "Values should truncate to the low 16 bits")
        XCTAssertEqual(kk_long_to_char(-5), 0xFFFB, "Negative value should truncate to the low 16 bits")
        XCTAssertEqual(kk_long_to_char(0x110000), 0, "Value above 16 bits should truncate to 0")
    }

    func testUIntToCharConversion() {
        XCTAssertEqual(kk_uint_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_uint_to_char(0x1F600), 0xF600, "Values should truncate to the low 16 bits")
        XCTAssertEqual(kk_uint_to_char(0x110000), 0, "Value above 16 bits should truncate to 0")
    }

    func testULongToCharConversion() {
        XCTAssertEqual(kk_ulong_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_ulong_to_char(0x1F600), 0xF600, "Values should truncate to the low 16 bits")
        XCTAssertEqual(kk_ulong_to_char(0x110000), 0, "Value above 16 bits should truncate to 0")
    }

    func testUByteToCharConversion() {
        XCTAssertEqual(kk_ubyte_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_ubyte_to_char(255), 255, "Maximum UByte should remain unchanged")
    }

    func testUShortToCharConversion() {
        XCTAssertEqual(kk_ushort_to_char(65), 65, "Valid ASCII value should remain unchanged")
        XCTAssertEqual(kk_ushort_to_char(0x1F600), 0x1F600, "UShort to Char should preserve the stored value")
        XCTAssertEqual(kk_ushort_to_char(65535), 65535, "Maximum UShort should remain unchanged")
    }

    func testCharToIntConversion() {
        XCTAssertEqual(kk_char_to_int(65), 65, "Char to Int should be identity")
        XCTAssertEqual(kk_char_to_int(0x1F600), 0x1F600, "Unicode Char to Int should be identity")
        XCTAssertEqual(kk_char_to_int(0), 0, "Zero should remain unchanged")
    }

    func testCharToLongConversion() {
        XCTAssertEqual(kk_char_to_long(65), 65, "Char to Long should be identity")
        XCTAssertEqual(kk_char_to_long(0x1F600), 0x1F600, "Unicode Char to Long should be identity")
    }

    func testCharToUIntConversion() {
        XCTAssertEqual(kk_char_to_uint(65), 65, "Char to UInt should be identity")
        XCTAssertEqual(kk_char_to_uint(0x1F600), 0x1F600, "Unicode Char to UInt should be identity")
    }

    func testCharToULongConversion() {
        XCTAssertEqual(kk_char_to_ulong(65), 65, "Char to ULong should be identity")
        XCTAssertEqual(kk_char_to_ulong(0x1F600), 0x1F600, "Unicode Char to ULong should be identity")
    }

    // MARK: - Additional Conversion Tests (STDLIB-PRIM-002)

    func testFloatToUIntConversion() {
        XCTAssertEqual(kk_float_to_uint(kk_float_to_bits(Float(3.14))), 3, "Positive float should convert to uint")
        XCTAssertEqual(kk_float_to_uint(kk_float_to_bits(Float(-1.5))), 0, "Negative float should convert to 0")
        XCTAssertEqual(kk_float_to_uint(kk_float_to_bits(Float.nan)), 0, "NaN should convert to 0")
        XCTAssertEqual(kk_float_to_uint(kk_float_to_bits(Float(UInt32.max))), Int(UInt32.max), "Max float should clamp to UInt32.max")
    }

    func testDoubleToUIntConversion() {
        XCTAssertEqual(kk_double_to_uint(kk_double_to_bits(3.14)), 3, "Positive double should convert to uint")
        XCTAssertEqual(kk_double_to_uint(kk_double_to_bits(-1.5)), 0, "Negative double should convert to 0")
        XCTAssertEqual(kk_double_to_uint(kk_double_to_bits(Double.nan)), 0, "NaN should convert to 0")
        XCTAssertEqual(kk_double_to_uint(kk_double_to_bits(Double(UInt32.max))), Int(UInt32.max), "Max double should clamp to UInt32.max")
    }

    func testFloatToULongConversion() {
        XCTAssertEqual(kk_float_to_ulong(kk_float_to_bits(Float(3.14))), 3, "Positive float should convert to ulong")
        XCTAssertEqual(kk_float_to_ulong(kk_float_to_bits(Float(-1.5))), 0, "Negative float should convert to 0")
        XCTAssertEqual(kk_float_to_ulong(kk_float_to_bits(Float.nan)), 0, "NaN should convert to 0")
    }

    func testDoubleToULongConversion() {
        XCTAssertEqual(kk_double_to_ulong(kk_double_to_bits(3.14)), 3, "Positive double should convert to ulong")
        XCTAssertEqual(kk_double_to_ulong(kk_double_to_bits(-1.5)), 0, "Negative double should convert to 0")
        XCTAssertEqual(kk_double_to_ulong(kk_double_to_bits(Double.nan)), 0, "NaN should convert to 0")
    }

    func testByteToUIntConversion() {
        XCTAssertEqual(kk_byte_to_uint(100), 100, "Positive byte should convert to uint")
        XCTAssertEqual(kk_byte_to_uint(-5), 251, "Negative byte should convert using two's complement")
    }

    func testShortToUIntConversion() {
        XCTAssertEqual(kk_short_to_uint(1000), 1000, "Positive short should convert to uint")
        XCTAssertEqual(kk_short_to_uint(-5), 65531, "Negative short should convert using two's complement")
    }

    func testByteToULongConversion() {
        XCTAssertEqual(kk_byte_to_ulong(100), 100, "Positive byte should convert to ulong")
        XCTAssertEqual(kk_byte_to_ulong(-5), 251, "Negative byte should convert using two's complement")
    }

    func testShortToULongConversion() {
        XCTAssertEqual(kk_short_to_ulong(1000), 1000, "Positive short should convert to ulong")
        XCTAssertEqual(kk_short_to_ulong(-5), 65531, "Negative short should convert using two's complement")
    }

    func testByteToCharConversion() {
        XCTAssertEqual(kk_byte_to_char(65), 65, "Valid ASCII should convert to char")
        XCTAssertEqual(kk_byte_to_char(-5), 0xFFFB, "Negative byte should truncate to 16 bits")
    }

    func testShortToCharConversion() {
        XCTAssertEqual(kk_short_to_char(65), 65, "Valid ASCII should convert to char")
        XCTAssertEqual(kk_short_to_char(0x1F600), 0xF600, "Value should truncate to low 16 bits")
    }

    func testFloatToCharConversion() {
        XCTAssertEqual(kk_float_to_char(kk_float_to_bits(Float(65.0))), 65, "Valid float should convert to char")
        XCTAssertEqual(kk_float_to_char(kk_float_to_bits(Float.nan)), 0, "NaN should convert to 0")
        XCTAssertEqual(kk_float_to_char(kk_float_to_bits(Float(-1.0))), 0, "Negative float should convert to 0")
    }

    func testDoubleToCharConversion() {
        XCTAssertEqual(kk_double_to_char(kk_double_to_bits(65.0)), 65, "Valid double should convert to char")
        XCTAssertEqual(kk_double_to_char(kk_double_to_bits(Double.nan)), 0, "NaN should convert to 0")
        XCTAssertEqual(kk_double_to_char(kk_double_to_bits(-1.0)), 0, "Negative double should convert to 0")
    }

    // MARK: - Cross-Type Conversion Tests

    func testCrossTypeUByteConversions() {
        // Test all UByte conversions work together
        let original = 200
        let asUByte = kk_int_to_ubyte(original)
        let backToInt = kk_ubyte_to_int(asUByte)
        let asLong = kk_ubyte_to_long(asUByte)
        let asUInt = kk_ubyte_to_uint(asUByte)
        let asULong = kk_ubyte_to_ulong(asUByte)
        let asChar = kk_ubyte_to_char(asUByte)
        
        XCTAssertEqual(backToInt, original, "UByte round-trip conversion should preserve value")
        XCTAssertEqual(asLong, original, "UByte to Long should preserve value")
        XCTAssertEqual(asUInt, original, "UByte to UInt should preserve value")
        XCTAssertEqual(asULong, original, "UByte to ULong should preserve value")
        XCTAssertEqual(asChar, original, "UByte to Char should preserve value")
    }

    func testCrossTypeUShortConversions() {
        // Test all UShort conversions work together
        let original = 50000
        let asUShort = kk_int_to_ushort(original)
        let backToInt = kk_ushort_to_int(asUShort)
        let asLong = kk_ushort_to_long(asUShort)
        let asUInt = kk_ushort_to_uint(asUShort)
        let asULong = kk_ushort_to_ulong(asUShort)
        let asChar = kk_ushort_to_char(asUShort)
        
        XCTAssertEqual(backToInt, original, "UShort round-trip conversion should preserve value")
        XCTAssertEqual(asLong, original, "UShort to Long should preserve value")
        XCTAssertEqual(asUInt, original, "UShort to UInt should preserve value")
        XCTAssertEqual(asULong, original, "UShort to ULong should preserve value")
        XCTAssertEqual(asChar, original, "UShort to Char should preserve value")
    }

    func testCrossTypeCharConversions() {
        // Test all Char conversions work together
        let original = 0x1F600 // 😀 emoji
        let asChar = kk_int_to_char(original)
        let backToInt = kk_char_to_int(asChar)
        let asLong = kk_char_to_long(asChar)
        let asUInt = kk_char_to_uint(asChar)
        let asULong = kk_char_to_ulong(asChar)

        XCTAssertEqual(backToInt, 0xF600, "Char round-trip conversion should preserve the low 16 bits")
        XCTAssertEqual(asLong, 0xF600, "Char to Long should preserve the low 16 bits")
        XCTAssertEqual(asUInt, 0xF600, "Char to UInt should preserve the low 16 bits")
        XCTAssertEqual(asULong, 0xF600, "Char to ULong should preserve the low 16 bits")
    }

}
