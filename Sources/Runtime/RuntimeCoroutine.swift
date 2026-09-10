import Dispatch
import Foundation

// MARK: - Lightweight pthread-based Thread-Local Storage (CORO-003)
//
// These helpers replace `Thread.current.threadDictionary` lookups with direct
// `pthread_key_t` thread-locals.  Each key stores an `Unmanaged` pointer to a
// Swift class instance.  A destructor callback releases the object when the
// thread exits, so there are no leaks.

/// Create a `pthread_key_t` with a destructor that releases the stored object.
func makePthreadKey() -> pthread_key_t {
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
func pthreadGetValue<T: AnyObject>(_ key: pthread_key_t) -> T? {
    guard let raw = pthread_getspecific(key) else { return nil }
    return Unmanaged<T>.fromOpaque(raw).takeUnretainedValue()
}

/// Store `value` under `key` for the current thread, releasing any previous value.
func pthreadSetValue<T: AnyObject>(_ key: pthread_key_t, _ value: T?) {
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

/// Identifier of a suspend-entry-loop invocation ("task").
///
/// Values are drawn from a global monotonic counter and are never reused, so a
/// map entry that outlives the invocation it belongs to (the async path leaves
/// entries in place for the resume-continuation chain) can never be picked up
/// by a later, unrelated invocation. An `ObjectIdentifier` of a per-invocation
/// token cannot give that guarantee: the allocator reuses the address of a
/// deallocated token, which silently aliases the two invocations and makes
/// `RuntimeContinuationState.current` / `RuntimeCoroutineScope.current` resolve
/// to another coroutine's state.
struct RuntimeTaskKey: Hashable, Sendable {
    let rawValue: UInt64

    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextRawValue: UInt64 = 1

    static func makeUnique() -> RuntimeTaskKey {
        lock.lock()
        let value = nextRawValue
        nextRawValue &+= 1
        lock.unlock()
        return RuntimeTaskKey(rawValue: value)
    }
}

/// Per-thread holder of the current task key. The key itself is a plain value;
/// this box only provides pthread-TLS storage for it.
private final class RuntimeTaskKeyBox {
    let key: RuntimeTaskKey

    init(key: RuntimeTaskKey) {
        self.key = key
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

private final class RuntimeCallbackContinuation: KKContinuation, @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    private let resumeWithRaw: Int

    init(contextRaw: Int, resumeWithRaw: Int) {
        self.context = UnsafeMutableRawPointer(bitPattern: contextRaw)
        self.resumeWithRaw = resumeWithRaw
    }

    func resumeWith(_ result: UnsafeMutableRawPointer?) {
        var thrown = 0
        _ = kk_function_invoke(resumeWithRaw, Int(bitPattern: result), &thrown)
        if thrown != 0 {
            _ = kk_native_processUnhandledException(thrown, nil)
        }
    }
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
// [DONE] RuntimeAsyncTask.awaitResult() and RuntimeJobHandle.join() (CORO-004,
//        Phase 2): suspend-aware via kk_kxmini_async_await / kk_job_join /
//        kk_job_await_completion.  When a caller continuation is supplied, they
//        register a completion resumer (addCompletionResumer / addJoinResumer)
//        and return the coroutine-suspended sentinel instead of blocking; the
//        awaiting coroutine is resumed when the task/job completes (normally,
//        exceptionally, or via cancel).  The lowering treats these callees as
//        suspend points and injects the caller continuation.  The blocking
//        awaitResult()/join() paths remain only as the continuation==0 fallback
//        used by non-suspend contexts (e.g. structured-concurrency child joins).
//        RuntimeAsyncTask no longer uses a task-level `ready` semaphore;
//        completion is delivered exclusively through completionResumers, and
//        sync awaitResult() blocks on a per-waiter gate registered via
//        addCompletionResumer.
//
// [TODO] runtimeFlowDeliverValue (RuntimeCoroutineFlow.swift): the suspend
//        collector path still blocks via waitForResumeSignal().  Full
//        migration requires making runtimeFlowDeliverValue itself async
//        (return via continuation instead of Bool) and restructuring the
//        flow collect loop as a suspend-entry loop.
//
// [DONE] kk_with_context (RuntimeCoroutineContext.swift): caller-blocking
//        semaphore removed for the IO/Default dispatcher path.  When called
//        from inside a coroutine, RuntimeContinuationState.current is captured
//        before the dispatch; the dispatched block calls callerState.resume()
//        on completion, releasing the caller's GCD thread immediately.
//        The non-coroutine fallback (runBlocking top-level, tests) retains the
//        semaphore for backward compatibility.
//
// [TODO] Channel send/receive (RuntimeCoroutineChannel.swift): functionally
//        correct but still blocks on the per-waiter DispatchSemaphore.  The
//        resumeClosure scaffolding exists in SuspendedSender/SuspendedReceiver
//        but is not wired, and the lowering passes continuation=0.  Migration:
//        wire resumeClosure and replace the continuation=0 placeholder with the
//        real caller continuation.  This is the most complex migration because
//        channels involve two independent parties (sender/receiver), each of
//        which may be a coroutine or a raw thread, plus post-wakeup state
//        inspection (delivered / result / cancelledWakeup).
//
// [DEBT-CORO-002 PHASE 1 DONE] RuntimeTypes.swift —
//        RuntimeSequenceCoroutine / RuntimeIteratorBuilderBox: producer now runs
//        on a dedicated OS Thread (Thread.detachNewThread) instead of a GCD
//        pool thread.  Only one thread blocks per iteration step (the consumer);
//        the GCD pool is no longer occupied by the producer between yields.
//        Each type exposes invokeBuilderLambda() for the next phase.
//
// [DEBT-CORO-002 PHASE 2 DONE] RuntimeTypes.swift / RuntimeSequenceBuilders.swift —
//        Consumer-side suspension infrastructure is wired and covered for both
//        runtime types.  Activation from generated code is still pending.
//
//        RuntimeIteratorBuilderBox: probeHasNextAsync(callerState:) installs a
//        resume continuation in consumerGate so no GCD thread is held while the
//        producer runs.  New C entry points __kk_iterator_builder_hasNext_coro /
//        __kk_iterator_builder_next_coro expose this for coroutine-aware callers.
//        Existing __kk_iterator_builder_hasNext / __kk_iterator_builder_next are
//        unchanged — callers do not yet check for COROUTINE_SUSPENDED.
//
//        RuntimeSequenceCoroutine: awaitProducerYieldAsync(callerState:) and
//        nextElementAsync(callerState:) provide the same non-blocking consumer
//        path.  End-of-sequence is signalled via kk_sequence_completed_sentinel()
//        (backed by runtimeStorage.sequenceCompletedBox).  Not yet wired to
//        runtimeTraverseSequenceWithState; that function must become
//        suspension-aware to activate this path.
//
// [DEBT-CORO-002 PHASE 3 DONE] RuntimeTypes.swift / RuntimeSequenceBuilders.swift /
//        CoroutineLoweringPass.swift — compiler-generated sequence/iterator
//        builders now route through kk_*_builder_build_coro.  yield() returns
//        COROUTINE_SUSPENDED from the builder body and the consumer resumes the
//        stored continuation on demand, so generated producers no longer need a
//        dedicated thread.  The old Thread-backed entry points remain as a
//        compatibility fallback for direct non-CPS runtime callbacks/tests.
//
// Priority order (remaining): Channel > flow
// (await/join completed in Phase 2; withContext completed in Phase 3.)

// MARK: - CORO-004: Cooperative Sync Gate

/// One-shot gate for cooperative producer/consumer synchronization.
///
/// Used by lazy sequence/iterator builders during the CORO-004 migration.
/// Supports non-blocking resume via a continuation closure (for suspend-point
/// wiring) with a `DispatchSemaphore` fallback for legacy synchronous callers.
final class RuntimeCoroutineSyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumeContinuation: RuntimeResumeContinuationBox?
    private var fallbackSemaphore: DispatchSemaphore?
    private var signalPending = false

    /// Wake a waiter. Prefer an installed continuation (async dispatch) over a
    /// fallback semaphore signal.
    func signal() {
        lock.lock()
        if let cont = resumeContinuation {
            resumeContinuation = nil
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async {
                cont.invoke()
            }
            return
        }
        if let sem = fallbackSemaphore {
            lock.unlock()
            sem.signal()
            return
        }
        signalPending = true
        lock.unlock()
    }

    /// Wait until `signal()`.
    ///
    /// When `resumeContinuation` is provided, installs it instead of blocking
    /// the current thread and returns `true`. Returns `false` when the wait was
    /// satisfied synchronously (pending signal or semaphore wakeup).
    @discardableResult
    func wait(resumeContinuation continuation: (@Sendable () -> Void)? = nil) -> Bool {
        lock.lock()
        if signalPending {
            signalPending = false
            lock.unlock()
            return false
        }
        if let continuation {
            resumeContinuation = RuntimeResumeContinuationBox(continuation)
            lock.unlock()
            return true
        }
        if fallbackSemaphore == nil {
            fallbackSemaphore = DispatchSemaphore(value: 0)
        }
        let sem = fallbackSemaphore!
        lock.unlock()
        sem.wait()
        return false
    }
}

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
    /// Flow collect context carried with the continuation so a flow emitter can
    /// continue delivering values after a suspend/resume on another thread.
    var flowCollectContext: RuntimeFlowCollectContext?
    /// Stores a thrown exception pointer when the coroutine body throws.
    /// Zero means no exception was thrown.  Set by runSuspendEntryLoopWithContinuation
    /// and consumed by kk_kxmini_launch_with_exception_handler to reliably
    /// distinguish exception returns from normal (possibly non-zero) return values.
    var thrownException: Int = 0
    private var uninterceptedEntryPointRaw: Int = 0
    private var uninterceptedCompletionContinuation: Int = 0
    private var hasStartedUninterceptedCoroutine = false
    private let stateLock = NSLock()
    /// STDLIB-CORO-BUG-01: one-shot resume guard.
    /// Set to `true` atomically (under `stateLock`) by the first successful resume
    /// so that any subsequent resume call is rejected with an `IllegalStateException`.
    /// Reset by `resetResumeState()` when the coroutine advances to the next suspend point.
    private var hasResumed: Bool = false
    private var delayTimers: [ObjectIdentifier: DispatchSourceTimer]
    private static let taskStateLock = NSLock()
    nonisolated(unsafe) private static var taskStateMap: [RuntimeTaskKey: RuntimeContinuationState] = [:]

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

    // CORO-003: Task-local continuation state registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the continuation state that is current for that execution context. This allows
    // `RuntimeContinuationState.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.

    /// Install continuation state for the given task key. Called at the top of the
    /// suspend-entry loop so that suspend function calls can discover the current state.
    static func installState(_ state: RuntimeContinuationState?, forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the task-state mapping when a suspend-entry loop finishes.
    static func removeState(forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
    }

    /// Look up the continuation state installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func stateForTask(_ key: RuntimeTaskKey) -> RuntimeContinuationState? {
        taskStateLock.lock()
        defer { taskStateLock.unlock() }
        return taskStateMap[key]
    }

    /// Convenience accessor used by suspend function invocations when they don't have a
    /// continuation handle. Uses the thread-level task key installed by the
    /// nearest enclosing suspend-entry loop.
    ///
    /// NOTE: This is *not* TLS for the state itself -- the state lives on the
    /// continuation. The task key is only used to *find* which continuation's
    /// state is active on this thread right now.
    static var current: RuntimeContinuationState? {
        get {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            return stateForTask(key)
        }
        set {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            installState(newValue, forTask: key)
        }
    }

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
        RuntimeLiveHandles.register(self)
    }

    func configureUninterceptedCoroutine(entryPointRaw: Int, completionContinuation: Int) {
        stateLock.lock()
        self.uninterceptedEntryPointRaw = entryPointRaw
        self.uninterceptedCompletionContinuation = completionContinuation
        self.hasStartedUninterceptedCoroutine = false
        stateLock.unlock()
    }

    func takeUninterceptedCoroutineStart() -> (entryPointRaw: Int, completionContinuation: Int)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard uninterceptedEntryPointRaw != 0, !hasStartedUninterceptedCoroutine else {
            return nil
        }
        hasStartedUninterceptedCoroutine = true
        return (
            entryPointRaw: uninterceptedEntryPointRaw,
            completionContinuation: uninterceptedCompletionContinuation
        )
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
        let timers = releaseAllDelayTimers()
        for timer in timers {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    /// Install the current continuation state for the given task key.
    static func installCurrent(_ state: RuntimeContinuationState?, forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the current continuation state for the given task key.
    static func removeCurrent(forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
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

    /// Resume the continuation with a successful value.
    ///
    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    @discardableResult
    func resume(with value: Int) -> Int? {
        stateLock.lock()
        if hasResumed {
            stateLock.unlock()
            let ise = runtimeAllocateIllegalStateException(
                message: "Already resumed, but proposed with update \(value)"
            )
            return ise
        }
        hasResumed = true
        completion = Int64(value)
        thrownException = 0
        stateLock.unlock()
        signalResume()
        return nil
    }

    /// Resume the continuation with a thrown exception.
    ///
    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    @discardableResult
    func resume(withException exception: Int) -> Int? {
        stateLock.lock()
        if hasResumed {
            stateLock.unlock()
            let ise = runtimeAllocateIllegalStateException(
                message: "Already resumed, but proposed with exception"
            )
            return ise
        }
        hasResumed = true
        completion = 0
        thrownException = exception
        stateLock.unlock()
        signalResume()
        return nil
    }

    /// Deliver a double-resume `IllegalStateException` so that the coroutine body
    /// observes the violation the next time it reads state.  Overwrites `thrownException`
    /// and resets `completion` to 0.  Called by C-level entry points when the one-shot
    /// guard fires (STDLIB-CORO-BUG-01).
    func deliverDoubleResumeException(_ ise: Int) {
        stateLock.lock()
        thrownException = ise
        completion = 0
        stateLock.unlock()
    }

    func makeContinuationContext() -> RuntimeCoroutineContext {
        let jobRaw: Int = jobHandle.map { Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained($0).toOpaque())) } ?? 0
        return RuntimeCoroutineContext(
            dispatcher: 0,
            name: scope?.name,
            exceptionHandler: nil,
            jobHandleRaw: jobRaw
        )
    }

    /// Reset resume state for the next suspend point.  Called after the
    /// coroutine loop resumes to prepare for the next potential suspension.
    /// Also resets the one-shot guard (STDLIB-CORO-BUG-01) so the next
    /// suspend point can accept a fresh resume.
    func resetResumeState() {
        stateLock.lock()
        resumeContinuation = nil
        fallbackSemaphore = nil
        resumeSignalPending = false
        hasResumed = false
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

/// CORO-004: Outcome of a suspend-aware task await.
enum RuntimeTaskAwaitOutcome: Equatable {
    /// Task finished (already complete, or blocking wait returned).
    case completed(result: Int, thrownException: Int)
    /// Registered a completion resumer; the caller must return `kk_coroutine_suspended()`.
    case suspended
}

private final class RuntimeTaskAwaitSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Int = 0
    private var thrownException: Int = 0

    func store(result: Int, thrownException: Int) {
        lock.lock()
        self.result = result
        self.thrownException = thrownException
        lock.unlock()
    }

    func load() -> RuntimeTaskAwaitOutcome {
        lock.lock()
        let value = result
        let thrown = thrownException
        lock.unlock()
        return .completed(result: value, thrownException: thrown)
    }
}

final class RuntimeAsyncTask: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0
    /// Stores a thrown exception (as a raw pointer Int) when the async body fails.
    /// Zero means no exception was thrown.
    private(set) var thrownException: Int = 0
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_kxmini_async_await or kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false
    /// Set when the async body is actually scheduled (`KxMiniRuntime.launch` / dispatcher queue).
    /// Keeps `kk_job_is_active` aligned with `RuntimeJobHandle` (inactive until `markStarted`).
    private var isBodyStarted = false
    /// CORO-004: Resumers invoked with (result, thrownException) when the task completes
    /// (normally, exceptionally, or via cancel). Suspend-aware awaiters
    /// (`kk_kxmini_async_await`) and the synchronous `awaitResult()` fallback both
    /// register here so completion never blocks on a task-level semaphore.
    private var completionResumers: [@Sendable (Int, Int) -> Void] = []

    init() {
        RuntimeLiveHandles.register(self)
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    /// CORO-004: Register a resumer invoked when this task completes. If the task is
    /// already complete, the resumer runs immediately on the calling thread.
    func addCompletionResumer(_ resumer: @escaping @Sendable (Int, Int) -> Void) {
        lock.lock()
        if isCompleted {
            let snapshotResult = result
            let snapshotThrown = thrownException
            lock.unlock()
            resumer(snapshotResult, snapshotThrown)
            return
        }
        completionResumers.append(resumer)
        lock.unlock()
    }

    func markStarted() {
        lock.lock()
        isBodyStarted = true
        lock.unlock()
    }

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

    /// Thread-safe snapshot of the active state (started, not completed, not cancelled).
    func isActiveSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isBodyStarted && !isCompleted && !isCancelled
    }

    /// Thread-safe snapshot for `kk_job_is_failed` (aligned with `RuntimeJobHandle.isFailedSnapshot`).
    func isFailedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted && thrownException != 0
    }

    func complete(with result: Int) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        self.result = result
        isCompleted = true
        let resumers = completionResumers
        completionResumers = []
        lock.unlock()
        for resumer in resumers {
            resumer(result, 0)
        }
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
        let resumers = completionResumers
        completionResumers = []
        lock.unlock()
        for resumer in resumers {
            resumer(0, exception)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let wasCompleted = isCompleted
        if !wasCompleted {
            isCompleted = true
        }
        let resumers = wasCompleted ? [] : completionResumers
        if !wasCompleted {
            completionResumers = []
        }
        let snapshotResult = result
        let snapshotThrown = thrownException
        lock.unlock()
        if !wasCompleted {
            for resumer in resumers {
                resumer(snapshotResult, snapshotThrown)
            }
        }
    }

    /// CORO-004: Await the task result, optionally suspending via `callerState`.
    ///
    /// When `callerState` is non-nil and the task has not completed yet, registers a
    /// completion resumer and returns `.suspended` instead of blocking a GCD thread.
    /// `afterResume` runs after the caller continuation is resumed (e.g. to release a
    /// passRetained handle). Pass `callerState: nil` for the blocking fallback used by
    /// non-suspend contexts (structured-concurrency child joins, `kk_await_all`, etc.).
    func awaitResult(
        callerState: RuntimeContinuationState?,
        afterResume: (@Sendable () -> Void)? = nil
    ) -> RuntimeTaskAwaitOutcome {
        lock.lock()
        if isCompleted {
            let value = result
            let thrown = thrownException
            lock.unlock()
            if thrown != 0, let callerState {
                // Already completed exceptionally: resume the caller's continuation
                // with the exception and report suspension so the state machine
                // throws after it returns.
                _ = callerState.resume(withException: thrown)
                return .suspended
            }
            return .completed(result: value, thrownException: thrown)
        }
        lock.unlock()

        if let callerState {
            addCompletionResumer { result, thrown in
                if thrown != 0 {
                    callerState.resume(withException: thrown)
                } else {
                    callerState.resume(with: result)
                }
                afterResume?()
            }
            return .suspended
        }

        // BUG-041: blocking fallback (see RuntimeJobHandle.join()) -- flush
        // undispatched launches from this thread before the gate.wait() below
        // so a task that's still pending in RuntimePendingLaunchQueue actually
        // gets a chance to run and signal completion.
        RuntimePendingLaunchQueue.flush()
        let gate = DispatchSemaphore(value: 0)
        let snapshot = RuntimeTaskAwaitSnapshot()
        addCompletionResumer { result, thrown in
            snapshot.store(result: result, thrownException: thrown)
            gate.signal()
        }
        gate.wait()
        return snapshot.load()
    }

    /// Blocking await for non-suspend contexts. Suspend-aware awaiting is handled by
    /// `awaitResult(callerState:afterResume:)` (CORO-004); see `kk_kxmini_async_await`.
    func awaitResult() -> Int {
        switch awaitResult(callerState: nil) {
        case .completed(let result, let thrown):
            return thrown != 0 ? thrown : result
        case .suspended:
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: blocking awaitResult cannot suspend")
        }
    }

}

// MARK: - Structured Concurrency (P5-89)

private enum RuntimeJobState: Equatable, Sendable {
    case new
    case active
    case completing
    case completed
    case cancelling
    case cancelled
    case failed

    var isCompleted: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .new, .active, .completing, .cancelling:
            return false
        }
    }

    var isCancelled: Bool {
        switch self {
        case .cancelling, .cancelled:
            return true
        case .new, .active, .completing, .completed, .failed:
            return false
        }
    }

    var isActive: Bool {
        self == .active
    }
}

