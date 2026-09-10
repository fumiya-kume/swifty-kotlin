import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeExperimentalTimeTests {
    @Test func monotonicMarkElapsedNowIsNonNegative() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let elapsed = timeMarkElapsedNow(mark)
        #expect(kk_duration_inWholeNanoseconds(elapsed) >= 0)
    }

    @Test func shiftedMarkReportsFutureAndPast() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let future = timeMarkPlusDuration(mark, durationFromMilliseconds(50))
        let past = timeMarkMinusDuration(mark, durationFromMilliseconds(50))

        #expect(timeMarkHasNotPassedNow(future) == 1)
        #expect(timeMarkHasPassedNow(future) == 0)
        #expect(timeMarkHasPassedNow(past) == 1)
        #expect(timeMarkHasNotPassedNow(past) == 0)
    }

    @Test func comparableTimeMarkDifferenceAndOrdering() async throws {
        let first = kk_time_source_monotonic_mark_now(0)
        try await Task.sleep(for: .microseconds(1))
        let second = kk_time_source_monotonic_mark_now(0)

        let diff = timeMarkMinusMark(second, first)
        #expect(kk_duration_inWholeNanoseconds(diff) >= 0)
        #expect(timeMarkCompare(second, first) > 0)
        #expect(timeMarkCompare(first, second) < 0)
    }

    @Test func timeSourceAsClockReturnsOriginBasedInstants() {
        let origin = kk_instant_from_epoch_millis(2_000)
        let clock = kk_time_source_as_clock(0, origin)

        let first = kk_clock_now(clock)
        #expect(kk_instant_compare(first, origin) >= 0)
        #expect(durationInWholeMilliseconds(kk_instant_until(origin, first)) < 500)

        Thread.sleep(forTimeInterval: 0.002)
        let second = kk_clock_now(clock)
        #expect(kk_instant_compare(second, first) >= 0)
    }

    @Test func clockNowBridgeUsesSystemFallbackForUnknownReceiver() {
        let now = kk_clock_now(0)

        #expect(now != 0)
        #expect(kk_instant_epoch_seconds(now) > 1_500_000_000)
    }
}
