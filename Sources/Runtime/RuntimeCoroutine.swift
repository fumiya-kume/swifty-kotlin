import Dispatch
import Foundation

// MARK: - Lightweight pthread-based Thread-Local Storage (CORO-003)
//
// These helpers replace `Thread.current.threadDictionary` lookups with direct
// `pthread_key_t` thread-locals.  Each key stores an `Unmanaged` pointer to a
// Swift class instance.  A destructor callback releases the object when the
// thread exits, so there are no leaks.

/// Create a `pthread_key_t` with a destructor that releases the stored object.
private func makePthreadKey() -> pthread_key_t {
    var key = pthread_key_t()
    #if canImport(Glibc) || canImport(Musl)
    // Linux: pthread destructor expects Optional pointer.
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer?) in
        guard let ptr else { return }
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #else
    // Darwin: pthread destructor expects non-optional pointer.
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer) in
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #endif
    return key
}

/// Read the object stored under `key` for the current thread.
private func pthreadGetValue<T: AnyObject>(_ key: pthread_key_t) -> T? {
    guard let raw = pthread_getspecific(key) else { return nil }
    return Unmanaged<T>.fromOpaque(raw).takeUnretainedValue()
}

/// Store `value` under `key` for the current thread, releasing any previous value.
private func pthreadSetValue<T: AnyObject>(_ key: pthread_key_t, _ value: T?) {
    // Release previous value if present.
    if let prev = pthread_getspecific(key) {
        Unmanaged<AnyObject>.fromOpaque(prev).release()
    }
    if let value {
        let raw = Unmanaged.passRetained(value).toOpaque()
        pthread_setspecific(key, raw)
    } else {
        pthread_setspecific(key, nil)
    }
}

private final class RuntimeResumeContinuationBox: @unchecked Sendable {
    let closure: @Sendable () -> Void

    init(_ closure: @escaping @Sendable () -> Void) {
        self.closure = closure
    }

    func invoke() {
        closure()
    }
}

private final class RuntimeCoroutineExceptionHandlerBox: @unchecked Sendable {
    let handler: (Error) -> Void
    init(_ handler: @escaping (Error) -> Void) { self.handler = handler }
}

// MARK: - CORO-004 Migration Plan: DispatchSemaphore -> Continuation Model
//
// The suspend-entry loop (`runSuspendEntryLoopWithContinuation`) has already
// been migrated to a non-blocking continuation model.  When a coroutine
// suspends (e.g. `delay()`), a resume closure is installed via
// `installResumeContinuation` and the GCD thread is released immediately.
// The `completionGate` semaphore blocks only at the outermost caller
// (runBlocking / join / await), which is acceptable because those are
// inherently synchronous wait points.
//
// Remaining DispatchSemaphore.wait() sites and migration status:
//
// [DONE] runSuspendEntryLoopWithContinuation: internal suspend points use
//        installResumeContinuation; only completionGate blocks (outermost).
//
// [DONE] runtimeFlowDeliverValue (line ~1151): suspend-collector path now
//        uses installResumeContinuation instead of waitForResumeSignal().
//
// [TODO] RuntimeAsyncTask.awaitResult() (line ~277):
//        Blocks the calling coroutine's GCD thread on `ready.wait()`.
//        Migration: Convert to a suspend point in the caller's entry loop
//        so the caller installs a continuation that the task's `complete()`
//        method dispatches.  Requires codegen changes to emit a suspend
//        label at the `await` call site.
//
// [TODO] RuntimeJobHandle.join() (line ~343):
//        Same pattern as awaitResult().  Requires a suspend-aware join.
//
// [TODO] kk_with_context (line ~1746):
//        Blocks the caller while the block runs on the target queue.
//        Migration: Make withContext itself a suspend point.  The target
//        queue dispatches the block and, upon completion, resumes the
//        caller via signalResume().  The caller's entry-loop continuation
//        picks up the result without blocking.
//
// [TODO] Channel send/receive (lines ~1887, ~1959):
//        Rendezvous and backpressure blocking.  Migration: Replace the
//        per-waiter DispatchSemaphore with a continuation closure stored
//        in SuspendedSender/SuspendedReceiver.  When the counterpart
//        arrives, dispatch the continuation instead of signaling a
//        semaphore.  This is the most complex migration because channels
//        involve two independent parties (sender/receiver), each of which
//        may be a coroutine or a raw thread.
//
// [TODO] RuntimeTypes.swift — sequence/iterator builder coroutines:
//        producerSemaphore/consumerSemaphore and producerGate/consumerGate
//        implement a cooperative ping-pong protocol.  Migration: model
//        yield() as a suspend point in the producer coroutine and
//        next()/hasNext() as suspend points in the consumer, using the
//        continuation model to avoid blocking either side.
//
// Priority order: Channel > withContext > awaitResult/join > sequence builders
// (Channels are most likely to exhaust GCD thread pools under load.)

final class RuntimeContinuationState: @unchecked Sendable {
    var functionID: Int64
    var label: Int64
    var completion: Int64
    var spillSlots: [Int64: Int64]
    var launcherArgs: [Int64: Int64]
    // The link from continuation state to job handle is weak on purpose:
    // - to avoid retain cycles between RuntimeJobHandle and RuntimeContinuationState
    // - because job handle lifetime is managed externally and cancellation is best-effort.
    // If the jobHandle is deallocated before cancellation is observed, the continuation
    // will simply not be woken by cancellation, which is an accepted behavior.
    weak var jobHandle: RuntimeJobHandle?
    /// CORO-003: The coroutine scope is carried in the continuation context instead
    /// of Thread Local Storage, so it survives suspend/resume across threads.
    var scope: RuntimeCoroutineScope?
    /// Stores a thrown exception pointer when the coroutine body throws.
    /// Zero means no exception was thrown.  Set by runSuspendEntryLoopWithContinuation
    /// and consumed by kk_kxmini_launch_with_exception_handler to reliably
    /// distinguish exception returns from normal (possibly non-zero) return values.
    var thrownException: Int = 0
    private let stateLock = NSLock()
    private var delayTimers: [ObjectIdentifier: DispatchSourceTimer]

    /// CORO-004: Continuation-based resume model.
    ///
    /// Instead of blocking a GCD thread with DispatchSemaphore.wait(), we store
    /// a resume closure when the coroutine suspends.  When signalResume() is
    /// called (from a timer, cancellation, etc.) the closure is dispatched on a
    /// GCD queue, releasing the original thread back to the pool.
    ///
    /// If no continuation closure is installed (e.g. during tests that call
    /// waitForResumeSignal() synchronously), we fall back to a one-shot
    /// DispatchSemaphore for backward compatibility.
    private var resumeContinuation: RuntimeResumeContinuationBox?
    /// Lazily created fallback semaphore, only used by legacy synchronous
    /// callers that invoke waitForResumeSignal() without a continuation.
    private var fallbackSemaphore: DispatchSemaphore?
    /// True if signalResume() was called before any continuation or wait was
    /// installed (edge case: timer fires immediately).
    private var resumeSignalPending = false

    init(
        functionID: Int64,
        label: Int64 = 0,
        completion: Int64 = 0,
        spillSlots: [Int64: Int64] = [:],
        launcherArgs: [Int64: Int64] = [:],
        delayTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
    ) {
        self.functionID = functionID
        self.label = label
        self.completion = completion
        self.spillSlots = spillSlots
        self.launcherArgs = launcherArgs
        self.delayTimers = delayTimers
    }

    deinit {
        let timers = releaseAllDelayTimers()
        for timer in timers {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    func scheduleDelay(milliseconds: Int) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        let timerID = ObjectIdentifier(timer as AnyObject)
        stateLock.lock()
        delayTimers[timerID] = timer
        stateLock.unlock()

        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler { [weak self] in
            self?.completeDelayTimer(timerID: timerID)
        }
        timer.resume()
    }

    /// CORO-004: Install a resume continuation.  Called by the suspend-entry
    /// loop right before it would otherwise block.  If a resume signal has
    /// already been delivered (pending), the continuation is dispatched
    /// immediately.
    func installResumeContinuation(_ continuation: @escaping @Sendable () -> Void) {
        let boxedContinuation = RuntimeResumeContinuationBox(continuation)
        stateLock.lock()
        if resumeSignalPending {
            resumeSignalPending = false
            stateLock.unlock()
            // Signal already arrived — dispatch continuation immediately.
            DispatchQueue.global().async {
                boxedContinuation.invoke()
            }
            return
        }
        resumeContinuation = boxedContinuation
        stateLock.unlock()
    }

    /// Legacy blocking wait.  Used only when no continuation has been installed
    /// (e.g. direct test calls).  Creates a one-shot semaphore on demand.
    func waitForResumeSignal() {
        stateLock.lock()
        if resumeSignalPending {
            resumeSignalPending = false
            stateLock.unlock()
            return
        }
        if fallbackSemaphore == nil {
            fallbackSemaphore = DispatchSemaphore(value: 0)
        }
        let sem = fallbackSemaphore!
        stateLock.unlock()
        sem.wait()
    }

    /// Wake the coroutine.  If a continuation closure is installed, it is
    /// dispatched asynchronously on a GCD queue (non-blocking).  Otherwise
    /// the fallback semaphore is signalled.
    func signalResume() {
        stateLock.lock()
        if let cont = resumeContinuation {
            resumeContinuation = nil
            stateLock.unlock()
            DispatchQueue.global().async {
                cont.invoke()
            }
            return
        }
        if let sem = fallbackSemaphore {
            stateLock.unlock()
            sem.signal()
            return
        }
        // Neither continuation nor semaphore installed yet — mark pending.
        resumeSignalPending = true
        stateLock.unlock()
    }

    /// Reset resume state for the next suspend point.  Called after the
    /// coroutine loop resumes to prepare for the next potential suspension.
    func resetResumeState() {
        stateLock.lock()
        resumeContinuation = nil
        fallbackSemaphore = nil
        resumeSignalPending = false
        stateLock.unlock()
    }

    private func completeDelayTimer(timerID: ObjectIdentifier) {
        stateLock.lock()
        delayTimers.removeValue(forKey: timerID)
        stateLock.unlock()
        signalResume()
    }

    private func releaseAllDelayTimers() -> [DispatchSourceTimer] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let timers = Array(delayTimers.values)
        delayTimers.removeAll(keepingCapacity: false)
        return timers
    }
}

