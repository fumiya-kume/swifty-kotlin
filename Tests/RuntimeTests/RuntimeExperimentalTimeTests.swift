import Dispatch
@testable import Runtime
import XCTest

final class RuntimeExperimentalTimeTests: IsolatedRuntimeXCTestCase {
    func testMonotonicMarkElapsedNowIsNonNegative() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let elapsed = kk_time_mark_elapsed_now(mark)
        XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(elapsed), 0)
    }

    func testShiftedMarkReportsFutureAndPast() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let future = kk_time_mark_plus_duration(mark, kk_duration_from_milliseconds(50))
        let past = kk_time_mark_minus_duration(mark, kk_duration_from_milliseconds(50))

        XCTAssertEqual(kk_time_mark_has_not_passed_now(future), 1)
        XCTAssertEqual(kk_time_mark_has_passed_now(future), 0)
        XCTAssertEqual(kk_time_mark_has_passed_now(past), 1)
        XCTAssertEqual(kk_time_mark_has_not_passed_now(past), 0)
    }

    func testComparableTimeMarkDifferenceAndOrdering() {
        let first = kk_time_source_monotonic_mark_now(0)
        usleep(1_000)
        let second = kk_time_source_monotonic_mark_now(0)

        let diff = kk_time_mark_minus_mark(second, first)
        XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(diff), 0)
        XCTAssertGreaterThan(kk_time_mark_compare(second, first), 0)
        XCTAssertLessThan(kk_time_mark_compare(first, second), 0)
    }
}
