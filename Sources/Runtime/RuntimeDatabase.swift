import Foundation
import CSQLite

// MARK: - Database Runtime (STDLIB-DB-140/141)

enum RuntimeDatabaseIsolationLevel: Int {
    case readUncommitted = 1
    case readCommitted = 2
    case repeatableRead = 4
    case serializable = 8
}

final class RuntimeSQLExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.sql.SQLException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.sql.SQLException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "SQLException: \(message)"
    }
}

final class RuntimeSavepointBox {
    let identifier: Int
    let name: String?
    weak var connection: RuntimeConnectionBox?

    init(identifier: Int, name: String?, connection: RuntimeConnectionBox) {
        self.identifier = identifier
        self.name = name
        self.connection = connection
    }
}

final class RuntimeConnectionBox {
    let url: String
    var autoCommit = true
    var closed = false
    var transactionIsolation = RuntimeDatabaseIsolationLevel.readCommitted
    var nextSavepointIdentifier = 1
    var savepoints: [RuntimeSavepointBox] = []

    init(url: String) {
        self.url = url
    }

    func ensureOpen() throws {
        if closed {
            throw DatabaseRuntimeError.sql("Connection is closed")
        }
    }

    func ensureTransactionalContext() throws {
        try ensureOpen()
        if autoCommit {
            throw DatabaseRuntimeError.sql("Operation requires autoCommit=false")
        }
    }

    func createSavepoint(name: String?) throws -> RuntimeSavepointBox {
        try ensureTransactionalContext()
        let savepoint = RuntimeSavepointBox(
            identifier: nextSavepointIdentifier,
            name: name,
            connection: self
        )
        nextSavepointIdentifier += 1
        savepoints.append(savepoint)
        return savepoint
    }

    func rollback(to savepoint: RuntimeSavepointBox?) throws {
        try ensureTransactionalContext()
        guard let savepoint else {
            savepoints.removeAll()
            return
        }
        guard savepoint.connection === self else {
            throw DatabaseRuntimeError.sql("Savepoint does not belong to this connection")
        }
        guard let index = savepoints.firstIndex(where: { $0 === savepoint }) else {
            throw DatabaseRuntimeError.sql("Savepoint is no longer active")
        }
        savepoints = Array(savepoints.prefix(index + 1))
    }

    func release(_ savepoint: RuntimeSavepointBox) throws {
        try ensureTransactionalContext()
        guard savepoint.connection === self else {
            throw DatabaseRuntimeError.sql("Savepoint does not belong to this connection")
        }
        guard let index = savepoints.firstIndex(where: { $0 === savepoint }) else {
            throw DatabaseRuntimeError.sql("Savepoint is no longer active")
        }
        savepoints.remove(at: index)
    }

    func commit() throws {
        try ensureTransactionalContext()
        savepoints.removeAll()
    }

    func rollback() throws {
        try rollback(to: nil)
    }

    func setAutoCommit(_ newValue: Bool) throws {
        try ensureOpen()
        if autoCommit == newValue {
            return
        }
        autoCommit = newValue
        savepoints.removeAll()
    }

    func setIsolation(_ rawValue: Int) throws {
        try ensureOpen()
        guard let level = RuntimeDatabaseIsolationLevel(rawValue: rawValue) else {
            throw DatabaseRuntimeError.sql("Unsupported transaction isolation level: \(rawValue)")
        }
        transactionIsolation = level
    }

    func close() {
        closed = true
        autoCommit = true
        savepoints.removeAll()
    }
}

enum DatabaseRuntimeError: Error {
    case sql(String)
    case invalidHandle(String)
}

private func runtimeAllocateSQLException(message: String) -> Int {
    let throwable = RuntimeSQLExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func databaseThrowable(from error: any Error) -> Int {
    if let dbError = error as? DatabaseRuntimeError {
        switch dbError {
        case let .sql(message):
            return runtimeAllocateSQLException(message: message)
        case let .invalidHandle(message):
            return runtimeAllocateThrowable(message: message)
        }
    }
    return runtimeAllocateThrowable(message: "\(error)")
}

private func runtimeDatabaseMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeConnectionBox(from raw: Int) -> RuntimeConnectionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeConnectionBox.self)
}

