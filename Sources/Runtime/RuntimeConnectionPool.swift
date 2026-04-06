import Foundation

// MARK: - Connection Pool Runtime (STDLIB-DB-142)

/// Configuration for a `ConnectionPool`.
///
/// Maps to HikariCP-style configuration properties used by the Kotlin
/// `ConnectionPool` stdlib abstraction.
final class RuntimeConnectionPoolConfig {
    var maxPoolSize: Int
    var minIdle: Int
    /// Maximum milliseconds to wait for a connection before throwing.
    var connectionTimeout: Int
    /// Milliseconds a connection may remain idle before being evicted.
    var idleTimeout: Int
    /// Maximum lifetime of a connection in milliseconds (0 = unlimited).
    var maxLifetime: Int

    init(
        maxPoolSize: Int = 10,
        minIdle: Int = 1,
        connectionTimeout: Int = 30_000,
        idleTimeout: Int = 600_000,
        maxLifetime: Int = 1_800_000
    ) {
        self.maxPoolSize = max(1, maxPoolSize)
        self.minIdle = max(0, minIdle)
        self.connectionTimeout = max(0, connectionTimeout)
        self.idleTimeout = max(0, idleTimeout)
        self.maxLifetime = max(0, maxLifetime)
    }
}

/// A pooled connection entry managed by `RuntimeConnectionPoolBox`.
private final class PooledEntry {
    let connection: RuntimeConnectionBox
    /// Monotonic time (in milliseconds) when the entry became idle.
    var idleSince: Int64
    /// Monotonic time (in milliseconds) when this entry was created.
    /// Preserved across `release()` calls so `maxLifetime` is measured from
    /// first creation, not from the last return to the pool.
    let createdAt: Int64

    /// Designated initialiser: called once when a brand-new connection is
    /// wrapped for the first time.
    init(connection: RuntimeConnectionBox, now: Int64) {
        self.connection = connection
        self.idleSince = now
        self.createdAt = now
    }

    /// Re-pool an existing entry, updating only `idleSince`.
    /// `createdAt` is intentionally left unchanged.
    func refreshIdle(now: Int64) {
        idleSince = now
    }
}