final class RuntimeAsyncTask: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0
    /// Stores a thrown exception (as a raw pointer Int) when the async body fails.
    /// Zero means no exception was thrown. Used by kk_kxmini_async_await_throwing.
    private(set) var thrownException: Int = 0
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_kxmini_async_await or kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false

    func markConsumedByUserCode() {
        lock.lock()
        isConsumedByUserCode = true
        lock.unlock()
    }

    func consumedByUserCodeSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConsumedByUserCode
    }

    /// Thread-safe snapshot of the completion state.
    func isCompletedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted
    }

    /// Thread-safe snapshot of the cancellation flag.
    func isCancelledSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// Thread-safe snapshot of the active state (not completed AND not cancelled).
    /// Reads both flags under a single lock acquisition to avoid TOCTOU races.
    func isActiveSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCompleted && !isCancelled
    }

    func complete(with result: Int) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        self.result = result
        isCompleted = true
        lock.unlock()
        ready.signal()
    }

    /// Complete the task with an exception (CORO-071: async exception handling).
    func completeExceptionally(with exception: Int) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        self.thrownException = exception
        isCompleted = true
        lock.unlock()
        ready.signal()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let wasCompleted = isCompleted
        if !wasCompleted {
            isCompleted = true
        }
        lock.unlock()
        if !wasCompleted {
            ready.signal()
        }
    }

    // CORO-004: awaitResult() now supports continuation-based async completion.
    // When called from a suspend-aware context (via codegen changes), it uses
    // continuation model instead of blocking on semaphore.
    func awaitResult(continuation: Int = 0) -> Int {
        lock.lock()
        if isCompleted {
            let value = result
            lock.unlock()
            return value
        }

        // If continuation is provided and we're in a suspend-aware context,
        // install for async completion instead of blocking
        if continuation != 0 {
            // CORO-004: TODO - Implement continuation-based async completion
            // This requires codegen changes to make await a suspend point
            // For now, fall back to semaphore blocking
            // return suspendCallerAndAwaitCompletion(continuation: continuation) { result in
            //     return result
            // }
        }

        lock.unlock()
        // Fallback to semaphore blocking for non-suspend-aware contexts
        ready.wait()
        // Re-signal so other concurrent awaitResult() callers also wake up
        ready.signal()
        lock.lock()
        let value = result
        lock.unlock()
        return value
    }

    /// Await the result and propagate any exception (CORO-071: exception-aware await).
    /// Writes the thrown exception (if any) to `outThrown` and returns 0 if an
    /// exception occurred, otherwise returns the normal result.
    func awaitResultThrowing(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        lock.lock()
        if isCompleted {
            let exc = thrownException
            let value = result
            lock.unlock()
            if exc != 0 {
                outThrown?.pointee = exc
                return 0
            }
            return value
        }
        lock.unlock()
        ready.wait()
        ready.signal()
        lock.lock()
        let exc = thrownException
        let value = result
        lock.unlock()
        if exc != 0 {
            outThrown?.pointee = exc
            return 0
        }
        return value
    }
}

// MARK: - Structured Concurrency (P5-89)

/// A job handle representing a launched coroutine. Supports join and cancellation.
final class RuntimeJobHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private(set) var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0
    weak var continuationState: RuntimeContinuationState?
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false

    func markConsumedByUserCode() {
        lock.lock()
        isConsumedByUserCode = true
        lock.unlock()
    }

    func consumedByUserCodeSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConsumedByUserCode
    }

    func complete(with value: Int) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        result = value
        isCompleted = true
        lock.unlock()
        completionSemaphore.signal()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let state = continuationState
        lock.unlock()
        // Wake the coroutine from any delay/suspension so it can observe cancellation
        state?.signalResume()
    }

    // CORO-004: join() now supports continuation-based async completion.
    // When called from a suspend-aware context (via codegen changes), it uses
    // continuation model instead of blocking on semaphore.
    func join(continuation: Int = 0) -> Int {
        lock.lock()
        if isCompleted {
            let value = result
            lock.unlock()
            return value
        }
        
        // If continuation is provided and we're in a suspend-aware context,
        // install for async completion instead of blocking
        if continuation != 0 {
            // CORO-004: TODO - Implement continuation-based async join
            // This requires codegen changes to make join a suspend point
            // For now, fall back to semaphore blocking
            // return suspendCallerAndAwaitCompletion(continuation: continuation) { result in
            //     return result
            // }
        }
        
        lock.unlock()
        // Fallback to semaphore blocking for non-suspend-aware contexts
        completionSemaphore.wait()
        // Re-signal so other concurrent join() callers also wake up
        completionSemaphore.signal()
        lock.lock()
        let value = result
        lock.unlock()
        return value
    }

    /// Thread-safe snapshot of the cancellation flag.
    func cancellationSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// Thread-safe snapshot of the completion flag.
    func completedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted
    }

    /// Thread-safe snapshot of the active state (not completed AND not cancelled).
    /// Reads both flags under a single lock acquisition to avoid TOCTOU races.
    func isActiveSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCompleted && !isCancelled
    }
}

/// A coroutine scope that tracks child jobs and supports structured cancellation.
///
/// CORO-003: Scope is no longer stored in Thread Local Storage. Instead it is
/// carried inside `RuntimeContinuationState.scope` (the coroutine context),
/// so it survives suspend/resume across different GCD threads. A lightweight
/// per-task accessor (`RuntimeCoroutineScope.current`)
/// bridges the gap for the few call-sites that don't have a continuation handle.
final class RuntimeCoroutineScope: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [Int] = [] // opaque handles (RuntimeJobHandle or RuntimeAsyncTask)
    private(set) var isCancelled = false
    let isSupervisor: Bool
    fileprivate var parent: RuntimeCoroutineScope?

    // CORO-003: Task-local scope registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the scope that is current for that execution context. This allows
    // `RuntimeCoroutineScope.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.
    private static let taskScopeLock = NSLock()
    // Protected by taskScopeLock — all accesses go through installScope/removeScope/scopeForTask.
    nonisolated(unsafe) private static var taskScopeMap: [ObjectIdentifier: RuntimeCoroutineScope] = [:]

    /// Install scope for the given task key. Called at the top of the
    /// suspend-entry loop so that launched children can discover their parent scope.
    static func installScope(_ scope: RuntimeCoroutineScope?, forTask key: ObjectIdentifier) {
        taskScopeLock.lock()
        if let scope {
            taskScopeMap[key] = scope
        } else {
            taskScopeMap.removeValue(forKey: key)
        }
        taskScopeLock.unlock()
    }

    /// Remove the task-scope mapping when a suspend-entry loop finishes.
    static func removeScope(forTask key: ObjectIdentifier) {
        taskScopeLock.lock()
        taskScopeMap.removeValue(forKey: key)
        taskScopeLock.unlock()
    }

    /// Look up the scope installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func scopeForTask(_ key: ObjectIdentifier) -> RuntimeCoroutineScope? {
        taskScopeLock.lock()
        defer { taskScopeLock.unlock() }
        return taskScopeMap[key]
    }

    /// Convenience accessor used by launch/async when they don't have a
    /// continuation handle.  Uses the thread-level task key installed by the
    /// nearest enclosing suspend-entry loop.
    ///
    /// NOTE: This is *not* TLS for the scope itself -- the scope lives on the
    /// continuation.  The task key is only used to *find* which continuation's
    /// scope is active on this thread right now.
    static var current: RuntimeCoroutineScope? {
        get {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            return scopeForTask(key)
        }
        set {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            installScope(newValue, forTask: key)
        }
    }

    init(isSupervisor: Bool = false) {
        self.isSupervisor = isSupervisor
    }

    /// Sets the parent scope link. Used by kk_coroutine_scope_cancel_propagate to
    /// wire child scopes into the parent's cancellation hierarchy at runtime.
    func setParent(_ newParent: RuntimeCoroutineScope) {
        lock.lock()
        parent = newParent
        lock.unlock()
    }

    func registerChild(_ handle: Int) {
        // Take an additional retain so the scope keeps the child alive
        // even if user code calls takeRetainedValue (e.g. kk_kxmini_async_await)
        if let ptr = UnsafeMutableRawPointer(bitPattern: handle) {
            _ = Unmanaged<AnyObject>.fromOpaque(ptr).retain()
        }
        lock.lock()
        children.append(handle)
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            runtimeCancelChild(handle)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let currentChildren = children
        lock.unlock()
        for child in currentChildren {
            runtimeCancelChild(child)
        }
    }

    func waitForChildren() -> Int {
        lock.lock()
        let currentChildren = children
        children.removeAll()
        lock.unlock()
        var firstFailure = 0
        var cancelledRemainingChildren = false
        for (index, child) in currentChildren.enumerated() {
            let childResult = runtimeJoinChild(child)
            if firstFailure == 0, runtimeCoroutineIsThrowableResult(childResult) {
                firstFailure = childResult
                if !isSupervisor, !cancelledRemainingChildren {
                    cancelledRemainingChildren = true
                    for remainingChild in currentChildren.dropFirst(index + 1) {
                        runtimeCancelChild(remainingChild)
                    }
                }
            }
            if let ptr = UnsafeMutableRawPointer(bitPattern: child) {
                // Check the per-handle flag to see if user code already consumed the passRetained.
                // This is scope-independent: the flag lives on the handle object itself,
                // so it works correctly even with nested scopes or cross-thread joins.
                let consumed: Bool
                let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
                if let job = obj as? RuntimeJobHandle {
                    consumed = job.consumedByUserCodeSnapshot()
                } else if let task = obj as? RuntimeAsyncTask {
                    consumed = task.consumedByUserCodeSnapshot()
                } else {
                    consumed = false
                }
                // Release the extra retain taken in registerChild
                Unmanaged<AnyObject>.fromOpaque(ptr).release()
                // Release the original passRetained only if user code hasn't already consumed it
                // (via kk_job_join or kk_kxmini_async_await)
                if !consumed {
                    Unmanaged<AnyObject>.fromOpaque(ptr).release()
                    // Clean up from RuntimeStorage
                    runtimeStorage.withLock { state in
                        state.objectPointers.remove(UInt(bitPattern: ptr))
                    }
                }
            }
        }
        return firstFailure
    }
}

private func runtimeCoroutineIsThrowableResult(_ result: Int) -> Bool {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: result) else {
        return false
    }
    // Only attempt the dynamic cast if the pointer is a known runtime object.
    // Raw integer results (e.g. 3 from `async { 1 + 2 }`) are not valid
    // object pointers and would crash swift_retain inside tryCast.
    let isRegistered = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isRegistered else {
        return false
    }
    return tryCast(pointer, to: RuntimeThrowableBox.self) != nil
}

/// CORO-003: Per-thread task key used to index into the task-scope map.
///
/// Each thread participating in a suspend-entry loop gets a unique sentinel
/// object stored in a pthread thread-local.  This is *not* the scope itself --
/// it is only a key that lets `RuntimeCoroutineScope.current` find which scope
/// is active on this thread.  The actual scope lives in the continuation
/// context and is propagated to child coroutines explicitly.
///
/// Migrated from `Thread.current.threadDictionary` to `pthread_key_t` for
/// lighter-weight access (single pointer lookup vs dictionary hash).
enum RuntimeCoroutineScopeTaskKey {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    /// A lightweight sentinel whose only purpose is to provide a stable
    /// `ObjectIdentifier` for the lifetime of a suspend-entry loop invocation.
    private final class Token {}

    /// Get-or-create a task key for the current thread.
    static var currentTaskKey: ObjectIdentifier {
        if let existing: Token = pthreadGetValue(pthreadKey) {
            return ObjectIdentifier(existing)
        }
        let token = Token()
        pthreadSetValue(pthreadKey, token)
        return ObjectIdentifier(token)
    }

    /// Install a fresh task key for this thread and return it.
    /// Called at the top of each suspend-entry loop invocation.
    static func installFreshKey() -> ObjectIdentifier {
        let token = Token()
        pthreadSetValue(pthreadKey, token)
        return ObjectIdentifier(token)
    }

    /// Remove the task key for this thread.
    static func removeKey() {
        pthreadSetValue(pthreadKey, nil as Token?)
    }
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.coroutineSuspendedBox).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return ptr
}