private func runtimeSavepointBox(from raw: Int) -> RuntimeSavepointBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSavepointBox.self)
}

private func withDatabaseFailure(
    outThrown: UnsafeMutablePointer<Int>?,
    fallback: Int,
    _ body: () throws -> Int
) -> Int {
    outThrown?.pointee = 0
    do {
        return try body()
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return fallback
    }
}

@_cdecl("kk_driver_manager_getConnection")
public func kk_driver_manager_getConnection(_ urlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: runtimeNullSentinelInt) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: urlRaw),
              let url = extractString(from: ptr),
              !url.isEmpty
        else {
            throw DatabaseRuntimeError.sql("JDBC URL must not be empty")
        }
        return registerRuntimeObject(RuntimeConnectionBox(url: url))
    }
}

@_cdecl("kk_connection_getAutoCommit")
public func kk_connection_getAutoCommit(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeConnectionBox(from: connectionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_getAutoCommit received invalid Connection handle")
    }
    return kk_box_bool(connection.autoCommit ? 1 : 0)
}

@_cdecl("kk_connection_setAutoCommit")
public func kk_connection_setAutoCommit(_ connectionRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_setAutoCommit received invalid Connection handle")
        }
        try connection.setAutoCommit(valueRaw != 0)
        return 0
    }
}

@_cdecl("kk_connection_commit")
public func kk_connection_commit(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_commit received invalid Connection handle")
        }
        try connection.commit()
        return 0
    }
}

@_cdecl("kk_connection_rollback")
public func kk_connection_rollback(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_rollback received invalid Connection handle")
        }
        try connection.rollback()
        return 0
    }
}

@_cdecl("kk_connection_setSavepoint")
public func kk_connection_setSavepoint(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: runtimeNullSentinelInt) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_setSavepoint received invalid Connection handle")
        }
        return registerRuntimeObject(try connection.createSavepoint(name: nil))
    }
}

@_cdecl("kk_connection_setSavepoint_named")
public func kk_connection_setSavepoint_named(_ connectionRaw: Int, _ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: runtimeNullSentinelInt) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_setSavepoint_named received invalid Connection handle")
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
              let name = extractString(from: ptr),
              !name.isEmpty
        else {
            throw DatabaseRuntimeError.sql("Savepoint name must not be empty")
        }
        return registerRuntimeObject(try connection.createSavepoint(name: name))
    }
}

@_cdecl("kk_connection_rollback_to_savepoint")
public func kk_connection_rollback_to_savepoint(_ connectionRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_rollback_to_savepoint received invalid Connection handle")
        }
        guard let savepoint = runtimeSavepointBox(from: savepointRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_rollback_to_savepoint received invalid Savepoint handle")
        }
        try connection.rollback(to: savepoint)
        return 0
    }
}

@_cdecl("kk_connection_releaseSavepoint")
public func kk_connection_releaseSavepoint(_ connectionRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_releaseSavepoint received invalid Connection handle")
        }
        guard let savepoint = runtimeSavepointBox(from: savepointRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_releaseSavepoint received invalid Savepoint handle")
        }
        try connection.release(savepoint)
        return 0
    }
}

@_cdecl("kk_connection_getTransactionIsolation")
public func kk_connection_getTransactionIsolation(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeConnectionBox(from: connectionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_getTransactionIsolation received invalid Connection handle")
    }
    return connection.transactionIsolation.rawValue
}

@_cdecl("kk_connection_setTransactionIsolation")
public func kk_connection_setTransactionIsolation(_ connectionRaw: Int, _ levelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let connection = runtimeConnectionBox(from: connectionRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_connection_setTransactionIsolation received invalid Connection handle")
        }
        try connection.setIsolation(levelRaw)
        return 0
    }
}

@_cdecl("kk_connection_close")
public func kk_connection_close(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeConnectionBox(from: connectionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_close received invalid Connection handle")
    }
    connection.close()
    return 0
}