/// Per-task key for the current job handle. Mirrors the scope task-key bridge.
enum RuntimeJobHandleTaskKey {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    static var currentTaskKey: RuntimeTaskKey {
        if let existing: RuntimeTaskKeyBox = pthreadGetValue(pthreadKey) {
            return existing.key
        }
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

}

/// BUG-041 fix: tracks whether the current thread is synchronously inside a
/// `runSuspendEntryLoopWithContinuation` burst (running compiled Kotlin
/// coroutine body code), as opposed to a raw/host call straight into a
/// `kk_kxmini_*` entry point (e.g. white-box runtime tests that call
/// `kk_kxmini_launch` directly and never suspend or join anything). Only the
/// former can race a synchronous `cancel()` against the dispatch queue --
/// there's no "next yield" to defer to for the latter, so deferring
/// unconditionally would leave those launches stranded forever.
///
/// A depth counter (not a flag) so a burst that itself synchronously drives a
/// nested `runSuspendEntryLoopWithContinuation` (e.g. a nested `runBlocking`)
/// doesn't have the inner call's exit clear the outer burst's "active" status
/// early.
enum RuntimeCoroutineBurstDepth {
    private static let pthreadKey: pthread_key_t = makePthreadKey()
    private final class Box: @unchecked Sendable { var depth: Int = 0 }

    private static func currentBox() -> Box {
        if let existing: Box = pthreadGetValue(pthreadKey) {
            return existing
        }
        let box = Box()
        pthreadSetValue(pthreadKey, box)
        return box
    }

    static func enter() { currentBox().depth += 1 }
    static func exit() { let box = currentBox(); box.depth = max(0, box.depth - 1) }
    static var isActive: Bool { currentBox().depth > 0 }
}

/// BUG-041 fix: defers the real GCD dispatch of a launched job's work item
/// until the enqueuing thread's current synchronous burst actually yields
/// (the next suspension or completion inside `runSuspendEntryLoopWithContinuation`).
///
/// Real kotlinx.coroutines schedules a freshly `launch`-ed child onto the same
/// single-threaded event loop as its parent, so the child never gets a turn to
/// run until the parent suspends or finishes. `DispatchQueue.global()` gives
/// this runtime true OS-thread parallelism instead, so without this queue a
/// pool thread can start running the child (and observe "not yet cancelled")
/// before a synchronous, same-thread `job.cancel()` right after `launch{}`
/// takes effect -- the exact race in BUG-041. Deferring dispatch until this
/// thread's burst yields makes that race impossible: a `cancel()` called
/// before the next yield always finds the job still undispatched.
enum RuntimePendingLaunchQueue {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    private final class Box: @unchecked Sendable {
        var items: [(job: RuntimeJobHandle, workItem: DispatchWorkItem)] = []
    }

