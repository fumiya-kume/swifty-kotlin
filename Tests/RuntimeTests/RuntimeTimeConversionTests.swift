@testable import Runtime
import XCTest

final class RuntimeTimeConversionTests: XCTestCase {
    func testInstantJavaInstantRoundTripPreservesComponents() {
        let instant = kk_instant_from_epoch_millis(1_234)
        let javaInstant = kk_instant_to_java_instant(instant)
        let roundTrip = kk_java_instant_to_kotlin_instant(javaInstant)

        XCTAssertEqual(kk_instant_epoch_seconds(roundTrip), 1)
        XCTAssertEqual(kk_instant_nano_of_second(roundTrip), 234_000_000)
    }

    func testDurationJavaDurationRoundTripPreservesNanoseconds() {
        let duration = kk_duration_from_nanoseconds(1_234_567_890)
        let javaDuration = kk_duration_to_java_duration(duration)
        let roundTrip = kk_java_duration_to_kotlin_duration(javaDuration)

        XCTAssertEqual(kk_duration_inWholeNanoseconds(roundTrip), 1_234_567_890)
    }

    func testNegativeDurationJavaDurationRoundTripPreservesNanoseconds() {
        let duration = kk_duration_from_nanoseconds(-1_500_000_001)
        let javaDuration = kk_duration_to_java_duration(duration)
        let roundTrip = kk_java_duration_to_kotlin_duration(javaDuration)

        XCTAssertEqual(kk_duration_inWholeNanoseconds(roundTrip), -1_500_000_001)
    }

    func testInstantJSDateRoundTripPreservesFractionalMilliseconds() {
        let instant = registerRuntimeObject(RuntimeInstantBox(epochSeconds: 12, nanoOfSecond: 345_678_900))
        let jsDate = kk_instant_to_js_date(instant)
        let roundTrip = kk_js_date_to_kotlin_instant(jsDate)

        XCTAssertEqual(kk_instant_epoch_seconds(roundTrip), 12)
        XCTAssertEqual(kk_instant_nano_of_second(roundTrip), 345_678_900)
    }
}