@_cdecl("kk_connection_isClosed")
public func kk_connection_isClosed(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeConnectionBox(from: connectionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_isClosed received invalid Connection handle")
    }
    return kk_box_bool(connection.closed ? 1 : 0)
}

@_cdecl("kk_savepoint_getSavepointId")
public func kk_savepoint_getSavepointId(_ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: 0) {
        guard let savepoint = runtimeSavepointBox(from: savepointRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_savepoint_getSavepointId received invalid Savepoint handle")
        }
        guard savepoint.name == nil else {
            throw DatabaseRuntimeError.sql("Named savepoints do not expose an integer identifier")
        }
        return savepoint.identifier
    }
}

@_cdecl("kk_savepoint_getSavepointName")
public func kk_savepoint_getSavepointName(_ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    withDatabaseFailure(outThrown: outThrown, fallback: runtimeNullSentinelInt) {
        guard let savepoint = runtimeSavepointBox(from: savepointRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_savepoint_getSavepointName received invalid Savepoint handle")
        }
        guard let name = savepoint.name else {
            throw DatabaseRuntimeError.sql("Unnamed savepoints do not expose a name")
        }
        return runtimeDatabaseMakeStringRaw(name)
    }
}


// MARK: - Database Connection Pool (STDLIB-DB-142)

private extension NSCondition {
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

final class RuntimeDatabaseConnectionBox {
    weak var pool: RuntimeDatabasePoolBox?
    let identifier: Int
    var rawHandle: Int = 0
    fileprivate var isOpen = true
    fileprivate var isInUse = false
    fileprivate var lastCheckoutAt: Date?
    fileprivate var lastReturnAt: Date?

    init(pool: RuntimeDatabasePoolBox, identifier: Int) {
        self.pool = pool
        self.identifier = identifier
    }
}

final class RuntimeDatabasePoolBox {
    private let condition = NSCondition()
    let maxConnections: Int
    let timeoutMillis: Int

    private var nextIdentifier = 1
    private var idleConnections: [RuntimeDatabaseConnectionBox] = []
    private var activeConnections: [Int: RuntimeDatabaseConnectionBox] = [:]
    private var waitingCount = 0

    init(maxConnections: Int, timeoutMillis: Int) {
        self.maxConnections = max(1, maxConnections)
        self.timeoutMillis = max(0, timeoutMillis)
    }

    private var totalConnections: Int {
        activeConnections.count + idleConnections.count
    }

    func acquire(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        condition.lock()
        waitingCount += 1
        defer {
            waitingCount -= 1
            condition.unlock()
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMillis) / 1000.0)

        while true {
            if let connection = nextReusableConnectionLocked() {
                return connection.rawHandle
            }
            if totalConnections < maxConnections {
                let connection = makeConnectionLocked()
                return connection.rawHandle
            }
            if timeoutMillis == 0 || !condition.wait(until: deadline) {
                runtimeSetThrown(
                    outThrown,
                    runtimeAllocateThrowable(
                        message: "IllegalStateException: Timed out acquiring database connection after \(timeoutMillis)ms."
                    )
                )
                return 0
            }
        }
    }

    func release(connection: RuntimeDatabaseConnectionBox, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        condition.withLock {
            guard connection.pool === self else {
                runtimeSetThrown(
                    outThrown,
                    runtimeAllocateThrowable(message: "IllegalArgumentException: Connection does not belong to this pool.")
                )
                return 0
            }
            guard connection.isOpen else {
                runtimeSetThrown(
                    outThrown,
                    runtimeAllocateThrowable(message: "IllegalStateException: Connection has already been closed.")
                )
                return 0
            }
            guard activeConnections.removeValue(forKey: connection.rawHandle) != nil else {
                runtimeSetThrown(
                    outThrown,
                    runtimeAllocateThrowable(message: "IllegalStateException: Connection is not currently checked out.")
                )
                return 0
            }

            connection.isInUse = false
            connection.lastReturnAt = Date()
            idleConnections.append(connection)
            condition.signal()
            return 1
        }
    }

    func activeCount() -> Int {
        condition.withLock { activeConnections.count }
    }

    func idleCount() -> Int {
        condition.withLock { idleConnections.count }
    }