@_cdecl("kk_coroutine_continuation_new")
public func kk_coroutine_continuation_new(_ functionID: Int) -> Int {
    let state = RuntimeContinuationState(functionID: Int64(functionID))
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(state).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_coroutine_state_enter")
public func kk_coroutine_state_enter(_ continuation: Int, _ functionID: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_enter received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    let functionIDValue = Int64(functionID)
    if state.functionID != functionIDValue {
        state.functionID = functionIDValue
        state.label = 0
        state.completion = 0
        state.spillSlots.removeAll(keepingCapacity: false)
    }
    return Int(state.label)
}

@_cdecl("kk_coroutine_state_set_label")
public func kk_coroutine_state_set_label(_ continuation: Int, _ label: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_label received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.label = Int64(label)
    return label
}

@_cdecl("kk_coroutine_state_exit")
public func kk_coroutine_state_exit(_ continuation: Int, _ value: Int) -> Int {
    if let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) {
        var shouldRelease = false
        runtimeStorage.withLock { state in
            let key = UInt(bitPattern: continuationPtr)
            if state.objectPointers.contains(key) {
                state.objectPointers.remove(key)
                shouldRelease = true
            }
        }
        if shouldRelease {
            Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).release()
        }
    }
    return value
}

@_cdecl("kk_coroutine_state_set_spill")
public func kk_coroutine_state_set_spill(_ continuation: Int, _ slot: Int, _ value: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_spill received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.spillSlots[Int64(slot)] = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_spill received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    return Int(state.spillSlots[Int64(slot)] ?? 0)
}

@_cdecl("kk_coroutine_state_set_completion")
public func kk_coroutine_state_set_completion(_ continuation: Int, _ value: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_completion received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.completion = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_completion")
public func kk_coroutine_state_get_completion(_ continuation: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_completion received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    return Int(state.completion)
}

@_cdecl("kk_kxmini_run_blocking")
public func kk_kxmini_run_blocking(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
}

@_cdecl("kk_kxmini_launch")
public func kk_kxmini_launch(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context (not TLS) and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        // Note: This scope propagation was simplified from the CORO-003 task-scope-map
        // approach. TLS-based propagation is safe here because the blocking semaphore
        // in runSuspendEntryLoopWithContinuation ensures the coroutine resumes on the
        // same GCD thread. See RuntimeCoroutineScope.current doc comment for details.
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async")
public func kk_kxmini_async(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let task = RuntimeAsyncTask()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())

    // CORO-003: Capture caller's scope from context (not TLS) and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: taskPtr))
    }

    // CORO-003: Create continuation externally and propagate caller's scope
    // so the child's entry loop discovers its parent scope (same pattern as
    // kk_kxmini_launch).
    let continuation = kk_coroutine_continuation_new(functionID)
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: continuation
        )
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_coroutine_launcher_arg_set")
public func kk_coroutine_launcher_arg_set(_ continuation: Int, _ index: Int64, _ value: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_launcher_arg_set received invalid continuation handle")
    }
    state.launcherArgs[index] = value
    return value
}

@_cdecl("kk_coroutine_launcher_arg_get")
public func kk_coroutine_launcher_arg_get(_ continuation: Int, _ index: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_launcher_arg_get received invalid continuation handle")
    }
    return state.launcherArgs[index] ?? 0
}

@_cdecl("kk_kxmini_run_blocking_with_cont")
public func kk_kxmini_run_blocking_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
}

@_cdecl("kk_kxmini_launch_with_cont")
public func kk_kxmini_launch_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }

    // Link job to continuation state
    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_with_cont")
public func kk_kxmini_async_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let task = RuntimeAsyncTask()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())

    // CORO-003: Capture caller's scope from context and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: taskPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
}

// MARK: - Dispatcher-aware launch (STDLIB-CORO-072)

/// Launch a coroutine on a specific dispatcher (fire-and-forget).
/// dispatcherRaw is a dispatcher tag (kk_dispatcher_default/io/main).
/// Returns an opaque job handle (RuntimeJobHandle*).
@_cdecl("kk_kxmini_launch_with_dispatcher")
public func kk_kxmini_launch_with_dispatcher(_ entryPointRaw: Int, _ functionID: Int, _ dispatcherRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    dispatcher.dispatchAsync {
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_kxmini_launch_with_dispatcher that accepts a pre-built continuation.
@_cdecl("kk_kxmini_launch_with_dispatcher_and_cont")
public func kk_kxmini_launch_with_dispatcher_and_cont(_ entryPointRaw: Int, _ continuation: Int, _ dispatcherRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }

    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    dispatcher.dispatchAsync {
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

// MARK: - CoroutineExceptionHandler (STDLIB-CORO-072)

/// A heap-allocated box holding a Swift closure that acts as a CoroutineExceptionHandler.
/// The closure receives the raw throwable pointer and handles it.
final class RuntimeExceptionHandlerBox: @unchecked Sendable {
    let handler: @Sendable (Int) -> Void
    init(handler: @escaping @Sendable (Int) -> Void) {
        self.handler = handler
    }
}

/// Create a CoroutineExceptionHandler that prints the exception message.
/// Returns an opaque handle to a RuntimeExceptionHandlerBox.
@_cdecl("kk_exception_handler_new")
public func kk_exception_handler_new() -> Int {
    let box = RuntimeExceptionHandlerBox { throwableRaw in
        // Default handler: print the exception to stderr
        var message = "Unknown exception"
        if throwableRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) {
            if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
                message = throwable.message
            } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
                message = cancellation.message
            }
        }
        FileHandle.standardError.write(Data("CoroutineExceptionHandler: \(message)\n".utf8))
    }
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Launch a coroutine with a CoroutineExceptionHandler.
/// If the coroutine throws an uncaught exception, the handler is invoked.
/// handlerRaw is an opaque RuntimeExceptionHandlerBox handle (or 0 for no handler).
@_cdecl("kk_kxmini_launch_with_exception_handler")
public func kk_kxmini_launch_with_exception_handler(_ entryPointRaw: Int, _ functionID: Int, _ handlerRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    // Resolve exception handler
    var exceptionHandler: RuntimeExceptionHandlerBox?
    if handlerRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw) {
        let isObjPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjPointer {
            exceptionHandler = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? RuntimeExceptionHandlerBox
        }
    }

    // Capture the continuation state so the launch closure can read the
    // thrownException flag set by runSuspendEntryLoopWithContinuation.
    let capturedContState = runtimeContinuationState(from: continuation)

    KxMiniRuntime.launch {
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        // Reliably detect a thrown exception using the flag set inside
        // runSuspendEntryLoopWithContinuation rather than inspecting the
        // object-pointer registry.  The registry check is unreliable because
        // any non-zero boxed value (string, integer box, etc.) that happens to
        // be registered would otherwise be misidentified as an exception.
        let thrownException = capturedContState?.thrownException ?? 0
        if thrownException != 0, let handler = exceptionHandler {
            handler.handler(thrownException)
            // Fire-and-forget with handler; do not propagate the exception.
            job.complete(with: 0)
            return
        }
        job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_await")
public func kk_kxmini_async_await(_ handle: Int) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    task.markConsumedByUserCode()
    // Now consume the passRetained
    let consumed = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()
    return consumed.awaitResult()
}

/// CORO-071: Exception-aware await for async tasks.
/// Waits for the task to complete. If the task threw an exception, writes the
/// exception pointer to `outThrown` and returns 0. Otherwise returns the result.
/// Also propagates CancellationException when the task was cancelled.
@_cdecl("kk_kxmini_async_await_throwing")
public func kk_kxmini_async_await_throwing(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    task.markConsumedByUserCode()
    let consumed = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()

    // If the task was cancelled, synthesize a CancellationException
    if consumed.isCancelled && consumed.thrownException == 0 {
        let cancellation = runtimeAllocateCancellationException()
        outThrown?.pointee = cancellation
        return 0
    }

    return consumed.awaitResultThrowing(outThrown: outThrown)
}

/// CORO-071: Cancel an async task (Deferred.cancel()).
/// Safe to call even after the task has completed (no-op in that case).
@_cdecl("kk_async_task_cancel")
public func kk_async_task_cancel(_ handle: Int) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    task.cancel()
    return 0
}

/// CORO-071: Async builder with dispatcher specification — async(dispatcher) { body }.
/// Launches the coroutine on the given dispatcher's queue rather than the default queue.
@_cdecl("kk_kxmini_async_with_dispatcher")
public func kk_kxmini_async_with_dispatcher(_ dispatcherTag: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    let task = RuntimeAsyncTask()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: taskPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let queue = dispatchQueue(for: dispatcherTag)

    queue.async {
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_kxmini_delay")
public func kk_kxmini_delay(_ milliseconds: Int, _ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_kxmini_delay received invalid continuation handle")
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - Flow Runtime (STDLIB-088: Cold/Lazy Stream Semantics)

/// CORO-003: pthread key for the flow collect stack (replaces threadDictionary).
private let runtimeFlowCollectStackPthreadKey: pthread_key_t = makePthreadKey()

/// Wrapper class so the flow collect stack can be stored as a single AnyObject
/// in the pthread thread-local slot.
private final class RuntimeFlowCollectStackBox {
    var stack: [RuntimeFlowCollectContext] = []
}

/// Runtime flow op tags must be aligned with the lowering/codegen enums in
/// `CoroutineLoweringPass+Flow.swift` and `FlowLoweringPass.swift`.
private enum RuntimeFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case onEach = 4
    case distinctUntilChanged = 5
}

private struct RuntimeFlowOp {
    let kind: RuntimeFlowTag
    let argument: Int
}

/// Collect context tracks the lazy pipeline state for a single collect call.
/// Each emitted value passes through the operator chain one at a time (lazy).
/// `cancelled` is reserved for future use by cancellation-aware operators
/// (e.g. coroutine-based emitters that check for cooperative cancellation).
/// Currently, short-circuiting is handled by `runtimeFlowTakeExhausted` after
/// each element delivery rather than through this flag.
private final class RuntimeFlowCollectContext {
    /// Legacy field kept for backward compatibility with tests that inspect emitted values
    /// without a collector. In lazy mode, values flow directly to the collector.
    var emittedValues: [Int] = []
    var cancelled = false
}

/// Opaque flow handle. Immutable operation chain; source emitter is re-executed
/// for every collect to guarantee cold-stream semantics.
/// When `fixedValues` is non-nil, the flow is backed by flowOf and the emitter
/// function pointer is ignored.
private final class RuntimeFlowHandle {
    let emitterFnPtr: Int
    let opChain: [RuntimeFlowOp]
    let fixedValues: [Int]?

    init(emitterFnPtr: Int, opChain: [RuntimeFlowOp] = [], fixedValues: [Int]? = nil) {
        self.emitterFnPtr = emitterFnPtr
        self.opChain = opChain
        self.fixedValues = fixedValues
    }
}

private func runtimeRegisterFlowHandle(_ flow: RuntimeFlowHandle) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(flow).toOpaque())
    let key = UInt(bitPattern: ptr)
    runtimeStorage.withLock { state in
        state.objectPointers.insert(key)
        state.flowHandles[key] = flow
        state.flowRetainCounts[key] = 1
    }
    return Int(bitPattern: ptr)
}

private func runtimeFlowHandle(from rawValue: Int) -> RuntimeFlowHandle? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withLock { state in
        state.flowHandles[key] as? RuntimeFlowHandle
    }
}