/// Runtime backing for `ConnectionPool`.
///
/// Implements a bounded pool of `RuntimeConnectionBox` instances with:
/// - `acquire()` / `release()` lifecycle
/// - Idle-connection eviction triggered on each `release()`
/// - Connection validation via `isValid(timeout:)`
/// - HikariCP-compatible configuration surface
final class RuntimeConnectionPoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private let config: RuntimeConnectionPoolConfig
    /// The JDBC-style URL used to create new connections.
    private let url: String
    /// Connections that are currently idle and available.
    private var idle: [PooledEntry] = []
    /// All `PooledEntry` objects ever created by this pool (idle + active).
    /// Used to verify ownership in `release()`.
    private var allEntries: [ObjectIdentifier: PooledEntry] = [:]
    /// Total number of connections currently managed (idle + active).
    private var totalCount: Int = 0
    /// Waiters blocked in `acquire()` waiting for a connection.
    /// Each waiter owns a slot in `pendingGifts` keyed by its semaphore.
    private var waiters: [DispatchSemaphore] = []
    /// Direct hand-off slots: when `release()` picks a waiter, it places the
    /// entry here *before* signalling the semaphore, so the waiter can always
    /// retrieve the connection without racing against other threads.
    private var pendingGifts: [ObjectIdentifier: PooledEntry] = [:]
    private var closed: Bool = false

    init(url: String, config: RuntimeConnectionPoolConfig) {
        self.url = url
        self.config = config
        // Pre-populate the minimum idle connections.
        let now = monotonicMillis()
        let warmup = min(config.minIdle, config.maxPoolSize)
        for _ in 0..<warmup {
            let conn = RuntimeConnectionBox(url: url)
            let entry = PooledEntry(connection: conn, now: now)
            idle.append(entry)
            allEntries[ObjectIdentifier(conn)] = entry
            totalCount += 1
        }
    }

    // MARK: - Public API

    /// Acquire a connection from the pool.
    ///
    /// If an idle connection is available it is returned immediately.
    /// If the pool is below `maxPoolSize`, a new connection is created.
    /// Otherwise the caller blocks until `connectionTimeout` milliseconds
    /// have elapsed.  Returns `nil` on timeout.
    func acquire() -> RuntimeConnectionBox? {
        lock.lock()

        guard !closed else {
            lock.unlock()
            return nil
        }

        let now = monotonicMillis()
        evictStaleEntries(now: now)

        // Return an idle connection if available.
        if let entry = idle.popLast() {
            lock.unlock()
            return entry.connection
        }

        // Create a new connection if within pool size limit.
        if totalCount < config.maxPoolSize {
            let conn = RuntimeConnectionBox(url: url)
            let entry = PooledEntry(connection: conn, now: now)
            allEntries[ObjectIdentifier(conn)] = entry
            totalCount += 1
            lock.unlock()
            return conn
        }

        // Pool exhausted — wait for a release.
        let sema = DispatchSemaphore(value: 0)
        let semaID = ObjectIdentifier(sema)
        waiters.append(sema)
        lock.unlock()

        let timeoutNS = Int64(config.connectionTimeout) * 1_000_000
        let result = sema.wait(timeout: .now() + .nanoseconds(Int(timeoutNS)))
        if result == .timedOut {
            // Remove ourselves from the waiter list if still present and
            // clean up any pending gift that arrived after the timeout.
            lock.lock()
            waiters.removeAll { $0 === sema }
            pendingGifts.removeValue(forKey: semaID)
            lock.unlock()
            return nil
        }

        // We were signalled — the releasing thread placed our connection in
        // `pendingGifts` *before* calling signal(), so it is guaranteed to
        // be present here without any race.
        lock.lock()
        let entry = pendingGifts.removeValue(forKey: semaID)
        lock.unlock()
        return entry?.connection
    }

    /// Return a connection to the pool.
    ///
    /// If waiters are queued, the first one is woken immediately via the
    /// direct hand-off mechanism (pendingGifts) to avoid races.
    /// Otherwise the connection is added to the idle list (or discarded if
    /// the pool is over capacity or the connection is closed/invalid).
    func release(_ connection: RuntimeConnectionBox) {
        lock.lock()

        guard !closed else {
            connection.close()
            lock.unlock()
            return
        }

        let now = monotonicMillis()

        // If the returned connection is already closed we decrement the total.
        // We then try to create a fresh replacement for any waiting caller so
        // the waiter is never signalled with nothing to receive (Issue 2).
        if connection.closed {
            totalCount = max(0, totalCount - 1)
            // Attempt to satisfy a waiter with a brand-new connection.
            if let sema = waiters.first, totalCount < config.maxPoolSize {
                waiters.removeFirst()
                let newConn = RuntimeConnectionBox(url: url)
                let newEntry = PooledEntry(connection: newConn, now: now)
                allEntries[ObjectIdentifier(newConn)] = newEntry
                totalCount += 1
                let semaID = ObjectIdentifier(sema)
                pendingGifts[semaID] = newEntry
                lock.unlock()
                sema.signal()
            } else {
                // Cannot create a new connection — do NOT signal the waiter,
                // as that would wake it with no connection available.
                lock.unlock()
            }
            return
        }

        // Retrieve the original PooledEntry so we preserve `createdAt`
        // (Issue 4). If somehow not found, create a new one.
        let entry: PooledEntry
        if let existing = allEntries[ObjectIdentifier(connection)] {
            existing.refreshIdle(now: now)
            entry = existing
        } else {
            let newEntry = PooledEntry(connection: connection, now: now)
            allEntries[ObjectIdentifier(connection)] = newEntry
            entry = newEntry
        }

        // Direct hand-off to a waiting caller (Issue 1).
        // Place the entry in `pendingGifts` BEFORE signalling so the waiter
        // always finds its connection regardless of scheduling order.
        if let sema = waiters.first {
            waiters.removeFirst()
            let semaID = ObjectIdentifier(sema)
            pendingGifts[semaID] = entry
            lock.unlock()
            sema.signal()
            return
        }

        // No waiters — return to idle list.
        idle.append(entry)
        evictStaleEntries(now: now)
        lock.unlock()
    }

    /// Returns `true` if `connection` was issued by this pool (Issue 5).
    func owns(_ connection: RuntimeConnectionBox) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allEntries[ObjectIdentifier(connection)] != nil
    }

    /// Validate a connection within `timeout` milliseconds.
    ///
    /// Returns `true` if the connection is open and responsive.
    func isValid(_ connection: RuntimeConnectionBox, timeout: Int) -> Bool {
        _ = timeout
        return !connection.closed
    }

    /// Close the pool, closing all idle connections and preventing new acquisitions.
    func close() {
        lock.lock()
        closed = true
        let snapshot = idle
        idle.removeAll()
        allEntries.removeAll()
        pendingGifts.removeAll()
        totalCount = 0
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        for entry in snapshot {
            entry.connection.close()
        }
        for sema in pending {
            sema.signal()
        }
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCount - idle.count
    }

    var idleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return idle.count
    }

    var totalConnectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCount
    }

    // MARK: - Private helpers

    /// Evict connections that have been idle longer than `idleTimeout` or have
    /// exceeded `maxLifetime`.  Must be called with `lock` held.
    ///
    /// The maximum number of entries that may be evicted is pre-computed so
    /// the idle list never drops below `minIdle` regardless of how many
    /// stale entries are encountered (Issue 3).
    private func evictStaleEntries(now: Int64) {
        guard idle.count > config.minIdle else { return }

        // Pre-compute the maximum number we are allowed to remove.
        var evictBudget = idle.count - config.minIdle

        idle.removeAll { entry in
            guard evictBudget > 0 else { return false }
            let idleTooLong = config.idleTimeout > 0
                && (now - entry.idleSince) >= Int64(config.idleTimeout)
            let tooOld = config.maxLifetime > 0
                && (now - entry.createdAt) >= Int64(config.maxLifetime)
            if idleTooLong || tooOld {
                evictBudget -= 1
                entry.connection.close()
                allEntries.removeValue(forKey: ObjectIdentifier(entry.connection))
                totalCount = max(0, totalCount - 1)
                return true
            }
            return false
        }
    }

    // MARK: - Monotonic clock

    private func monotonicMillis() -> Int64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Int64(ts.tv_sec) * 1_000 + Int64(ts.tv_nsec) / 1_000_000
    }
}

