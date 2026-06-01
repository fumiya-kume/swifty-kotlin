@testable import Runtime
import XCTest

final class RuntimeInstantTests: XCTestCase {
    func testInstantFromEpochMillisecondsUsesValueEquality() {
        let first = kk_instant_from_epoch_millis(0)
        let second = kk_instant_from_epoch_millis(0)

        XCTAssertEqual(kk_instant_compare(first, second), 0)
        XCTAssertEqual(kk_structural_eq(first, second), 1)
        XCTAssertEqual(kk_structural_ne(first, second), 0)
        XCTAssertEqual(kk_any_hashCode(first, 0), kk_any_hashCode(second, 0))
    }

    func testInstantFromEpochSecondsPreservesAndNormalizesNanoseconds() {
        let instant = kk_instant_from_epoch_seconds(1_700_000_000, 123_456_789)

        XCTAssertEqual(kk_instant_epoch_seconds(instant), 1_700_000_000)
        XCTAssertEqual(kk_instant_nano_of_second(instant), 123_456_789)
        XCTAssertEqual(kk_instant_to_epoch_millis(instant), 1_700_000_000_123)

        let adjusted = kk_instant_from_epoch_seconds(1, 1_500_000_000)
        XCTAssertEqual(kk_instant_epoch_seconds(adjusted), 2)
        XCTAssertEqual(kk_instant_nano_of_second(adjusted), 500_000_000)
        XCTAssertEqual(kk_instant_to_epoch_millis(adjusted), 2_500)
    }

    func testInstantEpochMillisecondsForBeforeEpochValues() {
        let beforeEpoch = kk_instant_from_epoch_seconds(-2, 500_000_000)

        XCTAssertEqual(kk_instant_epoch_seconds(beforeEpoch), -2)
        XCTAssertEqual(kk_instant_nano_of_second(beforeEpoch), 500_000_000)
        XCTAssertEqual(kk_instant_to_epoch_millis(beforeEpoch), -1_500)
    }

    func testInstantFoundationDateBridgeRoundTripsEpochMilliseconds() {
        let instant = kk_instant_from_epoch_seconds(-1, 250_000_000)
        let foundationDate = kk_instant_to_foundation_date(instant)

        XCTAssertEqual(kk_js_date_epoch_millis(foundationDate), -750)

        let roundTripped = kk_foundation_date_to_kotlin_instant(foundationDate)
        XCTAssertEqual(kk_instant_compare(roundTripped, instant), 0)
        XCTAssertEqual(kk_instant_to_epoch_millis(roundTripped), -750)
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

    func testInstantDistantPropertiesUseKotlinThresholds() {
        let ordinary = kk_instant_from_epoch_millis(0)
        XCTAssertEqual(kk_instant_is_distant_past(ordinary), 0)
        XCTAssertEqual(kk_instant_is_distant_future(ordinary), 0)

        let distantPast = kk_instant_from_epoch_millis(-3_217_862_419_200_001)
        let justAfterDistantPast = kk_instant_from_epoch_millis(-3_217_862_419_200_000)
        XCTAssertEqual(kk_instant_is_distant_past(distantPast), 1)
        XCTAssertEqual(kk_instant_is_distant_past(justAfterDistantPast), 0)

        let distantFuture = kk_instant_from_epoch_millis(3_093_527_980_800_000)
        let justBeforeDistantFuture = kk_instant_from_epoch_millis(3_093_527_980_799_999)
        XCTAssertEqual(kk_instant_is_distant_future(distantFuture), 1)
        XCTAssertEqual(kk_instant_is_distant_future(justBeforeDistantFuture), 0)
    }
}
