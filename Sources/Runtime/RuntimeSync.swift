import Foundation

// MARK: - Mutex (kotlinx.coroutines.sync.Mutex)

/// Runtime backing for `kotlinx.coroutines.sync.Mutex`.
///
/// A non-reentrant mutual exclusion lock.  `lock()` suspends if the mutex is
/// already held; `tryLock()` returns immediately.  `unlock()` releases the lock
/// and resumes one waiter (FIFO order).
final class RuntimeMutexHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var locked = false
    private var waiters: [(continuation: Int, queue: DispatchQueue)] = []

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return locked
    }

    /// Try to acquire the lock without suspending.
    /// Returns `true` if the lock was acquired, `false` otherwise.
    func tryLock() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if locked {
            return false
        }
        locked = true
        return true
    }

    /// Acquire the lock synchronously (non-suspend path).
    /// If the lock is free, acquires immediately and returns 0.
    /// If the lock is held, enqueues the waiter and returns the coroutine
    /// suspended sentinel so the codegen suspend/resume loop can handle it.
    func lockSync(continuation: Int) -> Int {
        lock.lock()
        if !locked {
            locked = true
            lock.unlock()
            return 0
        }
        // Already locked — suspend the caller.
        let queue = DispatchQueue.global()
        waiters.append((continuation: continuation, queue: queue))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release the lock.  If there are pending waiters, the first one is
    /// resumed on a GCD queue.
    func unlock() {
        lock.lock()
        guard locked else {
            lock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Mutex.unlock() called on an unlocked mutex")
        }
        if let waiter = waiters.first {
            waiters.removeFirst()
            // Keep locked — ownership transfers to the waiter.
            lock.unlock()
            // Resume the waiter's continuation.
            if waiter.continuation != 0,
               let contPtr = UnsafeMutableRawPointer(bitPattern: waiter.continuation) {
                let state = Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).takeUnretainedValue()
                state.signalResume()
            }
        } else {
            locked = false
            lock.unlock()
        }
    }
}

// MARK: - Semaphore (kotlinx.coroutines.sync.Semaphore)

/// Runtime backing for `kotlinx.coroutines.sync.Semaphore`.
///
/// A counting semaphore with `permits` initial permits.  `acquire()` suspends
/// when no permits are available; `tryAcquire()` returns immediately.
/// `release()` returns a permit and resumes one waiter (FIFO order).
final class RuntimeSemaphoreHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [(continuation: Int, queue: DispatchQueue)] = []

    init(permits: Int) {
        precondition(permits >= 0, "Semaphore permits must be non-negative")
        self.permits = permits
    }

    var availablePermits: Int {
        lock.lock()
        defer { lock.unlock() }
        return permits
    }

    /// Try to acquire a permit without suspending.
    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if permits > 0 {
            permits -= 1
            return true
        }
        return false
    }

    /// Acquire a permit.  If none are available, suspend the caller.
    func acquireSync(continuation: Int) -> Int {
        lock.lock()
        if permits > 0 {
            permits -= 1
            lock.unlock()
            return 0
        }
        let queue = DispatchQueue.global()
        waiters.append((continuation: continuation, queue: queue))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release a permit.  If waiters are pending, resume the first one.
    func release() {
        lock.lock()
        if let waiter = waiters.first {
            waiters.removeFirst()
            // Permit is consumed immediately by the waiter.
            lock.unlock()
            if waiter.continuation != 0,
               let contPtr = UnsafeMutableRawPointer(bitPattern: waiter.continuation) {
                let state = Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).takeUnretainedValue()
                state.signalResume()
            }
        } else {
            permits += 1
            lock.unlock()
        }
    }
}

// MARK: - C ABI entry points

@_cdecl("kk_mutex_create")
public func kk_mutex_create() -> Int {
    let mutex = RuntimeMutexHandle()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(mutex).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_mutex_lock")
public func kk_mutex_lock(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_lock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.lockSync(continuation: continuation)
}

@_cdecl("kk_mutex_unlock")
public func kk_mutex_unlock(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_unlock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    mutex.unlock()
    return 0
}

@_cdecl("kk_mutex_tryLock")
public func kk_mutex_tryLock(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_tryLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.tryLock() ? 1 : 0
}

@_cdecl("kk_mutex_isLocked")
public func kk_mutex_isLocked(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_isLocked received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.isLocked ? 1 : 0
}

@_cdecl("kk_semaphore_create")
public func kk_semaphore_create(_ permits: Int) -> Int {
    let semaphore = RuntimeSemaphoreHandle(permits: permits)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(semaphore).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_semaphore_acquire")
public func kk_semaphore_acquire(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_acquire received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.acquireSync(continuation: continuation)
}

@_cdecl("kk_semaphore_release")
public func kk_semaphore_release(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_release received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    semaphore.release()
    return 0
}

@_cdecl("kk_semaphore_tryAcquire")
public func kk_semaphore_tryAcquire(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_tryAcquire received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.tryAcquire() ? 1 : 0
}

@_cdecl("kk_semaphore_availablePermits")
public func kk_semaphore_availablePermits(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_availablePermits received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.availablePermits
}
