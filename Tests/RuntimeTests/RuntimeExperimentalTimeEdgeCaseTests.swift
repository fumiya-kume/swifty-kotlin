import Dispatch
@testable import Runtime
import XCTest

// MARK: - kotlin.time experimental API edge case coverage (STDLIB-TIME-EXP-001)
//
// Covers: TimeSource.Monotonic, TimeMark, markNow(), elapsedNow(), plus/minus Duration,
// hasPassedNow/hasNotPassedNow, ComparableTimeMark (compare/minus-mark), Clock interface
// stubs (kk_time_source_mark_now), POSIX-backed monotonic clock variants, duration
// overflow/saturation, toString on elapsed duration, and monotonicity invariants.

final class RuntimeExperimentalTimeEdgeCaseTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Helpers

    private func stringFromHandle(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    // MARK: - kk_time_source_mark_now (generic Clock interface stub)

    /// kk_time_source_mark_now is the generic Clock.markNow() entry point.
    /// It must return a non-zero handle backed by a valid TimeMark.
    func testGenericTimeSourceMarkNowReturnsValidHandle() {
        let mark = kk_time_source_mark_now(0)
        XCTAssertNotEqual(mark, 0, "kk_time_source_mark_now must return a non-zero handle")
    }

    /// The generic entry point and the Monotonic-specific one must agree on source semantics:
    /// both are backed by DispatchTime.now().uptimeNanoseconds, so two consecutive marks
    /// from either entry point should be non-decreasing.
    func testGenericAndMonotonicMarkNowAreNonDecreasing() {
        let generic = kk_time_source_mark_now(0)
        let monotonic = kk_time_source_monotonic_mark_now(0)
        // elapsed on generic >= 0 means monotonic clock didn't go back between the two calls.
        let elapsed = kk_time_mark_elapsed_now(generic)
        XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(elapsed), 0,
            "Elapsed time from generic Clock.markNow() must be >= 0")
        // monotonic mark created after generic should compare >= generic
        let cmp = kk_time_mark_compare(monotonic, generic)
        XCTAssertGreaterThanOrEqual(cmp, 0,
            "Monotonic mark taken after generic mark must not be earlier")
    }

    // MARK: - kk_clock_monotonic_mark_now (POSIX CLOCK_MONOTONIC variant)

    func testPosixClockMonotonicMarkNowReturnsValidHandle() {
        let mark = kk_clock_monotonic_mark_now()
        XCTAssertNotEqual(mark, 0, "kk_clock_monotonic_mark_now must return a non-zero handle")
    }

    /// kk_clock_monotonic_mark_now is backed by POSIX CLOCK_MONOTONIC, which does NOT share
    /// the same epoch as DispatchTime.now().uptimeNanoseconds used by kk_time_mark_elapsed_now.
    /// So we cannot call kk_time_mark_elapsed_now on a POSIX mark and expect a meaningful result.
    /// Instead we verify the mark handle itself is valid (non-zero).
    func testPosixClockMonotonicMarkNowReturnsNonZeroHandle() {
        let mark = kk_clock_monotonic_mark_now()
        XCTAssertNotEqual(mark, 0,
            "POSIX monotonic mark must yield a non-zero handle")
    }

    func testPosixClockMonotonicMarkNowIsNonDecreasingAcrossReads() {
        // 20 consecutive POSIX-clock marks must never go backwards.
        var prev = kk_clock_monotonic_mark_now()
        for i in 1...20 {
            let curr = kk_clock_monotonic_mark_now()
            let cmp = kk_time_mark_compare(curr, prev)
            XCTAssertGreaterThanOrEqual(cmp, 0,
                "POSIX monotonic clock went backwards at iteration \(i)")
            prev = curr
        }
    }

    // MARK: - kk_clock_gettime_monotonic_ns (raw nanoseconds)

    func testClockGettimeMonotonicNsIsPositive() {
        let ns = kk_clock_gettime_monotonic_ns()
        XCTAssertGreaterThan(ns, 0, "POSIX CLOCK_MONOTONIC ns value must be positive")
    }

    func testClockGettimeMonotonicNsIsNonDecreasing() {
        let t1 = kk_clock_gettime_monotonic_ns()
        let t2 = kk_clock_gettime_monotonic_ns()
        XCTAssertGreaterThanOrEqual(t2, t1,
            "kk_clock_gettime_monotonic_ns must be non-decreasing (monotonic)")
    }

    // MARK: - elapsedNow() always non-negative for present/past marks

    func testElapsedNowOnPastMarkIsNonNegative() {
        // A mark taken 100ms in the "past" (shifted backward) should have elapsed >= 100ms.
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = kk_time_mark_minus_duration(mark, kk_duration_from_milliseconds(100))
        let elapsed = kk_time_mark_elapsed_now(pastMark)
        let elapsedMs = kk_duration_inWholeMilliseconds(elapsed)
        XCTAssertGreaterThanOrEqual(elapsedMs, 100,
            "Elapsed for a mark set 100ms in the past should be >= 100ms")
    }

    func testElapsedNowOnFutureMarkIsNegative() {
        // A mark 10 seconds in the future has negative elapsed (not yet reached).
        let mark = kk_time_source_monotonic_mark_now(0)
        let futureMark = kk_time_mark_plus_duration(mark, kk_duration_from_seconds(10))
        let elapsed = kk_time_mark_elapsed_now(futureMark)
        XCTAssertLessThan(kk_duration_inWholeNanoseconds(elapsed), 0,
            "Elapsed for a far-future mark should be negative")
    }

    // MARK: - Monotonic source: consecutive markNow() never decreases

    func testMonotonicSourceNeverDecreases() {
        var prev = kk_time_source_monotonic_mark_now(0)
        for i in 1...50 {
            let curr = kk_time_source_monotonic_mark_now(0)
            let diff = kk_time_mark_minus_mark(curr, prev)  // curr - prev
            XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(diff), 0,
                "Monotonic source went backwards at iteration \(i)")
            prev = curr
        }
    }

    // MARK: - Duration arithmetic on TimeMark: consistency

    /// (mark + d).elapsedNow() should be approximately (mark.elapsedNow() - d).
    /// We verify the sign relationship: a mark shifted +1 second should have elapsed
    /// roughly 1 second less than the original mark.
    func testPlusOnSecondReducesElapsedByThatDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift 1 second forward
        let shiftedMark = kk_time_mark_plus_duration(mark, kk_duration_from_seconds(1))
        // shiftedMark.elapsedNow() should be roughly mark.elapsedNow() - 1s
        // Since the mark is ~1s in the future, elapsedNow should be negative (future).
        // With only nanoseconds elapsed since markNow(), that means approximately -1s.
        let elapsedShifted = kk_time_mark_elapsed_now(shiftedMark)
        let elapsedOriginal = kk_time_mark_elapsed_now(mark)
        let elapsedShiftedNs = kk_duration_inWholeNanoseconds(elapsedShifted)
        let elapsedOriginalNs = kk_duration_inWholeNanoseconds(elapsedOriginal)
        // elapsedShiftedNs ≈ elapsedOriginalNs - 1_000_000_000
        // Allow 50ms slack for test execution time between the two elapsedNow() calls.
        let slackNs = 50_000_000
        let difference = elapsedOriginalNs - elapsedShiftedNs
        XCTAssertGreaterThanOrEqual(difference, 1_000_000_000 - slackNs,
            "elapsed(original) - elapsed(original+1s) should be approximately 1s")
        XCTAssertLessThanOrEqual(difference, 1_000_000_000 + slackNs,
            "elapsed(original) - elapsed(original+1s) should be approximately 1s (upper bound)")
    }

    func testMinusOnSecondIncreasesElapsedByThatDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift 1 second backward → already 1 second in the past
        let pastMark = kk_time_mark_minus_duration(mark, kk_duration_from_seconds(1))
        let elapsedPast = kk_time_mark_elapsed_now(pastMark)
        let elapsedOriginal = kk_time_mark_elapsed_now(mark)
        let elapsedPastNs = kk_duration_inWholeNanoseconds(elapsedPast)
        let elapsedOriginalNs = kk_duration_inWholeNanoseconds(elapsedOriginal)
        // elapsedPastNs ≈ elapsedOriginalNs + 1_000_000_000
        let slackNs = 50_000_000
        let difference = elapsedPastNs - elapsedOriginalNs
        XCTAssertGreaterThanOrEqual(difference, 1_000_000_000 - slackNs,
            "elapsed(original-1s) - elapsed(original) should be approximately 1s")
        XCTAssertLessThanOrEqual(difference, 1_000_000_000 + slackNs,
            "elapsed(original-1s) - elapsed(original) should be approximately 1s (upper bound)")
    }

    // MARK: - hasPassedNow / hasNotPassedNow transitions

    /// A mark set 1 second in the past must have already passed.
    func testPastMarkHasPassedNow() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = kk_time_mark_minus_duration(mark, kk_duration_from_seconds(1))
        XCTAssertEqual(kk_time_mark_has_passed_now(pastMark), 1,
            "A mark 1s in the past must report hasPassedNow() == true")
        XCTAssertEqual(kk_time_mark_has_not_passed_now(pastMark), 0,
            "A mark 1s in the past must report hasNotPassedNow() == false")
    }

    /// A mark set 10 seconds in the future must NOT have passed yet.
    func testFutureMarkHasNotPassedNow() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let futureMark = kk_time_mark_plus_duration(mark, kk_duration_from_seconds(10))
        XCTAssertEqual(kk_time_mark_has_not_passed_now(futureMark), 1,
            "A mark 10s in the future must report hasNotPassedNow() == true")
        XCTAssertEqual(kk_time_mark_has_passed_now(futureMark), 0,
            "A mark 10s in the future must report hasPassedNow() == false")
    }

    /// hasPassedNow and hasNotPassedNow must be mutually exclusive for any mark.
    func testHasPassedAndHasNotPassedAreMutuallyExclusive() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = kk_time_mark_minus_duration(mark, kk_duration_from_milliseconds(100))
        let futureMark = kk_time_mark_plus_duration(mark, kk_duration_from_seconds(10))
        // past mark
        XCTAssertNotEqual(kk_time_mark_has_passed_now(pastMark), kk_time_mark_has_not_passed_now(pastMark),
            "hasPassedNow and hasNotPassedNow must differ for past mark")
        // future mark
        XCTAssertNotEqual(kk_time_mark_has_passed_now(futureMark), kk_time_mark_has_not_passed_now(futureMark),
            "hasPassedNow and hasNotPassedNow must differ for future mark")
    }

    // MARK: - ComparableTimeMark: compare

    func testCompareMarkToSelfIsZero() {
        let mark = kk_time_source_monotonic_mark_now(0)
        XCTAssertEqual(kk_time_mark_compare(mark, mark), 0,
            "A TimeMark compared to itself must return 0")
    }

    func testCompareEarlierMarkIsNegative() {
        // earlier < later → compare(earlier, later) < 0
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = kk_time_mark_plus_duration(earlier, kk_duration_from_milliseconds(100))
        XCTAssertLessThan(kk_time_mark_compare(earlier, later), 0,
            "compare(earlier, later) should be negative")
    }

    func testCompareLaterMarkIsPositive() {
        // later > earlier → compare(later, earlier) > 0
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = kk_time_mark_plus_duration(earlier, kk_duration_from_milliseconds(100))
        XCTAssertGreaterThan(kk_time_mark_compare(later, earlier), 0,
            "compare(later, earlier) should be positive")
    }

    func testCompareAntisymmetry() {
        let a = kk_time_source_monotonic_mark_now(0)
        let b = kk_time_mark_plus_duration(a, kk_duration_from_milliseconds(50))
        let ab = kk_time_mark_compare(a, b)
        let ba = kk_time_mark_compare(b, a)
        XCTAssertTrue((ab < 0 && ba > 0) || (ab > 0 && ba < 0) || (ab == 0 && ba == 0),
            "compare must be antisymmetric: sign(compare(a,b)) == -sign(compare(b,a))")
    }

    // MARK: - ComparableTimeMark: minus-mark (Duration subtraction)

    func testMinusMarkSameMarkGivesZeroDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let diff = kk_time_mark_minus_mark(mark, mark)
        XCTAssertEqual(kk_duration_inWholeNanoseconds(diff), 0,
            "mark - mark must equal zero duration")
    }

    func testMinusMarkLaterMinusEarlierIsPositive() {
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = kk_time_mark_plus_duration(earlier, kk_duration_from_milliseconds(200))
        let diff = kk_time_mark_minus_mark(later, earlier)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(diff), 200,
            "later - earlier should yield the exact shifted duration")
    }

    func testMinusMarkEarlierMinusLaterIsNegative() {
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = kk_time_mark_plus_duration(earlier, kk_duration_from_milliseconds(300))
        let diff = kk_time_mark_minus_mark(earlier, later)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(diff), -300,
            "earlier - later should yield negative duration")
    }

    // MARK: - Duration overflow / saturation in TimeMark arithmetic

    /// Adding Duration.INFINITE (represented as Int64.max nanoseconds) should saturate,
    /// not crash or wrap around.
    func testPlusDurationSaturatesAtInt64Max() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let infiniteDuration = kk_duration_from_nanoseconds(Int(Int64.max))
        let saturatedMark = kk_time_mark_plus_duration(mark, infiniteDuration)
        // The result must be a valid handle (non-zero).
        XCTAssertNotEqual(saturatedMark, 0,
            "Saturated TimeMark from + Duration.INFINITE must still yield a valid handle")
        // elapsedNow on a mark saturated at Int64.max should be a very large negative number
        // or very small positive (depends on system uptime vs Int64.max). Mainly: no crash.
        let elapsed = kk_time_mark_elapsed_now(saturatedMark)
        _ = kk_duration_inWholeNanoseconds(elapsed)  // must not crash
    }

    /// Subtracting Duration.INFINITE should saturate to Int64.min, not crash.
    func testMinusDurationSaturatesAtInt64Min() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let infiniteDuration = kk_duration_from_nanoseconds(Int(Int64.max))
        let saturatedMark = kk_time_mark_minus_duration(mark, infiniteDuration)
        XCTAssertNotEqual(saturatedMark, 0,
            "Saturated TimeMark from - Duration.INFINITE must yield a valid handle")
        // A mark in the extreme past must have passed.
        XCTAssertEqual(kk_time_mark_has_passed_now(saturatedMark), 1,
            "A mark saturated at Int64.min nanoseconds must report hasPassedNow")
        _ = kk_time_mark_elapsed_now(saturatedMark)  // must not crash
    }

    /// minus-mark on saturated marks: saturation must not produce NaN-like garbage.
    func testMinusMarkOnSaturatedMarksDoesNotCrash() {
        let a = kk_time_source_monotonic_mark_now(0)
        let inf = kk_duration_from_nanoseconds(Int(Int64.max))
        let maxMark = kk_time_mark_plus_duration(a, inf)
        let minMark = kk_time_mark_minus_duration(a, inf)
        let diff = kk_time_mark_minus_mark(maxMark, minMark)
        // diff must be a valid duration handle (non-zero); exact value may saturate.
        XCTAssertNotEqual(diff, 0,
            "minus-mark on saturated TimeMarks must return a valid duration handle")
    }

    // MARK: - TimeMark elapsedNow toString

    /// The Duration returned by elapsedNow() must produce a non-empty string with
    /// a valid time-unit suffix when passed to kk_duration_toString.
    func testElapsedNowDurationToStringHasValidSuffix() {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift the mark 50ms into the past so elapsedNow is clearly positive.
        let pastMark = kk_time_mark_minus_duration(mark, kk_duration_from_milliseconds(50))
        let elapsed = kk_time_mark_elapsed_now(pastMark)
        let strHandle = kk_duration_toString(elapsed)
        guard let str = stringFromHandle(strHandle) else {
            XCTFail("kk_duration_toString returned nil handle for elapsed duration")
            return
        }
        let validSuffixes = ["ns", "us", "ms", "s", "m", "h"]
        let hasValidSuffix = validSuffixes.contains { str.hasSuffix($0) }
        XCTAssertTrue(hasValidSuffix,
            "elapsedNow duration toString should end with a time-unit suffix; got: \(str)")
        XCTAssertFalse(str.isEmpty, "elapsedNow duration toString must not be empty")
    }

    // MARK: - Multiple independent TimeMarks from same source

    func testTwoMarksFromSameSourceCanSubtractToDuration() {
        let first = kk_time_source_monotonic_mark_now(0)
        let second = kk_time_source_monotonic_mark_now(0)
        // Both are from the same (Monotonic) source, so subtraction is valid.
        let diff = kk_time_mark_minus_mark(second, first)
        // second was taken after first → diff >= 0
        XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(diff), 0,
            "second - first from same source must be >= 0")
    }

    func testMultipleConsecutiveMarksAreStrictlyOrdered() {
        // 10 consecutive marks from Monotonic should be non-decreasing.
        var marks: [Int] = []
        for _ in 0..<10 {
            marks.append(kk_time_source_monotonic_mark_now(0))
        }
        for i in 1..<marks.count {
            let cmp = kk_time_mark_compare(marks[i], marks[i - 1])
            XCTAssertGreaterThanOrEqual(cmp, 0,
                "Consecutive Monotonic marks must be non-decreasing at index \(i)")
        }
    }

    // MARK: - kk_time_mark_plus_duration / minus_duration round-trip

    func testPlusMinusRoundTripRestoresOriginalMark() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let d = kk_duration_from_milliseconds(250)
        let shifted = kk_time_mark_plus_duration(mark, d)
        let restored = kk_time_mark_minus_duration(shifted, d)
        // restored == mark (same uptimeNanoseconds)
        XCTAssertEqual(kk_time_mark_compare(restored, mark), 0,
            "mark + d - d must equal the original mark")
    }

    func testMinusPlusRoundTripRestoresOriginalMark() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let d = kk_duration_from_milliseconds(250)
        let shifted = kk_time_mark_minus_duration(mark, d)
        let restored = kk_time_mark_plus_duration(shifted, d)
        XCTAssertEqual(kk_time_mark_compare(restored, mark), 0,
            "mark - d + d must equal the original mark")
    }

    // MARK: - hasPassedNow with zero-offset mark (current moment)

    func testZeroShiftMarkIsConsideredPassed() {
        // A mark with no shift from "now" — by the time we check, it's past.
        let mark = kk_time_source_monotonic_mark_now(0)
        // Even with zero elapsed, elapsedNow >= 0 so it has passed.
        let elapsed = kk_time_mark_elapsed_now(mark)
        XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(elapsed), 0,
            "A mark taken at 'now' must have non-negative elapsed immediately after")
        XCTAssertEqual(kk_time_mark_has_passed_now(mark), 1,
            "A mark taken at the current moment must immediately be considered passed")
    }

    // MARK: - Parallel calls to markNow produce independent handles

    private final class MarkHandlesBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func append(_ v: Int) { lock.lock(); values.append(v); lock.unlock() }
        func snapshot() -> [Int] { lock.lock(); let s = values; lock.unlock(); return s }
    }

    func testParallelMarkNowCallsProduceDistinctHandles() {
        let expectation = XCTestExpectation(description: "Parallel marks complete")
        expectation.expectedFulfillmentCount = 4

        let box = MarkHandlesBox()

        for _ in 0..<4 {
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = kk_time_source_monotonic_mark_now(0)
                box.append(handle)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
        let handles = box.snapshot()
        XCTAssertEqual(handles.count, 4, "All 4 parallel markNow calls should complete")
        // Each mark must produce a distinct allocation handle.
        let unique = Set(handles)
        XCTAssertEqual(unique.count, 4,
            "All parallel markNow calls must produce distinct handles")
    }
}
