@testable import Runtime
import XCTest

/// Edge case and boundary value coverage for kotlin.random (STDLIB-RANDOM-003).
/// Covers: seed reproducibility, nextBits boundaries, nextInt/nextDouble/nextBoolean/nextBytes edge cases.
final class RuntimeRandomBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func makeSeeded(_ seed: Int) -> Int {
        kk_random_create_seeded(seed)
    }

    private func bitsToDouble(_ bits: Int) -> Double {
        kk_bits_to_double(bits)
    }

    private func bitsToFloat(_ bits: Int) -> Float {
        kk_bits_to_float(bits)
    }

    private func ulongRaw(_ value: UInt64) -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: value))
    }

    private func ulongPayload(_ raw: Int) -> UInt64 {
        UInt64(UInt(bitPattern: raw))
    }

    // MARK: - Seed Reproducibility: nextInt

    func testSeedReproducibilityNextInt() {
        let r1 = makeSeeded(777)
        let r2 = makeSeeded(777)
        for _ in 0..<20 {
            XCTAssertEqual(kk_random_nextInt(r1), kk_random_nextInt(r2),
                           "nextInt: same seed must produce identical sequence")
        }
    }

    func testSeedReproducibilityNextIntUntil() {
        let r1 = makeSeeded(888)
        let r2 = makeSeeded(888)
        var thrown1: Int = 0
        var thrown2: Int = 0
        for _ in 0..<20 {
            let v1 = kk_random_nextInt_until(r1, 1000, &thrown1)
            let v2 = kk_random_nextInt_until(r2, 1000, &thrown2)
            XCTAssertEqual(thrown1, 0)
            XCTAssertEqual(thrown2, 0)
            XCTAssertEqual(v1, v2, "nextInt(until): same seed must produce identical sequence")
        }
    }

    func testSeedReproducibilityNextIntRange() {
        let r1 = makeSeeded(99)
        let r2 = makeSeeded(99)
        var thrown1: Int = 0
        var thrown2: Int = 0
        for _ in 0..<20 {
            let v1 = kk_random_nextInt_range(r1, -500, 500, &thrown1)
            let v2 = kk_random_nextInt_range(r2, -500, 500, &thrown2)
            XCTAssertEqual(thrown1, 0)
            XCTAssertEqual(thrown2, 0)
            XCTAssertEqual(v1, v2, "nextInt(from, until): same seed must produce identical sequence")
        }
    }

    // MARK: - Seed Reproducibility: nextDouble

    func testSeedReproducibilityNextDouble() {
        let r1 = makeSeeded(314)
        let r2 = makeSeeded(314)
        for _ in 0..<20 {
            let d1 = bitsToDouble(kk_random_nextDouble(r1))
            let d2 = bitsToDouble(kk_random_nextDouble(r2))
            XCTAssertEqual(d1, d2, "nextDouble: same seed must produce identical sequence")
        }
    }

    func testSeedReproducibilityNextDoubleUntil() {
        let r1 = makeSeeded(271)
        let r2 = makeSeeded(271)
        var thrown1: Int = 0
        var thrown2: Int = 0
        let untilBits = kk_double_to_bits(100.0)
        for _ in 0..<20 {
            let v1 = bitsToDouble(kk_random_nextDouble_until(r1, untilBits, &thrown1))
            let v2 = bitsToDouble(kk_random_nextDouble_until(r2, untilBits, &thrown2))
            XCTAssertEqual(thrown1, 0)
            XCTAssertEqual(thrown2, 0)
            XCTAssertEqual(v1, v2, "nextDouble(until): same seed must produce identical sequence")
        }
    }

    // MARK: - Seed Reproducibility: nextBoolean

    func testSeedReproducibilityNextBoolean() {
        let r1 = makeSeeded(2718)
        let r2 = makeSeeded(2718)
        for _ in 0..<20 {
            // kk_random_nextBoolean returns a boxed bool; unbox before comparing.
            let b1 = kk_unbox_bool(kk_random_nextBoolean(r1))
            let b2 = kk_unbox_bool(kk_random_nextBoolean(r2))
            XCTAssertEqual(b1, b2, "nextBoolean: same seed must produce identical sequence")
        }
    }

    // MARK: - Seed Reproducibility: cross-method sequence

    func testSeedReproducibilityMixedMethods() {
        let r1 = makeSeeded(1234567)
        let r2 = makeSeeded(1234567)
        // Interleave different method calls; both instances must stay in lock-step.
        XCTAssertEqual(kk_random_nextInt(r1), kk_random_nextInt(r2))
        XCTAssertEqual(bitsToDouble(kk_random_nextDouble(r1)), bitsToDouble(kk_random_nextDouble(r2)))
        XCTAssertEqual(bitsToFloat(kk_random_nextFloat(r1)), bitsToFloat(kk_random_nextFloat(r2)))
        // nextBoolean returns a boxed bool; compare unboxed semantic value.
        XCTAssertEqual(kk_unbox_bool(kk_random_nextBoolean(r1)), kk_unbox_bool(kk_random_nextBoolean(r2)))
        XCTAssertEqual(kk_random_nextInt(r1), kk_random_nextInt(r2))
    }

    // MARK: - Different Seeds Produce Different Values

    func testDifferentSeedsDifferentSequences() {
        let r1 = makeSeeded(1)
        let r2 = makeSeeded(2)
        var anyDiff = false
        for _ in 0..<20 {
            if kk_random_nextInt(r1) != kk_random_nextInt(r2) {
                anyDiff = true
                break
            }
        }
        XCTAssertTrue(anyDiff, "Different seeds should (almost certainly) produce different sequences")
    }

    // MARK: - nextBits: boundary values

    func testNextBitsZero() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextBits(r, 0, &thrown)
        XCTAssertEqual(thrown, 0, "nextBits(0) should not throw")
        XCTAssertEqual(result, 0, "nextBits(0) must return 0")
    }

    func testNextBitsOne() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextBits(r, 1, &thrown)
        XCTAssertEqual(thrown, 0, "nextBits(1) should not throw")
        XCTAssertTrue(result == 0 || result == 1,
                      "nextBits(1) must return 0 or 1, got \(result)")
    }

    func testNextBits32() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextBits(r, 32, &thrown)
        XCTAssertEqual(thrown, 0, "nextBits(32) should not throw")
        // Result is reinterpreted as Int32 (may be negative), check it fits Int32 range.
        XCTAssertTrue(result >= Int(Int32.min) && result <= Int(Int32.max),
                      "nextBits(32) result must fit in Int32 range, got \(result)")
    }

    func testNextBits31() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextBits(r, 31, &thrown)
        XCTAssertEqual(thrown, 0, "nextBits(31) should not throw")
        // 31-bit mask means top bit is always 0 → result is non-negative.
        XCTAssertGreaterThanOrEqual(result, 0,
                                    "nextBits(31) result must be >= 0, got \(result)")
        XCTAssertLessThan(result, (1 << 31),
                          "nextBits(31) result must be < 2^31, got \(result)")
    }

    func testNextBitsThrowsOnNegative() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        _ = kk_random_nextBits(r, -1, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextBits(-1) must throw IllegalArgumentException")
    }

    func testNextBitsThrowsOnOverflow() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        _ = kk_random_nextBits(r, 33, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextBits(33) must throw IllegalArgumentException")
    }

    func testNextBitsSeedReproducibility() {
        let r1 = makeSeeded(555)
        let r2 = makeSeeded(555)
        var thrown1: Int = 0
        var thrown2: Int = 0
        for bitCount in [0, 1, 8, 16, 31, 32] {
            let v1 = kk_random_nextBits(r1, bitCount, &thrown1)
            let v2 = kk_random_nextBits(r2, bitCount, &thrown2)
            XCTAssertEqual(thrown1, 0)
            XCTAssertEqual(thrown2, 0)
            XCTAssertEqual(v1, v2, "nextBits(\(bitCount)): same seed must produce identical values")
        }
    }

    // MARK: - nextInt: boundary range values

    func testNextIntUntilOne() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        let result = kk_random_nextInt_until(r, 1, &thrown)
        XCTAssertEqual(thrown, 0, "nextInt(until=1) should not throw")
        XCTAssertEqual(result, 0, "nextInt(until=1) must return 0")
    }

    func testNextIntRangeSingleValue() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        // from=5, until=6 → only 5 is valid
        let result = kk_random_nextInt_range(r, 5, 6, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 5, "nextInt(5, 6) must return 5")
    }

    func testNextIntRangeNegativeBounds() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextInt_range(r, -100, -1, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= -100 && result < -1,
                      "nextInt(-100, -1) result must be in [-100, -1), got \(result)")
    }

    func testNextIntRangeLargePositive() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let from = Int(Int32.max) - 10
        let until = Int(Int32.max)
        let result = kk_random_nextInt_range(r, from, until, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= from && result < until,
                      "nextInt near Int32.max: got \(result)")
    }

    func testNextIntUntilThrowsOnZero() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextInt_until(r, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextInt(until=0) must throw")
    }

    func testNextIntUntilThrowsOnNegative() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextInt_until(r, -10, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextInt(until=-10) must throw")
    }

    func testNextIntRangeThrowsWhenFromEqualsUntil() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextInt_range(r, 7, 7, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextInt(7, 7) must throw (empty range)")
    }

    func testNextIntRangeThrowsWhenFromGreaterThanUntil() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextInt_range(r, 10, 5, &thrown)
        XCTAssertNotEqual(thrown, 0, "nextInt(10, 5) must throw (inverted range)")
    }

    // MARK: - nextDouble: boundary / special values

    func testNextDoubleUnitRange() {
        let r = makeSeeded(42)
        for _ in 0..<100 {
            let d = bitsToDouble(kk_random_nextDouble(r))
            XCTAssertGreaterThanOrEqual(d, 0.0)
            XCTAssertLessThan(d, 1.0)
            XCTAssertTrue(d.isFinite)
        }
    }

    func testNextDoubleUntilThrowsOnZero() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_until(r, kk_double_to_bits(0.0), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(until=0.0) must throw")
    }

    func testNextDoubleUntilThrowsOnNegative() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_until(r, kk_double_to_bits(-1.0), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(until=-1.0) must throw")
    }

    func testNextDoubleUntilThrowsOnNaN() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_until(r, kk_double_to_bits(Double.nan), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(until=NaN) must throw")
    }

    func testNextDoubleUntilThrowsOnInfinity() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_until(r, kk_double_to_bits(Double.infinity), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(until=+Inf) must throw")
    }

    func testNextDoubleRangeThrowsWhenFromEqualsUntil() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_range(r, kk_double_to_bits(1.0), kk_double_to_bits(1.0), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(1.0, 1.0) must throw (empty range)")
    }

    func testNextDoubleRangeThrowsOnNaNFrom() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextDouble_range(r, kk_double_to_bits(Double.nan), kk_double_to_bits(1.0), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextDouble(NaN, 1.0) must throw")
    }

    // MARK: - nextFloat: boundary / special values

    func testNextFloatUnitRange() {
        let r = makeSeeded(42)
        for _ in 0..<100 {
            let f = bitsToFloat(kk_random_nextFloat(r))
            XCTAssertGreaterThanOrEqual(f, 0.0)
            XCTAssertLessThan(f, 1.0)
            XCTAssertTrue(f.isFinite)
        }
    }

    func testNextFloatUntilThrowsOnNaN() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextFloat_until(r, Int(Float.nan.bitPattern), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextFloat(until=NaN) must throw")
    }

    func testNextFloatUntilThrowsOnInfinity() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextFloat_until(r, Int(Float.infinity.bitPattern), &thrown)
        XCTAssertNotEqual(thrown, 0, "nextFloat(until=+Inf) must throw")
    }

    // MARK: - nextBoolean: distribution sanity

    func testNextBooleanProducesBothValues() {
        // Verify that nextBoolean eventually produces both true and false over many calls.
        let r = makeSeeded(12345)
        var sawTrue = false
        var sawFalse = false
        for _ in 0..<200 {
            let v = kk_unbox_bool(kk_random_nextBoolean(r))
            if v != 0 { sawTrue = true } else { sawFalse = true }
            if sawTrue && sawFalse { break }
        }
        XCTAssertTrue(sawTrue, "nextBoolean should produce true over 200 calls")
        XCTAssertTrue(sawFalse, "nextBoolean should produce false over 200 calls")
    }

    // MARK: - nextBytes: edge cases

    func testNextBytesEmptyArray() {
        let r = makeSeeded(42)
        let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
        let resultRaw = kk_random_nextBytes(r, emptyList)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: resultRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            XCTFail("nextBytes(empty) should return a valid RuntimeListBox")
            return
        }
        XCTAssertEqual(box.elements.count, 0, "nextBytes of empty array should return empty array")
    }

    func testNextBytesSingleElement() {
        let r = makeSeeded(42)
        let singleList = registerRuntimeObject(RuntimeListBox(elements: [0]))
        let resultRaw = kk_random_nextBytes(r, singleList)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: resultRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            XCTFail("nextBytes(1) should return a valid RuntimeListBox")
            return
        }
        XCTAssertEqual(box.elements.count, 1, "nextBytes should fill exactly 1 byte")
        let byte = box.elements[0]
        XCTAssertTrue(byte >= Int(Int8.min) && byte <= Int(Int8.max),
                      "Filled byte must be in Kotlin Byte range [-128, 127], got \(byte)")
    }

    func testNextBytesOddSize() {
        let r = makeSeeded(42)
        let oddList = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: 7)))
        let resultRaw = kk_random_nextBytes(r, oddList)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: resultRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            XCTFail("nextBytes(7) should return a valid RuntimeListBox")
            return
        }
        XCTAssertEqual(box.elements.count, 7, "nextBytes should fill exactly 7 bytes")
        for (i, byte) in box.elements.enumerated() {
            XCTAssertTrue(byte >= Int(Int8.min) && byte <= Int(Int8.max),
                          "Byte at index \(i) must be in [-128, 127], got \(byte)")
        }
    }

    func testNextBytesSeedReproducibility() {
        let size = 16
        let input1 = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: size)))
        let input2 = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: size)))
        let r1 = makeSeeded(9999)
        let r2 = makeSeeded(9999)
        let raw1 = kk_random_nextBytes(r1, input1)
        let raw2 = kk_random_nextBytes(r2, input2)
        guard let ptr1 = UnsafeMutableRawPointer(bitPattern: raw1),
              let box1 = tryCast(ptr1, to: RuntimeListBox.self),
              let ptr2 = UnsafeMutableRawPointer(bitPattern: raw2),
              let box2 = tryCast(ptr2, to: RuntimeListBox.self) else {
            XCTFail("nextBytes should return valid RuntimeListBox instances")
            return
        }
        XCTAssertEqual(box1.elements, box2.elements,
                       "nextBytes with same seed should produce identical byte sequences")
    }

    func testNextBytesLargeArray() {
        let r = makeSeeded(42)
        let size = 1024
        let largeList = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: size)))
        let resultRaw = kk_random_nextBytes(r, largeList)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: resultRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            XCTFail("nextBytes(1024) should return a valid RuntimeListBox")
            return
        }
        XCTAssertEqual(box.elements.count, size, "nextBytes should fill exactly \(size) bytes")
    }

    func testNextBytesSizeCreatesByteArray() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let resultRaw = kk_random_nextBytes_size(r, 7, &thrown)
        XCTAssertEqual(thrown, 0)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: resultRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            XCTFail("nextBytes(size) should return a valid RuntimeListBox")
            return
        }
        XCTAssertEqual(box.elements.count, 7, "nextBytes(size) should create exactly size bytes")
        for (i, byte) in box.elements.enumerated() {
            XCTAssertTrue(byte >= Int(Int8.min) && byte <= Int(Int8.max),
                          "Byte at index \(i) must be in [-128, 127], got \(byte)")
        }
    }

    func testNextBytesSizeThrowsForNegativeSize() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let resultRaw = kk_random_nextBytes_size(r, -1, &thrown)
        XCTAssertEqual(resultRaw, 0)
        XCTAssertNotEqual(thrown, 0, "nextBytes(size) must throw for negative size")
    }

    // MARK: - nextLong: boundary values (reconfirm via nextLong functions)

    func testNextLongRangeSingleValue() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        let result = kk_random_nextLong_range(r, 42, 43, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 42, "nextLong(42, 43) must return 42")
    }

    func testNextLongRangeNegativeBounds() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        let result = kk_random_nextLong_range(r, -1000, -1, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= -1000 && result < -1,
                      "nextLong(-1000, -1) result must be in [-1000, -1), got \(result)")
    }

    func testNextLongSeedReproducibility() {
        let r1 = makeSeeded(31416)
        let r2 = makeSeeded(31416)
        var thrown1: Int = 0
        var thrown2: Int = 0
        for _ in 0..<20 {
            let v1 = kk_random_nextLong_range(r1, 0, 1_000_000, &thrown1)
            let v2 = kk_random_nextLong_range(r2, 0, 1_000_000, &thrown2)
            XCTAssertEqual(thrown1, 0)
            XCTAssertEqual(thrown2, 0)
            XCTAssertEqual(v1, v2, "nextLong(range): same seed must produce identical sequence")
        }
    }

    // MARK: - nextULong: boundary values

    func testNextULongFullRangeSeedReproducibility() {
        let r1 = makeSeeded(41416)
        let r2 = makeSeeded(41416)
        for _ in 0..<20 {
            XCTAssertEqual(kk_random_nextULong(r1), kk_random_nextULong(r2))
        }
    }

    func testNextULongUntil() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        for _ in 0..<50 {
            let value = ulongPayload(kk_random_nextULong_until(r, ulongRaw(10), &thrown))
            XCTAssertEqual(thrown, 0)
            XCTAssertLessThan(value, 10)
        }
    }

    func testNextULongRange() {
        let r = makeSeeded(42)
        var thrown: Int = 0
        for _ in 0..<50 {
            let value = ulongPayload(kk_random_nextULong_range(r, ulongRaw(10), ulongRaw(20), &thrown))
            XCTAssertEqual(thrown, 0)
            XCTAssertGreaterThanOrEqual(value, 10)
            XCTAssertLessThan(value, 20)
        }
    }

    func testNextULongULongRange() {
        let r = makeSeeded(42)
        let range = registerRuntimeObject(RuntimeRangeBox(first: ulongRaw(30), last: ulongRaw(35), step: 1))
        var thrown: Int = 0
        for _ in 0..<50 {
            let value = ulongPayload(kk_random_nextULong_ulongRange(r, range, &thrown))
            XCTAssertEqual(thrown, 0)
            XCTAssertGreaterThanOrEqual(value, 30)
            XCTAssertLessThanOrEqual(value, 35)
        }
    }

    func testNextULongUntilThrowsOnZero() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextULong_until(r, 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testNextULongRangeThrowsWhenFromEqualsUntil() {
        let r = makeSeeded(1)
        var thrown: Int = 0
        _ = kk_random_nextULong_range(r, ulongRaw(7), ulongRaw(7), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testNextULongRangeSupportsUInt64MaxExclusiveUpper() {
        let r = makeSeeded(2)
        var thrown: Int = 0
        let value = ulongPayload(kk_random_nextULong_range(r, ulongRaw(UInt64.max - 2), ulongRaw(UInt64.max), &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertGreaterThanOrEqual(value, UInt64.max - 2)
        XCTAssertLessThan(value, UInt64.max)
    }
}