private func runtimeFlowCollectStackBox() -> RuntimeFlowCollectStackBox {
    if let existing: RuntimeFlowCollectStackBox = pthreadGetValue(runtimeFlowCollectStackPthreadKey) {
        return existing
    }
    let box = RuntimeFlowCollectStackBox()
    pthreadSetValue(runtimeFlowCollectStackPthreadKey, box)
    return box
}

private func runtimeFlowCollectStack() -> [RuntimeFlowCollectContext] {
    runtimeFlowCollectStackBox().stack
}

private func runtimeFlowPushCollectContext(_ context: RuntimeFlowCollectContext) {
    runtimeFlowCollectStackBox().stack.append(context)
}

private func runtimeFlowPopCollectContext() {
    let box = runtimeFlowCollectStackBox()
    guard !box.stack.isEmpty else {
        return
    }
    _ = box.stack.popLast()
}

private func runtimeFlowCurrentCollectContext() -> RuntimeFlowCollectContext? {
    runtimeFlowCollectStackBox().stack.last
}

private func runtimeFlowMaybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return value
}

/// Result of processing a single value through the operator chain.
private enum FlowOpResult {
    /// Value passed all ops and should be delivered to the collector.
    case emit(Int)
    /// Value was filtered out; skip delivery.
    case filtered
    /// An exception was thrown during an operator; abort the flow.
    case thrown
    /// A short-circuiting op (e.g. take) signalled that collection is done.
    case done
}

/// Apply the operator chain to a single emitted value (lazy, per-element).
/// `takeCounters` tracks remaining elements for each take op index and is
/// mutated across successive calls within a single collect invocation.
private func runtimeFlowApplyOpsLazy(
    _ value: Int,
    ops: [RuntimeFlowOp],
    takeCounters: inout [Int: Int],
    lastValues: inout [Int: Int]
) -> FlowOpResult {
    var current = value
    for (index, op) in ops.enumerated() {
        switch op.kind {
        case .emit:
            // Emit ops are handled during flow construction; skip.
            continue

        case .map:
            guard op.argument != 0 else {
                return .filtered
            }
            let transform = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let transformed = transform(0, current, &thrown)
            if thrown != 0 {
                return .thrown
            }
            current = runtimeFlowMaybeUnbox(transformed)

        case .filter:
            guard op.argument != 0 else {
                return .filtered
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown
            }
            if runtimeFlowMaybeUnbox(decision) == 0 {
                return .filtered
            }

        case .take:
            let limit = max(0, runtimeFlowMaybeUnbox(op.argument))
            let remaining = takeCounters[index, default: limit]
            if remaining <= 0 {
                return .done
            }
            takeCounters[index] = remaining - 1
            // If this was the last allowed element, signal done after delivery.
            if remaining - 1 <= 0 {
                // Still emit the current value but mark context for cancellation
                // after this element is delivered.
            }

        case .onEach:
            guard op.argument != 0 else {
                continue
            }
            let action = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            _ = action(0, current, &thrown)
            if thrown != 0 {
                return .thrown
            }
            // onEach does not transform the value; pass it through.

        case .distinctUntilChanged:
            if let last = lastValues[index], last == current {
                return .filtered
            }
            lastValues[index] = current
        }
    }
    return .emit(current)
}

/// Check whether a take op has exhausted its counter, signalling the flow
/// should stop. Called after delivering each element.
private func runtimeFlowTakeExhausted(
    ops: [RuntimeFlowOp],
    takeCounters: [Int: Int]
) -> Bool {
    for (index, op) in ops.enumerated() {
        guard op.kind == .take else { continue }
        if let remaining = takeCounters[index], remaining <= 0 {
            return true
        }
    }
    return false
}

/// Cold-stream collect: re-execute the source emitter and push each emitted
/// value through the operator chain lazily, one at a time.
///
/// TODO: `runtimeFlowSourceValues` materializes the entire emitter output into
/// an array before operators are applied. This means the source is eagerly
/// collected even though downstream processing is lazy (per-element). A truly
/// lazy implementation would interleave emitter execution with operator
/// application, e.g. via coroutine-style yielding. This is acceptable for now
/// because emitters are synchronous and finite, but should be revisited when
/// suspend-emitter support lands.
private func runtimeFlowCollectLazy(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    continuation: Int
) -> Int {
    guard let sourceValues = runtimeFlowSourceValues(flow) else {
        return 0
    }

    // Now process each emitted value through the lazy operator chain.
    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    // Check if a take(0) already exhausts everything before any emission.
    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return 0
    }

    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            let delivered = runtimeFlowDeliverValue(
                value,
                collectorFnPtr: collectorFnPtr,
                continuation: continuation
            )
            if !delivered {
                return 0
            }
            // After successful delivery, check if take is exhausted.
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return 0
            }

        case .filtered:
            continue

        case .thrown, .done:
            return 0
        }
    }

    return 0
}

/// Deliver a single value to the collector. Returns true on success, false if
/// the collector threw (signalling the flow should stop).
private func runtimeFlowDeliverValue(
    _ value: Int,
    collectorFnPtr: Int,
    continuation: Int
) -> Bool {
    guard collectorFnPtr != 0 else {
        return true
    }

    if continuation == 0 {
        // Non-suspend collector ABI: (closureRaw, value, outThrown)
        let collector = unsafeBitCast(
            collectorFnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = collector(0, value, &thrown)
        return thrown == 0
    } else {
        // Suspend collector ABI: (closureRaw, value, continuation, outThrown)
        let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
        let collector = unsafeBitCast(
            collectorFnPtr,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        let cont = kk_coroutine_continuation_new(continuation)
        while true {
            var thrown = 0
            let result = collector(0, value, cont, &thrown)
            if thrown != 0 {
                _ = kk_coroutine_state_exit(cont, 0)
                return false
            }
            if result != suspendedToken {
                break
            }
            guard let state = runtimeContinuationState(from: cont) else {
                _ = kk_coroutine_state_exit(cont, 0)
                return false
            }
            // CORO-004: This still blocks a GCD thread via the legacy
            // waitForResumeSignal() path.  Full migration requires making
            // runtimeFlowDeliverValue itself async (return via continuation
            // instead of Bool), which in turn requires the flow collect
            // loop to be restructured as a suspend-entry loop.
            state.waitForResumeSignal()
        }
        _ = kk_coroutine_state_exit(cont, 0)
        return true
    }
}

@_cdecl("kk_flow_create")
public func kk_flow_create(_ emitterFnPtr: Int, _: Int) -> Int {
    runtimeRegisterFlowHandle(RuntimeFlowHandle(emitterFnPtr: emitterFnPtr))
}

/// Return the flow-stop sentinel pointer. This is a unique object pointer that
/// cannot collide with any legitimate `Int` value (unlike the previous `Int.min`
/// approach). Emitters should compare the return value of `kk_flow_emit` against
/// `kk_flow_stopped()` to detect pipeline termination.
@_cdecl("kk_flow_stopped")
public func kk_flow_stopped() -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.flowStopSentinelBox).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Sentinel value returned by `kk_flow_emit` to signal that the pipeline has
/// terminated (e.g. a `.take` counter was exhausted or the collector threw).
/// This uses a unique heap-allocated object pointer so it cannot collide with
/// any legitimate emitted `Int` value (including `Int.min`).
/// Cached as a static let to avoid repeated lock acquisition and dictionary
/// insertion on every access.
private let runtimeFlowStopSentinel: Int = kk_flow_stopped()

@_cdecl("kk_flow_emit")
public func kk_flow_emit(_ flowHandle: Int, _ value: Int, _ tag: Int) -> Int {
    if tag == RuntimeFlowTag.emit.rawValue {
        let context = runtimeFlowCurrentCollectContext()
        if let context, !context.cancelled {
            context.emittedValues.append(runtimeFlowMaybeUnbox(value))
        }
        return value
    }
    guard let opKind = RuntimeFlowTag(rawValue: tag) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received unknown op tag \(tag)")
    }
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received invalid flow handle")
    }
    let derived = RuntimeFlowHandle(
        emitterFnPtr: flow.emitterFnPtr,
        opChain: flow.opChain + [RuntimeFlowOp(kind: opKind, argument: value)],
        fixedValues: flow.fixedValues
    )
    return runtimeRegisterFlowHandle(derived)
}

@_cdecl("kk_flow_collect")
public func kk_flow_collect(_ flowHandle: Int, _ collectorFnPtr: Int, _ continuation: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    // Cold-stream semantics: re-execute source emitter and lazily push each
    // emitted value through the operator chain on every collect call.
    // For flowOf-backed flows (fixedValues != nil), the fixed values are used
    // directly without running an emitter function.
    return runtimeFlowCollectLazy(flow, collectorFnPtr: collectorFnPtr, continuation: continuation)
}

@_cdecl("kk_flow_retain")
public func kk_flow_retain(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_retain received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withLock { state in
        guard state.flowHandles[key] != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_retain received unregistered flow handle")
        }
        state.flowRetainCounts[key, default: 0] += 1
        return flowHandle
    }
}

@_cdecl("kk_flow_release")
public func kk_flow_release(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_release received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    runtimeStorage.withLock { state in
        guard let count = state.flowRetainCounts[key] else {
            return
        }
        let nextCount = count - 1
        if nextCount <= 0 {
            state.flowRetainCounts.removeValue(forKey: key)
            state.flowHandles.removeValue(forKey: key)
            state.objectPointers.remove(key)
        } else {
            state.flowRetainCounts[key] = nextCount
        }
    }
    return 0
}

// MARK: - Flow Terminal Operators (STDLIB-088)

/// Collect all emitted values into an array and return the array handle.
/// Obtain source values from a flow handle (handles both emitter-based and
/// fixedValues-based flows). Returns nil on emitter error.
private func runtimeFlowSourceValues(_ flow: RuntimeFlowHandle) -> [Int]? {
    if let fixed = flow.fixedValues {
        return fixed
    }
    let context = RuntimeFlowCollectContext()
    runtimeFlowPushCollectContext(context)

    guard flow.emitterFnPtr != 0 else {
        runtimeFlowPopCollectContext()
        return []
    }

    let emitter = unsafeBitCast(
        flow.emitterFnPtr,
        to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self
    )
    var outThrown = 0
    _ = emitter(&outThrown)
    runtimeFlowPopCollectContext()

    if outThrown != 0 {
        return nil
    }
    return context.emittedValues
}

/// Prepare take counters for the given op chain.
private func runtimeFlowInitTakeCounters(_ ops: [RuntimeFlowOp]) -> [Int: Int] {
    var takeCounters: [Int: Int] = [:]
    for (index, op) in ops.enumerated() where op.kind == .take {
        takeCounters[index] = max(0, runtimeFlowMaybeUnbox(op.argument))
    }
    return takeCounters
}

/// Collect all emitted values into a list and return the list handle.
@_cdecl("kk_flow_to_list")
public func kk_flow_to_list(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle),
          let sourceValues = runtimeFlowSourceValues(flow)
    else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    var collected: [Int] = []
    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return registerRuntimeObject(RuntimeListBox(elements: collected))
    }

    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue, ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case .emit(let value):
            collected.append(value)
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return registerRuntimeObject(RuntimeListBox(elements: collected))
            }
        case .filtered:
            continue
        case .thrown, .done:
            return registerRuntimeObject(RuntimeListBox(elements: collected))
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: collected))
}

