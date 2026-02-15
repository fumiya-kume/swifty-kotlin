import XCTest
@testable import Runtime

final class RuntimeCoroutineStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testContinuationStoresAndLoadsSpillSlotsAndCompletion() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        XCTAssertEqual(kk_coroutine_state_enter(continuation, 42), 0)

        XCTAssertEqual(kk_coroutine_state_set_spill(continuation, 0, 111), 111)
        XCTAssertEqual(kk_coroutine_state_set_spill(continuation, 2, 333), 333)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 111)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 1), 0)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 2), 333)

        XCTAssertEqual(kk_coroutine_state_set_completion(continuation, 777), 777)
        XCTAssertEqual(kk_coroutine_state_get_completion(continuation), 777)
    }

    func testStateEnterResetsCompletionAndSpillsWhenFunctionChanges() {
        let continuation = kk_coroutine_continuation_new(7)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_state_set_label(continuation, 5)
        _ = kk_coroutine_state_set_spill(continuation, 0, 91)
        _ = kk_coroutine_state_set_completion(continuation, 123)

        XCTAssertEqual(kk_coroutine_state_enter(continuation, 7), 5)
        XCTAssertEqual(kk_coroutine_state_enter(continuation, 8), 0)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 0)
        XCTAssertEqual(kk_coroutine_state_get_completion(continuation), 0)
    }
}
