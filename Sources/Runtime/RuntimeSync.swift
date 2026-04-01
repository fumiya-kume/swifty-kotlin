import Foundation

// MARK: - Mutex (kotlinx.coroutines.sync.Mutex)

/// Runtime backing for `kotlinx.coroutines.sync.Mutex`.
///
/// A non-reentrant mutual exclusion lock.  `lock()` suspends if the mutex is
/// already held; `tryLock()` returns immediately.  `unlock()` releases the lock
/// and resumes one waiter (FIFO order).
final class RuntimeMutexHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var isHeld = false
    private var waiters: [Int] = []
    private var blockingWaiters: [DispatchSemaphore] = []

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHeld
    }

    /// Try to acquire the lock without suspending.
    /// Returns `true` if the lock was acquired, `false` otherwise.
    func tryLock() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isHeld {
            return false
        }
        isHeld = true
        return true
    }

    /// Acquire the mutex, blocking the calling thread until it is available.
    /// Used by `kk_mutex_withLock` which runs on a regular (non-coroutine) thread.
    func lockBlocking() {
        lock.lock()
        if !isHeld {
            isHeld = true
            lock.unlock()
            return
        }
        let sema = DispatchSemaphore(value: 0)
        blockingWaiters.append(sema)
        lock.unlock()
        sema.wait()
    }

    /// Acquire the lock synchronously (non-suspend path).
    /// If the lock is free, acquires immediately and returns 0.
    /// If the lock is held, enqueues the waiter and returns the coroutine
    /// suspended sentinel so the codegen suspend/resume loop can handle it.
    func lockSync(continuation: Int) -> Int {
        lock.lock()
        if !isHeld {
            isHeld = true
            lock.unlock()
            return 0
        }
        // Already locked — suspend the caller.
        waiters.append(continuation)
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release the lock.  If there are pending waiters, the first one is
    /// resumed on a GCD queue.
    func unlock() {
        lock.lock()
        guard isHeld else {
            lock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Mutex.unlock() called on an unlocked mutex")
        }
        // Prefer blocking (thread-based) waiters before coroutine waiters.
        if !blockingWaiters.isEmpty {
            let sema = blockingWaiters.removeFirst()
            // Keep isHeld = true — ownership transfers to the blocking waiter.
            lock.unlock()
            sema.signal()
            return
        }
        while let continuation = waiters.first {
            waiters.removeFirst()
            if runtimeSyncContinuationIsCancelled(continuation) {
                continue
            }
            // Keep the mutex held — ownership transfers to the resumed waiter.
            lock.unlock()
            runtimeSyncResume(continuation)
            return
        }
        isHeld = false
        lock.unlock()
    }
}

// MARK: - ReentrantReadWriteLock (java.util.concurrent.locks)

/// Runtime backing for `java.util.concurrent.locks.ReentrantReadWriteLock`.
///
/// The handle is an identity token; the actual recursive lock lives in shared
/// runtime state and is keyed by the handle value.
final class RuntimeReentrantReadWriteLockHandle: @unchecked Sendable {}

// MARK: - Semaphore (kotlinx.coroutines.sync.Semaphore)

/// Runtime backing for `kotlinx.coroutines.sync.Semaphore`.
///
/// A counting semaphore with `permits` initial permits.  `acquire()` suspends
/// when no permits are available; `tryAcquire()` returns immediately.
/// `release()` returns a permit and resumes one waiter (FIFO order).
final class RuntimeSemaphoreHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let maxPermits: Int
    private var permits: Int
    private var waiters: [Int] = []

    init(permits: Int) {
        precondition(permits >= 0, "Semaphore permits must be non-negative")
        self.maxPermits = permits
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
        waiters.append(continuation)
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release a permit.  If waiters are pending, resume the first one.
    func release() {
        lock.lock()
        while let continuation = waiters.first {
            waiters.removeFirst()
            if runtimeSyncContinuationIsCancelled(continuation) {
                continue
            }
            // Permit is consumed immediately by the resumed waiter.
            lock.unlock()
            runtimeSyncResume(continuation)
            return
        }
        guard permits < maxPermits else {
            lock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Semaphore.release() exceeded acquired permits")
        }
        permits += 1
        lock.unlock()
    }
}

private func runtimeSyncResume(_ continuation: Int) {
    guard continuation != 0,
          let contPtr = UnsafeMutableRawPointer(bitPattern: continuation)
    else {
        return
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).takeUnretainedValue()
    state.signalResume()
}

private func runtimeSyncContinuationIsCancelled(_ continuation: Int) -> Bool {
    guard continuation != 0,
          let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return false
    }
    return job.cancellationSnapshot()
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

@_cdecl("kk_reentrant_read_write_lock_new")
public func kk_reentrant_read_write_lock_new() -> Int {
    let handle = RuntimeReentrantReadWriteLockHandle()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(handle).toOpaque())
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

// MARK: - Mutex.withLock { } (kotlinx.coroutines.sync.Mutex.withLock)

/// Runtime backing for `Mutex.withLock { }`.
///
/// Attempts to acquire the mutex using the coroutine suspension mechanism.
/// If the mutex is free, acquires it, invokes `action`, releases the mutex,
/// and returns the action result.  If the mutex is already held, enqueues the
/// continuation and returns `COROUTINE_SUSPENDED` so the coroutine runtime
/// can release the thread and resume when the lock becomes available.
/// The action is passed as a Swift function pointer (`actionFnPtr`) and an
/// opaque environment pointer (`actionEnvPtr`) following the standard closure-
/// conversion ABI used throughout KSwiftK.
@_cdecl("kk_mutex_withLock")
public func kk_mutex_withLock(_ handle: Int, _ actionFnPtr: Int, _ actionEnvPtr: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_withLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()

    // Attempt to acquire the mutex via the coroutine suspension mechanism.
    // If contended, lockSync enqueues the continuation and returns COROUTINE_SUSPENDED.
    let lockResult = mutex.lockSync(continuation: continuation)
    if lockResult != 0 {
        // Mutex is contended — caller will be resumed once the lock is available.
        return lockResult
    }
    defer { mutex.unlock() }

    // Invoke the action closure: fn(envPtr) -> intptr_t.
    var result: Int = 0
    if actionFnPtr != 0,
       let fnRaw = UnsafeRawPointer(bitPattern: actionFnPtr)
    {
        typealias ActionFn = @convention(c) (Int) -> Int
        let fn = unsafeBitCast(fnRaw, to: ActionFn.self)
        result = fn(actionEnvPtr)
    }

    return result
}
