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

    func testStatementExecuteUpdateAndQueryRoundTrip() {
        var thrown = 0
        let connection = kk_jdbc_driver_manager_getConnection(runtimeString("jdbc:sqlite::memory:"), &thrown)
        XCTAssertEqual(thrown, 0)

        let statement = kk_jdbc_connection_createStatement(connection, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(
            kk_jdbc_statement_executeUpdate(statement, runtimeString("create table users(id integer, name text)"), &thrown),
            0
        )
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(
            kk_jdbc_statement_executeUpdate(statement, runtimeString("insert into users(id, name) values (1, 'Ada')"), &thrown),
            1
        )
        XCTAssertEqual(thrown, 0)

        let resultSet = kk_jdbc_statement_executeQuery(statement, runtimeString("select id, name from users"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_bool(kk_jdbc_result_set_next(resultSet, &thrown)), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_jdbc_result_set_getInt(resultSet, 1, &thrown), 1)
        XCTAssertEqual(stringValue(kk_jdbc_result_set_getString(resultSet, 2, &thrown)), "Ada")
        XCTAssertEqual(kk_unbox_bool(kk_jdbc_result_set_next(resultSet, &thrown)), 0)

        XCTAssertEqual(kk_jdbc_result_set_close(resultSet, &thrown), 0)
        XCTAssertEqual(kk_jdbc_statement_close(statement, &thrown), 0)
        XCTAssertEqual(kk_jdbc_connection_close(connection, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testPreparedStatementBindsAndColumnLabelLookup() {
        var thrown = 0
        let connection = kk_jdbc_driver_manager_getConnection(runtimeString("jdbc:sqlite::memory:"), &thrown)
        XCTAssertEqual(thrown, 0)
        let statement = kk_jdbc_connection_createStatement(connection, &thrown)
        XCTAssertEqual(
            kk_jdbc_statement_executeUpdate(statement, runtimeString("create table items(id integer, title text)"), &thrown),
            0
        )
        XCTAssertEqual(thrown, 0)

        let prepared = kk_jdbc_connection_prepareStatement(
            connection,
            runtimeString("insert into items(id, title) values (?, ?)"),
            &thrown
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_jdbc_prepared_statement_setInt(prepared, 1, 7, &thrown), 0)
        XCTAssertEqual(kk_jdbc_prepared_statement_setString(prepared, 2, runtimeString("Notebook"), &thrown), 0)
        XCTAssertEqual(kk_jdbc_prepared_statement_executeUpdate(prepared, &thrown), 1)
        XCTAssertEqual(thrown, 0)

        let query = kk_jdbc_statement_executeQuery(statement, runtimeString("select id, title from items"), &thrown)
        XCTAssertEqual(kk_unbox_bool(kk_jdbc_result_set_next(query, &thrown)), 1)
        XCTAssertEqual(kk_jdbc_result_set_getIntByLabel(query, runtimeString("id"), &thrown), 7)
        XCTAssertEqual(stringValue(kk_jdbc_result_set_getStringByLabel(query, runtimeString("title"), &thrown)), "Notebook")

        XCTAssertEqual(kk_jdbc_result_set_close(query, &thrown), 0)
        XCTAssertEqual(kk_jdbc_prepared_statement_close(prepared, &thrown), 0)
        XCTAssertEqual(kk_jdbc_statement_close(statement, &thrown), 0)
        XCTAssertEqual(kk_jdbc_connection_close(connection, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testUnsupportedURLProducesThrowable() {
        var thrown = 0
        let connection = kk_jdbc_driver_manager_getConnection(runtimeString("jdbc:mysql://localhost/test"), &thrown)
        XCTAssertEqual(connection, 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertTrue((extractString(from: UnsafeMutableRawPointer(bitPattern: kk_throwable_message(thrown))) ?? "").contains("unsupported JDBC URL"))
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
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