    private static func currentBox() -> Box {
        if let existing: Box = pthreadGetValue(pthreadKey) {
            return existing
        }
        let box = Box()
        pthreadSetValue(pthreadKey, box)
        return box
    }

    /// Queue `workItem` for dispatch on this thread's next `flush()` -- unless
    /// there's no active burst to flush it at (a direct, non-coroutine call),
    /// in which case there's no race to close and it's dispatched right away.
    static func enqueue(job: RuntimeJobHandle, workItem: DispatchWorkItem) {
        guard RuntimeCoroutineBurstDepth.isActive else {
            KxMiniRuntime.launch(workItem: workItem)
            return
        }
        currentBox().items.append((job, workItem))
    }

    /// Dispatch every work item queued on this thread since the last flush.
    /// Jobs already cancelled while pending are dropped instead of dispatched --
    /// equivalent to `DispatchWorkItem.cancel()` winning before the block runs.
    static func flush() {
        let box = currentBox()
        guard !box.items.isEmpty else { return }
        let pending = box.items
        box.items = []
        for entry in pending where !entry.job.cancellationSnapshot() {
            KxMiniRuntime.launch(workItem: entry.workItem)
        }
    }
}

/// A job handle representing a launched coroutine. Supports join, cancellation,
/// explicit completion, and parent-child propagation.
final class RuntimeJobHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var state: RuntimeJobState = .new
    private var result: Int = 0
    private var failure: Int = 0
    private var cancelCause: Int = 0
    private var cancelMessage: String = "CancellationException"
    weak var continuationState: RuntimeContinuationState?
    private var childJobHandles: [Int] = []
    /// Set on the handle returned by `kotlinx.coroutines.SupervisorJob()`. Lets
    /// `CoroutineScope(context)` (see `kk_coroutine_scope_new_with_context`) tell a plain
    /// `Job()` in the context apart from a `SupervisorJob()`, so the constructed scope gets
    /// the right sibling-failure-isolation semantics.
    var isSupervisorMarker = false
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false
    /// The underlying dispatch work item for fire-and-forget launches. Kept weak
    /// so that cancellation can prevent the body from starting when the job is
    /// cancelled before the dispatched closure begins.
    weak var dispatchWorkItem: DispatchWorkItem? = nil
    /// Distinguishes a scheduled active job from one whose body has begun.
    /// Cancellation can complete the former immediately when its work item is
    /// cancelled before execution starts.
    private var hasStartedExecuting = false
    /// CORO-004: Resumers invoked with the terminal value when the job completes.
    /// Lets a suspend-aware `Job.join()` caller resume via its continuation instead
    /// of blocking a GCD thread on `completionSemaphore`.
    private var joinResumers: [@Sendable (Int) -> Void] = []
    /// STDLIB-CORO-001: Closure that dispatches the body for CoroutineStart.LAZY.
    /// Set when `kk_kxmini_launch_lazy` returns; `startIfNeeded()` runs it once.
    private var lazyStartBody: (@Sendable () -> Void)?

    init() {
        RuntimeLiveHandles.register(self)
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    static var current: RuntimeJobHandle? {
        get {
            let key = RuntimeJobHandleTaskKey.currentTaskKey
            return currentForTask(key)
        }
        set {
            let key = RuntimeJobHandleTaskKey.currentTaskKey
            installCurrent(newValue, forTask: key)
        }
    }

    private static let taskJobLock = NSLock()
    nonisolated(unsafe) private static var taskJobMap: [RuntimeTaskKey: RuntimeJobHandle] = [:]

    private static func installCurrent(_ job: RuntimeJobHandle?, forTask key: RuntimeTaskKey) {
        taskJobLock.lock()
        if let job {
            taskJobMap[key] = job
        } else {
            taskJobMap.removeValue(forKey: key)
        }
        taskJobLock.unlock()
    }

    private static func currentForTask(_ key: RuntimeTaskKey) -> RuntimeJobHandle? {
        taskJobLock.lock()
        defer { taskJobLock.unlock() }
        return taskJobMap[key]
    }

    func markStarted() {
        lock.lock()
        hasStartedExecuting = true
        if state == .new {
            state = .active
        }
        lock.unlock()
    }

    /// Publishes the active state as soon as launch returns, before the
    /// dispatch queue gets a chance to run the body.
    func markScheduled() {
        lock.lock()
        if state == .new {
            state = .active
        }
        lock.unlock()
    }

    /// STDLIB-CORO-001: Capture the deferred-start action for a LAZY job.
    func installLazyStartBody(_ body: @escaping @Sendable () -> Void) {
        lock.lock()
        if state == .new {
            lazyStartBody = body
        }
        lock.unlock()
    }

    /// STDLIB-CORO-001: Start a LAZY job by dispatching its body exactly once.
    func startIfNeeded() {
        lock.lock()
        guard state == .new, let body = lazyStartBody else {
            lock.unlock()
            return
        }
        lazyStartBody = nil
        lock.unlock()
        body()
    }

    func registerChild(_ childHandle: Int) {
        lock.lock()
        childJobHandles.append(childHandle)
        let shouldCancelImmediately = state.isCancelled
        lock.unlock()
        if shouldCancelImmediately {
            runtimeCancelChild(childHandle)
        }
    }

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

    /// CORO-004: Register a resumer invoked with the terminal value when the job
    /// completes (normally, exceptionally, or via cancellation). If the job is
    /// already complete, the resumer runs immediately on the calling thread.
    func addJoinResumer(_ resumer: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        if state.isCompleted {
            let value = terminalValueLocked()
            lock.unlock()
            resumer(value)
            return
        }
        joinResumers.append(resumer)
        lock.unlock()
    }

    private func terminalValueLocked() -> Int {
        switch state {
        case .completed:
            return result
        case .failed:
            return failure
        case .cancelled:
            return cancelCause
        case .new, .active, .completing, .cancelling:
            return 0
        }
    }

    private func completeLocked(successState: RuntimeJobState, value: Int, failureValue: Int = 0) -> Bool {
        switch state {
        case .new, .active:
            state = .completing
            if successState == .completed {
                result = value
                failure = 0
                cancelCause = 0
                state = .completed
            } else if successState == .failed {
                failure = failureValue
                result = 0
                cancelCause = 0
                state = .failed
            }
            return true
        case .cancelling:
            // The coroutine body has finished executing (including catch/finally blocks)
            // after observing cancellation. Transition to fully cancelled so that
            // join() can return. The cancelCause is preserved from when cancel() was called.
            state = .cancelled
            return true
        case .completed, .cancelled, .failed:
            return false
        case .completing:
            return false
        }
    }

    func complete(with value: Int) -> Bool {
        lock.lock()
        let shouldSignal = completeLocked(successState: .completed, value: value)
        let resumers = shouldSignal ? joinResumers : []
        if shouldSignal {
            joinResumers = []
        }
        let terminal = shouldSignal ? terminalValueLocked() : 0
        lock.unlock()
        if shouldSignal {
            completionSemaphore.signal()
            for resumer in resumers {
                resumer(terminal)
            }
        }
        return shouldSignal
    }

    func completeExceptionally(with exception: Int) -> Bool {
        lock.lock()
        let shouldSignal = completeLocked(successState: .failed, value: 0, failureValue: exception)
        let resumers = shouldSignal ? joinResumers : []
        if shouldSignal {
            joinResumers = []
        }
        let terminal = shouldSignal ? terminalValueLocked() : 0
        lock.unlock()
        if shouldSignal {
            completionSemaphore.signal()
            for resumer in resumers {
                resumer(terminal)
            }
        }
        return shouldSignal
    }

    func cancel(cause: Int = 0) -> Bool {
        cancel(message: "CancellationException", cause: cause)
    }

    @discardableResult
    func cancel(message: String, cause: Int = 0) -> Bool {
        let resolvedCause = cause != 0 ? cause : runtimeAllocateCancellationException(message: message)
        // If the dispatch work item has not begun executing, cancel it now so
        // the body never runs. The state update below is the authoritative
        // completion signal if cancellation already lost the race.
        dispatchWorkItem?.cancel()
        var childrenToCancel: [Int] = []
        var stateToResume: RuntimeContinuationState?
        var shouldSignalCompletion = false
        var joinResumersToRun: [@Sendable (Int) -> Void] = []
        var terminalForJoin = 0
        lock.lock()
        switch state {
        case .completed, .cancelled, .failed:
            lock.unlock()
            return false
        case .cancelling:
            // Already cancelling, just update cause if not set
            if cancelCause == 0 {
                cancelCause = resolvedCause
            }
            if cancelMessage == "CancellationException" {
                cancelMessage = message
            }
            lock.unlock()
            return false
        case .new, .active, .completing:
            cancelMessage = message
            cancelCause = resolvedCause
            result = 0
            failure = 0
            // A job that has not started executing can become terminal
            // immediately. Once execution has begun, keep the intermediate
            // cancelling state so explicit completion mirrors lifecycle
            // semantics.
            if state == .new || (state == .active && !hasStartedExecuting) {
                state = .cancelled
                shouldSignalCompletion = true
                joinResumersToRun = joinResumers
                joinResumers = []
                terminalForJoin = terminalValueLocked()
            } else {
                state = .cancelling
                stateToResume = continuationState
            }
            childrenToCancel = childJobHandles
        }
        lock.unlock()

        stateToResume?.signalResume()
        for child in childrenToCancel {
            runtimeCancelChild(child)
        }
        if shouldSignalCompletion {
            completionSemaphore.signal()
            for resumer in joinResumersToRun {
                resumer(terminalForJoin)
            }
        }
        return true
    }

    /// Blocking wait for job completion. Suspend-aware joining (which avoids blocking
    /// a GCD thread) is handled by `kk_job_join` via `addJoinResumer` (CORO-004); this
    /// method is the synchronous fallback for non-suspend contexts.
    func join() -> Int {
        // STDLIB-CORO-001: Start a LAZY job on demand before joining.
        startIfNeeded()
        // BUG-041: this (or a sibling launched on the same thread) may still be
        // sitting undispatched in RuntimePendingLaunchQueue -- flush before any
        // chance of blocking below, or a job that was never handed to GCD would
        // never signal completionSemaphore.
        RuntimePendingLaunchQueue.flush()
        lock.lock()
        if state.isCompleted {
            let value = terminalValueLocked()
            lock.unlock()
            return value
        }
        lock.unlock()
        completionSemaphore.wait()
        completionSemaphore.signal()
        lock.lock()
        let value = terminalValueLocked()
        lock.unlock()
        return value
    }

    func awaitCompletion() -> Int {
        join()
    }

    func cancellationMessageSnapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return cancelMessage
    }

