@testable import Runtime
import XCTest

final class RuntimeInstantTests: IsolatedRuntimeXCTestCase {
    func testInstantFromEpochMillisecondsUsesValueEquality() {
        let first = kk_instant_from_epoch_millis(0)
        let second = kk_instant_from_epoch_millis(0)

        XCTAssertEqual(kk_instant_compare(first, second), 0)
        XCTAssertEqual(kk_structural_eq(first, second), 1)
        XCTAssertEqual(kk_structural_ne(first, second), 0)
        XCTAssertEqual(kk_any_hashCode(first, 0), kk_any_hashCode(second, 0))
    }

    func testInstantElapsedProducesPositiveDuration() {
        let epoch = kk_instant_from_epoch_millis(0)
        let elapsed = kk_instant_elapsed(epoch)

        XCTAssertGreaterThan(kk_duration_inWholeSeconds(elapsed), 0)
        XCTAssertGreaterThan(kk_duration_inWholeNanoseconds(elapsed), 0)
    }

    func testInstantUntilMatchesExpectedDuration() {
        let start = kk_instant_from_epoch_millis(1_000)
        let end = kk_instant_from_epoch_millis(3_000)

        let duration = kk_instant_until(start, end)

        XCTAssertEqual(kk_duration_inWholeSeconds(duration), 2)
        XCTAssertEqual(kk_duration_inWholeMilliseconds(duration), 2_000)
    }
}
