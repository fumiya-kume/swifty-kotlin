import Foundation

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
