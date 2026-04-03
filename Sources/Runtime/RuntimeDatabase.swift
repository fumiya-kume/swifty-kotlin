import Foundation

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
