import Dispatch
import Foundation
@testable import Runtime
import XCTest

private final class RuntimeDatabaseAcquireResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class RuntimeDatabaseTests: IsolatedRuntimeXCTestCase {
    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }

    func testPoolCreateAcquireReleaseAndReuseConnection() throws {
        var thrown = 0
        let pool = kk_db_pool_new(2, 100, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_db_pool_max_connections(pool), 2)
        XCTAssertEqual(kk_db_pool_timeout_millis(pool), 100)

        let first = kk_db_pool_acquire(pool, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_db_pool_active_count(pool), 1)
        XCTAssertEqual(kk_db_pool_idle_count(pool), 0)
        XCTAssertEqual(kk_db_pool_total_count(pool), 1)
        XCTAssertEqual(kk_db_connection_in_use(first), 1)
        XCTAssertEqual(kk_db_connection_is_open(first), 1)

        XCTAssertEqual(kk_db_pool_release(pool, first, &thrown), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_db_pool_active_count(pool), 0)
        XCTAssertEqual(kk_db_pool_idle_count(pool), 1)
        XCTAssertEqual(kk_db_connection_in_use(first), 0)

        let second = kk_db_pool_acquire(pool, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(second, first)
        XCTAssertEqual(kk_db_connection_id(second), 1)
        XCTAssertEqual(kk_db_pool_active_count(pool), 1)
        XCTAssertEqual(kk_db_pool_idle_count(pool), 0)
    }

    func testPoolHonorsMaxConnectionsAndTracksWaitingCount() throws {
        var thrown = 0
        let pool = kk_db_pool_new(1, 500, &thrown)
        XCTAssertEqual(thrown, 0)

        let first = kk_db_pool_acquire(pool, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_db_pool_total_count(pool), 1)

        let started = expectation(description: "waiting acquire started")
        let finished = expectation(description: "waiting acquire finished")
        let queue = DispatchQueue(label: "runtime.database.tests", qos: .userInitiated)
        let resultBox = RuntimeDatabaseAcquireResultBox()

        queue.async {
            started.fulfill()
            var innerThrown = 0
            resultBox.set(kk_db_pool_acquire(pool, &innerThrown))
            XCTAssertEqual(innerThrown, 0)
            finished.fulfill()
        }

        wait(for: [started], timeout: 1.0)
        let waitingObserved = waitForCondition(timeout: 1.0) {
            kk_db_pool_waiting_count(pool) == 1
        }
        XCTAssertTrue(waitingObserved, "Expected one waiter while pool is exhausted")

        XCTAssertEqual(kk_db_pool_release(pool, first, &thrown), 1)
        XCTAssertEqual(thrown, 0)

        wait(for: [finished], timeout: 1.0)
        XCTAssertEqual(resultBox.get(), first)
        XCTAssertEqual(kk_db_pool_waiting_count(pool), 0)
        XCTAssertEqual(kk_db_pool_active_count(pool), 1)
    }

    func testPoolAcquireTimeoutReturnsThrowable() throws {
        var thrown = 0
        let pool = kk_db_pool_new(1, 20, &thrown)
        XCTAssertEqual(thrown, 0)

        let first = kk_db_pool_acquire(pool, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(first, 0)

        let second = kk_db_pool_acquire(pool, &thrown)
        XCTAssertEqual(second, 0)
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertTrue(box.message.contains("Timed out acquiring database connection"))
        XCTAssertEqual(kk_db_pool_waiting_count(pool), 0)
        XCTAssertEqual(kk_db_pool_active_count(pool), 1)
    }

    func testPoolRejectsInvalidReleaseAndMismatchedPool() throws {
        var thrown = 0
        let firstPool = kk_db_pool_new(1, 100, &thrown)
        XCTAssertEqual(thrown, 0)
        let secondPool = kk_db_pool_new(1, 100, &thrown)
        XCTAssertEqual(thrown, 0)

        let connection = kk_db_pool_acquire(firstPool, &thrown)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_db_pool_release(secondPool, connection, &thrown), 0)
        XCTAssertTrue(try XCTUnwrap(throwableBox(from: thrown)).message.contains("does not belong to this pool"))

        thrown = 0
        XCTAssertEqual(kk_db_pool_release(firstPool, connection, &thrown), 1)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_db_pool_release(firstPool, connection, &thrown), 0)
        XCTAssertTrue(try XCTUnwrap(throwableBox(from: thrown)).message.contains("not currently checked out"))
    }

    private func waitForCondition(timeout: TimeInterval, pollInterval: TimeInterval = 0.01, _ body: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if body() {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return body()
    }
}
