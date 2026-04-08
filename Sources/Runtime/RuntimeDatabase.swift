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
    /// Wall-clock time when this pool connection object was created (for `maxLifetime`).
    fileprivate let createdAt = Date()
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
    private var validationQuery: String?
    private var testOnBorrow = false
    private var testOnReturn = false
    private var maxIdleTime: TimeInterval = 300.0 // 5 minutes
    private var maxLifetime: TimeInterval = 1800.0 // 30 minutes

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
            
            // Validate connection if test on return is enabled
            if testOnReturn && !validateConnection(connection) {
                connection.isOpen = false
                return 1  // Connection validated and closed, don't return to pool
            }
            
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
            
            // Check if connection has exceeded maximum lifetime (from creation, not last checkout)
            let age = Date().timeIntervalSince(connection.createdAt)
            if age > maxLifetime {
                connection.isOpen = false
                continue
            }
            
            // Check if connection has been idle too long
            if let lastReturn = connection.lastReturnAt {
                let idleTime = Date().timeIntervalSince(lastReturn)
                if idleTime > maxIdleTime {
                    connection.isOpen = false
                    continue
                }
            }
            
            // Validate connection if test on borrow is enabled
            if testOnBorrow && !validateConnection(connection) {
                connection.isOpen = false
                continue
            }
            
            connection.isInUse = true
            connection.lastCheckoutAt = Date()
            activeConnections[connection.rawHandle] = connection
            return connection
        }
        return nil
    }
    
    private func validateConnection(_ connection: RuntimeDatabaseConnectionBox) -> Bool {
        // Idle hand-outs are always `!isInUse` here; `testOnBorrow`/`testOnReturn` need a real
        // probe (e.g. run `validationQuery` against the open sqlite/db handle). This stub pool
        // box does not carry a DB pointer, so we only assert structural health.
        guard connection.isOpen, !connection.isInUse else { return false }
        if let query = validationQuery, !query.isEmpty {
            _ = query
            // TODO(STDLIB-DB): execute `query` when connection exposes `sqlite3*`.
        }
        return true
    }
    
    func setValidationQuery(_ query: String?) {
        condition.withLock {
            self.validationQuery = query
        }
    }
    
    func setTestOnBorrow(_ test: Bool) {
        condition.withLock {
            self.testOnBorrow = test
        }
    }
    
    func setTestOnReturn(_ test: Bool) {
        condition.withLock {
            self.testOnReturn = test
        }
    }
    
    func setMaxIdleTime(_ seconds: TimeInterval) {
        condition.withLock {
            self.maxIdleTime = max(0, seconds)
        }
    }
    
    func setMaxLifetime(_ seconds: TimeInterval) {
        condition.withLock {
            self.maxLifetime = max(0, seconds)
        }
    }
    
    func isValid(_ connection: RuntimeDatabaseConnectionBox) -> Bool {
        return condition.withLock {
            guard connection.isOpen else { return false }
            
            let age = Date().timeIntervalSince(connection.createdAt)
            if age > maxLifetime { return false }
            
            // Check if connection has been idle too long
            if let lastReturn = connection.lastReturnAt {
                let idleTime = Date().timeIntervalSince(lastReturn)
                if idleTime > maxIdleTime { return false }
            }
            
            return true
        }
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

@_cdecl("kk_db_connection_is_valid")
public func kk_db_connection_is_valid(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeDatabaseConnectionBox(from: connectionRaw),
          let pool = connection.pool else {
        return kk_box_bool(0)
    }
    return kk_box_bool(pool.isValid(connection) ? 1 : 0)
}

@_cdecl("kk_db_pool_set_validation_query")
public func kk_db_pool_set_validation_query(_ poolRaw: Int, _ queryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_db_pool_set_validation_query received invalid pool handle")
        }
        let query = queryRaw == 0 ? nil : try jdbcExtractString(queryRaw)
        pool.setValidationQuery(query)
        return 0
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return 0
    }
}