    func waitingCountSnapshot() -> Int {
        condition.withLock { waitingCount }
    }

    func totalCount() -> Int {
        condition.withLock { totalConnections }
    }

    private func nextReusableConnectionLocked() -> RuntimeDatabaseConnectionBox? {
        while !idleConnections.isEmpty {
            let connection = idleConnections.removeFirst()
            guard connection.isOpen else {
                continue
            }
            connection.isInUse = true
            connection.lastCheckoutAt = Date()
            activeConnections[connection.rawHandle] = connection
            return connection
        }
        return nil
    }

    private func makeConnectionLocked() -> RuntimeDatabaseConnectionBox {
        let connection = RuntimeDatabaseConnectionBox(pool: self, identifier: nextIdentifier)
        nextIdentifier += 1
        let raw = registerRuntimeObject(connection)
        connection.rawHandle = raw
        connection.isInUse = true
        connection.lastCheckoutAt = Date()
        activeConnections[raw] = connection
        return connection
    }
}

func runtimeDatabasePoolBox(from rawValue: Int) -> RuntimeDatabasePoolBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeDatabasePoolBox.self)
}

func runtimeDatabaseConnectionBox(from rawValue: Int) -> RuntimeDatabaseConnectionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeDatabaseConnectionBox.self)
}

private func runtimeDatabaseInvalidHandle(_ outThrown: UnsafeMutablePointer<Int>?, kind: String) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "IllegalArgumentException: Invalid database \(kind) handle."))
    return 0
}

@_cdecl("kk_db_pool_new")
public func kk_db_pool_new(_ maxConnections: Int, _ timeoutMillis: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard maxConnections > 0 else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateThrowable(message: "IllegalArgumentException: maxConnections must be positive, but was \(maxConnections).")
        )
        return 0
    }
    guard timeoutMillis >= 0 else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateThrowable(message: "IllegalArgumentException: timeoutMillis must be non-negative, but was \(timeoutMillis).")
        )
        return 0
    }
    return registerRuntimeObject(RuntimeDatabasePoolBox(maxConnections: maxConnections, timeoutMillis: timeoutMillis))
}

@_cdecl("kk_db_pool_acquire")
public func kk_db_pool_acquire(_ poolRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
        return runtimeDatabaseInvalidHandle(outThrown, kind: "pool")
    }
    return pool.acquire(outThrown: outThrown)
}

@_cdecl("kk_db_pool_release")
public func kk_db_pool_release(_ poolRaw: Int, _ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
        return runtimeDatabaseInvalidHandle(outThrown, kind: "pool")
    }
    guard let connection = runtimeDatabaseConnectionBox(from: connectionRaw) else {
        return runtimeDatabaseInvalidHandle(outThrown, kind: "connection")
    }
    return pool.release(connection: connection, outThrown: outThrown)
}

@_cdecl("kk_db_pool_active_count")
public func kk_db_pool_active_count(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.activeCount() ?? 0
}

@_cdecl("kk_db_pool_idle_count")
public func kk_db_pool_idle_count(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.idleCount() ?? 0
}

@_cdecl("kk_db_pool_waiting_count")
public func kk_db_pool_waiting_count(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.waitingCountSnapshot() ?? 0
}

@_cdecl("kk_db_pool_total_count")
public func kk_db_pool_total_count(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.totalCount() ?? 0
}

@_cdecl("kk_db_pool_max_connections")
public func kk_db_pool_max_connections(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.maxConnections ?? 0
}

@_cdecl("kk_db_pool_timeout_millis")
public func kk_db_pool_timeout_millis(_ poolRaw: Int) -> Int {
    runtimeDatabasePoolBox(from: poolRaw)?.timeoutMillis ?? 0
}

@_cdecl("kk_db_connection_id")
public func kk_db_connection_id(_ connectionRaw: Int) -> Int {
    runtimeDatabaseConnectionBox(from: connectionRaw)?.identifier ?? 0
}

@_cdecl("kk_db_connection_in_use")
public func kk_db_connection_in_use(_ connectionRaw: Int) -> Int {
    (runtimeDatabaseConnectionBox(from: connectionRaw)?.isInUse ?? false) ? 1 : 0
}