    func cancellationCauseSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCause
    }

    /// Thread-safe snapshot of the cancellation flag.
    func cancellationSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isCancelled
    }

    /// Thread-safe snapshot of the completion flag.
    func completedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isCompleted
    }

    /// Thread-safe snapshot of the active state.
    func isActiveSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isActive
    }

    func isFailedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .failed
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
    /// Cancellation message stored when cancel(message:cause:) is called on this scope.
    private(set) var cancellationMessage: String = "CancellationException"
    /// Cancellation cause stored when cancel(message:cause:) is called on this scope.
    private(set) var cancellationCause: Int = 0
    let isSupervisor: Bool
    fileprivate var parent: RuntimeCoroutineScope?
    /// Optional debug name assigned via CoroutineName context element (STDLIB-CORO-077).
    var name: String?

    // CORO-003: Task-local scope registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the scope that is current for that execution context. This allows
    // `RuntimeCoroutineScope.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.
    private static let taskScopeLock = NSLock()
    // Protected by taskScopeLock — all accesses go through installScope/removeScope/scopeForTask.
    nonisolated(unsafe) private static var taskScopeMap: [RuntimeTaskKey: RuntimeCoroutineScope] = [:]

    /// Install scope for the given task key. Called at the top of the
    /// suspend-entry loop so that launched children can discover their parent scope.
    static func installScope(_ scope: RuntimeCoroutineScope?, forTask key: RuntimeTaskKey) {
        taskScopeLock.lock()
        if let scope {
            taskScopeMap[key] = scope
        } else {
            taskScopeMap.removeValue(forKey: key)
        }
        taskScopeLock.unlock()
    }

    /// Remove the task-scope mapping when a suspend-entry loop finishes.
    static func removeScope(forTask key: RuntimeTaskKey) {
        taskScopeLock.lock()
        taskScopeMap.removeValue(forKey: key)
        taskScopeLock.unlock()
    }

    /// Look up the scope installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func scopeForTask(_ key: RuntimeTaskKey) -> RuntimeCoroutineScope? {
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
        RuntimeLiveHandles.register(self)
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
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

    /// Cancel with a specific message and cause so that a materialised
    /// CancellationException carries the correct values.
    func cancel(message: String, cause: Int) {
        lock.lock()
        if !isCancelled {
            cancellationMessage = message
            cancellationCause = cause
        }
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
            let shouldIgnoreChildCancellation = isCancelled && runtimeCoroutineIsCancellationResult(childResult)
            if firstFailure == 0,
               runtimeCoroutineIsThrowableResult(childResult),
               !shouldIgnoreChildCancellation
            {
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
                    runtimeStorage.withGCLock { state in
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
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isRegistered else {
        return false
    }
    return tryCast(pointer, to: RuntimeThrowableBox.self) != nil
}

private func runtimeCoroutineIsCancellationResult(_ result: Int) -> Bool {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: result) else {
        return false
    }
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isRegistered else {
        return false
    }
    return tryCast(pointer, to: RuntimeCancellationBox.self) != nil
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

    /// Get-or-create a task key for the current thread.
    static var currentTaskKey: RuntimeTaskKey {
        if let existing: RuntimeTaskKeyBox = pthreadGetValue(pthreadKey) {
            return existing.key
        }
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

    /// Install a fresh task key for this thread and return it.
    /// Called at the top of each suspend-entry loop invocation.
    static func installFreshKey() -> RuntimeTaskKey {
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

    /// Remove the task key for this thread.
    static func removeKey() {
        pthreadSetValue(pthreadKey, nil as RuntimeTaskKeyBox?)
    }
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.coroutineSuspendedBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return ptr
}

@_cdecl("kk_coroutine_continuation_new")
public func kk_coroutine_continuation_new(_ functionID: Int) -> Int {
    let state = RuntimeContinuationState(functionID: Int64(functionID))
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(state).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private final class RuntimeDirectSuspendCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasReturned = false
    private var outcome: (result: Int, thrown: Int)?

    /// Record completion and report whether the caller already returned.
    func record(result: Int, thrown: Int) -> Bool {
        lock.lock()
        outcome = (result, thrown)
        let shouldSignal = hasReturned
        lock.unlock()
        return shouldSignal
    }

    /// Mark the initial invocation as returned and return a completion that
    /// happened before that point, if any.
    func markReturned() -> (result: Int, thrown: Int)? {
        lock.lock()
        hasReturned = true
        let completed = outcome
        lock.unlock()
        return completed
    }
}

/// STDLIB-CORO-BUG-01: runtime support for a suspend function calling another
/// suspend function directly (not through launch/async/withContext). The
/// callee runs on its own fresh continuation (childContinuation) via the
/// standard entry loop; its completion is relayed into the caller's own
/// continuation (callerContinuationRaw) instead of being dropped, so the
/// caller's entry loop -- already about to suspend on this call -- gets woken
/// up with the real result. A synchronously completed child returns its result
/// directly; only a child that remains suspended schedules a caller resume.
@_cdecl("kk_coroutine_call_direct_suspend")
public func kk_coroutine_call_direct_suspend(
    _ entryPointRaw: Int,
    _ childContinuation: Int,
    _ callerContinuationRaw: Int
) -> Int {
    guard let callerState = runtimeContinuationState(from: callerContinuationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_call_direct_suspend received invalid caller continuation handle")
    }
    if let childState = runtimeContinuationState(from: childContinuation) {
        childState.scope = callerState.scope
        childState.jobHandle = callerState.jobHandle
    }
    let completion = RuntimeDirectSuspendCompletion()
    _ = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: childContinuation,
        onCompletion: { result, thrown in
            // Always publish the outcome, including clearing the thrown slot on
            // success: the caller's state machine reads this slot at the resume
            // label, and a stale exception from a previously caught throw would
            // otherwise be re-observed (and re-thrown) at the next suspend point.
            callerState.thrownException = thrown
            if thrown == 0 {
                callerState.completion = Int64(result)
            }
            if completion.record(result: result, thrown: thrown) {
                callerState.signalResume()
            }
        }
    )
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    if let outcome = completion.markReturned() {
        if outcome.thrown != 0 {
            // The state machine reads the thrown exception after a resume.
            callerState.signalResume()
            return suspendedToken
        }
        return outcome.result
    }
    return suspendedToken
}

@_cdecl("kk_create_coroutine_unintercepted")
public func kk_create_coroutine_unintercepted(_ entryPointRaw: Int, _ completionContinuation: Int) -> Int {
    let continuation = kk_coroutine_continuation_new(entryPointRaw)
    runtimeContinuationState(from: continuation)?.configureUninterceptedCoroutine(
        entryPointRaw: entryPointRaw,
        completionContinuation: completionContinuation
    )
    return continuation
}

@_cdecl("kk_start_coroutine_unintercepted_or_return")
public func kk_start_coroutine_unintercepted_or_return(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    startCoroutineUninterceptedOrReturn(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: runtimeContinuationState(from: continuation)?.takeUninterceptedCoroutineStart()?.completionContinuation ?? 0,
        outThrown: outThrown
    )
}

private func startUninterceptedCoroutineFromResume(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int
) {
    var thrown = 0
    let result = startCoroutineUninterceptedOrReturn(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: &thrown
    )
    if completionContinuation == 0 {
        return
    }
    if thrown != 0 {
        kk_coroutine_continuation_resume_with_exception(completionContinuation, thrown)
        return
    }
    if result != Int(bitPattern: kk_coroutine_suspended()) {
        kk_coroutine_continuation_resume(completionContinuation, result)
    }
}

private func continueUninterceptedCoroutineToCompletion(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int
) {
    var thrown = 0
    let result = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: &thrown
    )
    if completionContinuation == 0 {
        return
    }
    if thrown != 0 {
        kk_coroutine_continuation_resume_with_exception(completionContinuation, thrown)
    } else {
        kk_coroutine_continuation_resume(completionContinuation, result)
    }
}

private func startCoroutineUninterceptedOrReturn(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        outThrown?.pointee = 0
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        outThrown?.pointee = 0
        return 0
    }

    let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(state.scope, forTask: taskKey)
    RuntimeContinuationState.installState(state, forTask: taskKey)
    RuntimeJobHandle.current = state.jobHandle
    defer {
        RuntimeCoroutineScope.removeScope(forTask: taskKey)
        RuntimeContinuationState.removeCurrent(forTask: taskKey)
        RuntimeCoroutineScopeTaskKey.removeKey()
        RuntimeJobHandle.current = nil
    }

    var thrownValue = 0
    let result = entryPoint(continuation, &thrownValue)
    if thrownValue != 0 {
        outThrown?.pointee = thrownValue
        state.thrownException = thrownValue
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    if result != suspendedToken {
        outThrown?.pointee = 0
        return result
    }

    outThrown?.pointee = 0
    state.installResumeContinuation {
        continueUninterceptedCoroutineToCompletion(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            completionContinuation: completionContinuation
        )
    }
    return suspendedToken
}

@_cdecl("kk_coroutine_state_enter")
public func kk_coroutine_state_enter(_ continuation: Int, _ functionID: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_enter received invalid continuation handle")
    }
    let functionIDValue = Int64(functionID)
    if state.functionID != functionIDValue {
        state.functionID = functionIDValue
        state.label = 0
        state.completion = 0
        state.thrownException = 0
        state.spillSlots.removeAll(keepingCapacity: false)
    }
    return Int(state.label)
}

@_cdecl("kk_coroutine_state_set_label")
public func kk_coroutine_state_set_label(_ continuation: Int, _ label: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_label received invalid continuation handle")
    }
    state.label = Int64(label)
    return label
}

@_cdecl("kk_coroutine_state_exit")
public func kk_coroutine_state_exit(_ continuation: Int, _ value: Int) -> Int {
    if let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) {
        var shouldRelease = false
        runtimeStorage.withGCLock { state in
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
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_spill received invalid continuation handle")
    }
    state.spillSlots[Int64(slot)] = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_spill received invalid continuation handle")
    }
    return Int(state.spillSlots[Int64(slot)] ?? 0)
}

@_cdecl("kk_coroutine_state_set_completion")
public func kk_coroutine_state_set_completion(_ continuation: Int, _ value: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_completion received invalid continuation handle")
    }
    state.completion = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_completion")
public func kk_coroutine_state_get_completion(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_completion received invalid continuation handle")
    }
    return Int(state.completion)
}

@_cdecl("kk_coroutine_state_get_thrown_exception")
public func kk_coroutine_state_get_thrown_exception(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_thrown_exception received invalid continuation handle")
    }
    return state.thrownException
}

@_cdecl("kk_coroutine_continuation_context")
public func kk_coroutine_continuation_context(_ continuation: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_context received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        return Int(bitPattern: callbackContinuation.context)
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_context received invalid continuation handle")
    }
    return runtimeRegisterObject(state.makeContinuationContext())
}

@_cdecl("kk_coroutine_current_context")
public func kk_coroutine_current_context() -> Int {
    let context = RuntimeContinuationState.current?.makeContinuationContext()
        ?? RuntimeCoroutineContext()
    return runtimeRegisterObject(context)
}

@_cdecl("kk_coroutine_continuation_factory")
public func kk_coroutine_continuation_factory(_ contextRaw: Int, _ resumeWithRaw: Int) -> Int {
    runtimeRegisterObject(RuntimeCallbackContinuation(contextRaw: contextRaw, resumeWithRaw: resumeWithRaw))
}

@_cdecl("kk_coroutine_continuation_resume_with")
public func kk_coroutine_continuation_resume_with(_ continuation: Int, _ resultRaw: Int) {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        callbackContinuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw))
        return
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with received invalid continuation handle")
    }

    if let start = state.takeUninterceptedCoroutineStart() {
        if resultRaw != 0,
           let resultPtr = UnsafeMutableRawPointer(bitPattern: resultRaw),
           let resultBox = tryCast(resultPtr, to: RuntimeResultBox.self),
           !resultBox.isSuccess
        {
            if start.completionContinuation != 0 {
                kk_coroutine_continuation_resume_with_exception(
                    start.completionContinuation,
                    resultBox.exception
                )
            }
            return
        }
        startUninterceptedCoroutineFromResume(
            entryPointRaw: start.entryPointRaw,
            continuation: continuation,
            completionContinuation: start.completionContinuation
        )
        return
    }

    if resultRaw != 0,
       let resultPtr = UnsafeMutableRawPointer(bitPattern: resultRaw),
       let resultBox = tryCast(resultPtr, to: RuntimeResultBox.self)
    {
        let ise: Int?
        if resultBox.isSuccess {
            ise = state.resume(with: resultBox.value)
        } else {
            ise = state.resume(withException: resultBox.exception)
        }
        if let ise {
            state.deliverDoubleResumeException(ise)
        }
        return
    }

    if let ise = state.resume(with: resultRaw) {
        state.deliverDoubleResumeException(ise)
    }
}

