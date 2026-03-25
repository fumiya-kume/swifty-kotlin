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
        XCTAssertEqual(kk_int_coerceAtMost(-15, -1), -1, "Negative value above negative maximum should be clamped")
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
        // Test precision loss when converting between Float and Double
        let preciseDouble = 1.23456789012345
        let doubleBits = doubleToBits(preciseDouble)
        let floatBits = kk_float_to_double_bits(doubleBits)
        let convertedBack = bitsToDouble(floatBits)

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

    // MARK: - Error Handling Tests

    func testCoerceInEmptyRangePrecondition() {
        // Test that empty ranges trigger preconditions
        let minValue = 10
        let maxValue = 5
        let testValue = 7

        // This should trigger a precondition failure
        XCTAssertThrowsError(
            withExtendedLifetime((minValue, maxValue, testValue)) { _ in
                kk_int_coerceIn(testValue, minValue, maxValue)
            }
        ) { error in
            XCTAssertNotNil(error, "Should trigger precondition failure")
        }
    }

    func testDoubleCoerceInEmptyRangePrecondition() {
        // Test empty range with doubles
        let minValue = 10.0
        let maxValue = 5.0
        let testValue = 7.0

        XCTAssertThrowsError(
            withExtendedLifetime((minValue, maxValue, testValue)) { _ in
                let minBits = doubleToBits(minValue)
                let maxBits = doubleToBits(maxValue)
                let valueBits = doubleToBits(testValue)
                kk_double_coerceIn(valueBits, minBits, maxBits)
            }
        ) { error in
            XCTAssertNotNil(error, "Should trigger precondition failure")
        }
    }

    func testFloatCoerceInEmptyRangePrecondition() {
        // Test empty range with floats
        let minValue: Float = 10.0
        let maxValue: Float = 5.0
        let testValue: Float = 7.0

        XCTAssertThrowsError(
            withExtendedLifetime((minValue, maxValue, testValue)) { _ in
                let minBits = floatToBits(minValue)
                let maxBits = floatToBits(maxValue)
                let valueBits = floatToBits(testValue)
                kk_float_coerceIn(valueBits, minBits, maxBits)
            }
        ) { error in
            XCTAssertNotNil(error, "Should trigger precondition failure")
        }
    }
}

// Helper for testing precondition failures
private extension XCTestCase {
    func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (_ error: Error) -> Void = { _ in }) {
        do {
            _ = try expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