@_cdecl("kk_db_pool_set_test_on_borrow")
public func kk_db_pool_set_test_on_borrow(_ poolRaw: Int, _ test: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_db_pool_set_test_on_borrow received invalid pool handle")
        }
        pool.setTestOnBorrow(test != 0)
        return 0
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return 0
    }
}

@_cdecl("kk_db_pool_set_test_on_return")
public func kk_db_pool_set_test_on_return(_ poolRaw: Int, _ test: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_db_pool_set_test_on_return received invalid pool handle")
        }
        pool.setTestOnReturn(test != 0)
        return 0
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return 0
    }
}

@_cdecl("kk_db_pool_set_max_idle_time")
public func kk_db_pool_set_max_idle_time(_ poolRaw: Int, _ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_db_pool_set_max_idle_time received invalid pool handle")
        }
        pool.setMaxIdleTime(TimeInterval(seconds))
        return 0
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return 0
    }
}

@_cdecl("kk_db_pool_set_max_lifetime")
public func kk_db_pool_set_max_lifetime(_ poolRaw: Int, _ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let pool = runtimeDatabasePoolBox(from: poolRaw) else {
            throw DatabaseRuntimeError.invalidHandle("kk_db_pool_set_max_lifetime received invalid pool handle")
        }
        pool.setMaxLifetime(TimeInterval(seconds))
        return 0
    } catch {
        outThrown?.pointee = databaseThrowable(from: error)
        return 0
    }
}

// MARK: - JDBC Runtime (STDLIB-DB-140)

enum RuntimeJDBCError: Error {
    case invalidHandle(String)
    case unsupportedURL(String)
    case sqlite(String)
    case columnNotFound(String)
    case resultSetClosed
    case statementClosed
    case connectionClosed
}

final class RuntimeJDBCSavepointBox {
    let identifier: Int
    let name: String?
    weak var connection: RuntimeJDBCConnectionBox?

    init(identifier: Int, name: String?, connection: RuntimeJDBCConnectionBox) {
        self.identifier = identifier
        self.name = name
        self.connection = connection
    }
}

final class RuntimeJDBCConnectionBox {
    private(set) var db: OpaquePointer?
    var closed = false
    var autoCommit = true
    /// Raw JDBC transaction isolation constant (TRANSACTION_READ_COMMITTED = 2 by default).
    var transactionIsolation = 2
    private var nextSavepointID = 1
    private var savepoints: [RuntimeJDBCSavepointBox] = []

    init(db: OpaquePointer) {
        self.db = db
    }

    func requireDB() throws -> OpaquePointer {
        guard !closed, let db else {
            throw RuntimeJDBCError.connectionClosed
        }
        return db
    }