@_cdecl("kk_coroutine_continuation_resume")
public func kk_coroutine_continuation_resume(_ continuation: Int, _ value: Int) {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        let resultRaw = runtimeRegisterObject(RuntimeResultBox(isSuccess: true, value: value, exception: 0))
        callbackContinuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw))
        return
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume received invalid continuation handle")
    }
    if let start = state.takeUninterceptedCoroutineStart() {
        startUninterceptedCoroutineFromResume(
            entryPointRaw: start.entryPointRaw,
            continuation: continuation,
            completionContinuation: start.completionContinuation
        )
        return
    }
    if let ise = state.resume(with: value) {
        // STDLIB-CORO-BUG-01: double-resume detected — surface the ISE via thrownException.
        state.deliverDoubleResumeException(ise)
    }
}

@_cdecl("kk_coroutine_continuation_resume_with_exception")
public func kk_coroutine_continuation_resume_with_exception(_ continuation: Int, _ exception: Int) {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with_exception received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        let resultRaw = runtimeRegisterObject(RuntimeResultBox(isSuccess: false, value: 0, exception: exception))
        callbackContinuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw))
        return
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with_exception received invalid continuation handle")
    }
    if let ise = state.resume(withException: exception) {
        // STDLIB-CORO-BUG-01: double-resume detected — surface the ISE via thrownException.
        state.deliverDoubleResumeException(ise)
    }
}

@_cdecl("kk_kxmini_run_blocking")
public func kk_kxmini_run_blocking(
    _ entryPointRaw: Int,
    _ functionID: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // Create a job handle for runBlocking so that cancellation is observable
    // via kk_coroutine_check_cancellation, which requires state.jobHandle to
    // be non-nil.  Without this, calling cancel() inside runBlocking would
    // silently succeed but subsequent suspension points (e.g. delay()) would
    // never observe the cancellation.
    let job = RuntimeJobHandle()
    return runSuspendEntryLoop(
        entryPointRaw: entryPointRaw,
        functionID: functionID,
        jobHandle: job,
        outThrown: outThrown
    )
}

@_cdecl("kk_kxmini_launch")
public func kk_kxmini_launch(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let workItem = DispatchWorkItem {
        // Mark the body as started on the dispatch thread, then re-check
        // cancellation. A cancel() that wins before the work item executes
        // completes the scheduled job immediately; if cancellation happens
        // between markStarted() and the guard below, the body is skipped here.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        // Note: This scope propagation was simplified from the CORO-003 task-scope-map
        // approach. TLS-based propagation is safe here because the blocking semaphore
        // in runSuspendEntryLoopWithContinuation ensures the coroutine resumes on the
        // same GCD thread. See RuntimeCoroutineScope.current doc comment for details.
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // Forward outThrown so an exception that escapes the launched body (including
        // CancellationException from cooperative cancellation) completes the job
        // exceptionally instead of being silently discarded as a normal `0` result --
        // the pre-existing bug this fixes: `job.complete(with: result)` unconditionally,
        // which threw away `thrownValue` and could leave the exception object referenced
        // nowhere once its stack frame unwound.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    return Int(bitPattern: jobPtr)
}

// MARK: - STDLIB-CORO-001: CoroutineStart.LAZY launch

/// Launch a coroutine without starting it immediately (CoroutineStart.LAZY).
/// The body is dispatched the first time `join()` or `startIfNeeded()` is called.
@_cdecl("kk_kxmini_launch_lazy")
public func kk_kxmini_launch_lazy(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    job.installLazyStartBody { [entryPointRaw, continuation, callerScope, callerJob] in
        let workItem = DispatchWorkItem {
            job.markStarted()
            if job.cancellationSnapshot() {
                _ = job.complete(with: 0)
                return
            }
            RuntimeCoroutineScope.current = callerScope
            RuntimeJobHandle.current = callerJob
            var thrown = 0
            let result = runSuspendEntryLoopWithContinuation(
                entryPointRaw: entryPointRaw,
                continuation: continuation,
                outThrown: &thrown
            )
            RuntimeCoroutineScope.current = nil
            RuntimeJobHandle.current = nil
            if thrown != 0 {
                _ = job.completeExceptionally(with: thrown)
            } else {
                _ = job.complete(with: result)
            }
        }
        job.dispatchWorkItem = workItem
        job.markScheduled()
        RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    }
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_kxmini_launch_lazy that accepts a pre-built continuation
/// (for lambda arguments that capture outer variables).
@_cdecl("kk_kxmini_launch_lazy_with_cont")
public func kk_kxmini_launch_lazy_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context (not TLS) and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    job.installLazyStartBody { [entryPointRaw, continuation, callerScope, callerJob] in
        let workItem = DispatchWorkItem {
            job.markStarted()
            if job.cancellationSnapshot() {
                _ = job.complete(with: 0)
                return
            }
            RuntimeCoroutineScope.current = callerScope
            RuntimeJobHandle.current = callerJob
            var thrown = 0
            let result = runSuspendEntryLoopWithContinuation(
                entryPointRaw: entryPointRaw,
                continuation: continuation,
                outThrown: &thrown
            )
            RuntimeCoroutineScope.current = nil
            RuntimeJobHandle.current = nil
            if thrown != 0 {
                _ = job.completeExceptionally(with: thrown)
            } else {
                _ = job.complete(with: result)
            }
        }
        job.dispatchWorkItem = workItem
        job.markScheduled()
        RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
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
    // STDLIB-CORO-BUG-05: capture the continuation state so we can tell a
    // thrown exception apart from a normal (possibly zero) result after the
    // entry loop returns -- mirrors kk_kxmini_launch_with_exception_handler.
    // Without this, `async { throw ... }` completed the task with `result`
    // (which the loop forces to 0 on a throw, see runSuspendEntryLoopWithContinuation),
    // so `await()` observed thrownException == 0 and silently resumed with 0
    // instead of re-throwing.
    let capturedContState = runtimeContinuationState(from: continuation)

    KxMiniRuntime.launch {
        task.markStarted()
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: continuation
        )
        if let thrown = capturedContState?.thrownException, thrown != 0 {
            task.completeExceptionally(with: thrown)
        } else {
            task.complete(with: result)
        }
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
public func kk_kxmini_run_blocking_with_cont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // When this drives a `suspend () -> R` value invoked inside an active
    // coroutine (see kk_suspend_function_invoke_0), the body runs on a fresh
    // continuation. Seed it with the ambient scope so `launch`/`async` inside the
    // invoked block register with the enclosing structured-concurrency scope
    // (e.g. a Kotlin-level `coroutineScope { }`) rather than detaching. Only the
    // scope is inherited, not the caller job: inheriting the caller job would
    // re-parent a supervisor scope's children to the root job and break failure
    // isolation. A genuine top-level `runBlocking` has no ambient scope,
    // so this is a no-op there.
    let contState = runtimeContinuationState(from: continuation)
    if let contState, contState.scope == nil {
        contState.scope = RuntimeCoroutineScope.current
    }
    if let contState {
        // A non-capturing flow emitter enters through the direct C callback and
        // creates this continuation before the nested suspend loop installs its
        // task-local state. Preserve the collector context from the flow stack
        // as a fallback so delayed emissions remain attached to the same collect.
        contState.flowCollectContext = RuntimeContinuationState.current?.flowCollectContext
            ?? runtimeFlowCurrentCollectContext()
    }
    // Forward `outThrown` so an exception thrown by the blocking body reaches the
    // caller. Callers (e.g. the `runBlocking`/suspend-value thunks) branch on this
    // slot to rethrow; dropping it silently swallowed the exception.
    return runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: outThrown
    )
}

@_cdecl("kk_suspend_coroutine")
public func kk_suspend_coroutine(_ fnPtr: Int, _ closureRaw: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    var thrown = 0
    _ = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: continuation,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return Int(bitPattern: kk_coroutine_suspended())
}

@_cdecl("kk_kxmini_launch_with_cont")
public func kk_kxmini_launch_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // See kk_kxmini_launch: forward outThrown so an exception escaping the body
        // completes the job exceptionally instead of being discarded as a normal result.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: continuation, outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
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
    // STDLIB-CORO-BUG-05: same fix as kk_kxmini_async -- this is the launcher-thunk
    // (argument-bearing) counterpart, taken whenever the async {} block captures
    // anything from the enclosing scope, so it needs the same thrownException
    // check before completing the task, or `async { ...; throw ... }.await()`
    // silently resumes with 0 instead of re-throwing whenever the block closes
    // over an outer variable.
    let capturedContState = runtimeContinuationState(from: continuation)

    KxMiniRuntime.launch {
        task.markStarted()
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        if let thrown = capturedContState?.thrownException, thrown != 0 {
            task.completeExceptionally(with: thrown)
        } else {
            task.complete(with: result)
        }
    }
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_produce")
public func kk_produce(_ entryPointRaw: Int, _ capture0: Int) -> Int {
    let continuation = kk_coroutine_continuation_new(entryPointRaw)
    if let contState = runtimeContinuationState(from: continuation) {
        contState.launcherArgs[1] = Int64(capture0)
    }
    return kk_kxmini_produce_with_cont(entryPointRaw, continuation)
}

/// Launch a producer on a channel with the requested buffering policy.
/// `channelFlow` and `callbackFlow` use the Kotlin buffered default, while
/// `produce` retains its rendezvous behavior through the public wrapper below.
func runtimeKxMiniProduceWithCont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    channelCapacity: Int
) -> Int {
    let channelHandle = kk_channel_create(channelCapacity)
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }

    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
        contState.launcherArgs[0] = Int64(channelHandle)
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        _ = kk_channel_close(channelHandle)
        _ = job.complete(with: result)
    }
    return channelHandle
}

@_cdecl("kk_kxmini_produce_with_cont")
public func kk_kxmini_produce_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeKxMiniProduceWithCont(entryPointRaw, continuation, channelCapacity: 0)
}

// MARK: - Dispatcher-aware launch (STDLIB-CORO-072)