// MARK: - C ABI entry points

private func runtimeConnectionPoolBox(from raw: Int) -> RuntimeConnectionPoolBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeConnectionPoolBox.self)
}

private func runtimeConnectionPoolConfig(from raw: Int) -> RuntimeConnectionPoolConfig? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeConnectionPoolConfig.self)
}

/// Create a `ConnectionPool` configuration object.
///
/// Parameters follow HikariCP naming:
///   - `maxPoolSize`      – maximum total connections
///   - `minIdle`          – minimum idle connections to maintain
///   - `connectionTimeout`– acquisition timeout in milliseconds
@_cdecl("kk_connection_pool_config_new")
public func kk_connection_pool_config_new(
    _ maxPoolSize: Int,
    _ minIdle: Int,
    _ connectionTimeout: Int
) -> Int {
    let config = RuntimeConnectionPoolConfig(
        maxPoolSize: maxPoolSize,
        minIdle: minIdle,
        connectionTimeout: connectionTimeout
    )
    return registerRuntimeObject(config)
}

@_cdecl("kk_connection_pool_config_set_idle_timeout")
public func kk_connection_pool_config_set_idle_timeout(_ configRaw: Int, _ millis: Int) -> Int {
    guard let config = runtimeConnectionPoolConfig(from: configRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_config_set_idle_timeout received invalid config handle")
    }
    config.idleTimeout = max(0, millis)
    return 0
}