    func commit() throws {
        let db = try requireDB()
        if !autoCommit {
            let rc = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            guard rc == SQLITE_OK else {
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
            savepoints.removeAll()
            // Re-open the next transaction immediately so subsequent statements are still guarded.
            let beginRc = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            guard beginRc == SQLITE_OK else {
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
        }
    }

    func rollback() throws {
        let db = try requireDB()
        if !autoCommit {
            let rc = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            guard rc == SQLITE_OK else {
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
            savepoints.removeAll()
            // Re-open the next transaction immediately so subsequent statements are still guarded.
            let beginRc = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            guard beginRc == SQLITE_OK else {
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
        }
    }

    /// Returns an SQL-safe double-quoted identifier for a savepoint name.
    /// Any double-quote characters in `name` are doubled to escape them.
    private func quotedSavepointName(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    func rollback(to savepoint: RuntimeJDBCSavepointBox) throws {
        guard savepoint.connection === self else {
            throw RuntimeJDBCError.sqlite("Savepoint does not belong to this connection")
        }
        let db = try requireDB()
        let rawName = savepoint.name ?? "sp_\(savepoint.identifier)"
        let spName = quotedSavepointName(rawName)
        let rc = sqlite3_exec(db, "ROLLBACK TO SAVEPOINT \(spName)", nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
        }
        if let index = savepoints.firstIndex(where: { $0 === savepoint }) {
            savepoints = Array(savepoints.prefix(through: index))
        }
    }

    func createSavepoint(name: String?) throws -> RuntimeJDBCSavepointBox {
        let db = try requireDB()
        let sp = RuntimeJDBCSavepointBox(identifier: nextSavepointID, name: name, connection: self)
        nextSavepointID += 1
        let rawName = name ?? "sp_\(sp.identifier)"
        let spName = quotedSavepointName(rawName)
        let rc = sqlite3_exec(db, "SAVEPOINT \(spName)", nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
        }
        savepoints.append(sp)
        return sp
    }

    func releaseSavepoint(_ savepoint: RuntimeJDBCSavepointBox) throws {
        guard savepoint.connection === self else {
            throw RuntimeJDBCError.sqlite("Savepoint does not belong to this connection")
        }
        let db = try requireDB()
        let rawName = savepoint.name ?? "sp_\(savepoint.identifier)"
        let spName = quotedSavepointName(rawName)
        let rc = sqlite3_exec(db, "RELEASE SAVEPOINT \(spName)", nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
        }
        savepoints.removeAll(where: { $0 === savepoint })
    }

    func setAutoCommit(_ newValue: Bool) throws {
        let db = try requireDB()
        guard autoCommit != newValue else { return }
        if newValue {
            // Transitioning from autoCommit=false to autoCommit=true: commit any
            // open transaction before enabling auto-commit mode.
            let rc = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            guard rc == SQLITE_OK else {
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
        }
        autoCommit = newValue
        if !newValue {
            // Issue BEGIN TRANSACTION immediately so that commit()/rollback() have
            // an active transaction to work with.
            let rc = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            guard rc == SQLITE_OK else {
                autoCommit = true  // revert on failure
                throw RuntimeJDBCError.sqlite(sqliteMessage(from: db))
            }
        }
        savepoints.removeAll()
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

final class RuntimeJDBCStatementBox {
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

final class RuntimeJDBCPreparedStatementBox {
    let connection: RuntimeJDBCConnectionBox
    private(set) var statement: OpaquePointer?
    var closed = false
    private var batchCommands: [String] = []
    private var parameterCount: Int32 = 0
    private let originalSQL: String
    private var parameterValues: [Any?] = []
    private var parameterTypes: [Int32] = []

    init(connection: RuntimeJDBCConnectionBox, statement: OpaquePointer, sql: String) {
        self.connection = connection
        self.statement = statement
        self.parameterCount = sqlite3_bind_parameter_count(statement)
        self.originalSQL = sql
        self.parameterValues = Array(repeating: nil, count: Int(parameterCount))
        self.parameterTypes = Array(repeating: 0, count: Int(parameterCount))
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
        batchCommands.removeAll()
    }
    
    func addBatch() {
        if statement != nil {
            let currentParameters = captureCurrentParameters()
            let batchSQL = generateBatchSQL(with: currentParameters)
            batchCommands.append(batchSQL)
        }
    }
    
    func clearBatch() {
        batchCommands.removeAll()
    }
    
    func executeBatch() throws -> [Int] {
        let db = try connection.requireDB()
        var results: [Int] = []
        
        for command in batchCommands {
            let batchStatement = try jdbcPrepareStatement(db: db, sql: command)
            defer { sqlite3_finalize(batchStatement) }
            
            let result = try jdbcExecuteUpdate(db: db, statement: batchStatement)
            results.append(result)
        }
        
        return results
    }
    
    func getParameterCount() -> Int32 {
        return parameterCount
    }
    
    func setParameterValue(_ index: Int32, value: Any?, type: Int32) {
        let idx = Int(index - 1)
        guard idx >= 0 && idx < parameterValues.count else { return }
        parameterValues[idx] = value
        parameterTypes[idx] = type
    }
    
    func captureCurrentParameters() -> [Any?] {
        return Array(parameterValues)
    }
    
    func generateBatchSQL(with parameters: [Any?]) -> String {
        var result = originalSQL
        let paramCount = min(parameters.count, Int(parameterCount))

        for i in 0..<paramCount {
            let value = parameters[i]
            let stringValue: String

            if let value {
                switch parameterTypes[i] {
                case SQLITE_TEXT:
                    let raw: String
                    if let s = value as? String {
                        raw = s
                    } else if let ns = value as? NSString {
                        raw = ns as String
                    } else {
                        raw = String(describing: value)
                    }
                    let escaped = raw.replacingOccurrences(of: "'", with: "''")
                    stringValue = "'\(escaped)'"
                case SQLITE_INTEGER:
                    if let n = value as? Int {
                        stringValue = String(n)
                    } else if let n64 = value as? Int64 {
                        stringValue = String(n64)
                    } else if let n32 = value as? Int32 {
                        stringValue = String(n32)
                    } else {
                        stringValue = String(describing: value)
                    }
                case SQLITE_FLOAT:
                    if let d = value as? Double {
                        stringValue = jdbcAsciiSqlDouble(d)
                    } else if let f = value as? Float {
                        stringValue = jdbcAsciiSqlDouble(Double(f))
                    } else {
                        stringValue = String(describing: value)
                    }
                case SQLITE_NULL:
                    stringValue = "NULL"
                default:
                    stringValue = "NULL"
                }
            } else {
                stringValue = "NULL"
            }

            if let range = result.range(of: "?") {
                result.replaceSubrange(range, with: stringValue)
            }
        }

        return result
    }
}

/// ASCII SQL literal for floating point (finite only; avoids locale-dependent formatting).
private func jdbcAsciiSqlDouble(_ value: Double) -> String {
    guard value.isFinite else { return "NULL" }
    return String(format: "%.17g", value)
}

final class RuntimeJDBCResultSetBox {
    enum Ownership {
        case ownedStatement(OpaquePointer)
        case borrowedPreparedStatement(RuntimeJDBCPreparedStatementBox)
    }

    private let ownership: Ownership
    private(set) var statement: OpaquePointer?
    var closed = false
    var lastStepWasRow = false
    var lastColumnWasNull = false
    var columnCount = 0
    /// 1-based row counter; 0 means positioned before the first row.
    var currentRow = 0

    init(statement: OpaquePointer, ownership: Ownership) {
        self.statement = statement
        self.ownership = ownership
        self.columnCount = Int(sqlite3_column_count(statement))
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

func jdbcStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

func jdbcErrorThrowable(_ error: Error) -> Int {
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

func jdbcConnectionBox(from raw: Int) -> RuntimeJDBCConnectionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCConnectionBox.self)
}

private func jdbcSavepointBox(from raw: Int) -> RuntimeJDBCSavepointBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCSavepointBox.self)
}

func jdbcStatementBox(from raw: Int) -> RuntimeJDBCStatementBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCStatementBox.self)
}

func jdbcPreparedStatementBox(from raw: Int) -> RuntimeJDBCPreparedStatementBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCPreparedStatementBox.self)
}

func jdbcResultSetBox(from raw: Int) -> RuntimeJDBCResultSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCResultSetBox.self)
}

func jdbcExtractString(_ raw: Int) throws -> String {
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

private func jdbcColumnInt(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    resultSet.lastColumnWasNull = sqlite3_column_type(statement, index) == SQLITE_NULL
    return Int(sqlite3_column_int64(statement, index))
}

private func jdbcColumnString(statement: OpaquePointer, index: Int32) -> Int {
    guard let text = sqlite3_column_text(statement, index) else {
        return runtimeNullSentinelInt
    }
    return jdbcStringRaw(String(cString: text))
}

private func jdbcColumnString(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    guard let text = sqlite3_column_text(statement, index) else {
        resultSet.lastColumnWasNull = true
        return runtimeNullSentinelInt
    }
    resultSet.lastColumnWasNull = false
    return jdbcStringRaw(String(cString: text))
}

private func jdbcColumnDouble(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    resultSet.lastColumnWasNull = sqlite3_column_type(statement, index) == SQLITE_NULL
    let value = sqlite3_column_double(statement, index)
    return kk_box_double(Int(truncatingIfNeeded: value.bitPattern))
}

private func jdbcColumnFloat(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    resultSet.lastColumnWasNull = sqlite3_column_type(statement, index) == SQLITE_NULL
    let value = Float(sqlite3_column_double(statement, index))
    return kk_box_float(Int(truncatingIfNeeded: UInt32(value.bitPattern)))
}

private func jdbcColumnLong(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    resultSet.lastColumnWasNull = sqlite3_column_type(statement, index) == SQLITE_NULL
    let value = sqlite3_column_int64(statement, index)
    return kk_box_long(Int(truncatingIfNeeded: value))
}

private func jdbcColumnBoolean(statement: OpaquePointer, index: Int32, resultSet: RuntimeJDBCResultSetBox) -> Int {
    resultSet.lastColumnWasNull = sqlite3_column_type(statement, index) == SQLITE_NULL
    let value = sqlite3_column_int(statement, index)
    return kk_box_bool(value != 0 ? 1 : 0)
}

final class RuntimeJDBCResultSetMetaDataBox {
    /// Snapshot at construction so metadata stays valid after the ResultSet/statement is closed.
    private let columnCount: Int
    private let columnNames: [String]
    private let columnDeclTypesUppercased: [String]

    init(statement: OpaquePointer) {
        let cc = Int(sqlite3_column_count(statement))
        self.columnCount = cc
        var names: [String] = []
        var decls: [String] = []
        names.reserveCapacity(cc)
        decls.reserveCapacity(cc)
        for i in 0..<cc {
            let namePtr = sqlite3_column_name(statement, Int32(i))
            names.append(namePtr.map { String(cString: $0) } ?? "")
            let declPtr = sqlite3_column_decltype(statement, Int32(i))
            decls.append(declPtr.map { String(cString: $0).uppercased() } ?? "")
        }
        self.columnNames = names
        self.columnDeclTypesUppercased = decls
    }
    
    func getColumnCount() -> Int {
        return columnCount
    }
    
    func getColumnName(_ index: Int) -> String? {
        guard index >= 1 && index <= columnCount else { return nil }
        let name = columnNames[index - 1]
        return name.isEmpty ? nil : name
    }
    
    func getColumnLabel(_ index: Int) -> String? {
        return getColumnName(index)
    }
    
    func getColumnType(_ index: Int) -> Int32 {
        guard index >= 1 && index <= columnCount else { return 0 }
        let decl = columnDeclTypesUppercased[index - 1]
        if decl.contains("INT") { return SQLITE_INTEGER }
        if decl.contains("TEXT") || decl.contains("CLOB") || decl.contains("CHAR") || decl.contains("STR") {
            return SQLITE_TEXT
        }
        if decl.contains("BLOB") { return SQLITE_BLOB }
        if decl.contains("REAL") || decl.contains("FLOA") || decl.contains("DOUB") { return SQLITE_FLOAT }
        return SQLITE_NULL
    }
    
    func getColumnTypeName(_ index: Int) -> String {
        let type = getColumnType(index)
        switch type {
        case SQLITE_INTEGER:
            return "INTEGER"
        case SQLITE_FLOAT:
            return "FLOAT"
        case SQLITE_TEXT:
            return "TEXT"
        case SQLITE_BLOB:
            return "BLOB"
        case SQLITE_NULL:
            return "NULL"
        default:
            return "UNKNOWN"
        }
    }
    
    func isNullable(_ index: Int) -> Int {
        return 1 // ResultSetMetaData.columnNullable
    }
    
    func isAutoIncrement(_ index: Int) -> Bool {
        return false
    }
    
    func isReadOnly(_ index: Int) -> Bool {
        return true
    }
    
    func isSearchable(_ index: Int) -> Bool {
        return true
    }
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
        return registerRuntimeObject(RuntimeJDBCPreparedStatementBox(connection: connection, statement: statement, sql: sql))
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
        let value = kk_unbox_long(value)
        let rc = sqlite3_bind_int64(statement, Int32(index), sqlite3_int64(value))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: value, type: SQLITE_INTEGER)
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
        preparedStatement.setParameterValue(Int32(index), value: value, type: SQLITE_TEXT)
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

@_cdecl("kk_jdbc_prepared_statement_setDouble")
public func kk_jdbc_prepared_statement_setDouble(_ preparedStatementRaw: Int, _ index: Int, _ value: Double, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let rc = sqlite3_bind_double(statement, Int32(index), value)
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: value, type: SQLITE_FLOAT)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setFloat")
public func kk_jdbc_prepared_statement_setFloat(_ preparedStatementRaw: Int, _ index: Int, _ value: Float, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let rc = sqlite3_bind_double(statement, Int32(index), Double(value))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: value, type: SQLITE_FLOAT)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setLong")
public func kk_jdbc_prepared_statement_setLong(_ preparedStatementRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let longValue = kk_unbox_long(value)
        let rc = sqlite3_bind_int64(statement, Int32(index), sqlite3_int64(longValue))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: longValue, type: SQLITE_INTEGER)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setBoolean")
public func kk_jdbc_prepared_statement_setBoolean(_ preparedStatementRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let boolValue = kk_unbox_bool(value) != 0 ? 1 : 0
        let rc = sqlite3_bind_int(statement, Int32(index), Int32(boolValue))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: boolValue != 0, type: SQLITE_INTEGER)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_setNull")
public func kk_jdbc_prepared_statement_setNull(_ preparedStatementRaw: Int, _ index: Int, _ sqlType: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let statement = try preparedStatement.requireStatement()
        let rc = sqlite3_bind_null(statement, Int32(index))
        guard rc == SQLITE_OK else {
            throw RuntimeJDBCError.sqlite(sqliteMessage(from: try preparedStatement.connection.requireDB()))
        }
        preparedStatement.setParameterValue(Int32(index), value: nil, type: SQLITE_NULL)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_addBatch")
public func kk_jdbc_prepared_statement_addBatch(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        preparedStatement.addBatch()
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_clearBatch")
public func kk_jdbc_prepared_statement_clearBatch(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        preparedStatement.clearBatch()
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_prepared_statement_executeBatch")
public func kk_jdbc_prepared_statement_executeBatch(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let results = try preparedStatement.executeBatch()
        let arrayBox = RuntimeArrayBox(length: results.count)
        for (index, result) in results.enumerated() {
            arrayBox.elements[index] = result
        }
        return registerRuntimeObject(arrayBox)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_prepared_statement_getParameterCount")
public func kk_jdbc_prepared_statement_getParameterCount(_ preparedStatementRaw: Int) -> Int {
    guard let preparedStatement = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
        return 0
    }
    return Int(preparedStatement.getParameterCount())
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
            resultSet.currentRow += 1
            return kk_box_bool(1)
        case SQLITE_DONE:
            resultSet.lastStepWasRow = false
            // JDBC spec: getRow() must return 0 when not positioned on a valid row.
            resultSet.currentRow = 0
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
        return jdbcColumnInt(statement: statement, index: Int32(index - 1), resultSet: resultSet)
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
        return jdbcColumnInt(statement: statement, index: index, resultSet: resultSet)
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
        return jdbcColumnString(statement: statement, index: Int32(index - 1), resultSet: resultSet)
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
        return jdbcColumnString(statement: statement, index: index, resultSet: resultSet)
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

@_cdecl("kk_jdbc_result_set_wasNull")
public func kk_jdbc_result_set_wasNull(_ resultSetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("result set"))
        return kk_box_bool(0)
    }
    return kk_box_bool(resultSet.lastColumnWasNull ? 1 : 0)
}

@_cdecl("kk_jdbc_result_set_getDouble")
public func kk_jdbc_result_set_getDouble(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnDouble(statement: statement, index: Int32(index - 1), resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getDoubleByLabel")
public func kk_jdbc_result_set_getDoubleByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnDouble(statement: statement, index: index, resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getBoolean")
public func kk_jdbc_result_set_getBoolean(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnBoolean(statement: statement, index: Int32(index - 1), resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return kk_box_bool(0)
    }
}

@_cdecl("kk_jdbc_result_set_getBooleanByLabel")
public func kk_jdbc_result_set_getBooleanByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnBoolean(statement: statement, index: index, resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return kk_box_bool(0)
    }
}

@_cdecl("kk_jdbc_result_set_getLong")
public func kk_jdbc_result_set_getLong(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnLong(statement: statement, index: Int32(index - 1), resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getLongByLabel")
public func kk_jdbc_result_set_getLongByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnLong(statement: statement, index: index, resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getFloat")
public func kk_jdbc_result_set_getFloat(_ resultSetRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        return jdbcColumnFloat(statement: statement, index: Int32(index - 1), resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getFloatByLabel")
public func kk_jdbc_result_set_getFloatByLabel(_ resultSetRaw: Int, _ labelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let label = try jdbcExtractString(labelRaw)
        let index = try jdbcResolveColumnIndex(statement: statement, label: label)
        return jdbcColumnFloat(statement: statement, index: index, resultSet: resultSet)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_result_set_getMetaData")
public func kk_jdbc_result_set_getMetaData(_ resultSetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let resultSet = jdbcResultSetBox(from: resultSetRaw) else {
            throw RuntimeJDBCError.invalidHandle("result set")
        }
        let statement = try resultSet.requireStatement()
        let metaData = RuntimeJDBCResultSetMetaDataBox(statement: statement)
        return registerRuntimeObject(metaData)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

private func jdbcResultSetMetaDataBox(from raw: Int) -> RuntimeJDBCResultSetMetaDataBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCResultSetMetaDataBox.self)
}

@_cdecl("kk_jdbc_result_set_meta_getColumnCount")
public func kk_jdbc_result_set_meta_getColumnCount(_ metaDataRaw: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_jdbc_result_set_meta_getColumnCount received invalid ResultSetMetaData handle")
    }
    return metaData.getColumnCount()
}

@_cdecl("kk_jdbc_result_set_meta_getColumnName")
public func kk_jdbc_result_set_meta_getColumnName(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return runtimeNullSentinelInt
    }
    guard let name = metaData.getColumnName(index) else {
        return runtimeNullSentinelInt
    }
    return jdbcStringRaw(name)
}

@_cdecl("kk_jdbc_result_set_meta_getColumnLabel")
public func kk_jdbc_result_set_meta_getColumnLabel(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return runtimeNullSentinelInt
    }
    guard let label = metaData.getColumnLabel(index) else {
        return runtimeNullSentinelInt
    }
    return jdbcStringRaw(label)
}

@_cdecl("kk_jdbc_result_set_meta_getColumnType")
public func kk_jdbc_result_set_meta_getColumnType(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return 0
    }
    return Int(metaData.getColumnType(index))
}

@_cdecl("kk_jdbc_result_set_meta_getColumnTypeName")
public func kk_jdbc_result_set_meta_getColumnTypeName(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return runtimeNullSentinelInt
    }
    return jdbcStringRaw(metaData.getColumnTypeName(index))
}

@_cdecl("kk_jdbc_result_set_meta_isNullable")
public func kk_jdbc_result_set_meta_isNullable(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return 0
    }
    return metaData.isNullable(index)
}

@_cdecl("kk_jdbc_result_set_meta_isAutoIncrement")
public func kk_jdbc_result_set_meta_isAutoIncrement(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(metaData.isAutoIncrement(index) ? 1 : 0)
}

@_cdecl("kk_jdbc_result_set_meta_isReadOnly")
public func kk_jdbc_result_set_meta_isReadOnly(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(metaData.isReadOnly(index) ? 1 : 0)
}

@_cdecl("kk_jdbc_result_set_meta_isSearchable")
public func kk_jdbc_result_set_meta_isSearchable(_ metaDataRaw: Int, _ index: Int) -> Int {
    guard let metaData = jdbcResultSetMetaDataBox(from: metaDataRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(metaData.isSearchable(index) ? 1 : 0)
}