/// Launch a coroutine on a specific dispatcher (fire-and-forget).
/// dispatcherRaw is a dispatcher tag (kk_dispatcher_default/io/main).
/// Returns an opaque job handle (RuntimeJobHandle*).
@_cdecl("kk_kxmini_launch_with_dispatcher")
public func kk_kxmini_launch_with_dispatcher(_ entryPointRaw: Int, _ functionID: Int, _ dispatcherRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        let savedDispatcher = RuntimeDispatcher.current
        RuntimeDispatcher.current = dispatcher
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // See kk_kxmini_launch: forward outThrown so an exception escaping the body
        // completes the job exceptionally instead of being discarded as a normal result.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    dispatcher.queue.async(execute: workItem)
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_kxmini_launch_with_dispatcher that accepts a pre-built continuation.
@_cdecl("kk_kxmini_launch_with_dispatcher_and_cont")
public func kk_kxmini_launch_with_dispatcher_and_cont(_ entryPointRaw: Int, _ continuation: Int, _ dispatcherRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        let savedDispatcher = RuntimeDispatcher.current
        RuntimeDispatcher.current = dispatcher
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // See kk_kxmini_launch: forward outThrown so an exception escaping the body
        // completes the job exceptionally instead of being discarded as a normal result.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    dispatcher.queue.async(execute: workItem)
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
                message = throwable.message ?? "Throwable"
            } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
                message = cancellation.message ?? "CancellationException"
            }
        }
        FileHandle.standardError.write(Data("CoroutineExceptionHandler: \(message)\n".utf8))
    }
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
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
    runtimeStorage.withGCLock { state in
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
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    // Resolve exception handler
    var exceptionHandler: RuntimeExceptionHandlerBox?
    if handlerRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw) {
        let isObjPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjPointer {
            exceptionHandler = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? RuntimeExceptionHandlerBox
        }
    }

    // Capture the continuation state so the launch closure can read the
    // thrownException flag set by runSuspendEntryLoopWithContinuation.
    let capturedContState = runtimeContinuationState(from: continuation)

    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        // Reliably detect a thrown exception using the flag set inside
        // runSuspendEntryLoopWithContinuation rather than inspecting the
        // object-pointer registry.  The registry check is unreliable because
        // any non-zero boxed value (string, integer box, etc.) that happens to
        // be registered would otherwise be misidentified as an exception.
        let thrownException = capturedContState?.thrownException ?? 0
        if thrownException != 0 {
            // A CoroutineExceptionHandler consumes an uncaught exception for this
            // fire-and-forget launch path. Without a handler, preserve the failure
            // on the job instead of silently reporting normal completion.
            if let handler = exceptionHandler {
                handler.handler(thrownException)
                _ = job.complete(with: 0)
            } else {
                _ = job.completeExceptionally(with: thrownException)
            }
            return
        }
        _ = job.complete(with: result)
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_await")
public func kk_kxmini_async_await(_ handle: Int, _ continuation: Int) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle),
          let task = runtimeAsyncTask(from: handle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    task.markConsumedByUserCode()

    // NOTE: unlike the (now-fixed) kk_job_join, this deliberately does NOT release the
    // handle's passRetained after await -- see the NOTE on kk_job_join above for why:
    // Kotlin code may still read the Deferred (e.g. `d.await(); println(d.isActive)`)
    // after this call, and releasing here would leave that reference dangling.

    // CORO-004: suspend-aware await via `awaitResult(callerState:)`.
    if continuation != 0, let callerState = runtimeContinuationState(from: continuation) {
        switch task.awaitResult(callerState: callerState, afterResume: {}) {
        case .suspended:
            return Int(bitPattern: kk_coroutine_suspended())
        case .completed(let result, let thrown):
            if thrown != 0 {
                // A task that already failed before `await()` runs never goes through
                // the completion resumer above, so publish the failure on the caller
                // state and hand control back to the state machine's resume label --
                // the same protocol `kk_coroutine_call_direct_suspend` uses. Returning
                // the (zero) result here instead would swallow the child exception.
                callerState.thrownException = thrown
                callerState.signalResume()
                return Int(bitPattern: kk_coroutine_suspended())
            }
            return result
        }
    }

    // Non-suspend context: block until complete without consuming the passRetained
    // (`takeUnretainedValue` reads the object without taking ownership of the retain).
    let task2 = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    return task2.awaitResult()
}

@_cdecl("kk_kxmini_delay")
public func kk_kxmini_delay(_ milliseconds: Int, _ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_kxmini_delay received invalid continuation handle")
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - Structured Concurrency C ABI (P5-89)

/// Enters `scope` as the ambient scope for the coroutine running right now.
///
/// Besides the task-scope map (`RuntimeCoroutineScope.current`), the scope is
/// stored on the running continuation. A `suspend` block invoked next runs on a
/// *fresh* child continuation whose scope is seeded from its caller's
/// continuation (see `kk_coroutine_call_direct_suspend`), so binding the scope
/// here is what lets children launched inside a Kotlin-level `coroutineScope { }`
/// block register with the freshly created scope rather than the outer one.
private func enterScopeOnCurrentContinuation(_ scope: RuntimeCoroutineScope?) {
    RuntimeCoroutineScope.current = scope
    RuntimeContinuationState.current?.scope = scope
}

/// Creates a new coroutine scope and installs it as the current scope in the
/// task-scope registry (CORO-003: no TLS for the scope itself).
@_cdecl("kk_coroutine_scope_new")
public func kk_coroutine_scope_new() -> Int {
    let scope = RuntimeCoroutineScope()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // Push: save parent scope and set this as current via the task-scope map
    scope.parent = RuntimeCoroutineScope.current
    enterScopeOnCurrentContinuation(scope)

    return Int(bitPattern: ptr)
}

@_cdecl("kk_supervisor_scope_new")
public func kk_supervisor_scope_new() -> Int {
    let scope = RuntimeCoroutineScope(isSupervisor: true)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withGCLock { state in
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
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_cancel received invalid scope handle")
    }
    scope.cancel()
    return 0
}

/// Waits for all children in the scope to complete, then pops/releases the scope.
@_cdecl("kk_coroutine_scope_wait")
public func kk_coroutine_scope_wait(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle),
          let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_wait received invalid scope handle")
    }
    let firstFailure = scope.waitForChildren()

    // Pop: restore parent scope in the task-scope map (CORO-003) and on the
    // running continuation, mirroring enterScopeOnCurrentContinuation.
    enterScopeOnCurrentContinuation(scope.parent)

    // Release the scope
    runtimeStorage.withGCLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).release()
    // The Kotlin ABI models this as `Throwable?`; absence of a failure must use
    // the shared null sentinel (see runtimeResultExceptionOrNull) rather than raw
    // 0, so a `!= null` check in bundled Kotlin resolves correctly.
    return firstFailure == 0 ? runtimeNullSentinelInt : firstFailure
}

/// Returns 1 if the scope is active (not cancelled), 0 if cancelled.
/// This is the ABI backing for `scope.isActive` in Kotlin.
@_cdecl("kk_coroutine_scope_is_active")
public func kk_coroutine_scope_is_active(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        // Builder lambdas use a no-receiver ABI. Older lowering can still name
        // the CoroutineScope property bridge for a bare `isActive` read, but
        // provides no scope handle; in that shape the Kotlin meaning is the
        // currently running job's active state.
        return kk_coroutine_current_is_active()
    }
    return scope.isCancelled ? 0 : 1
}

/// Returns 1 if the scope has been cancelled, 0 otherwise.
/// This is the ABI backing for checking `scope.coroutineContext[Job]?.isCancelled`.
@_cdecl("kk_coroutine_scope_is_cancelled")
public func kk_coroutine_scope_is_cancelled(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        return 1 // invalid handle → treat as cancelled
    }
    return scope.isCancelled ? 1 : 0
}

/// Registers a child job/deferred handle with the given scope.
@_cdecl("kk_coroutine_scope_register_child")
public func kk_coroutine_scope_register_child(_ scopeHandle: Int, _ childHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_register_child received invalid scope handle")
    }
    scope.registerChild(childHandle)
    return childHandle
}

// MARK: - kotlinx.coroutines.CoroutineScope(context) / Job() / SupervisorJob() (STDLIB-CORO-090)
//
// Unlike `kk_coroutine_scope_new`/`kk_supervisor_scope_new` (used by the lexically-scoped
// `coroutineScope { }`/`supervisorScope { }` block constructs, which push the new scope as
// the ambient "current" scope and tear it down via `kk_coroutine_scope_wait` when the block
// exits), a `CoroutineScope(context)` value is typically stored in a Kotlin property and
// used across many unrelated later calls (`scope.launch { }`, `scope.cancel()`). It must
// NOT be pushed as ambient/current at construction time, and -- per the same reasoning as
// the NOTE on `kk_job_join` -- must NOT be released here, since a live Kotlin reference can
// keep calling members on it indefinitely.

/// Backing for the top-level `CoroutineScope(context: CoroutineContext): CoroutineScope`
/// factory function. Reads a `SupervisorJob()` element in `context` (if any) to decide
/// whether children launched into this scope get supervisor (sibling-failure-isolated)
/// semantics, matching `kotlinx.coroutines.ContextScope`.
@_cdecl("kk_coroutine_scope_new_with_context")
public func kk_coroutine_scope_new_with_context(_ contextRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    var isSupervisor = false
    if let job = runtimeJobHandle(from: ctx.jobHandleRaw) {
        isSupervisor = job.isSupervisorMarker
    }
    let scope = RuntimeCoroutineScope(isSupervisor: isSupervisor)
    return runtimeRegisterObject(scope)
}

/// Backing for `CoroutineScope.launch { block }`. Unlike `kk_kxmini_launch` (which
/// registers the new job with whatever scope happens to be ambient/"current" at the
/// call site), this launches into the EXPLICIT receiver `scope` passed in by the
/// caller. That is the whole point of a property-stored, unstructured
/// `CoroutineScope(...)`: `scope.cancel()` must cascade to jobs started this way no
/// matter which scope (if any) is ambient wherever `.launch` happens to be called from.
@_cdecl("kk_coroutine_scope_launch")
public func kk_coroutine_scope_launch(_ scopeHandle: Int, _ entryPointRaw: Int, _ functionID: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_launch received invalid scope handle")
    }
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
        // Propagate the explicit receiver scope (not whatever is ambient) to the
        // child continuation's context so nested launch/async inside the block
        // discover `scope`, matching kotlinx.coroutines' CoroutineScope.launch.
        state.scope = scope
    }
    scope.registerChild(Int(bitPattern: jobPtr))

    KxMiniRuntime.launch {
        // See the identical guard in kk_kxmini_launch: a cancel() that races in
        // between this function returning and the dispatched closure actually
        // running must skip the body entirely (CoroutineStart.DEFAULT semantics).
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        RuntimeCoroutineScope.current = scope
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_coroutine_scope_launch that accepts a pre-built continuation carrying
/// the launched suspend lambda's captured outer variables (BUG-049). Mirrors
/// kk_coroutine_scope_launch except that the continuation (with its capture slots
/// already populated by the caller) is threaded through the launcher thunk instead of
/// being freshly allocated from a functionID.
@_cdecl("kk_coroutine_scope_launch_with_cont")
public func kk_coroutine_scope_launch_with_cont(_ scopeHandle: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_launch_with_cont received invalid scope handle")
    }
    let job = RuntimeJobHandle()
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
        // Propagate the explicit receiver scope (not whatever is ambient) to the
        // child continuation's context so nested launch/async inside the block
        // discover `scope`, matching kk_coroutine_scope_launch above.
        state.scope = scope
    }
    scope.registerChild(Int(bitPattern: jobPtr))

    KxMiniRuntime.launch {
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        RuntimeCoroutineScope.current = scope
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    return Int(bitPattern: jobPtr)
}
/// Backing for the bare `kotlinx.coroutines.Job(): Job` factory (no parent argument --
/// the only shape currently registered in Sema).
@_cdecl("kk_job_new")
public func kk_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.markStarted()
    return runtimeRegisterObject(job)
}

/// Backing for `kotlinx.coroutines.SupervisorJob(): Job`. Identical to `kk_job_new` except
/// for the `isSupervisorMarker` flag that `kk_coroutine_scope_new_with_context` reads.
@_cdecl("kk_supervisor_job_new")
public func kk_supervisor_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.isSupervisorMarker = true
    job.markStarted()
    return runtimeRegisterObject(job)
}