@_cdecl("kk_db_connection_is_open")
public func kk_db_connection_is_open(_ connectionRaw: Int) -> Int {
    (runtimeDatabaseConnectionBox(from: connectionRaw)?.isOpen ?? false) ? 1 : 0
}

// MARK: - JDBC Runtime (STDLIB-DB-140)

private enum RuntimeJDBCError: Error {
    case invalidHandle(String)
    case unsupportedURL(String)
    case sqlite(String)
    case columnNotFound(String)
    case resultSetClosed
    case statementClosed
    case connectionClosed
}

private final class RuntimeJDBCConnectionBox {
    private(set) var db: OpaquePointer?
    var closed = false

    init(db: OpaquePointer) {
        self.db = db
    }

    func requireDB() throws -> OpaquePointer {
        guard !closed, let db else {
            throw RuntimeJDBCError.connectionClosed
        }
        return db
    }

    func close() throws {
        guard !closed, let db else {
            closed = true
            return
        }
        let rc = sqlite3_close(db)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
        }
        self.db = nil
        self.closed = true
    }
}

private final class RuntimeJDBCStatementBox {
    let connection: RuntimeJDBCConnectionBox
    var closed = false

    init(connection: RuntimeJDBCConnectionBox) {
        self.connection = connection
    }

    func requireConnection() throws -> RuntimeJDBCConnectionBox {
        guard !closed else {
            throw RuntimeJDBCError.statementClosed
        }
        return connection
    }

    func close() {
        closed = true
    }
}

private final class RuntimeJDBCPreparedStatementBox {
    let connection: RuntimeJDBCConnectionBox
    private(set) var statement: OpaquePointer?
    var closed = false

    init(connection: RuntimeJDBCConnectionBox, statement: OpaquePointer) {
        self.connection = connection
        self.statement = statement
    }

    deinit {
        if let statement {
            sqlite3_finalize(statement)
        }
    }

    func requireStatement() throws -> OpaquePointer {
        guard !closed, let statement else {
            throw RuntimeJDBCError.statementClosed
        }
        _ = try connection.requireDB()
        return statement
    }

    func close() {
        guard let statement else {
            closed = true
            return
        }
        sqlite3_finalize(statement)
        self.statement = nil
        self.closed = true
    }
}

private final class RuntimeJDBCResultSetBox {
    enum Ownership {
        case ownedStatement(OpaquePointer)
        case borrowedPreparedStatement(RuntimeJDBCPreparedStatementBox)
    }

    private let ownership: Ownership
    private(set) var statement: OpaquePointer?
    var closed = false
    var lastStepWasRow = false

    init(statement: OpaquePointer, ownership: Ownership) {
        self.statement = statement
        self.ownership = ownership
    }

    deinit {
        close()
    }

    func requireStatement() throws -> OpaquePointer {
        guard !closed, let statement else {
            throw RuntimeJDBCError.resultSetClosed
        }
        return statement
    }

    func close() {
        guard !closed else { return }
        defer {
            statement = nil
            closed = true
            lastStepWasRow = false
        }
        guard let statement else { return }
        switch ownership {
        case let .ownedStatement(owned):
            if owned == statement {
                sqlite3_finalize(statement)
            } else {
                sqlite3_finalize(owned)
            }
        case .borrowedPreparedStatement:
            sqlite3_reset(statement)
        }
    }
}

private func sqliteMessage(from db: OpaquePointer?) -> String {
    if let db, let cString = sqlite3_errmsg(db) {
        return String(cString: cString)
    }
    return "unknown sqlite error"
}

