import Dispatch
import Foundation
@testable import Runtime
import XCTest

private let runtimeTestIsolationSemaphore = DispatchSemaphore(value: 1)

/// Use this base class for runtime tests that mutate global runtime state or
/// observe file-global callback state.
class IsolatedRuntimeXCTestCase: XCTestCase {
    override final func setUp() {
        runtimeTestIsolationSemaphore.wait()
        super.setUp()
        kk_runtime_force_reset()
        resetIsolatedRuntimeTestState()
    }

    override final func tearDown() {
        resetIsolatedRuntimeTestState()
        kk_runtime_force_reset()
        super.tearDown()
        runtimeTestIsolationSemaphore.signal()
    }

    func resetIsolatedRuntimeTestState() {}
}

/// Monotonic counters make launch/cancel assertions immune to stale signals
/// from prior tests while still supporting C-callable global entry points.
final class RuntimeCoroutineTestState: @unchecked Sendable {
    private let condition = NSCondition()
    private var launchEventCount = 0
    private var cancelLoopIterations = 0

    func reset() {
        condition.lock()
        launchEventCount = 0
        cancelLoopIterations = 0
        condition.broadcast()
        condition.unlock()
    }

    func launchEventCountSnapshot() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return launchEventCount
    }

    func recordLaunchEvent() {
        condition.lock()
        launchEventCount += 1
        condition.broadcast()
        condition.unlock()
    }

    func waitForLaunchEvent(after baseline: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while launchEventCount <= baseline {
            if !condition.wait(until: deadline) {
                return launchEventCount > baseline
            }
        }
        return true
    }

    func recordCancelLoopIteration() {
        condition.lock()
        cancelLoopIterations += 1
        condition.broadcast()
        condition.unlock()
    }

    func cancelLoopIterationsSnapshot() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return cancelLoopIterations
    }

    func waitForCancelLoopIterations(atLeast minimum: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while cancelLoopIterations < minimum {
            if !condition.wait(until: deadline) {
                return cancelLoopIterations >= minimum
            }
        }
        return true
    }
}