/// Joins (waits for) a job handle to complete and releases it.
/// This consumes the handle (balances the passRetained from launch).
@_cdecl("kk_job_join")
public func kk_job_join(_ jobHandle: Int, _ continuation: Int) -> Int {
    guard jobHandle != 0, let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        job.markConsumedByUserCode()
    } else if let task = obj as? RuntimeAsyncTask {
        task.markConsumedByUserCode()
    }

    // CORO-004: suspend-aware join. Register a resumer and suspend when the job/task is
    // still running.
    //
    // NOTE: `join()`/`await()` must NOT release the handle's original passRetained here.
    // Kotlin code routinely keeps using a Job/Deferred reference after joining it (e.g.
    // `job.join(); println(job.isCancelled)`), so treating join as "the final use" and
    // releasing eagerly leaves that reference dangling -- a real, previously-reproducing
    // use-after-free crash in `kk_job_is_cancelled`/`kk_job_is_failed`/etc. once accessed
    // post-join. `markConsumedByUserCode()` above already tells `waitForChildren()` to
    // skip its own release for a joined handle, so simply not releasing here just leaves
    // the handle allocated for the life of the process (an intentional, bounded leak)
    // instead of freeing memory a still-live Kotlin variable can reach.
    let releaseHandle: @Sendable () -> Void = {}
    if continuation != 0, let callerState = runtimeContinuationState(from: continuation) {
        if let job = obj as? RuntimeJobHandle {
            job.startIfNeeded()
            if !job.completedSnapshot() {
                job.addJoinResumer { value in
                    callerState.resume(with: value)
                    releaseHandle()
                }
                return Int(bitPattern: kk_coroutine_suspended())
            }
        } else if let task = obj as? RuntimeAsyncTask {
            switch task.awaitResult(callerState: callerState, afterResume: releaseHandle) {
            case .suspended:
                return Int(bitPattern: kk_coroutine_suspended())
            case .completed(let result, _):
                // Already complete: return synchronously (do not resume callerState).
                releaseHandle()
                return result
            }
        }
    }

    let result: Int = if let job = obj as? RuntimeJobHandle {
        job.join()
    } else if let task = obj as? RuntimeAsyncTask {
        task.awaitResult()
    } else {
        0
    }
    // See the NOTE above: do not release the original passRetained from launch here --
    // the Kotlin-level Job/Deferred variable may still be read after this synchronous join.
    return result
}

/// Await job completion using the same consuming wait path as join().
@_cdecl("kk_job_await_completion")
public func kk_job_await_completion(_ jobHandle: Int, _ continuation: Int) -> Int {
    kk_job_join(jobHandle, continuation)
}

// MARK: - Coroutine yield()

/// Cooperatively yields the current coroutine, allowing other coroutines to run.
/// This is the lowering target for `kotlinx.coroutines.yield()`.
@_cdecl("kk_coroutine_yield")
public func kk_coroutine_yield(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    // Schedule the continuation to resume after a brief delay so other
    // dispatched coroutines get a turn before this one continues.
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(1)) { [weak state] in
        _ = state?.resume(with: 0)
    }
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - withTimeout / withTimeoutOrNull

/// Runs a `withTimeout`/`withTimeoutOrNull` block on a deadline, reporting whether
/// the deadline expired first.
///
/// BUG-190: the block runs on its own *child* continuation seeded from the caller,
/// never on the caller's continuation. When the deadline expires the block's entry
/// loop is abandoned while still suspended (e.g. inside `delay()`); sharing the
/// caller's continuation state meant that loop's pending timer later fired a
/// `signalResume()` on the caller, spuriously resuming the caller's *next* suspend
/// point (e.g. `job.join()`) a second time. Two concurrent resumptions of the same
/// body then let one of them signal the completion gate early, so `runBlocking`
/// returned -- and the process exited -- while statements after the join were still
/// running or had not run at all.
private func runTimeoutBlock(
    timeoutMillis: Int,
    entryPointRaw: Int,
    continuation: Int
) -> (timedOut: Bool, result: Int) {
    let scopeHandle = kk_coroutine_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()

    let blockContinuation = kk_coroutine_continuation_new(entryPointRaw)
    let blockJob = RuntimeJobHandle()
    if let blockState = runtimeContinuationState(from: blockContinuation) {
        blockState.scope = scope
        blockState.jobHandle = blockJob
        blockJob.continuationState = blockState
    }
    blockJob.markStarted()

    final class ResultBox: @unchecked Sendable { var value = 0 }
    let resultBox = ResultBox()
    let deadline = DispatchTime.now() + .milliseconds(timeoutMillis)

    let workItem = DispatchWorkItem {
        resultBox.value = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw, continuation: blockContinuation
        )
    }
    DispatchQueue.global().async(execute: workItem)
    let waitResult = workItem.wait(timeout: deadline)
    if waitResult == .timedOut {
        workItem.cancel()
        // Cancel the block's own job so an abandoned, still-suspended body observes
        // cancellation cooperatively and unwinds instead of running to completion.
        blockJob.cancel(message: "TimeoutCancellationException")
        scope.cancel()
        _ = kk_coroutine_scope_wait(scopeHandle)
        return (true, 0)
    }
    _ = kk_coroutine_scope_wait(scopeHandle)
    return (false, resultBox.value)
}

/// Runs the given block with a timeout. If the block does not complete within
/// `timeoutMillis`, a CancellationException is thrown (represented as a trap
/// in this runtime).
/// Used as the lowering target for `withTimeout(timeMillis) { }`.
@_cdecl("kk_with_timeout")
public func kk_with_timeout(_ timeoutMillis: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    let outcome = runTimeoutBlock(
        timeoutMillis: timeoutMillis,
        entryPointRaw: entryPointRaw,
        continuation: continuation
    )
    if outcome.timedOut {
        runtimeStructuredPanic("withTimeout timed out after \(timeoutMillis)ms (CancellationException)")
    }
    return outcome.result
}

/// Runs the given block with a timeout. If the block does not complete within
/// `timeoutMillis`, returns null (0) instead of throwing.
/// Used as the lowering target for `withTimeoutOrNull(timeMillis) { }`.
@_cdecl("kk_with_timeout_or_null")
public func kk_with_timeout_or_null(_ timeoutMillis: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    let outcome = runTimeoutBlock(
        timeoutMillis: timeoutMillis,
        entryPointRaw: entryPointRaw,
        continuation: continuation
    )
    if outcome.timedOut {
        // Use the shared null-sentinel convention (see e.g. RuntimeRangeAndDispatch's
        // `orNull` helpers) rather than raw 0, which is a valid unboxed Int result and
        // would otherwise be indistinguishable from "no value" when printed/compared.
        return runtimeNullSentinelInt
    }
    return outcome.result
}

// MARK: - Child Cancel/Join Helpers (P5-89)

/// Cancel a child handle (RuntimeJobHandle or RuntimeAsyncTask).
func runtimeCancelChild(_ handle: Int) {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        _ = job.cancel()
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
        _ = job.cancel()
    } else if let task = obj as? RuntimeAsyncTask {
        task.cancel()
    }
    return 0
}

/// Cancel a job with an explicit cause.
@_cdecl("kk_job_cancel_with_cause")
public func kk_job_cancel_with_cause(_ jobHandle: Int, _ cause: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_cancel_with_cause received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        _ = job.cancel(cause: cause)
    } else if let task = obj as? RuntimeAsyncTask {
        task.cancel()
    }
    return 0
}

/// Cancel any `CoroutineContext`-like raw value by finding its Job and cancelling it.
/// The optional cause is accepted for API compatibility, but the current runtime
/// cancellation model is flag-based and does not preserve a custom cause.
@_cdecl("kk_context_cancel")
public func kk_context_cancel(_ contextRaw: Int, _ causeRaw: Int) -> Int {
    _ = causeRaw
    _ = kk_job_cancel(contextRaw)
    let context = resolveToCoroutineContext(contextRaw)
    if context.jobHandleRaw != 0 && context.jobHandleRaw != contextRaw {
        _ = kk_job_cancel(context.jobHandleRaw)
    }
    return 0
}

/// Convenience overload for `CoroutineContext.cancel()` calls that omit a cause.
@_cdecl("kk_context_cancel_no_cause")
public func kk_context_cancel_no_cause(_ contextRaw: Int) -> Int {
    kk_context_cancel(contextRaw, 0)
}

/// Mark a job as completed with a result. Returns 1 if the transition succeeded.
@_cdecl("kk_job_complete")
public func kk_job_complete(_ jobHandle: Int, _ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_complete received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.complete(with: value) ? 1 : 0
    }
    if let task = obj as? RuntimeAsyncTask {
        task.complete(with: value)
        return 1
    }
    return 0
}

/// Mark a job as failed with an exception cause. Returns 1 if the transition succeeded.
@_cdecl("kk_job_complete_exceptionally")
public func kk_job_complete_exceptionally(_ jobHandle: Int, _ exception: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_complete_exceptionally received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.completeExceptionally(with: exception) ? 1 : 0
    }
    if let task = obj as? RuntimeAsyncTask {
        task.completeExceptionally(with: exception)
        return 1
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
        return job.isActiveSnapshot() ? 1 : 0
    } else if let task = obj as? RuntimeAsyncTask {
        return task.isActiveSnapshot() ? 1 : 0
    }
    return 0
}

/// Zero-arg ABI backing for the bare `isActive` reference inside a coroutine
/// builder body (kotlinx.coroutines.isActive), which reads the currently
/// running job rather than an explicit receiver. No enclosing job (e.g. at
/// the outermost runBlocking root) is treated as active, matching the
/// not-yet-cancelled default.
@_cdecl("kk_coroutine_current_is_active")
public func kk_coroutine_current_is_active() -> Int {
    // Prefer the job attached to the active continuation. The separate
    // task-local job map can still contain the parent runBlocking job while a
    // launcher thunk is entering its child continuation.
    guard let job = RuntimeContinuationState.current?.jobHandle ?? RuntimeJobHandle.current else {
        return 1
    }
    return job.isActiveSnapshot() ? 1 : 0
}

/// Returns the raw handle for the CoroutineScope carried by the current
/// continuation. Coroutine builder lambdas keep a no-receiver ABI, so the
/// lowering of an implicit CoroutineScope extension call obtains its receiver
/// through this bridge instead.
@_cdecl("kk_coroutine_current_scope")
public func kk_coroutine_current_scope() -> Int {
    if let state = RuntimeContinuationState.current {
        if let scope = state.scope ?? RuntimeCoroutineScope.current {
            state.scope = scope
            return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
        }

        // A top-level runBlocking body has a continuation but no inherited scope.
        // Materialize its CoroutineScope lazily when a builder lambda needs the
        // implicit receiver, then attach it to the continuation for suspensions
        // and child launchers that follow.
        let scope = RuntimeCoroutineScope()
        state.scope = scope
        RuntimeCoroutineScope.current = scope
        return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
    }
    guard let scope = RuntimeCoroutineScope.current else {
        return 0
    }
    return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
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

/// Returns 1 if the job has failed with an exception.
/// ABI backing for `job.isFailed` in Kotlin (kswiftc extension).
@_cdecl("kk_job_is_failed")
public func kk_job_is_failed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0 // invalid handle → treat as not failed
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = obj as? RuntimeJobHandle {
        return job.isFailedSnapshot() ? 1 : 0
    } else if let task = obj as? RuntimeAsyncTask {
        return task.isFailedSnapshot() ? 1 : 0
    }
    return 0
}

/// Check if the coroutine associated with `continuation` has been cancelled.
/// If cancelled, allocates a CancellationException, writes it to `outThrown`,
/// and returns 1. Otherwise returns 0 with outThrown untouched.
@_cdecl("kk_coroutine_check_cancellation")
public func kk_coroutine_check_cancellation(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    if let job = state.jobHandle, job.cancellationSnapshot() {
        let cancellation = runtimeAllocateCancellationException(
            message: job.cancellationMessageSnapshot(),
            cause: job.cancellationCauseSnapshot()
        )
        outThrown?.pointee = cancellation
        return 1
    }
    // Fallback: if there is no job handle but the scope has been cancelled
    // (e.g. via scope.cancel()), still observe the cancellation.  This
    // provides a safety net for execution contexts that lack a job handle.
    if state.jobHandle == nil, let scope = state.scope, scope.isCancelled {
        let cancellation = runtimeAllocateCancellationException(
            message: scope.cancellationMessage, cause: scope.cancellationCause)
        outThrown?.pointee = cancellation
        return 1
    }
    return 0
}