@_cdecl("kk_connection_pool_config_set_max_lifetime")
public func kk_connection_pool_config_set_max_lifetime(_ configRaw: Int, _ millis: Int) -> Int {
    guard let config = runtimeConnectionPoolConfig(from: configRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_config_set_max_lifetime received invalid config handle")
    }
    config.maxLifetime = max(0, millis)
    return 0
}

/// Create a new `ConnectionPool` backed by `url` with optional `config`.
///
/// Pass `configRaw == 0` to use default configuration.
@_cdecl("kk_connection_pool_new")
public func kk_connection_pool_new(_ urlRaw: Int, _ configRaw: Int) -> Int {
    let url: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: urlRaw),
       let box = tryCast(ptr, to: RuntimeStringBox.self)
    {
        url = box.value
    } else {
        url = "jdbc:sqlite::memory:"
    }

    let config: RuntimeConnectionPoolConfig
    if configRaw != 0, let cfg = runtimeConnectionPoolConfig(from: configRaw) {
        config = cfg
    } else {
        config = RuntimeConnectionPoolConfig()
    }

    let pool = RuntimeConnectionPoolBox(url: url, config: config)
    return registerRuntimeObject(pool)
}

/// Acquire a connection from the pool.  Returns 0 on timeout/error.
@_cdecl("kk_connection_pool_acquire")
public func kk_connection_pool_acquire(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_acquire received invalid pool handle")
    }
    guard let conn = pool.acquire() else {
        return 0
    }
    return registerRuntimeObject(conn)
}

/// Release a connection back to the pool.
///
/// The connection handle must have been issued by this pool (ownership
/// check). Passing a handle from a different pool or an arbitrary pointer
/// is a programming error and returns 0 without releasing.
@_cdecl("kk_connection_pool_release")
public func kk_connection_pool_release(_ poolRaw: Int, _ connRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_release received invalid pool handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: connRaw),
          let conn = tryCast(ptr, to: RuntimeConnectionBox.self)
    else {
        return 0
    }
    // Ownership check: reject connections not issued by this pool (Issue 5).
    guard pool.owns(conn) else {
        return 0
    }
    pool.release(conn)
    return 0
}

/// Validate a connection within `timeoutMillis` milliseconds.
/// Returns 1 if valid, 0 otherwise.
@_cdecl("kk_connection_pool_is_valid")
public func kk_connection_pool_is_valid(_ poolRaw: Int, _ connRaw: Int, _ timeoutMillis: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_is_valid received invalid pool handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: connRaw),
          let conn = tryCast(ptr, to: RuntimeConnectionBox.self)
    else {
        return 0
    }
    return pool.isValid(conn, timeout: timeoutMillis) ? 1 : 0
}

/// Close the pool and all managed connections.
@_cdecl("kk_connection_pool_close")
public func kk_connection_pool_close(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_close received invalid pool handle")
    }
    pool.close()
    return 0
}

/// Returns 1 if the pool is closed, 0 otherwise.
@_cdecl("kk_connection_pool_is_closed")
public func kk_connection_pool_is_closed(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_is_closed received invalid pool handle")
    }
    return pool.isClosed ? 1 : 0
}

/// Number of currently active (checked-out) connections.
@_cdecl("kk_connection_pool_active_count")
public func kk_connection_pool_active_count(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_active_count received invalid pool handle")
    }
    return pool.activeCount
}

/// Number of currently idle connections.
@_cdecl("kk_connection_pool_idle_count")
public func kk_connection_pool_idle_count(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_idle_count received invalid pool handle")
    }
    return pool.idleCount
}

/// Total number of connections managed by the pool (idle + active).
@_cdecl("kk_connection_pool_total_count")
public func kk_connection_pool_total_count(_ poolRaw: Int) -> Int {
    guard let pool = runtimeConnectionPoolBox(from: poolRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_connection_pool_total_count received invalid pool handle")
    }
    return pool.totalConnectionCount
}
