@testable import Runtime
import XCTest

final class RuntimeSystemTests: XCTestCase {
    func testProcessStartNanosIsNotInFutureAndStableAcrossCalls() {
        let first = kk_system_process_start_nanos()
        let now = kk_system_nanoTime()
        let second = kk_system_process_start_nanos()

        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThanOrEqual(first, now, "processStartNanos should not be later than nanoTime.")
        XCTAssertEqual(first, second, "processStartNanos should remain stable across repeated calls.")
    }
}
