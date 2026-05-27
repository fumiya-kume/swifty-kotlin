import Dispatch
import Foundation
@testable import Runtime
import XCTest

final class RuntimeExperimentalTimeTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
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
        let expectation = XCTestExpectation(description: "Time difference measurement")
        
        let first = kk_time_source_monotonic_mark_now(0)
        
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .microseconds(1))
        timer.setEventHandler {
            let second = kk_time_source_monotonic_mark_now(0)
            
            let diff = kk_time_mark_minus_mark(second, first)
            XCTAssertGreaterThanOrEqual(kk_duration_inWholeNanoseconds(diff), 0)
            XCTAssertGreaterThan(kk_time_mark_compare(second, first), 0)
            XCTAssertLessThan(kk_time_mark_compare(first, second), 0)
            
            expectation.fulfill()
        }
        timer.resume()
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTimeSourceAsClockReturnsOriginBasedInstants() {
        let origin = kk_instant_from_epoch_millis(2_000)
        let clock = kk_time_source_as_clock(0, origin)

        let first = kk_clock_now(clock)
        XCTAssertGreaterThanOrEqual(kk_instant_compare(first, origin), 0)
        XCTAssertLessThan(kk_duration_inWholeMilliseconds(kk_instant_until(origin, first)), 500)

        Thread.sleep(forTimeInterval: 0.002)
        let second = kk_clock_now(clock)
        XCTAssertGreaterThanOrEqual(kk_instant_compare(second, first), 0)
    }
}