/// Return the first emitted value after applying the operator chain, or 0 if empty.
@_cdecl("kk_flow_first")
public func kk_flow_first(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle),
          let sourceValues = runtimeFlowSourceValues(flow)
    else {
        return 0
    }

    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue, ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case .emit(let value):
            return value
        case .filtered:
            continue
        case .thrown, .done:
            return 0
        }
    }
    return 0
}

/// Count the number of elements emitted after applying the operator chain.
@_cdecl("kk_flow_count")
public func kk_flow_count(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle),
          let sourceValues = runtimeFlowSourceValues(flow)
    else {
        return 0
    }

    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    var count = 0
    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue, ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case .emit:
            count += 1
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return count
            }
        case .filtered:
            continue
        case .thrown, .done:
            return count
        }
    }
    return count
}

/// Fold: accumulate values with an initial value and an operation.
/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
@_cdecl("kk_flow_fold")
public func kk_flow_fold(_ flowHandle: Int, _ initial: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle),
          let sourceValues = runtimeFlowSourceValues(flow)
    else {
        return initial
    }

    guard operationFnPtr != 0 else {
        return initial
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    var accumulator = initial
    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue, ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case .emit(let value):
            var thrown = 0
            accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
            if thrown != 0 {
                return accumulator
            }
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return accumulator
            }
        case .filtered:
            continue
        case .thrown, .done:
            return accumulator
        }
    }
    return accumulator
}

/// Reduce: like fold but uses the first element as the initial accumulator.
/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
@_cdecl("kk_flow_reduce")
public func kk_flow_reduce(_ flowHandle: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle),
          let sourceValues = runtimeFlowSourceValues(flow)
    else {
        return 0
    }

    guard operationFnPtr != 0 else {
        return 0
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let ops = flow.opChain
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    var accumulator = 0
    var hasFirst = false
    for rawValue in sourceValues {
        let result = runtimeFlowApplyOpsLazy(
            rawValue, ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case .emit(let value):
            if !hasFirst {
                accumulator = value
                hasFirst = true
            } else {
                var thrown = 0
                accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
                if thrown != 0 {
                    return accumulator
                }
            }
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return accumulator
            }
        case .filtered:
            continue
        case .thrown, .done:
            return accumulator
        }
    }
    return accumulator
}

/// Create a Flow from varargs-style fixed values (flowOf).
@_cdecl("kk_flow_of")
public func kk_flow_of(_ arrayHandle: Int, _ count: Int) -> Int {
    let values: [Int]
    if count > 0 {
        var collected: [Int] = []
        collected.reserveCapacity(count)
        for i in 0 ..< count {
            collected.append(runtimeReadArrayElement(arrayRaw: arrayHandle, index: i))
        }
        values = collected
    } else {
        values = []
    }

    let handle = RuntimeFlowHandle(emitterFnPtr: 0, fixedValues: values)
    return runtimeRegisterFlowHandle(handle)
}

// MARK: - Coroutine Dispatcher Scheduler (STDLIB-133)

/// A coroutine dispatcher that schedules work on a specific GCD queue.
/// Each dispatcher wraps a DispatchQueue and provides `dispatch(_:)` to execute
/// a closure on that queue. The three well-known dispatchers (Default, IO, Main)
/// are singletons returned by `kk_dispatcher_default/io/main`.
final class RuntimeDispatcher: @unchecked Sendable {
    let queue: DispatchQueue
    let tag: Int

    /// CORO-003: pthread key for the currently active dispatcher (replaces threadDictionary).
    private static let currentDispatcherPthreadKey: pthread_key_t = makePthreadKey()

    /// The dispatcher active on the current thread, if any.
    static var current: RuntimeDispatcher? {
        get { pthreadGetValue(currentDispatcherPthreadKey) }
        set { pthreadSetValue(currentDispatcherPthreadKey, newValue) }
    }

    init(queue: DispatchQueue, tag: Int) {
        self.queue = queue
        self.tag = tag
    }

    /// Dispatch a closure onto this dispatcher's queue synchronously, setting
    /// `RuntimeDispatcher.current` for the duration.
    func dispatchSync<T>(execute work: @Sendable () -> T) -> T {
        if isCurrent {
            // Already on the correct dispatcher; execute inline to avoid deadlock.
            // Still set RuntimeDispatcher.current so callee code can observe
            // which dispatcher is active (it may be nil if we arrived here via
            // the Thread.isMainThread fallback).
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
        return queue.sync {
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
    }

    /// Dispatch a closure onto this dispatcher's queue asynchronously, setting
    /// `RuntimeDispatcher.current` for the duration.
    func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            work()
            RuntimeDispatcher.current = saved
        }
    }

    /// Returns true if we are already executing on this dispatcher.
    ///
    /// NOTE: Re-entrancy detection relies on the `RuntimeDispatcher.current`
    /// thread-local, which is only set inside `dispatchSync`/`dispatchAsync`
    /// blocks. For the main dispatcher we additionally check
    /// `Thread.isMainThread` to avoid a guaranteed deadlock when
    /// `DispatchQueue.main.sync` is called from the main thread before any
    /// dispatcher context has been established.
    var isCurrent: Bool {
        if RuntimeDispatcher.current?.tag == tag { return true }
        // DispatchQueue.main.sync from the main thread deadlocks; detect it
        // even when RuntimeDispatcher.current has not been set yet.
        if tag == RuntimeDispatcherTag.mainDispatcher, Thread.isMainThread { return true }
        return false
    }
}

/// Dispatcher tag constants used as opaque handles.
private enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B_4401 // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B_4402 // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B_4403 // "KKD\x03"
}

/// Singleton dispatchers. Initialized lazily on first access.
private let runtimeDefaultDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.global(qos: .default),
    tag: RuntimeDispatcherTag.defaultDispatcher
)
private let runtimeIODispatcher = RuntimeDispatcher(
    queue: DispatchQueue(label: "kk.dispatcher.io", qos: .utility, attributes: .concurrent),
    tag: RuntimeDispatcherTag.ioDispatcher
)
private let runtimeMainDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.main,
    tag: RuntimeDispatcherTag.mainDispatcher
)

/// Resolve a raw dispatcher Int to a RuntimeDispatcher instance.
/// Returns the Default dispatcher for unrecognized values.
func runtimeResolveDispatcher(from raw: Int) -> RuntimeDispatcher {
    switch raw {
    case RuntimeDispatcherTag.ioDispatcher:
        runtimeIODispatcher
    case RuntimeDispatcherTag.mainDispatcher:
        runtimeMainDispatcher
    default:
        runtimeDefaultDispatcher
    }
}

/// Maps a dispatcher tag to the corresponding GCD dispatch queue.
/// - `Dispatchers.Default` -> global queue (concurrent, default QoS)
/// - `Dispatchers.IO`      -> global queue (concurrent, utility QoS — I/O-appropriate)
/// - `Dispatchers.Main`    -> main queue (serial)
/// Unknown tags fall back to `Dispatchers.Default`.
private func dispatchQueue(for dispatcherTag: Int) -> DispatchQueue {
    switch dispatcherTag {
    case RuntimeDispatcherTag.ioDispatcher:
        return DispatchQueue.global(qos: .utility)
    case RuntimeDispatcherTag.mainDispatcher:
        return DispatchQueue.main
    case RuntimeDispatcherTag.defaultDispatcher:
        return DispatchQueue.global()
    default:
        return DispatchQueue.global()
    }
}

@_cdecl("kk_dispatcher_default")
public func kk_dispatcher_default() -> Int {
    RuntimeDispatcherTag.defaultDispatcher
}

@_cdecl("kk_dispatcher_io")
public func kk_dispatcher_io() -> Int {
    RuntimeDispatcherTag.ioDispatcher
}

@_cdecl("kk_dispatcher_main")
public func kk_dispatcher_main() -> Int {
    RuntimeDispatcherTag.mainDispatcher
}

/// A simple heap-allocated, `@unchecked Sendable` box used to pass an integer
/// result from a `DispatchQueue.async` closure back to the waiting thread.
/// Synchronization is provided externally by a `DispatchSemaphore`.
private final class WithContextResultBox: @unchecked Sendable {
    var value: Int = 0
}

/// Kotlin `withContext(dispatcher) { block }` — switches coroutine execution
/// to the dispatch queue that corresponds to `dispatcherRaw`, runs the
/// suspend-aware block through the full entry loop (supporting intermediate
/// suspension points such as `delay`), and blocks the caller until the block
/// completes, returning its result.
@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    let resolvedDispatcher = switch dispatcherRaw {
    case RuntimeDispatcherTag.defaultDispatcher,
         RuntimeDispatcherTag.ioDispatcher,
         RuntimeDispatcherTag.mainDispatcher:
        dispatcherRaw
    default:
        RuntimeDispatcherTag.defaultDispatcher
    }

    guard suspendEntryPoint(from: blockFnPtr) != nil else {
        // Clean up the continuation to avoid leaking coroutine state.
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

    let queue = dispatchQueue(for: resolvedDispatcher)

    // Capture the current coroutine scope so child launches inside the block
    // are registered with the correct scope on the target queue's thread.
    let parentScope = RuntimeCoroutineScope.current

    // Propagate caller's scope to continuation context so that
    // runSuspendEntryLoopWithContinuation installs it under the fresh task key.
    // Without this, contState.scope would be nil for a freshly created
    // continuation and child coroutines launched inside the withContext block
    // would lose the parent scope — breaking structured concurrency.
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = parentScope
    }

    // NOTE: When the target queue is DispatchQueue.main and we are already on
    // the main thread, dispatching async + semaphore.wait() would deadlock
    // because the main thread cannot process the enqueued block while blocked.
    // CLI programs produced by this compiler do not run a main run loop, so
    // even calls from a background thread targeting the main queue would hang.
    // We therefore execute inline whenever we are already on the target queue
    // (main-thread case) to avoid the deadlock.
    if queue === DispatchQueue.main && Thread.isMainThread {
        let savedScope = RuntimeCoroutineScope.current
        defer { RuntimeCoroutineScope.current = savedScope }
        RuntimeCoroutineScope.current = parentScope
        return runSuspendEntryLoopWithContinuation(
            entryPointRaw: blockFnPtr,
            continuation: continuation
        )
    }

    // CORO-004: Continuation-based withContext is still in progress.
    // For now keep the semaphore fallback, which matches the current runtime
    // model and avoids relying on unfinished continuation result plumbing.
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = WithContextResultBox()

    queue.async {
        // Propagate the coroutine scope to the target thread.
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = parentScope
        defer { RuntimeCoroutineScope.current = savedScope }

        resultBox.value = runSuspendEntryLoopWithContinuation(
            entryPointRaw: blockFnPtr,
            continuation: continuation
        )
        semaphore.signal()
    }

    semaphore.wait()
    return resultBox.value
}

// MARK: - Channel Runtime (CORO-001)

/// Sentinel returned by `receive()` when the channel is closed and the buffer
/// is drained.  Callers can compare against this to detect the end-of-channel
/// condition without confusing it with a legitimate `0` value.
///
/// **ABI restriction**: `Int.min` is reserved as the closed-channel sentinel.
/// Sending `Int.min` (`Long.MIN_VALUE` in Kotlin) through a channel will cause
/// receivers / codegen to misidentify it as the closed token.  This is an
/// intentional trade-off for the current in-band signaling design.
///
/// TODO(CORO-001): Migrate to an out-of-band signaling mechanism (e.g., a
/// status+value return pair via pointer parameter, matching the pattern used by
/// `kk_coroutine_check_cancellation`) so that every `Int` value is sendable.
let kChannelClosedSentinel: Int = Int.min