private func jdbcStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func jdbcErrorThrowable(_ error: Error) -> Int {
    let message: String
    switch error {
    case let RuntimeJDBCError.invalidHandle(kind):
        message = "SQLException: invalid \(kind) handle"
    case let RuntimeJDBCError.unsupportedURL(url):
        message = "SQLException: unsupported JDBC URL: \(url)"
    case let RuntimeJDBCError.sqlite(details):
        message = "SQLException: \(details)"
    case let RuntimeJDBCError.columnNotFound(label):
        message = "SQLException: column not found: \(label)"
    case RuntimeJDBCError.resultSetClosed:
        message = "SQLException: result set is closed"
    case RuntimeJDBCError.statementClosed:
        message = "SQLException: statement is closed"
    case RuntimeJDBCError.connectionClosed:
        message = "SQLException: connection is closed"
    default:
        message = "SQLException: \(error.localizedDescription)"
    }
    return runtimeAllocateThrowable(message: message)
}

private func jdbcConnectionBox(from raw: Int) -> RuntimeJDBCConnectionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCConnectionBox.self)
}

private func jdbcStatementBox(from raw: Int) -> RuntimeJDBCStatementBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCStatementBox.self)
}

private func jdbcPreparedStatementBox(from raw: Int) -> RuntimeJDBCPreparedStatementBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCPreparedStatementBox.self)
}

private func jdbcResultSetBox(from raw: Int) -> RuntimeJDBCResultSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCResultSetBox.self)
}

private func jdbcExtractString(_ raw: Int) throws -> String {
    guard let value = extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) else {
        throw RuntimeJDBCError.invalidHandle("string")
    }
    return value
}

private func jdbcPath(from url: String) throws -> String {
    if url == ":memory:" || url == "jdbc:sqlite::memory:" {
        return ":memory:"
    }
    if url.hasPrefix("jdbc:sqlite:") {
        return String(url.dropFirst("jdbc:sqlite:".count))
    }
    if url.contains(":") {
        throw RuntimeJDBCError.unsupportedURL(url)
    }
    return url
}

private func jdbcPrepareStatement(
    db: OpaquePointer,
    sql: String
) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard rc == SQLITE_OK, let statement else {
        throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
    }
    return statement
}

private func jdbcResetForExecution(_ statement: OpaquePointer) {
    sqlite3_reset(statement)
}

private func jdbcExecuteUpdate(db: OpaquePointer, statement: OpaquePointer) throws -> Int {
    let rc = sqlite3_step(statement)
    defer {
        sqlite3_reset(statement)
    }
    guard rc == SQLITE_DONE else {
        throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
    }
    return Int(sqlite3_changes(db))
}

private func jdbcResolveColumnIndex(statement: OpaquePointer, label: String) throws -> Int32 {
    let count = sqlite3_column_count(statement)
    for idx in 0 ..< count {
        guard let namePtr = sqlite3_column_name(statement, idx) else { continue }
        if String(cString: namePtr).caseInsensitiveCompare(label) == .orderedSame {
            return idx
        }
    }
    throw RuntimeJDBCError.columnNotFound(label)
}