/// Directly cancel a continuation (sets isCancelled on its linked job handle).
@_cdecl("kk_coroutine_cancel")
public func kk_coroutine_cancel(_ continuation: Int) {
    guard let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return
    }
    _ = job.cancel()
}

/// Cancel the currently running coroutine without requiring a continuation handle.
@_cdecl("kk_coroutine_cancel_current")
public func kk_coroutine_cancel_current(_ message: Int, _ causeRaw: Int) -> Int {
    let text = extractString(from: UnsafeMutableRawPointer(bitPattern: message)) ?? "CancellationException"
    let normalizedCause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    guard let state = RuntimeContinuationState.current else {
        return 0
    }
    if let job = state.jobHandle {
        _ = job.cancel(message: text, cause: normalizedCause)
    } else if let scope = state.scope {
        scope.cancel(message: text, cause: normalizedCause)
    }
    return 0
}

/// Returns 1 if the given throwable raw pointer is a CancellationException, 0 otherwise.
@_cdecl("kk_is_cancellation_exception")
public func kk_is_cancellation_exception(_ throwableRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    return obj is RuntimeCancellationBox ? 1 : 0
}

/// Throws a CancellationException if the ambient job/scope has been cancelled.
/// Lowering target for the bare (no-receiver) `kotlinx.coroutines.ensureActive()`.
/// Mirrors `kk_coroutine_check_cancellation`'s two checks (job, then scope fallback),
/// but reads the ambient current job/scope directly since this call carries no
/// continuation handle of its own.
@_cdecl("kk_ensure_active")
public func kk_ensure_active(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let job = RuntimeJobHandle.current, job.cancellationSnapshot() {
        outThrown?.pointee = runtimeAllocateCancellationException(
            message: job.cancellationMessageSnapshot(),
            cause: job.cancellationCauseSnapshot()
        )
        return 0
    }
    if RuntimeJobHandle.current == nil, let scope = RuntimeCoroutineScope.current, scope.isCancelled {
        outThrown?.pointee = runtimeAllocateCancellationException(
            message: scope.cancellationMessage, cause: scope.cancellationCause
        )
        return 0
    }
    return 0
}

/// Singleton backing `kotlinx.coroutines.NonCancellable`. A `RuntimeJobHandle` that
/// is never cancelled: installing it as a continuation's jobHandle (see
/// `kk_with_context_full`) makes cancellation checks against that continuation
/// always observe "active", regardless of the enclosing job's real state.
private let runtimeNonCancellableJob: RuntimeJobHandle = {
    let job = RuntimeJobHandle()
    job.markStarted()
    return job
}()

@_cdecl("kk_non_cancellable_instance")
public func kk_non_cancellable_instance() -> Int {
    // Unlike `runtimeRegisterObject` (which does `passRetained`, appropriate for a
    // freshly-created object), this must not take a new retain on every call: the
    // module-level `let` above already keeps `runtimeNonCancellableJob` alive for the
    // process lifetime, so repeatedly retaining it here would leak one reference per
    // `withContext(NonCancellable)` call. `passUnretained` registers the same pointer
    // (the `objectPointers` insert is idempotent) without incrementing the refcount.
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeNonCancellableJob).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

// MARK: - Suspend Entry Loop

func runSuspendEntryLoop(
    entryPointRaw: Int,
    functionID: Int,
    jobHandle: RuntimeJobHandle? = nil,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    guard suspendEntryPoint(from: entryPointRaw) != nil else {
        return 0
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let jobHandle, let state = runtimeContinuationState(from: continuation) {
        jobHandle.continuationState = state
        state.jobHandle = jobHandle
        jobHandle.markStarted()
    }
    return runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: outThrown
    )
}

/// When `onCompletion` is nil, this runs the synchronous path and blocks the
/// caller on `completionGate`.
/// When `onCompletion` is non-nil, this starts the loop, returns immediately,
/// and invokes the callback on completion without blocking a dispatcher thread.
func runSuspendEntryLoopWithContinuation(
    entryPointRaw: Int,
    continuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    onCompletion: (@Sendable (_ result: Int, _ thrown: Int) -> Void)? = nil
) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        outThrown?.pointee = 0
        _ = kk_coroutine_state_exit(continuation, 0)
        onCompletion?(0, 0)
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
    //      throws, signal the completion gate (sync path) or invoke onCompletion
    //      (async path) so the caller is unblocked / notified.
    //
    // The completion gate semaphore is only used by the synchronous path
    // (runBlocking, join, await).  The async path (onCompletion != nil) never
    // blocks any GCD thread — the completion callback is invoked instead.

    // Sync path only: gate and result box.
    let completionGate: DispatchSemaphore? = onCompletion == nil ? DispatchSemaphore(value: 0) : nil
    final class ResultBox: @unchecked Sendable { var value: Int = 0 }
    let resultBox = ResultBox()

    // CORO-003: Install the scope carried by this continuation into the
    // task-scope map so that child launches dispatched on this thread can
    // discover their parent scope without TLS.
    let contState = runtimeContinuationState(from: continuation)
    let currentTaskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(contState?.scope, forTask: currentTaskKey)
    RuntimeContinuationState.installState(contState, forTask: currentTaskKey)
    RuntimeJobHandle.current = contState?.jobHandle

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
        var key: RuntimeTaskKey
        init(key: RuntimeTaskKey) { self.key = key }
    }
    let taskKeyBox = TaskKeyBox(key: currentTaskKey)

    loopBodyBox.body = {
        // BUG-041: mark this thread as synchronously running a coroutine body
        // for the duration of `entryPoint`'s call below, so RuntimePendingLaunchQueue
        // knows any `launch{}` it makes has a real burst to be flushed at.
        RuntimeCoroutineBurstDepth.enter()
        var thrownValue = 0
        let result = entryPoint(continuation, &thrownValue)
        if thrownValue != 0 {
            // BUG-041: this burst is ending (with a thrown exception); dispatch
            // anything it `launch`-ed for real now that no more synchronous
            // code on this thread can race a cancel() against them.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            RuntimeJobHandle.current = nil
            _ = kk_coroutine_state_exit(continuation, 0)
            // Record the thrown exception in the continuation state so callers
            // such as kk_kxmini_launch_with_exception_handler can reliably
            // distinguish a thrown exception from a normal (possibly non-zero)
            // return value without inspecting the object-pointer registry.
            contState?.thrownException = thrownValue
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(0, thrownValue)
            } else {
                outThrown?.pointee = thrownValue
                resultBox.value = 0
                completionGate?.signal()
            }
            return
        }
        if result != suspendedToken {
            // BUG-041: burst completed with a concrete result; flush before
            // signalling completion for the same reason as the thrown path.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            RuntimeJobHandle.current = nil
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(result, 0)
            } else {
                outThrown?.pointee = 0
                resultBox.value = result
                completionGate?.signal()
            }
            return
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            // BUG-041: defensive terminal fallback; flush for consistency with
            // the other exit paths above.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            RuntimeJobHandle.current = nil
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(0, 0)
            } else {
                outThrown?.pointee = 0
                resultBox.value = 0
                completionGate?.signal()
            }
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
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            let freshKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
            taskKeyBox.key = freshKey
            RuntimeCoroutineScope.installScope(state.scope, forTask: freshKey)
            RuntimeContinuationState.installState(state, forTask: freshKey)
            RuntimeJobHandle.current = state.jobHandle
            // Reset stale resume state from the previous cycle before
            // re-entering the loop.  Must happen here (not before
            // installResumeContinuation) to avoid clearing a pending
            // signal meant for the current suspend point.
            state.resetResumeState()
            loopBodyBox.body?()
        }
        // BUG-041: this burst is suspending, so it's yielding the thread --
        // dispatch anything it `launch`-ed for real now, exactly like a
        // single-threaded Kotlin dispatcher would once the caller yields.
        RuntimeCoroutineBurstDepth.exit()
        RuntimePendingLaunchQueue.flush()
        // The current thread is released here — no blocking.
    }

    // Kick off the first iteration synchronously on the current thread.
    loopBodyBox.body?()

    if let gate = completionGate {
        // Sync path: block until the coroutine completes.
        gate.wait()

        // Break the strong reference cycle: loopBodyBox -> closure -> loopBodyBox
        loopBodyBox.body = nil
        RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
        RuntimeContinuationState.removeState(forTask: currentTaskKey)
        RuntimeCoroutineScopeTaskKey.removeKey()
        RuntimeJobHandle.current = nil

        return resultBox.value
    }

    // Async path: return immediately.  The resume continuation chain handles
    // global-map cleanup (currentTaskKey entries) when the loop eventually
    // completes.  Clean up only the initial thread's locals here.
    RuntimeCoroutineScopeTaskKey.removeKey()
    RuntimeJobHandle.current = nil
    return 0
}

// MARK: - STDLIB-CORO-068: Suspend Function Invocation

/// Invoke a suspend function with 0 arguments using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke_0`.
@_silgen_name("kk_suspend_function_invoke_0")
public func kk_suspend_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateNullPointerException(message: "")
        return 0
    }

    // STDLIB-CORO-BUG-01: a `suspend () -> R` value's invoke thunk has the
    // `(outThrown) -> R` shape (boxed closure or raw thunk); dispatch through
    // kk_function_invoke_0, which handles both with the correct arity, rather
    // than bit-casting it to a continuation-taking suspend entry point.
    // Capture the caller continuation first: the callee's nested run loop
    // reinstalls the thread task key, so `.current` no longer resolves here
    // after the call returns.
    let callerState = RuntimeContinuationState.current
    var thrown = 0
    let result = kk_function_invoke_0(functionRaw, &thrown)
    // Publish the outcome on the caller's continuation so the suspend-invocation
    // lowering observes a thrown exception (and clears any stale one on success).
    callerState?.thrownException = thrown
    outThrown?.pointee = thrown
    return result
}

/// Invoke a suspend function with 1 argument using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke`.
@_silgen_name("kk_suspend_function_invoke")
public func kk_suspend_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateNullPointerException(message: "")
        return 0
    }

    // STDLIB-CORO-BUG-01: the 1-argument counterpart of kk_suspend_function_invoke_0.
    // A `suspend (T) -> R` value's invoke thunk has the `(arg, outThrown) -> R`
    // shape (boxed closure or raw thunk); dispatch through kk_function_invoke,
    // which handles both, rather than bit-casting it to a continuation-taking
    // suspend entry point.
    let callerState = RuntimeContinuationState.current
    var thrown = 0
    let result = kk_function_invoke(functionRaw, arg, &thrown)
    // Publish the outcome on the caller's continuation so the suspend-invocation
    // lowering observes a thrown exception (and clears any stale one on success).
    callerState?.thrownException = thrown
    outThrown?.pointee = thrown
    return result
}

/// Invoke a suspend function with 2 arguments using the function-value ABI.
@_silgen_name("kk_suspend_function_invoke_2")
public func kk_suspend_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateNullPointerException(message: "")
        return 0
    }

    let callerState = RuntimeContinuationState.current
    var thrown = 0
    let result = kk_function_invoke_2(functionRaw, arg1, arg2, &thrown)
    callerState?.thrownException = thrown
    outThrown?.pointee = thrown
    return result
}