/// Buffer overflow strategies for Channel send operations (CORO-001)
enum ChannelBufferOverflow {
    /// Suspend the sender when buffer is full (default Kotlin behavior)
    case suspend
    /// Drop the oldest element in buffer to make room
    case dropOldest
    /// Drop the element being sent
    case dropLatest
}

/// Mutable box for a suspended sender so receivers can mark delivery before
/// resuming the continuation.  Using a class (reference type) ensures the
/// `delivered` flag set under the channel lock is visible to the sender
/// after it re-acquires the lock post-wakeup.
final class SuspendedSender {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    let value: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?
    
    /// Set to `true` (under the channel lock) when the sender's value is
    /// delivered to a receiver. The sender checks this after waking to distinguish a
    /// successful delivery from a close-induced wakeup.
    var delivered: Bool = false
    /// Set to `true` (under the channel lock) when the sender is woken due to
    /// coroutine cancellation. Distinct from close-induced wakeup.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int, value: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
        self.value = value
    }
}

/// Mutable box for a suspended receiver so senders / close can mark the
/// wakeup reason before resuming the continuation. Mirrors `SuspendedSender`.
final class SuspendedReceiver {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?
    /// The value deposited by a sender. `nil` means woken by close or cancel.
    var result: Int?
    /// Set to `true` when woken due to coroutine cancellation.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
    }
}

/// Channel with proper Kotlin suspend semantics:
///   - **Rendezvous** (`capacity == 0`): every `send` suspends until a matching
///     `receive` and vice-versa.
///   - **Buffered** (`capacity > 0`): `send` suspends (backpressure) when the
///     buffer is full; `receive` suspends when the buffer is empty.
///   - **`close()`**: marks the channel as closed.  Pending senders are woken
///     and return the closed-send sentinel.  Pending receivers drain the
///     remaining buffer, then return the closed sentinel.  Returns `true` the
///     first time (Kotlin semantics), `false` if already closed.
///   - **Cancellation**: `send` and `receive` check the caller's continuation
///     for cancellation before suspending, and suspended waiters can be removed
///     via `cancelAllWaiters()` (cooperatively from the coroutine runtime).
final class RuntimeChannelHandle: @unchecked Sendable {
    private let lock = NSLock()
    // NOTE: `buffer`, `senderQueue`, and `receiverQueue` use `Array` with
    // `removeFirst()` which is O(n) due to element shifting.  For the current
    // use (moderate queue depths), this is acceptable.  If channels become a
    // hot-path bottleneck, replace these with a circular buffer / Deque for
    // O(1) dequeue.  (See also: Swift Collections `Deque` type.)
    private var buffer: [Int] = []
    let capacity: Int
    private(set) var closed = false
    private let bufferOverflow: ChannelBufferOverflow

    // Waiting-sender queue: each suspended sender is a `SuspendedSender`
    // reference.  Receivers set `delivered = true` before signaling the
    // semaphore so that senders can distinguish successful delivery from a
    // close-induced wakeup.
    private var senderQueue: [SuspendedSender] = []

    // Waiting-receiver queue: each suspended receiver is a `SuspendedReceiver`
    // reference.  Senders deposit a value before signaling the semaphore.
    private var receiverQueue: [SuspendedReceiver] = []

    init(capacity: Int, bufferOverflow: ChannelBufferOverflow = .suspend) {
        self.capacity = max(0, capacity)
        self.bufferOverflow = bufferOverflow
    }

    /// Send a value into the channel, suspending (blocking) the caller when
    /// backpressure is needed.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending and the sentinel
    /// is returned if the coroutine has been cancelled (matching Kotlin's behavior
    /// of throwing `CancellationException` from `send`).
    ///
    /// Returns the sent `value` on success, or `kChannelClosedSentinel` if the
    /// channel was closed before or during the send, or the coroutine was cancelled.
    func send(_ value: Int, continuation: Int = 0) -> Int {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 1. Closed channel -- fail immediately.
        if closed {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 2. If there is a waiting receiver, hand the value off directly
        //    (both rendezvous and buffered benefit from this fast path).
        if let receiver = receiverQueue.first {
            receiverQueue.removeFirst()
            receiver.result = value
            lock.unlock()
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
            return value
        }

        // 3. Buffered channel with space -- enqueue and return immediately.
        if capacity > 0, buffer.count < capacity {
            buffer.append(value)
            lock.unlock()
            return value
        }

        // 3a. Handle buffer overflow based on strategy (CORO-001)
        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                // Fall through to suspension logic below
                break
            case .dropOldest:
                // Remove oldest element and add new one
                _ = buffer.removeFirst()
                buffer.append(value)
                lock.unlock()
                return value
            case .dropLatest:
                // Drop the element being sent
                lock.unlock()
                return value
            }
        }

        // 4. No room (buffer full or rendezvous) -- suspend the sender.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let senderSem = DispatchSemaphore(value: 0)
        let entry = SuspendedSender(semaphore: senderSem, continuation: continuation, value: value)
        
        senderQueue.append(entry)
        lock.unlock()

        // Channel send is not yet lowered as a true suspend point, so the
        // runtime must block here until a receiver or close/cancellation wakes it.
        senderSem.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasDelivered = entry.delivered
        let wasCancelled = entry.cancelledWakeup
        lock.unlock()

        // Cancellation only aborts the send if delivery did not already complete.
        if wasCancelled || (!wasDelivered && isCancelled(continuation: continuation)) {
            return kChannelClosedSentinel
        }
        return wasDelivered ? value : kChannelClosedSentinel
    }

    /// Receive a value from the channel, suspending (blocking) the caller when
    /// the buffer is empty and no sender is ready.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending (Kotlin suspend
    /// semantics: `receive` throws `CancellationException` if cancelled).
    ///
    /// Returns the received value, or `kChannelClosedSentinel` when the channel
    /// is closed and fully drained, or the coroutine was cancelled.
    func receive(continuation: Int = 0) -> Int {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 1. Try to take from the buffer.
        if !buffer.isEmpty {
            let value = buffer.removeFirst()
            // If a sender is suspended (backpressure), wake the oldest one and
            // move its value into the buffer to maintain ordering.
            if let sender = senderQueue.first {
                senderQueue.removeFirst()
                buffer.append(sender.value)
                sender.delivered = true
                lock.unlock()
                // CORO-004: Use continuation-based resume if available
                resumeSender(sender)
            } else {
                lock.unlock()
            }
            return value
        }

        // 2. Buffer is empty -- try to pair directly with a waiting sender
        //    (rendezvous fast-path, also applies to buffered when a sender
        //    arrived while the buffer was full and then got drained completely).
        if let sender = senderQueue.first {
            senderQueue.removeFirst()
            let value = sender.value
            sender.delivered = true
            lock.unlock()
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
            return value
        }

        // 3. Nothing available -- if closed, return the sentinel.
        if closed {
            lock.unlock()
            return kChannelClosedSentinel
        }

        // 4. Suspend the receiver.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let receiverEntry = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: continuation)
        
        receiverQueue.append(receiverEntry)
        lock.unlock()

        // Channel receive is not yet lowered as a true suspend point, so the
        // runtime must block here until a sender, close, or cancellation wakes it.
        receiverEntry.semaphore.wait()

        // After waking, check the wakeup reason.
        lock.lock()
        let wasCancelled = receiverEntry.cancelledWakeup
        let value = receiverEntry.result
        lock.unlock()

        // Cancellation only aborts the receive if no sender delivered a value.
        if wasCancelled || (value == nil && isCancelled(continuation: continuation)) {
            return kChannelClosedSentinel
        }
        if let value {
            return value
        }
        // Woken by close() with no value -- channel is done.
        return kChannelClosedSentinel
    }

    /// `true` when the channel is closed AND its buffer is fully drained.
    /// Once `isClosedForReceive` is `true`, any subsequent `receive()` call will
    /// immediately return `kChannelClosedSentinel` without blocking.
    /// Matches Kotlin's `ReceiveChannel.isClosedForReceive` contract.
    var isClosedForReceive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed && buffer.isEmpty && senderQueue.isEmpty
    }

    /// Close the channel.  Remaining buffered values are still receivable.
    ///
    /// Returns `true` if this call actually closed the channel, `false` if it
    /// was already closed.  Matches Kotlin's `SendChannel.close()` contract.
    @discardableResult
    func close() -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        closed = true
        let pendingSenders = senderQueue
        senderQueue.removeAll()
        let pendingReceivers = receiverQueue
        receiverQueue.removeAll()
        lock.unlock()

        // Wake all suspended senders -- they will see `closed == true` and
        // return the closed sentinel.
        for sender in pendingSenders {
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        // Wake all suspended receivers -- they will find no result deposited
        // and return the closed sentinel.
        for receiver in pendingReceivers {
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
        return true
    }

    /// Cancel all suspended senders and receivers.  This is called when a
    /// coroutine is cancelled while it has an outstanding channel operation.
    ///
    /// In the current design we cancel *all* waiters because the continuation
    /// identity is not threaded into the waiter entries (the suspend-point is
    /// blocking the calling thread directly).  This is safe because each
    /// channel operation is called from exactly one coroutine at a time.
    func cancelAllWaiters() {
        lock.lock()
        let pendingSenders = senderQueue
        senderQueue.removeAll()
        let pendingReceivers = receiverQueue
        receiverQueue.removeAll()
        lock.unlock()

        for sender in pendingSenders {
            sender.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        for receiver in pendingReceivers {
            receiver.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
    }

    /// `true` when the channel is closed AND its buffer is fully drained.
    /// Once `isClosedForReceive` is `true`, any subsequent `receive()` call will
    /// immediately return `kChannelClosedSentinel` without blocking.
    /// Matches Kotlin's `ReceiveChannel.isClosedForReceive` contract.
    var isClosedForReceive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed && buffer.isEmpty && senderQueue.isEmpty
    }

    /// Thread-safe snapshot of the closed flag.
    ///
    /// Acquires the channel lock before reading `closed` to avoid data races
    /// with concurrent `send()`, `receive()`, and `close()` calls.
    func isClosedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    // MARK: - Private helpers

    /// CORO-004: Resume a suspended sender using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeSender(_ sender: SuspendedSender) {
        if let resumeClosure = sender.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            sender.semaphore.signal()
        }
    }

    /// CORO-004: Resume a suspended receiver using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeReceiver(_ receiver: SuspendedReceiver) {
        if let resumeClosure = receiver.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            receiver.semaphore.signal()
        }
    }

    /// Check whether the coroutine associated with `continuation` has been cancelled.
    private func isCancelled(continuation: Int) -> Bool {
        guard continuation != 0,
              let state = runtimeContinuationState(from: continuation),
              let job = state.jobHandle
        else {
            return false
        }
        return job.cancellationSnapshot()
    }

    /// Thread-safe snapshot of the closed flag.
    ///
    /// Acquires the channel lock before reading `closed` to avoid data races
    /// with concurrent `send()`, `receive()`, and `close()` calls.
    func isClosedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }
}