private func jdbcColumnInt(statement: OpaquePointer, index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func jdbcColumnString(statement: OpaquePointer, index: Int32) -> Int {
    guard let text = sqlite3_column_text(statement, index) else {
        return runtimeNullSentinelInt
    }
    return jdbcStringRaw(String(cString: text))
}

private func jdbcBindString(_ statement: OpaquePointer, index: Int32, value: String) -> Int32 {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@_cdecl("kk_jdbc_driver_manager_getConnection")
public func kk_jdbc_driver_manager_getConnection(_ urlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        let url = try jdbcExtractString(urlRaw)
        let path = try jdbcPath(from: url)
        var db: OpaquePointer?
        let rc = sqlite3_open(path, &db)
        guard rc == SQLITE_OK, let db else {
            defer { if let db { sqlite3_close(db) } }
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
        }
        return registerRuntimeObject(RuntimeJDBCConnectionBox(db: db))
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_connection_createStatement")
public func kk_jdbc_connection_createStatement(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        _ = try connection.requireDB()
        return registerRuntimeObject(RuntimeJDBCStatementBox(connection: connection))
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_connection_prepareStatement")
public func kk_jdbc_connection_prepareStatement(_ connectionRaw: Int, _ sqlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        let db = try connection.requireDB()
        let sql = try jdbcExtractString(sqlRaw)
        let statement = try jdbcPrepareStatement(db: db, sql: sql)
        return registerRuntimeObject(RuntimeJDBCPreparedStatementBox(connection: connection, statement: statement))
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_connection_close")
public func kk_jdbc_connection_close(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        try connection.close()
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_statement_executeQuery")
public func kk_jdbc_statement_executeQuery(_ statementRaw: Int, _ sqlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let statement = jdbcStatementBox(from: statementRaw) else {
            throw RuntimeJDBCError.invalidHandle("statement")
        }
        let connection = try statement.requireConnection()
        let db = try connection.requireDB()
        let sql = try jdbcExtractString(sqlRaw)
        let sqliteStatement = try jdbcPrepareStatement(db: db, sql: sql)
        let resultSet = RuntimeJDBCResultSetBox(
            statement: sqliteStatement,
            ownership: .ownedStatement(sqliteStatement)
        )
        return registerRuntimeObject(resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_statement_executeUpdate")
public func kk_jdbc_statement_executeUpdate(_ statementRaw: Int, _ sqlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let statement = jdbcStatementBox(from: statementRaw) else {
            throw RuntimeJDBCError.invalidHandle("statement")
        }
        let connection = try statement.requireConnection()
        let db = try connection.requireDB()
        let sql = try jdbcExtractString(sqlRaw)
        let sqliteStatement = try jdbcPrepareStatement(db: db, sql: sql)
        defer { sqlite3_finalize(sqliteStatement) }
        return try jdbcExecuteUpdate(db: db, statement: sqliteStatement)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_statement_close")
public func kk_jdbc_statement_close(_ statementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let statement = jdbcStatementBox(from: statementRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("statement"))
        return 0
    }
    statement.close()
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setInt")
public func kk_jdbc_prepared_statement_setInt(_ preparedStatementRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let rc = sqlite3_bind_int64(statement, Int32(index), sqlite3_int64(value))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setString")
public func kk_jdbc_prepared_statement_setString(_ preparedStatementRaw: Int, _ index: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let value = try jdbcExtractString(valueRaw)
        let rc = jdbcBindString(statement, index: Int32(index), value: value)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_executeQuery")
public func kk_jdbc_prepared_statement_executeQuery(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        jdbcResetForExecution(statement)
        let resultSet = RuntimeJDBCResultSetBox(
            statement: statement,
            ownership: .borrowedPreparedStatement(preparedStatement)
        )
        return registerRuntimeObject(resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_prepared_statement_executeUpdate")
public func kk_jdbc_prepared_statement_executeUpdate(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let db = try preparedStatement.connection.requireDB()
        return try jdbcExecuteUpdate(db: db, statement: statement)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_prepared_statement_close")
public func kk_jdbc_prepared_statement_close(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("prepared statement"))
        return 0
    }
    preparedStatement.close()
    return 0
}

@_cdecl("kk_jdbc_result_set_next")
public func kk_jdbc_result_set_next(_ resultSetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let rc = sqlite3_step(statement)
        switch rc {
        case SQLITE_ROW:
            resultSet.lastStepWasRow = true
            return kk_box_bool(1)
        case SQLITE_DONE:
            resultSet.lastStepWasRow = false
            return kk_box_bool(0)
        default:
            resultSet.lastStepWasRow = false
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: sqlite3_db_handle(statement)))
        }
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return kk_box_bool(0)
    }
}

@_cdecl("kk_jdbc_result_set_getInt")
public func kk_jdbc_result_set_getInt(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnInt(statement: statement, index: Int32(index - 1))
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getIntByLabel")
public func kk_jdbc_result_set_getIntByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnInt(statement: statement, index: index)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getString")
public func kk_jdbc_result_set_getString(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnString(statement: statement, index: Int32(index - 1))
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return runtimeNullSentinelInt
    }
}

@_cdecl("kk_jdbc_result_set_getStringByLabel")
public func kk_jdbc_result_set_getStringByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnString(statement: statement, index: index)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return runtimeNullSentinelInt
    }
}

@_cdecl("kk_jdbc_result_set_close")
public func kk_jdbc_result_set_close(_ resultSetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("result set"))
        return 0
    }
    resultSet.close()
    return 0
}
