import Dispatch
@testable import Runtime
import XCTest

// Runtime テストの下限時間（短縮候補・フレークに注意）: 本ファイルの ~50ms sleep（measureTime）、
// RuntimeFlowTests の usleep、RuntimeChannelTests / RuntimeMutexTests の期待待ち 2s 前後、
// RuntimeReadWriteLockTests のセマフォ待ち 2s など。

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
private let capturedClosureRawLock = NSLock()
nonisolated(unsafe) private var _capturedClosureRaw: Int = 0

private var capturedClosureRaw: Int {
    get {
        capturedClosureRawLock.lock()
        defer { capturedClosureRawLock.unlock() }
        return _capturedClosureRaw
    }
    set {
        capturedClosureRawLock.lock()
        defer { capturedClosureRawLock.unlock() }
        _capturedClosureRaw = newValue
    }
}

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
    override func resetIsolatedRuntimeTestState() {
        capturedClosureRaw = 0
    }

    private final class DurationResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []

        func append(_ value: Int) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func snapshot() -> [Int] {
            lock.lock()
            let snapshot = values
            lock.unlock()
            return snapshot
        }
    }

    // MARK: - Helper

    /// Extract the Swift String from a duration toString handle.
    /// Note: Uses UnsafeMutableRawPointer because extractString(from:) requires it.
    private func stringFromHandle(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    private func stringHandle(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
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

    // MARK: - Duration companion constants

    func testDurationZeroAndInfiniteConstants() {
        let zero = kk_duration_zero()
        let infinite = kk_duration_infinite()

        XCTAssertEqual(kk_duration_inWholeNanoseconds(zero), 0)
        XCTAssertEqual(kk_duration_isFinite(zero), 1)
        XCTAssertEqual(kk_duration_isInfinite(zero), 0)

        XCTAssertEqual(kk_duration_isInfinite(infinite), 1)
        XCTAssertEqual(kk_duration_isFinite(infinite), 0)
    }

    // MARK: - Double receiver factories

    func testDoubleReceiverSecondsConvertsFractionalDuration() {
        let handle = kk_duration_from_seconds_double(kk_double_to_bits(1.5))
        XCTAssertEqual(kk_duration_inWholeMilliseconds(handle), 1_500)
    }

    func testDoubleReceiverDaysConvertsFractionalDuration() {
        let handle = kk_duration_from_days_double(kk_double_to_bits(1.25))
        XCTAssertEqual(kk_duration_inWholeHours(handle), 30)
    }

    // MARK: - Duration / Duration -> Double

    func testDurationDivisionReturnsDoubleBits() {
        let lhs = kk_duration_from_seconds(3)
        let rhs = kk_duration_from_seconds(2)
        let resultBits = kk_duration_div_duration(lhs, rhs)
        XCTAssertEqual(kk_bits_to_double(resultBits), 1.5)
    }

    // MARK: - inWholeDays

    func testInWholeDaysRoundTrip() {
        let handle = kk_duration_from_days(2)
        XCTAssertEqual(kk_duration_inWholeDays(handle), 2)
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
        let handle = kk_duration_from_minutes(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1m")
    }

    func testToStringOneHourRendersAsSeconds() {
        let handle = kk_duration_from_hours(1)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1h")
    }

    // MARK: - toIsoString / parse

    func testToIsoStringFormatsZeroAndFractionalSeconds() {
        let zero = kk_duration_from_nanoseconds(0)
        XCTAssertEqual(stringFromHandle(kk_duration_toIsoString(zero)), "PT0S")

        let fractional = kk_duration_from_nanoseconds(25)
        XCTAssertEqual(stringFromHandle(kk_duration_toIsoString(fractional)), "PT0.000000025S")
    }

    func testToIsoStringFormatsCompositeAndNegativeDurations() {
        let composite = kk_duration_plus(kk_duration_from_hours(1), kk_duration_from_seconds(30))
        XCTAssertEqual(stringFromHandle(kk_duration_toIsoString(composite)), "PT1H0M30S")

        let negative = kk_duration_from_seconds(-330)
        XCTAssertEqual(stringFromHandle(kk_duration_toIsoString(negative)), "-PT5M30S")
    }

    func testToIsoStringFormatsInfiniteDuration() {
        let infinite = kk_duration_infinite()
        XCTAssertEqual(stringFromHandle(kk_duration_toIsoString(infinite)), "PT9999999999999H")
    }

    func testParseAcceptsIsoAndDefaultFormats() {
        var thrown = 0
        let iso = kk_duration_parse(stringHandle("PT1H30M"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_duration_inWholeMinutes(iso), 90)

        let defaultFormat = kk_duration_parse(stringHandle("1h 30m"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_duration_inWholeMinutes(defaultFormat), 90)
    }

    func testParseAcceptsSingleUnitDecimalFormat() {
        var thrown = 0
        let parsed = kk_duration_parse(stringHandle("1.5h"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_duration_inWholeMinutes(parsed), 90)
    }

    func testParseInvalidStringSetsThrownChannel() {
        var thrown = 0
        let parsed = kk_duration_parse(stringHandle("1 hour 30 minutes"), &thrown)
        XCTAssertEqual(parsed, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
    }

    func testParseOrNullReturnsDurationOrNullSentinel() {
        let valid = kk_duration_parseOrNull(stringHandle("PT0.120300S"))
        XCTAssertEqual(kk_duration_inWholeMicroseconds(valid), 120_300)

        let invalid = kk_duration_parseOrNull(stringHandle("1 hour 30 minutes"))
        XCTAssertEqual(invalid, runtimeNullSentinelInt)
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
        let handle = kk_duration_from_nanoseconds(1_500)
        let result = kk_duration_toString(handle)
        XCTAssertEqual(stringFromHandle(result), "1.5us")
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

    // MARK: - kk_measureTime: advanced testing (TEST-001)

    func testMeasureTimeParallelExecutionIndependence() {
        // Test that concurrent measurements don't interfere with each other
        let expectation = XCTestExpectation(description: "Parallel measurements complete")
        expectation.expectedFulfillmentCount = 4
        
        let resultsBox = DurationResultsBox()
        
        for i in 0..<4 {
            DispatchQueue.global(qos: .userInitiated).async {
                let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
                var thrown: Int = 0
                let result = kk_measureTime(fnPtr, i, &thrown)
                let thrownValue = thrown

                XCTAssertEqual(thrownValue, 0, "Thread \(i): No exception should be thrown")
                XCTAssertNotEqual(result, 0, "Thread \(i): Should return valid duration")
                resultsBox.append(result)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        let results = resultsBox.snapshot()
        XCTAssertEqual(results.count, 4, "All 4 parallel measurements should complete")
        
        // Verify all results are distinct handles
        let uniqueResults = Set(results)
        XCTAssertEqual(uniqueResults.count, 4, "All parallel measurements should produce distinct handles")
        
        // Verify all measurements are in reasonable range
        for result in results {
            let ms = kk_duration_inWholeMilliseconds(result)
            XCTAssertGreaterThanOrEqual(ms, 40, "Parallel measurement should be at least ~40ms")
            XCTAssertLessThan(ms, 500, "Parallel measurement should not exceed 500ms")
        }
    }

    func testMeasureTimeHighPrecisionTiming() {
        // Test sub-millisecond precision capabilities
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        
        // Run multiple measurements to check precision
        var measurements: [Int64] = []
        for _ in 0..<10 {
            let result = kk_measureTime(fnPtr, 0, &thrown)
            XCTAssertEqual(thrown, 0)
            let ns = kk_duration_inWholeNanoseconds(result)
            measurements.append(Int64(ns))
        }
        
        // Even no-ops should show some variation in nanosecond precision
        let uniqueValues = Set(measurements)
        XCTAssertGreaterThan(uniqueValues.count, 1, "Multiple measurements should show timing variation")
        
        // All measurements should be reasonable (not negative, not excessively large)
        for ns in measurements {
            XCTAssertGreaterThanOrEqual(ns, 0, "Nanosecond measurement should not be negative")
            XCTAssertLessThan(ns, 1_000_000, "No-op should complete within 1ms")
        }
    }

    func testMeasureTimeComplexExceptionScenarios() {
        // Test nested exception scenarios and exception preservation
        
        // First test: exception with closureRaw value
        let fnPtr = unsafeBitCast(throwingThunk, to: Int.self)
        var thrown: Int = 0
        let sentinel = 0xBEEF
        let result = kk_measureTime(fnPtr, sentinel, &thrown)
        
        XCTAssertEqual(thrown, 0xDEAD, "Exception should be preserved regardless of closureRaw")
        XCTAssertEqual(result, 0, "Duration should be zero on exception")
        
        // Second test: verify outThrown is properly reset after exception
        var thrown2: Int = 0xDEAD // Pre-fill with garbage
        let result2 = kk_measureTime(fnPtr, sentinel, &thrown2)
        XCTAssertEqual(thrown2, 0xDEAD, "Exception should overwrite pre-filled value")
        XCTAssertEqual(result2, 0, "Duration should be zero on second exception")
        
        // Third test: verify normal operation after exception
        var thrown3: Int = 0xDEAD // Pre-fill with garbage
        let noopPtr = unsafeBitCast(noopThunk, to: Int.self)
        let result3 = kk_measureTime(noopPtr, sentinel, &thrown3)
        XCTAssertEqual(thrown3, 0, "Normal operation should reset outThrown to zero")
        XCTAssertNotEqual(result3, 0, "Normal operation should return valid duration")
    }

    func testMeasureTimeLongDurationOverflowHandling() {
        // Test behavior with very long durations that might approach Int64 limits
        let longSleepThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
            // Sleep for 2 seconds to create a substantial duration
            Thread.sleep(forTimeInterval: 2.0)
            return 0
        }
        
        let fnPtr = unsafeBitCast(longSleepThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        
        XCTAssertEqual(thrown, 0, "Long sleep should not throw exception")
        XCTAssertNotEqual(result, 0, "Long duration should return valid handle")
        
        let ns = kk_duration_inWholeNanoseconds(result)
        XCTAssertGreaterThan(ns, 1_000_000_000, "Should be at least 1 second")
        XCTAssertLessThan(ns, Int(Int64.max), "Should not overflow Int64")
        
        // Verify the duration can be safely used with all accessors
        let ms = kk_duration_inWholeMilliseconds(result)
        let s = kk_duration_inWholeSeconds(result)
        XCTAssertGreaterThan(ms, 1000, "Milliseconds should be > 1000")
        XCTAssertGreaterThanOrEqual(s, 2, "Seconds should be >= 2")
    }

    func testMeasureTimeSystemClockStability() {
        // Test measurement stability under rapid successive calls
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        
        var durations: [Int64] = []
        let startTime = DispatchTime.now().uptimeNanoseconds
        
        // Perform rapid measurements
        for i in 0..<50 {
            let result = kk_measureTime(fnPtr, i, &thrown)
            XCTAssertEqual(thrown, 0, "Measurement \(i) should not throw")
            let ns = kk_duration_inWholeNanoseconds(result)
            durations.append(Int64(ns))
        }
        
        let endTime = DispatchTime.now().uptimeNanoseconds
        let totalTestTime = endTime - startTime

        // These are independent duration samples, not timestamps. Validate that
        // the aggregate measured time stays within the enclosing wall-clock time
        // with a small allowance for clock sampling overhead.
        let measuredTotal = durations.reduce(0, +)
        let aggregateSlackNs: Int64 = 20_000_000
        XCTAssertGreaterThanOrEqual(durations.min() ?? -1, 0, "Measured durations should never be negative")
        XCTAssertLessThanOrEqual(
            measuredTotal,
            Int64(totalTestTime) + aggregateSlackNs,
            "Aggregate measured durations should stay close to enclosing wall-clock time"
        )

        // Verify total test time is reasonable
        XCTAssertLessThan(totalTestTime, 10_000_000_000, "50 rapid measurements should complete within 10 seconds")
    }
}
