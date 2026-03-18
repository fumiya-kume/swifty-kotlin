@testable import Runtime
import XCTest

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
}
