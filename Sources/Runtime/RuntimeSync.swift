import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Mutex (kotlinx.coroutines.sync.Mutex)

/// Runtime backing for `kotlinx.coroutines.sync.Mutex`.
///
/// A non-reentrant mutual exclusion lock with FIFO waiter ordering.
/// `lock()` blocks or suspends depending on the caller path, `tryLock()`
/// returns immediately, and `unlock()` transfers ownership to the oldest
/// queued waiter.
final class RuntimeMutexHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var isHeld = false
    private enum Waiter {
        case blocking(DispatchSemaphore)
        case coroutine(Int)
    }
    private var waiters: [Waiter] = []

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
        if isHeld || !waiters.isEmpty {
            return false
        }
        isHeld = true
        return true
    }

    /// Acquire the mutex, blocking the calling thread until it is available.
    /// Used by `kk_mutex_withLock` which runs on a regular (non-coroutine) thread.
    func lockBlocking() {
        _ = lockSync(continuation: 0)
    }

    /// Acquire the lock synchronously (non-suspend path).
    /// If the lock is free, acquires immediately and returns 0.
    /// If the lock is held and `continuation != 0`, enqueues the coroutine
    /// waiter and returns the coroutine suspended sentinel.
    /// If the lock is held and `continuation == 0`, the caller is treated as a
    /// blocking waiter and sleeps until ownership transfers.
    func lockSync(continuation: Int) -> Int {
        lock.lock()
        if !isHeld && waiters.isEmpty {
            isHeld = true
            lock.unlock()
            return 0
        }
        if continuation == 0 {
            let sema = DispatchSemaphore(value: 0)
            waiters.append(.blocking(sema))
            lock.unlock()
            sema.wait()
            return 0
        }
        waiters.append(.coroutine(continuation))
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
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            switch waiter {
            case let .blocking(sema):
                // Keep isHeld = true — ownership transfers to the blocking waiter.
                lock.unlock()
                sema.signal()
                return
            case let .coroutine(continuation):
                if runtimeSyncContinuationIsCancelled(continuation) {
                    continue
                }
                // Keep the mutex held — ownership transfers to the resumed waiter.
                lock.unlock()
                runtimeSyncResume(continuation)
                return
            }
        }
        isHeld = false
        lock.unlock()
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

// MARK: - ReadWriteLock (kotlin.concurrent.ReentrantReadWriteLock)

/// Runtime backing for `kotlin.concurrent.ReentrantReadWriteLock`.
///
/// Uses a native pthread read/write lock to allow concurrent readers and an
/// exclusive writer on blocking threads.
final class RuntimeReadWriteLockHandle: @unchecked Sendable {
    private var lock = pthread_rwlock_t()
    /// Mutex protecting the write-owner tracking fields below.
    private var ownerMutex = pthread_mutex_t()
    /// The pthread_t of the thread currently holding the write lock, or nil.
    private var writeOwner: pthread_t?
    /// How many times the current write-owner has re-entered writeLock().
    private var writeHoldCount: Int = 0

    init() {
        precondition(pthread_rwlock_init(&lock, nil) == 0, "Failed to initialize pthread_rwlock_t")
        precondition(pthread_mutex_init(&ownerMutex, nil) == 0, "Failed to initialize owner mutex")
    }

    deinit {
        pthread_rwlock_destroy(&lock)
        pthread_mutex_destroy(&ownerMutex)
    }

    func readLock() {
        precondition(pthread_rwlock_rdlock(&lock) == 0, "Failed to acquire read lock")
    }

    func writeLock() {
        let self_thread = pthread_self()
        pthread_mutex_lock(&ownerMutex)
        if let owner = writeOwner, pthread_equal(owner, self_thread) != 0 {
            // Reentrant write-lock by the same thread – just bump the count.
            writeHoldCount += 1
            pthread_mutex_unlock(&ownerMutex)
            return
        }
        pthread_mutex_unlock(&ownerMutex)

        precondition(pthread_rwlock_wrlock(&lock) == 0, "Failed to acquire write lock")

        pthread_mutex_lock(&ownerMutex)
        writeOwner = self_thread
        writeHoldCount = 1
        pthread_mutex_unlock(&ownerMutex)
    }

    func unlock() {
        let self_thread = pthread_self()
        pthread_mutex_lock(&ownerMutex)
        if let owner = writeOwner, pthread_equal(owner, self_thread) != 0 {
            writeHoldCount -= 1
            if writeHoldCount == 0 {
                writeOwner = nil
                pthread_mutex_unlock(&ownerMutex)
                precondition(pthread_rwlock_unlock(&lock) == 0, "Failed to unlock read/write lock")
            } else {
                pthread_mutex_unlock(&ownerMutex)
            }
            return
        }
        pthread_mutex_unlock(&ownerMutex)
        // Read-lock unlock path (no owner tracking needed).
        precondition(pthread_rwlock_unlock(&lock) == 0, "Failed to unlock read/write lock")
    }
}

private func runtimeInvokeReadWriteLockAction(_ actionFnPtr: Int, _ actionEnvPtr: Int) -> Int {
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

@_cdecl("kk_read_write_lock_create")
public func kk_read_write_lock_create() -> Int {
    let lock = RuntimeReadWriteLockHandle()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(lock).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_read_write_lock_read")
public func kk_read_write_lock_read(_ handle: Int, _ actionFnPtr: Int, _ actionEnvPtr: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_read_write_lock_read received invalid read/write lock handle")
    }
    let lock = Unmanaged<RuntimeReadWriteLockHandle>.fromOpaque(ptr).takeUnretainedValue()
    lock.readLock()
    defer { lock.unlock() }
    return runtimeInvokeReadWriteLockAction(actionFnPtr, actionEnvPtr)
}

@_cdecl("kk_read_write_lock_write")
public func kk_read_write_lock_write(_ handle: Int, _ actionFnPtr: Int, _ actionEnvPtr: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_read_write_lock_write received invalid read/write lock handle")
    }
    let lock = Unmanaged<RuntimeReadWriteLockHandle>.fromOpaque(ptr).takeUnretainedValue()
    lock.writeLock()
    defer { lock.unlock() }
    return runtimeInvokeReadWriteLockAction(actionFnPtr, actionEnvPtr)
}

// MARK: - Mutex.withLock { } (kotlinx.coroutines.sync.Mutex.withLock)

/// Runtime backing for `Mutex.withLock { }`.
///
/// Attempts to acquire the mutex, invokes `action`, releases the mutex, and
/// returns the action result.  The current lowering passes a zero continuation
/// placeholder, so contended calls block on a regular semaphore; if a real
/// continuation is supplied, the same FIFO waiter queue can still suspend and
/// resume the caller.
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

// MARK: - Lock.withLock { } (kotlin.concurrent.Lock.withLock)

/// Runtime backing for `kotlin.concurrent.Lock.withLock { }`.
///
/// Acquires the mutex in a blocking way using `lockBlocking()`, executes the action,
/// and releases the mutex. The action is represented as a plain closure call with
/// no coroutine suspension support.
@_cdecl("kk_lock_withLock")
public func kk_lock_withLock(_ handle: Int, _ actionFnPtr: Int, _ actionEnvPtr: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_lock_withLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()

    mutex.lockBlocking()
    defer { mutex.unlock() }

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