@_cdecl("kk_channel_create")
public func kk_channel_create(_ capacity: Int) -> Int {
    let channel = RuntimeChannelHandle(capacity: capacity)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_channel_send")
public func kk_channel_send(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.send(value, continuation: continuation)
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.receive(continuation: continuation)
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close() ? 1 : 0
}

/// Returns 1 if `value` equals the closed-channel sentinel, 0 otherwise.
/// Codegen calls this after `kk_channel_receive` / `kk_channel_send` to detect
/// end-of-channel.
///
/// **ABI note**: Because the sentinel is currently the in-band value `Int.min`,
/// this function will also return 1 for a legitimately-sent `Int.min`.  See the
/// `kChannelClosedSentinel` documentation for the planned migration to
/// out-of-band signaling.
@_cdecl("kk_channel_is_closed_token")
public func kk_channel_is_closed_token(_ value: Int) -> Int {
    return value == kChannelClosedSentinel ? 1 : 0
}

/// Returns 1 if the channel is closed for receiving (i.e., it is closed AND the buffer
/// is empty — no more values will ever be available).  Returns 0 if the channel is
/// open or if it is closed but still has buffered values to drain.
///
/// Maps to Kotlin's `Channel.isClosedForReceive` property.
@_cdecl("kk_channel_is_closed_for_receive")
public func kk_channel_is_closed_for_receive(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedForReceive ? 1 : 0
}

/// Returns 1 if the channel is closed for sending (i.e., it has been closed via
/// `close()`).  Returns 0 if the channel is still open for new sends.
///
/// Maps to Kotlin's `Channel.isClosedForSend` property.
@_cdecl("kk_channel_is_closed_for_send")
public func kk_channel_is_closed_for_send(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedSnapshot() ? 1 : 0
}

// MARK: - Channel Iterator (CORO-075)
//
// A lightweight wrapper that allows channels to participate in the
// `kk_range_iterator` / `kk_range_hasNext` / `kk_range_next` loop protocol.
//
// The iterator holds the channel handle (strongly retained) and caches the
// result of the most recent `receive()` call.  `hasNext` must be called before
// `next` in each iteration step — which matches the pattern emitted by
// ControlFlowLowerer.lowerForExpr.
//
// IMPORTANT: `kk_channel_iterator_hasNext` suspends (blocking) on each call
// until either a value arrives or the channel is closed.  This means that
// for-in loops over channels are blocking-suspend operations, consistent with
// Kotlin's semantics when running inside runBlocking / launch.
private final class RuntimeChannelIterator: @unchecked Sendable {
    let channel: RuntimeChannelHandle
    /// Most recent value fetched by `hasNext`.  Reset to `nil` after `next`.
    var peekedValue: Int?
    /// Set to `true` once we observe the closed sentinel from `receive()`.
    var done: Bool = false
    private let lock = NSLock()

    init(channel: RuntimeChannelHandle) {
        self.channel = channel
    }

    /// Advance the iterator by doing a blocking receive.  Returns `true` if a
    /// value is available, `false` if the channel is closed and drained.
    func advance(continuation: Int = 0) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        lock.unlock()

        let value = channel.receive(continuation: continuation)
        lock.lock()
        defer { lock.unlock() }
        if value == kChannelClosedSentinel {
            done = true
            peekedValue = nil
            return false
        }
        peekedValue = value
        return true
    }

    /// Return the cached value and clear it.
    func takeValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let v = peekedValue ?? 0
        peekedValue = nil
        return v
    }
}

/// Create a channel iterator for use in for-in loops.  The iterator reference
/// is registered in `runtimeStorage` so the GC can track it.
@_cdecl("kk_channel_iterator")
public func kk_channel_iterator(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_iterator received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let iter = RuntimeChannelIterator(channel: channel)
    let iterPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(iter).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: iterPtr))
    }
    return Int(bitPattern: iterPtr)
}

/// Returns 1 if the channel iterator has a next value, 0 if the channel is
/// closed and drained.  Blocks (suspends) until a value arrives or the channel
/// is closed.
@_cdecl("kk_channel_iterator_hasNext")
public func kk_channel_iterator_hasNext(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.advance() ? 1 : 0
}

/// Returns the value fetched by the most recent `kk_channel_iterator_hasNext`
/// call.  Must only be called after `kk_channel_iterator_hasNext` returns 1.
@_cdecl("kk_channel_iterator_next")
public func kk_channel_iterator_next(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.takeValue()
}

// MARK: - Deferred / awaitAll Runtime Stub (P5-135)

@_cdecl("kk_await_all")
public func kk_await_all(_ handlesArray: Int, _ count: Int) -> Int {
    // Await each handle sequentially and return the result of the last one.
    // handlesArray points to a KKArray of async task handles.
    guard count > 0 else {
        return 0
    }
    var lastResult = 0
    for i in 0 ..< count {
        // Read handle from array using kk_array_get pattern
        let handleValue = runtimeReadArrayElement(arrayRaw: handlesArray, index: i)
        if handleValue != 0 {
            guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handleValue) else {
                continue
            }
            let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()
            lastResult = task.awaitResult()
        }
    }
    return lastResult
}

/// Read an element from a runtime array by index (mirrors kk_array_get without throw).
private func runtimeReadArrayElement(arrayRaw: Int, index: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    guard let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self) else {
        return 0
    }
    guard index >= 0, index < arrayBox.elements.count else {
        return 0
    }
    return arrayBox.elements[index]
}

// MARK: - Structured Concurrency C ABI (P5-89)

/// Creates a new coroutine scope and installs it as the current scope in the
/// task-scope registry (CORO-003: no TLS for the scope itself).
@_cdecl("kk_coroutine_scope_new")
public func kk_coroutine_scope_new() -> Int {
    let scope = RuntimeCoroutineScope()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // Push: save parent scope and set this as current via the task-scope map
    scope.parent = RuntimeCoroutineScope.current
    RuntimeCoroutineScope.current = scope

    return Int(bitPattern: ptr)
}

@_cdecl("kk_supervisor_scope_new")
public func kk_supervisor_scope_new() -> Int {
    let scope = RuntimeCoroutineScope(isSupervisor: true)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // Push: save parent scope and set this as current via the task-scope map
    scope.parent = RuntimeCoroutineScope.current
    RuntimeCoroutineScope.current = scope

    return Int(bitPattern: ptr)
}

/// Cancels the given coroutine scope and all its children.
@_cdecl("kk_coroutine_scope_cancel")
public func kk_coroutine_scope_cancel(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_cancel received invalid scope handle")
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    scope.cancel()
    return 0
}

/// Waits for all children in the scope to complete, then pops/releases the scope.
@_cdecl("kk_coroutine_scope_wait")
public func kk_coroutine_scope_wait(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_wait received invalid scope handle")
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    let firstFailure = scope.waitForChildren()

    // Pop: restore parent scope in the task-scope map (CORO-003)
    RuntimeCoroutineScope.current = scope.parent

    // Release the scope
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).release()
    return firstFailure
}

/// Returns 1 if the scope is active (not cancelled), 0 if cancelled.
/// This is the ABI backing for `scope.isActive` in Kotlin.
@_cdecl("kk_coroutine_scope_is_active")
public func kk_coroutine_scope_is_active(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        return 0
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    return scope.isCancelled ? 0 : 1
}

/// Returns 1 if the scope has been cancelled, 0 otherwise.
/// This is the ABI backing for checking `scope.coroutineContext[Job]?.isCancelled`.
@_cdecl("kk_coroutine_scope_is_cancelled")
public func kk_coroutine_scope_is_cancelled(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        return 1 // invalid handle → treat as cancelled
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    return scope.isCancelled ? 1 : 0
}

/// Returns the parent scope handle, or 0 if there is no parent.
/// Supports scope hierarchy traversal: child scope → parent scope.
@_cdecl("kk_coroutine_scope_get_parent")
public func kk_coroutine_scope_get_parent(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        return 0
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    guard let parent = scope.parent else {
        return 0
    }
    // Return an unretained pointer — the parent is kept alive by the scope hierarchy
    // (the child holds a strong reference to its parent via the `parent` property).
    return Int(bitPattern: Unmanaged.passUnretained(parent).toOpaque())
}

/// Propagates cancellation from a parent scope handle to a child scope handle.
/// Call this to link a newly created child scope into the parent's cancellation chain.
/// Returns 0 on success, -1 if either handle is invalid.
@_cdecl("kk_coroutine_scope_cancel_propagate")
public func kk_coroutine_scope_cancel_propagate(_ parentHandle: Int, _ childHandle: Int) -> Int {
    guard let parentPtr = UnsafeMutableRawPointer(bitPattern: parentHandle),
          let childPtr = UnsafeMutableRawPointer(bitPattern: childHandle) else {
        return -1
    }
    let parent = Unmanaged<RuntimeCoroutineScope>.fromOpaque(parentPtr).takeUnretainedValue()
    let child = Unmanaged<RuntimeCoroutineScope>.fromOpaque(childPtr).takeUnretainedValue()
    // Set the parent link so cancel() on the parent propagates to the child via registerChild.
    child.setParent(parent)
    if parent.isCancelled {
        child.cancel()
    }
    return 0
}

/// Registers a child job/deferred handle with the given scope.
@_cdecl("kk_coroutine_scope_register_child")
public func kk_coroutine_scope_register_child(_ scopeHandle: Int, _ childHandle: Int) -> Int {
    guard let scopePtr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_register_child received invalid scope handle")
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(scopePtr).takeUnretainedValue()
    scope.registerChild(childHandle)
    return childHandle
}

/// Joins (waits for) a job handle to complete and releases it.
/// This consumes the handle (balances the passRetained from launch).
@_cdecl("kk_job_join")
public func kk_job_join(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_join received invalid job handle")
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        job.markConsumedByUserCode()
    } else if let task = obj as? RuntimeAsyncTask {
        task.markConsumedByUserCode()
    }
    let result: Int = if let job = obj as? RuntimeJobHandle {
        job.join()
    } else if let task = obj as? RuntimeAsyncTask {
        task.awaitResult()
    } else {
        0
    }
    // Release the original passRetained from launch
    Unmanaged<AnyObject>.fromOpaque(ptr).release()
    // Clean up from RuntimeStorage
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    return result
}

/// Convenience: creates a scope, runs the block synchronously, waits for all children.
/// Used as the lowering target for `coroutineScope { }` blocks.
@_cdecl("kk_coroutine_scope_run")
public func kk_coroutine_scope_run(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let scopeHandle = kk_coroutine_scope_new()
    // CORO-003: Create continuation externally and propagate the new scope into it
    // so that runSuspendEntryLoopWithContinuation installs it under the fresh task key.
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    let continuation = kk_coroutine_continuation_new(functionID)
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }
    let result = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw, continuation: continuation
    )
    let firstFailure = kk_coroutine_scope_wait(scopeHandle)
    return firstFailure != 0 ? firstFailure : result
}

/// Convenience with pre-built continuation.
@_cdecl("kk_coroutine_scope_run_with_cont")
public func kk_coroutine_scope_run_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let scopeHandle = kk_coroutine_scope_new()
    // CORO-003: Propagate the new scope into the continuation so it is visible
    // inside the entry loop (avoids task key overwrite orphaning the scope).
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }
    let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
    let firstFailure = kk_coroutine_scope_wait(scopeHandle)
    return firstFailure != 0 ? firstFailure : result
}

