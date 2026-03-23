import Dispatch
@testable import Runtime
import XCTest

// MARK: - C-callable thunks for kk_measureTime tests

/// A no-op closure thunk that returns 0 immediately.
private let noopThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    0
}

/// A closure thunk that sleeps ~50ms before returning.
private let sleep50msThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    Thread.sleep(forTimeInterval: 0.05)
    return 0
}

/// Global to capture closureRaw value passed to the thunk.
/// Access is single-threaded in tests; disable concurrency-safety check.
nonisolated(unsafe) private var capturedClosureRaw: Int = 0

/// A closure thunk that captures its closureRaw value into a global for verification.
private let captureClosureRawThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, _ in
    capturedClosureRaw = closureRaw
    return 0
}

/// A closure thunk that simulates a thrown exception by writing to outThrown.
private let throwingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    // Simulate a thrown exception with a sentinel value.
    outThrown?.pointee = 0xDEAD
    return 0
}

final class RuntimeDurationTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helper

    /// Extract the Swift String from a duration toString handle.
    /// Note: Uses UnsafeMutableRawPointer because extractString(from:) requires it.
    private func stringFromHandle(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    // MARK: - Factory: kk_duration_from_nanoseconds

    func testFromNanosecondsStoresExactValue() {
        let handle = kk_duration_from_nanoseconds(500)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 500)
    }

    func testFromNanosecondsZero() {
        let handle = kk_duration_from_nanoseconds(0)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 0)
    }

    func testFromNanosecondsNegative() {
        let handle = kk_duration_from_nanoseconds(-1000)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), -1000)
    }

    // MARK: - Factory: kk_duration_from_microseconds

    func testFromMicrosecondsConvertsToNanoseconds() {
        let handle = kk_duration_from_microseconds(3)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 3000)
    }

    func testFromMicrosecondsZero() {
        let handle = kk_duration_from_microseconds(0)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 0)
    }

    // MARK: - Factory: kk_duration_from_milliseconds

    func testFromMillisecondsConvertsToNanoseconds() {
        let handle = kk_duration_from_milliseconds(5)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 5_000_000)
    }

    func testFromMillisecondsRoundTrip() {
        let handle = kk_duration_from_milliseconds(42)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 42)
    }

    func testFromMillisecondsZero() {
        let handle = kk_duration_from_milliseconds(0)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 0)
    }

    func testFromMillisecondsNegative() {
        let handle = kk_duration_from_milliseconds(-100)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), -100)
    }

    // MARK: - Factory: kk_duration_from_seconds

    func testFromSecondsConvertsToNanoseconds() {
        let handle = kk_duration_from_seconds(2)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 2_000_000_000)
    }

    func testFromSecondsRoundTrip() {
        let handle = kk_duration_from_seconds(7)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 7)
    }

    func testFromSecondsZero() {
        let handle = kk_duration_from_seconds(0)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 0)
    }

    func testFromSecondsNegative() {
        let handle = kk_duration_from_seconds(-3)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), -3)
    }

    // MARK: - Factory: kk_duration_from_minutes

    func testFromMinutesConvertsToNanoseconds() {
        let handle = kk_duration_from_minutes(1)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 60_000_000_000)
    }

    func testFromMinutesRoundTripSeconds() {
        let handle = kk_duration_from_minutes(2)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 120)
    }

    func testFromMinutesZero() {
        let handle = kk_duration_from_minutes(0)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 0)
    }

    // MARK: - Factory: kk_duration_from_hours

    func testFromHoursConvertsToNanoseconds() {
        let handle = kk_duration_from_hours(1)
        let expected = Int(3600) * 1_000_000_000
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), expected)
    }

    func testFromHoursRoundTripSeconds() {
        let handle = kk_duration_from_hours(2)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 7200)
    }

    func testFromHoursZero() {
        let handle = kk_duration_from_hours(0)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 0)
    }

    // MARK: - inWholeHours

    func testInWholeHoursFromHoursRoundTrip() {
        let handle = kk_duration_from_hours(3)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 3)
    }

    func testInWholeHoursFromMinutes() {
        let handle = kk_duration_from_minutes(150)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 2)
    }

    func testInWholeHoursFromSeconds() {
        let handle = kk_duration_from_seconds(7200)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 2)
    }

    func testInWholeHoursTruncatesSubHour() {
        // 90 minutes = 1.5 hours -> inWholeHours should return 1
        let handle = kk_duration_from_minutes(90)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 1)
    }

    func testInWholeHoursSubHourReturnsZero() {
        let handle = kk_duration_from_minutes(59)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 0)
    }

    func testInWholeHoursZero() {
        let handle = kk_duration_from_hours(0)
        XCTAssertEqual(kk_duration_inWholeHours(handle), 0)
    }

    func testInWholeHoursNegative() {
        let handle = kk_duration_from_hours(-5)
        XCTAssertEqual(kk_duration_inWholeHours(handle), -5)
    }

    // MARK: - Saturation on overflow

    func testFromSecondsLargeValueSaturates() {
        // Int64.max / 1_000_000_000 = 9_223_372_036, so 9_223_372_037 will overflow.
        let handle = kk_duration_from_seconds(9_223_372_037)
        let ns = kk_duration_inWholeNanoseconds(handle)
        // The result must be saturated to Int64.max.
        XCTAssertEqual(ns, Int(Int64.max))
    }

    func testFromMillisecondsLargeNegativeValueSaturates() {
        // Int64.min / 1_000_000 = -9_223_372_036_854, so -9_223_372_036_855 will overflow.
        let handle = kk_duration_from_milliseconds(-9_223_372_036_855)
        let ns = kk_duration_inWholeNanoseconds(handle)
        // The result must be saturated to Int64.min.
        XCTAssertEqual(ns, Int(Int64.min))
    }

    // MARK: - inWholeMicroseconds

    func testInWholeMicrosecondsFromSeconds() {
        let handle = kk_duration_from_seconds(3)
        XCTAssertEqual(kk_duration_inWholeMicroseconds(handle), 3_000_000)
    }

    func testInWholeMicrosecondsFromMilliseconds() {
        let handle = kk_duration_from_milliseconds(2500)
        XCTAssertEqual(kk_duration_inWholeMicroseconds(handle), 2_500_000)
    }

    func testInWholeMicrosecondsRoundTrip() {
        let handle = kk_duration_from_microseconds(42)
        XCTAssertEqual(kk_duration_inWholeMicroseconds(handle), 42)
    }

    func testInWholeMicrosecondsTruncatesSubMicrosecond() {
        // 1500 ns = 1.5 us -> inWholeMicroseconds should return 1
        let handle = kk_duration_from_nanoseconds(1500)
        XCTAssertEqual(kk_duration_inWholeMicroseconds(handle), 1)
    }

    func testInWholeMicrosecondsSubMicrosecondReturnsZero() {
        // 999 ns < 1 us -> inWholeMicroseconds should return 0
        let handle = kk_duration_from_nanoseconds(999)
        XCTAssertEqual(kk_duration_inWholeMicroseconds(handle), 0)
    }

    // MARK: - inWholeMilliseconds truncation

    func testInWholeMillisecondsTruncatesSubMillisecond() {
        // 1_500_000 ns = 1.5 ms -> inWholeMilliseconds should return 1
        let handle = kk_duration_from_nanoseconds(1_500_000)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 1)
    }

    func testInWholeMillisecondsSubMillisecondReturnsZero() {
        // 999_999 ns < 1 ms -> inWholeMilliseconds should return 0
        let handle = kk_duration_from_nanoseconds(999_999)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 0)
    }

    // MARK: - inWholeSeconds truncation

    func testInWholeSecondsTruncatesSubSecond() {
        // 1500 ms = 1.5 s -> inWholeSeconds should return 1
        let handle = kk_duration_from_milliseconds(1500)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 1)
    }

    func testInWholeSecondsSubSecondReturnsZero() {
        let handle = kk_duration_from_milliseconds(999)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 0)
    }

    // MARK: - toString formatting

    func testToStringZeroSeconds() {
        let handle = kk_duration_from_nanoseconds(0)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "0s")
    }

    func testToStringWholeSeconds() {
        let handle = kk_duration_from_seconds(5)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "5s")
    }

    func testToStringNegativeWholeSeconds() {
        let handle = kk_duration_from_seconds(-3)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "-3s")
    }

    func testToStringWholeMilliseconds() {
        let handle = kk_duration_from_milliseconds(42)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "42ms")
    }

    func testToStringWholeMicroseconds() {
        let handle = kk_duration_from_microseconds(7)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "7us")
    }

    func testToStringNanoseconds() {
        let handle = kk_duration_from_nanoseconds(123)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "123ns")
    }

    func testToStringOneMinuteRendersAsSeconds() {
        // 1 minute = 60_000_000_000 ns, which is divisible by 1_000_000_000
        let handle = kk_duration_from_minutes(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "60s")
    }

    func testToStringOneHourRendersAsSeconds() {
        let handle = kk_duration_from_hours(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "3600s")
    }

    // MARK: - Multiple independent durations

    func testMultipleDurationsAreIndependent() {
        let h1 = kk_duration_from_seconds(10)
        let h2 = kk_duration_from_milliseconds(500)
        XCTAssertEqual(kk_duration_inWholeSeconds(h1), 10)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(h2), 500)
    }

    // MARK: - RuntimeDurationBox accessor chain

    func testDurationBoxAccessorChainEndToEnd() {
        // Verify the direct RuntimeDurationBox path by constructing one
        // manually and confirming the accessor chain works end-to-end.
        let box = RuntimeDurationBox(nanoseconds: 42_000_000)
        let handle = registerRuntimeObject(box)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 42)
        XCTAssertEqual(kk_duration_inWholeSeconds(handle), 0)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(handle), 42_000_000)
    }

    func testDurationBoxLargeValueDoesNotCrash() {
        // Verify that a box with Int64.max nanoseconds does not crash accessors.
        let box = RuntimeDurationBox(nanoseconds: Int64.max)
        let handle = registerRuntimeObject(box)
        let ms = kk_duration_inWholeMilliseconds(handle)
        let s = kk_duration_inWholeSeconds(handle)
        XCTAssertGreaterThan(ms, 0)
        XCTAssertGreaterThan(s, 0)
    }

    // MARK: - inWholeMinutes

    func testInWholeMinutesFromMinutesRoundTrip() {
        let handle = kk_duration_from_minutes(5)
        XCTAssertEqual(kk_duration_inWholeMinutes(handle), 5)
    }

    func testInWholeMinutesTruncatesSubMinute() {
        // 90 seconds = 1.5 minutes -> inWholeMinutes should return 1
        let handle = kk_duration_from_seconds(90)
        XCTAssertEqual(kk_duration_inWholeMinutes(handle), 1)
    }

    func testInWholeMinutesSubMinuteReturnsZero() {
        let handle = kk_duration_from_seconds(59)
        XCTAssertEqual(kk_duration_inWholeMinutes(handle), 0)
    }

    func testInWholeMinutesFromHours() {
        let handle = kk_duration_from_hours(2)
        XCTAssertEqual(kk_duration_inWholeMinutes(handle), 120)
    }

    func testInWholeMinutesNegative() {
        let handle = kk_duration_from_minutes(-3)
        XCTAssertEqual(kk_duration_inWholeMinutes(handle), -3)
    }

    // MARK: - Saturation edge cases

    func testFromMicrosecondsLargePositiveSaturates() {
        // Int64.max / 1_000 overflows, should saturate
        let handle = kk_duration_from_microseconds(Int(Int64.max / 999))
        let ns = kk_duration_inWholeNanoseconds(handle)
        XCTAssertEqual(ns, Int(Int64.max))
    }

    func testFromMinutesLargePositiveSaturates() {
        // Very large minutes value should saturate
        let handle = kk_duration_from_minutes(Int(Int64.max / 1_000_000_000))
        let ns = kk_duration_inWholeNanoseconds(handle)
        XCTAssertEqual(ns, Int(Int64.max))
    }

    func testFromHoursLargePositiveSaturates() {
        // Very large hours value should saturate
        let handle = kk_duration_from_hours(Int(Int64.max / 1_000_000_000))
        let ns = kk_duration_inWholeNanoseconds(handle)
        XCTAssertEqual(ns, Int(Int64.max))
    }

    // MARK: - toString edge cases

    func testToStringSubMicrosecondRendersAsNanoseconds() {
        // 1_500 ns: 1500 % 1000 == 500 (not divisible), so renders as "1500ns"
        let handle = kk_duration_from_nanoseconds(1_500)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1500ns")
    }

    func testToStringExactlyOneMicrosecond() {
        let handle = kk_duration_from_microseconds(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1us")
    }

    func testToStringExactlyOneNanosecond() {
        let handle = kk_duration_from_nanoseconds(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1ns")
    }

    func testToStringNegativeMilliseconds() {
        let handle = kk_duration_from_milliseconds(-7)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "-7ms")
    }

    func testToStringNegativeNanoseconds() {
        let handle = kk_duration_from_nanoseconds(-123)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "-123ns")
    }

    // MARK: - kk_measureTime: basic timing

    func testMeasureTimeReturnsNonZeroDuration() {
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0, "No exception should be thrown")
        XCTAssertNotEqual(result, 0, "Should return a valid duration handle")
        // Even a no-op should take >= 0 nanoseconds
        let ns = kk_duration_inWholeNanoseconds(result)
        XCTAssertGreaterThanOrEqual(ns, 0)
    }

    func testMeasureTimeElapsedIsPlausible() {
        // A 50ms sleep should produce a duration roughly in [40ms, 500ms]
        let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        let ms = kk_duration_inWholeMilliseconds(result)
        XCTAssertGreaterThanOrEqual(ms, 40, "Should be at least ~40ms")
        XCTAssertLessThan(ms, 500, "Should not exceed 500ms")
    }

    func testMeasureTimeNoopIsFast() {
        // A no-op closure should complete in well under 100ms
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        let ms = kk_duration_inWholeMilliseconds(result)
        XCTAssertLessThan(ms, 100, "No-op should complete in < 100ms")
    }

    // MARK: - kk_measureTime: exception propagation

    func testMeasureTimeReturnsZeroOnException() {
        let fnPtr = unsafeBitCast(throwingThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "Exception sentinel should be propagated")
        XCTAssertEqual(thrown, 0xDEAD, "Should propagate the exact exception value")
        XCTAssertEqual(result, 0, "Duration handle should be 0 on exception")
    }

    func testMeasureTimeOutThrownInitializedToZero() {
        // Verify outThrown is cleared before invocation
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0xBEEF // pre-fill with garbage
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0, "outThrown should be reset to 0 for non-throwing closure")
        XCTAssertNotEqual(result, 0)
    }

    // MARK: - kk_measureTime: closureRaw passthrough

    func testMeasureTimePassesClosureRawToThunk() {
        // The captureClosureRawThunk stores its closureRaw argument into a global.
        // We verify kk_measureTime forwards the closureRaw value correctly.
        capturedClosureRaw = 0
        let fnPtr = unsafeBitCast(captureClosureRawThunk, to: Int.self)
        var thrown: Int = 0
        let sentinel = 42
        let result = kk_measureTime(fnPtr, sentinel, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(capturedClosureRaw, sentinel, "closureRaw should be forwarded to the thunk")
        // The duration should still be valid (non-zero handle)
        XCTAssertNotEqual(result, 0)
        let ns = kk_duration_inWholeNanoseconds(result)
        XCTAssertGreaterThanOrEqual(ns, 0)
    }

    // MARK: - kk_measureTime: nullable outThrown

    func testMeasureTimeNilOutThrownDoesNotCrash() {
        // kk_measureTime accepts a nullable outThrown pointer.
        // Passing nil should not crash even for a non-throwing closure.
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        let result = kk_measureTime(fnPtr, 0, nil)
        XCTAssertNotEqual(result, 0)
        let ns = kk_duration_inWholeNanoseconds(result)
        XCTAssertGreaterThanOrEqual(ns, 0)
    }

    // MARK: - kk_measureTime: result is a proper Duration

    func testMeasureTimeResultWorksWithDurationAccessors() {
        // Verify the returned handle is a valid RuntimeDurationBox
        // that works with all duration accessor functions.
        let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        // All accessors should work without crashing
        let ns = kk_duration_inWholeNanoseconds(result)
        let ms = kk_duration_inWholeMilliseconds(result)
        let s = kk_duration_inWholeSeconds(result)
        let min = kk_duration_inWholeMinutes(result)

        XCTAssertGreaterThan(ns, 0)
        XCTAssertGreaterThanOrEqual(ms, 40)
        XCTAssertGreaterThanOrEqual(s, 0)
        XCTAssertGreaterThanOrEqual(min, 0)
    }

    func testMeasureTimeResultWorksWithToString() {
        // The toString of a measured duration should produce a non-empty string
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let strHandle = kk_duration_toString(result)
        guard let str = stringFromHandle(strHandle) else {
            XCTFail("toString returned nil for a valid duration handle")
            return
        }
        // The string should end with a time unit suffix.
        // Check longest suffixes first to avoid "s" matching "ns"/"us"/"ms".
        let validSuffixes = ["ns", "us", "ms", "s"]
        let hasValidSuffix = validSuffixes.contains { str.hasSuffix($0) }
        XCTAssertTrue(hasValidSuffix, "toString should end with a time unit suffix, got: \(str)")
    }

    // MARK: - kk_measureTime: consecutive calls

    func testMeasureTimeConsecutiveCallsProduceIndependentDurations() {
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown1: Int = 0
        var thrown2: Int = 0
        let result1 = kk_measureTime(fnPtr, 0, &thrown1)
        let result2 = kk_measureTime(fnPtr, 0, &thrown2)
        XCTAssertEqual(thrown1, 0)
        XCTAssertEqual(thrown2, 0)
        // Both should be valid, independent duration handles
        XCTAssertNotEqual(result1, 0)
        XCTAssertNotEqual(result2, 0)
        // They should be distinct handles (different allocations)
        XCTAssertNotEqual(result1, result2)
    }
}
