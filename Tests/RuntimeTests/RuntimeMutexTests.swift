import Dispatch
@testable import Runtime
import XCTest

private final class RuntimeMutexTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func reset() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private nonisolated(unsafe) var runtimeMutexTestState = RuntimeMutexTestState()
private nonisolated(unsafe) var runtimeMutexWithLockObservedLockedInside = false

@_cdecl("runtime_mutex_with_lock_action")
private func runtime_mutex_with_lock_action(_ envRaw: Int) -> Int {
    runtimeMutexWithLockObservedLockedInside = kk_mutex_isLocked(envRaw) != 0
    return 77
}

final class RuntimeMutexTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        runtimeMutexTestState.reset()
        runtimeMutexWithLockObservedLockedInside = false
    }

    func testMutexBasicLockTryLockUnlockAndWithLock() {
        let handle = kk_mutex_create()
        XCTAssertNotEqual(handle, 0)

        XCTAssertEqual(kk_mutex_isLocked(handle), 0)
        XCTAssertEqual(kk_mutex_lock(handle, 0), 0)
        XCTAssertEqual(kk_mutex_isLocked(handle), 1)
        XCTAssertEqual(kk_mutex_tryLock(handle), 0)
        XCTAssertEqual(kk_mutex_unlock(handle), 0)
        XCTAssertEqual(kk_mutex_isLocked(handle), 0)
        XCTAssertEqual(kk_mutex_tryLock(handle), 1)
        XCTAssertEqual(kk_mutex_isLocked(handle), 1)
        XCTAssertEqual(kk_mutex_unlock(handle), 0)

        let actionFn = unsafeBitCast(
            runtime_mutex_with_lock_action as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let withLockResult = kk_mutex_withLock(handle, actionFn, handle, 0)
        XCTAssertEqual(withLockResult, 77)
        XCTAssertTrue(runtimeMutexWithLockObservedLockedInside)
        XCTAssertEqual(kk_mutex_isLocked(handle), 0)
        XCTAssertEqual(kk_mutex_tryLock(handle), 1)
        XCTAssertEqual(kk_mutex_unlock(handle), 0)
    }

    func testMutexLockWaitersAreServedInFIFOOrder() {
        let handle = kk_mutex_create()
        XCTAssertNotEqual(handle, 0)

        XCTAssertEqual(kk_mutex_lock(handle, 0), 0)
        runtimeMutexTestState.record("main-acquired")
        XCTAssertEqual(kk_mutex_isLocked(handle), 1)

        let waiter1Done = DispatchSemaphore(value: 0)
        let waiter2Done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = kk_mutex_lock(handle, 0)
            runtimeMutexTestState.record("waiter-1-acquired")
            _ = kk_mutex_unlock(handle)
            runtimeMutexTestState.record("waiter-1-released")
            waiter1Done.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)

        DispatchQueue.global().async {
            _ = kk_mutex_lock(handle, 0)
            runtimeMutexTestState.record("waiter-2-acquired")
            _ = kk_mutex_unlock(handle)
            runtimeMutexTestState.record("waiter-2-released")
            waiter2Done.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(kk_mutex_tryLock(handle), 0)

        XCTAssertEqual(kk_mutex_unlock(handle), 0)

        XCTAssertEqual(waiter1Done.wait(timeout: .now() + .seconds(2)), .success)
        XCTAssertEqual(waiter2Done.wait(timeout: .now() + .seconds(2)), .success)

        XCTAssertEqual(kk_mutex_isLocked(handle), 0)
        XCTAssertEqual(kk_mutex_tryLock(handle), 1)
        XCTAssertEqual(kk_mutex_unlock(handle), 0)

        XCTAssertEqual(
            runtimeMutexTestState.snapshot(),
            [
                "main-acquired",
                "waiter-1-acquired",
                "waiter-1-released",
                "waiter-2-acquired",
                "waiter-2-released",
            ]
        )
    }
}