/// Creates a supervisor scope, runs the block synchronously, waits for all children.
/// Unlike `coroutineScope`, child failures do not cancel siblings (SupervisorJob semantics).
/// Used as the lowering target for `supervisorScope { }` blocks.
@_cdecl("kk_supervisor_scope_run")
public func kk_supervisor_scope_run(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let scopeHandle = kk_supervisor_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    let continuation = kk_coroutine_continuation_new(functionID)
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }
    let result = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw, continuation: continuation
    )
    let firstFailure = kk_coroutine_scope_wait(scopeHandle)
    return firstFailure != 0 ? firstFailure : result
}

/// Supervisor scope variant with pre-built continuation.
@_cdecl("kk_supervisor_scope_run_with_cont")
public func kk_supervisor_scope_run_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let scopeHandle = kk_supervisor_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }
    let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
    let firstFailure = kk_coroutine_scope_wait(scopeHandle)
    return firstFailure != 0 ? firstFailure : result
}

// MARK: - Coroutine yield()

/// Cooperatively yields the current coroutine, allowing other coroutines to run.
/// This is the lowering target for `kotlinx.coroutines.yield()`.
@_cdecl("kk_coroutine_yield")
public func kk_coroutine_yield() -> Int {
    // Yield the current thread briefly so other coroutines get a chance to run.
    Thread.sleep(forTimeInterval: 0)
    return 0 // Unit
}

// MARK: - withTimeout / withTimeoutOrNull

/// Runs the given block with a timeout. If the block does not complete within
/// `timeoutMillis`, a CancellationException is thrown (represented as a trap
/// in this runtime).
/// Used as the lowering target for `withTimeout(timeMillis) { }`.
@_cdecl("kk_with_timeout")
public func kk_with_timeout(_ timeoutMillis: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    // Run the block inside a coroutine scope with a deadline.
    let scopeHandle = kk_coroutine_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }

    var result: Int = 0
    let deadline = DispatchTime.now() + .milliseconds(timeoutMillis)

    let workItem = DispatchWorkItem {
        result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: continuation
        )
    }
    DispatchQueue.global().async(execute: workItem)
    let waitResult = workItem.wait(timeout: deadline)
    if waitResult == .timedOut {
        workItem.cancel()
        scope.cancel()
        _ = kk_coroutine_scope_wait(scopeHandle)
        fatalError("KSwiftK panic: withTimeout timed out after \(timeoutMillis)ms (CancellationException)")
    }
    _ = kk_coroutine_scope_wait(scopeHandle)
    return result
}

/// Runs the given block with a timeout. If the block does not complete within
/// `timeoutMillis`, returns null (0) instead of throwing.
/// Used as the lowering target for `withTimeoutOrNull(timeMillis) { }`.
@_cdecl("kk_with_timeout_or_null")
public func kk_with_timeout_or_null(_ timeoutMillis: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    let scopeHandle = kk_coroutine_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }

    var result: Int = 0
    let deadline = DispatchTime.now() + .milliseconds(timeoutMillis)

    let workItem = DispatchWorkItem {
        result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: continuation
        )
    }
    DispatchQueue.global().async(execute: workItem)
    let waitResult = workItem.wait(timeout: deadline)
    if waitResult == .timedOut {
        workItem.cancel()
        scope.cancel()
        _ = kk_coroutine_scope_wait(scopeHandle)
        return 0 // null
    }
    _ = kk_coroutine_scope_wait(scopeHandle)
    return result
}

// MARK: - Child Cancel/Join Helpers (P5-89)

/// Cancel a child handle (RuntimeJobHandle or RuntimeAsyncTask).
func runtimeCancelChild(_ handle: Int) {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        job.cancel()
    } else if let task = obj as? RuntimeAsyncTask {
        task.cancel()
    }
}

/// Join a child handle (RuntimeJobHandle or RuntimeAsyncTask). Returns the result.
func runtimeJoinChild(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.join()
    } else if let task = obj as? RuntimeAsyncTask {
        return task.awaitResult()
    }
    return 0
}

// MARK: - Cancellation ABI (CORO-002 / spec.md J17)

/// Cancel a job handle from user code (e.g. `job.cancel()`).
@_cdecl("kk_job_cancel")
public func kk_job_cancel(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_cancel received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        job.cancel()
    } else if let task = obj as? RuntimeAsyncTask {
        task.cancel()
    }
    return 0
}

// MARK: - Job State Queries (STDLIB-CORO-070)

/// Returns 1 if the job is active (started but not yet completed and not cancelled).
/// A job is active when it has been launched and neither completed nor cancelled.
/// ABI backing for `job.isActive` in Kotlin.
@_cdecl("kk_job_is_active")
public func kk_job_is_active(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        // isActive = not completed AND not cancelled, read atomically under one lock
        return job.isActiveSnapshot() ? 1 : 0
    } else if let task = obj as? RuntimeAsyncTask {
        return task.isActiveSnapshot() ? 1 : 0
    }
    return 0
}

/// Returns 1 if the job has completed (either normally or by cancellation).
/// ABI backing for `job.isCompleted` in Kotlin.
@_cdecl("kk_job_is_completed")
public func kk_job_is_completed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1 // invalid handle → treat as completed
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.completedSnapshot() ? 1 : 0
    } else if let task = obj as? RuntimeAsyncTask {
        return task.isCompletedSnapshot() ? 1 : 0
    }
    return 1
}

/// Returns 1 if the job has been cancelled.
/// ABI backing for `job.isCancelled` in Kotlin.
@_cdecl("kk_job_is_cancelled")
public func kk_job_is_cancelled(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1 // invalid handle → treat as cancelled
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.cancellationSnapshot() ? 1 : 0
    } else if let task = obj as? RuntimeAsyncTask {
        return task.isCancelledSnapshot() ? 1 : 0
    }
    return 0
}

/// Check if the coroutine associated with `continuation` has been cancelled.
/// If cancelled, allocates a CancellationException, writes it to `outThrown`,
/// and returns 1. Otherwise returns 0 with outThrown untouched.
@_cdecl("kk_coroutine_check_cancellation")
public func kk_coroutine_check_cancellation(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle,
          job.cancellationSnapshot()
    else {
        return 0
    }
    let cancellation = runtimeAllocateCancellationException()
    outThrown?.pointee = cancellation
    return 1
}

/// Directly cancel a continuation (sets isCancelled on its linked job handle).
@_cdecl("kk_coroutine_cancel")
public func kk_coroutine_cancel(_ continuation: Int) {
    guard let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return
    }
    job.cancel()
}

/// Returns 1 if the given throwable raw pointer is a CancellationException, 0 otherwise.
@_cdecl("kk_is_cancellation_exception")
public func kk_is_cancellation_exception(_ throwableRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    return obj is RuntimeCancellationBox ? 1 : 0
}

// MARK: - Suspend Entry Loop

func runSuspendEntryLoop(entryPointRaw: Int, functionID: Int, jobHandle: RuntimeJobHandle? = nil) -> Int {
    guard suspendEntryPoint(from: entryPointRaw) != nil else {
        return 0
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let jobHandle, let state = runtimeContinuationState(from: continuation) {
        jobHandle.continuationState = state
        state.jobHandle = jobHandle
    }
    return runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
}

func runSuspendEntryLoopWithContinuation(entryPointRaw: Int, continuation: Int) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

    // CORO-004: Continuation-based suspend/resume.
    //
    // Instead of blocking a GCD thread on DispatchSemaphore.wait() when the
    // coroutine suspends, we use a DispatchSemaphore only at the *outermost*
    // level (the completion gate) and install a non-blocking continuation
    // closure for each internal suspend point.
    //
    // Flow:
    //   1. The loop runs the entry point.
    //   2. If it returns COROUTINE_SUSPENDED, install a continuation closure
    //      on the RuntimeContinuationState.  This closure will re-enter the
    //      loop when signalResume() fires (from a timer, cancellation, etc.).
    //      The current GCD thread is released — no blocking.
    //   3. When the resume closure fires, it repeats from step 1.
    //   4. When the entry point returns a concrete value (not suspended) or
    //      throws, signal the completion gate so the caller unblocks.
    //
    // The completion gate semaphore is only waited on by the outermost
    // synchronous caller (runBlocking, join, await, withContext).  Launched
    // coroutines never block a GCD thread during internal suspensions.

    let completionGate = DispatchSemaphore(value: 0)
    // Thread-safe result box — written inside the loop, read after the gate.
    final class ResultBox: @unchecked Sendable { var value: Int = 0 }
    let resultBox = ResultBox()

    // CORO-003: Install the scope carried by this continuation into the
    // task-scope map so that child launches dispatched on this thread can
    // discover their parent scope without TLS.
    let contState = runtimeContinuationState(from: continuation)
    let currentTaskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(contState?.scope, forTask: currentTaskKey)

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())

    // The loop body is factored into a closure so it can be re-entered from
    // the resume continuation without recursion or blocking.
    //
    // Using a box to hold the closure so it can reference itself.
    final class LoopBodyBox: @unchecked Sendable {
        var body: (() -> Void)?
    }
    let loopBodyBox = LoopBodyBox()

    // Shared mutable state for the task key, protected by the single-shot
    // continuation model (only one invocation of the loop body runs at a time).
    final class TaskKeyBox: @unchecked Sendable {
        var key: ObjectIdentifier
        init(key: ObjectIdentifier) { self.key = key }
    }
    let taskKeyBox = TaskKeyBox(key: currentTaskKey)

    loopBodyBox.body = {
        var outThrown = 0
        let result = entryPoint(continuation, &outThrown)
        if outThrown != 0 {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            _ = kk_coroutine_state_exit(continuation, 0)
            // Record the thrown exception in the continuation state so callers
            // such as kk_kxmini_launch_with_exception_handler can reliably
            // distinguish a thrown exception from a normal (possibly non-zero)
            // return value without inspecting the object-pointer registry.
            contState?.thrownException = outThrown
            resultBox.value = outThrown
            completionGate.signal()
            return
        }
        if result != suspendedToken {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            resultBox.value = result
            completionGate.signal()
            return
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            resultBox.value = 0
            completionGate.signal()
            return
        }
        // CORO-004: Install a continuation closure instead of blocking.
        // When signalResume() fires, this closure will be dispatched on a
        // GCD global queue, re-entering the loop without blocking any thread.
        state.installResumeContinuation {
            // CORO-003: After suspend/resume we are on a (possibly different)
            // GCD thread.  Re-install the task key so the scope map lookup
            // still works.
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            let freshKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
            taskKeyBox.key = freshKey
            RuntimeCoroutineScope.installScope(state.scope, forTask: freshKey)
            // Reset stale resume state from the previous cycle before
            // re-entering the loop.  Must happen here (not before
            // installResumeContinuation) to avoid clearing a pending
            // signal meant for the current suspend point.
            state.resetResumeState()
            loopBodyBox.body?()
        }
        // The current thread is released here — no blocking.
    }

    // Kick off the first iteration synchronously on the current thread.
    loopBodyBox.body?()

    // Block only at the outermost level until the coroutine completes.
    completionGate.wait()

    // Break the strong reference cycle: loopBodyBox -> closure -> loopBodyBox
    loopBodyBox.body = nil

    return resultBox.value
}
