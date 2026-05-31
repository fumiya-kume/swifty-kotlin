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
// [TODO] runtimeFlowDeliverValue (RuntimeCoroutineFlow.swift): the suspend
//        collector path still blocks via waitForResumeSignal().  Full
//        migration requires making runtimeFlowDeliverValue itself async
//        (return via continuation instead of Bool) and restructuring the
//        flow collect loop as a suspend-entry loop.
//
// [TODO] RuntimeAsyncTask.awaitResult() / awaitResultThrowing():
//        Blocks the calling coroutine's GCD thread on `ready.wait()`.
//        Migration: Convert to a suspend point in the caller's entry loop
//        so the caller installs a continuation that the task's `complete()`
//        method dispatches.  Requires codegen changes to emit a suspend
//        label at the `await` call site.
//
// [TODO] RuntimeJobHandle.join():
//        Same pattern as awaitResult().  Requires a suspend-aware join.
//
// [TODO] kk_with_context (RuntimeCoroutineContext.swift):
//        Blocks the caller while the block runs on the target queue.
//        Migration: Make withContext itself a suspend point.  The target
//        queue dispatches the block and, upon completion, resumes the
//        caller via signalResume().  The caller's entry-loop continuation
//        picks up the result without blocking.
//
// [TODO] Channel send/receive (RuntimeCoroutineChannel.swift):
//        Rendezvous and backpressure blocking.  Migration: Replace the
//        per-waiter DispatchSemaphore with a continuation closure stored
//        in SuspendedSender/SuspendedReceiver.  When the counterpart
//        arrives, dispatch the continuation instead of signaling a
//        semaphore.  This is the most complex migration because channels
//        involve two independent parties (sender/receiver), each of which
//        may be a coroutine or a raw thread.
//
// [TODO] RuntimeTypes.swift / RuntimeSequenceBuilders.swift —
//        sequence/iterator builder coroutines:
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
    nonisolated(unsafe) private static var taskStateMap: [ObjectIdentifier: RuntimeContinuationState] = [:]

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
    static func installState(_ state: RuntimeContinuationState?, forTask key: ObjectIdentifier) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the task-state mapping when a suspend-entry loop finishes.
    static func removeState(forTask key: ObjectIdentifier) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
    }

    /// Look up the continuation state installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func stateForTask(_ key: ObjectIdentifier) -> RuntimeContinuationState? {
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
        let timers = releaseAllDelayTimers()
        for timer in timers {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    /// Install the current continuation state for the given task key.
    static func installCurrent(_ state: RuntimeContinuationState?, forTask key: ObjectIdentifier) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the current continuation state for the given task key.
    static func removeCurrent(forTask key: ObjectIdentifier) {
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
    /// Set when the async body is actually scheduled (`KxMiniRuntime.launch` / dispatcher queue).
    /// Keeps `kk_job_is_active` aligned with `RuntimeJobHandle` (inactive until `markStarted`).
    private var isBodyStarted = false
    /// CORO-004: Resumers invoked with (result, thrownException) when the task completes
    /// (normally, exceptionally, or via cancel). Lets a suspend-aware awaiter
    /// (`Deferred.await`) resume via its continuation instead of blocking a GCD thread
    /// on `ready`.
    private var completionResumers: [@Sendable (Int, Int) -> Void] = []

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
        ready.signal()
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
        ready.signal()
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
            ready.signal()
            for resumer in resumers {
                resumer(snapshotResult, snapshotThrown)
            }
        }
    }

    /// Blocking wait for the task result. Suspend-aware awaiting (which avoids
    /// blocking a GCD thread) is handled by `kk_kxmini_async_await` via
    /// `addCompletionResumer` (CORO-004); this method is the synchronous fallback
    /// used by non-suspend contexts (e.g. structured-concurrency child joins).
    func awaitResult() -> Int {
        lock.lock()
        if isCompleted {
            let value = result
            lock.unlock()
            return value
        }
        lock.unlock()
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

    private final class Token {}

    static var currentTaskKey: ObjectIdentifier {
        if let existing: Token = pthreadGetValue(pthreadKey) {
            return ObjectIdentifier(existing)
        }
        let token = Token()
        pthreadSetValue(pthreadKey, token)
        return ObjectIdentifier(token)
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
    private weak var parentJob: RuntimeJobHandle?
    private var childJobHandles: [Int] = []
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false
    /// CORO-004: Resumers invoked with the terminal value when the job completes.
    /// Lets a suspend-aware `Job.join()` caller resume via its continuation instead
    /// of blocking a GCD thread on `completionSemaphore`.
    private var joinResumers: [@Sendable (Int) -> Void] = []

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
    nonisolated(unsafe) private static var taskJobMap: [ObjectIdentifier: RuntimeJobHandle] = [:]

    private static func installCurrent(_ job: RuntimeJobHandle?, forTask key: ObjectIdentifier) {
        taskJobLock.lock()
        if let job {
            taskJobMap[key] = job
        } else {
            taskJobMap.removeValue(forKey: key)
        }
        taskJobLock.unlock()
    }

    private static func currentForTask(_ key: ObjectIdentifier) -> RuntimeJobHandle? {
        taskJobLock.lock()
        defer { taskJobLock.unlock() }
        return taskJobMap[key]
    }

    func markStarted() {
        lock.lock()
        if state == .new {
            state = .active
        }
        lock.unlock()
    }

    func setParent(_ parent: RuntimeJobHandle) {
        lock.lock()
        parentJob = parent
        lock.unlock()
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
            // A never-started job can become terminal immediately. Once a job
            // has started, keep the intermediate cancelling state so explicit
            // completion mirrors kotlinx.coroutines lifecycle semantics.
            if state == .new && continuationState == nil {
                state = .cancelled
                shouldSignalCompletion = true
                joinResumersToRun = joinResumers
                joinResumers = []
                terminalForJoin = terminalValueLocked()
            } else {
                state = .cancelling
            }
            cancelCause = resolvedCause
            result = 0
            failure = 0
            stateToResume = continuationState
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

    func completeCancellationIfNeeded() -> Bool {
        lock.lock()
        guard state == .cancelling else {
            lock.unlock()
            return false
        }
        state = .cancelled
        let resumers = joinResumers
        joinResumers = []
        let terminal = terminalValueLocked()
        lock.unlock()
        completionSemaphore.signal()
        for resumer in resumers {
            resumer(terminal)
        }
        return true
    }

    /// Blocking wait for job completion. Suspend-aware joining (which avoids blocking
    /// a GCD thread) is handled by `kk_job_join` via `addJoinResumer` (CORO-004); this
    /// method is the synchronous fallback for non-suspend contexts.
    func join() -> Int {
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
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_enter received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
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

@_cdecl("kk_coroutine_state_get_thrown_exception")
public func kk_coroutine_state_get_thrown_exception(_ continuation: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_thrown_exception received invalid continuation handle")
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
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
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
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
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()

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
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
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
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
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
    job.markStarted()
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
        job.setParent(callerJob)
        callerJob.registerChild(Int(bitPattern: jobPtr))
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
        RuntimeJobHandle.current = callerJob
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        _ = job.complete(with: result)
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
        task.markStarted()
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
public func kk_kxmini_run_blocking_with_cont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
    return result
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
    job.markStarted()

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
        job.setParent(callerJob)
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    KxMiniRuntime.launch {
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        _ = job.complete(with: result)
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
        task.markStarted()
        // Propagate scope to GCD thread so nested launch/async discover the parent.
        RuntimeCoroutineScope.current = callerScope
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        RuntimeCoroutineScope.current = nil
        task.complete(with: result)
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

@_cdecl("kk_kxmini_produce_with_cont")
public func kk_kxmini_produce_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let channelHandle = kk_channel_create(0)
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
    job.markStarted()
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
        job.setParent(callerJob)
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    dispatcher.dispatchAsync {
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        _ = job.complete(with: result)
    }
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
    job.markStarted()

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
        job.setParent(callerJob)
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    dispatcher.dispatchAsync {
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        _ = job.complete(with: result)
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
    job.markStarted()
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
        job.setParent(callerJob)
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

    KxMiniRuntime.launch {
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
        if thrownException != 0, let handler = exceptionHandler {
            handler.handler(thrownException)
            // Fire-and-forget with handler; do not propagate the exception.
            _ = job.complete(with: 0)
            return
        }
        _ = job.complete(with: result)
    }
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_await")
public func kk_kxmini_async_await(_ handle: Int, _ continuation: Int) -> Int {
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    task.markConsumedByUserCode()

    // CORO-004: suspend-aware await. When invoked from a coroutine state machine
    // (continuation != 0) and the task has not completed yet, register a resumer and
    // suspend instead of blocking a GCD thread. The passRetained handle is released
    // when the resumer fires (the task stays alive via the closure capture until then).
    if continuation != 0, !task.isCompletedSnapshot(),
       let callerState = runtimeContinuationState(from: continuation) {
        task.addCompletionResumer { result, thrown in
            if thrown != 0 {
                callerState.resume(withException: thrown)
            } else {
                callerState.resume(with: result)
            }
            // Recreate the pointer from the Int handle (Sendable) inside the closure.
            if let releasePtr = UnsafeMutableRawPointer(bitPattern: handle) {
                Unmanaged<RuntimeAsyncTask>.fromOpaque(releasePtr).release()
            }
        }
        return Int(bitPattern: kk_coroutine_suspended())
    }

    // Completed or non-suspend context: consume the passRetained and return synchronously.
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
        task.markStarted()
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

// MARK: - Structured Concurrency C ABI (P5-89)

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
    RuntimeCoroutineScope.current = scope

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
    runtimeStorage.withGCLock { state in
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
    // still running, releasing the passRetained handle once the resumer fires.
    if continuation != 0, let callerState = runtimeContinuationState(from: continuation) {
        let releaseHandle: @Sendable () -> Void = {
            // Recreate the pointer from the Int handle (Sendable) inside the closure.
            guard let releasePtr = UnsafeMutableRawPointer(bitPattern: jobHandle) else { return }
            Unmanaged<AnyObject>.fromOpaque(releasePtr).release()
            runtimeStorage.withGCLock { state in
                state.objectPointers.remove(UInt(bitPattern: releasePtr))
            }
        }
        if let job = obj as? RuntimeJobHandle, !job.completedSnapshot() {
            job.addJoinResumer { value in
                callerState.resume(with: value)
                releaseHandle()
            }
            return Int(bitPattern: kk_coroutine_suspended())
        } else if let task = obj as? RuntimeAsyncTask, !task.isCompletedSnapshot() {
            task.addCompletionResumer { result, thrown in
                if thrown != 0 {
                    callerState.resume(withException: thrown)
                } else {
                    callerState.resume(with: result)
                }
                releaseHandle()
            }
            return Int(bitPattern: kk_coroutine_suspended())
        }
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
    runtimeStorage.withGCLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    return result
}

/// Await job completion using the same consuming wait path as join().
@_cdecl("kk_job_await_completion")
public func kk_job_await_completion(_ jobHandle: Int, _ continuation: Int) -> Int {
    kk_job_join(jobHandle, continuation)
}

/// Convenience: creates a scope, runs the block synchronously, waits for all children.
/// Used as the lowering target for `coroutineScope { }` blocks.
@_cdecl("kk_coroutine_scope_run")
public func kk_coroutine_scope_run(
    _ entryPointRaw: Int,
    _ functionID: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
    if firstFailure != 0 {
        outThrown?.pointee = firstFailure
        return 0
    }
    return result
}

/// Convenience with pre-built continuation.
@_cdecl("kk_coroutine_scope_run_with_cont")
public func kk_coroutine_scope_run_with_cont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
    if firstFailure != 0 {
        outThrown?.pointee = firstFailure
        return 0
    }
    return result
}

/// Creates a supervisor scope, runs the block synchronously, waits for all children.
/// Unlike `coroutineScope`, child failures do not cancel siblings (SupervisorJob semantics).
/// Used as the lowering target for `supervisorScope { }` blocks.
@_cdecl("kk_supervisor_scope_run")
public func kk_supervisor_scope_run(
    _ entryPointRaw: Int,
    _ functionID: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
    if firstFailure != 0 {
        outThrown?.pointee = firstFailure
        return 0
    }
    return result
}

/// Supervisor scope variant with pre-built continuation.
@_cdecl("kk_supervisor_scope_run_with_cont")
public func kk_supervisor_scope_run_with_cont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let scopeHandle = kk_supervisor_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = scope
    }
    let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
    let firstFailure = kk_coroutine_scope_wait(scopeHandle)
    if firstFailure != 0 {
        outThrown?.pointee = firstFailure
        return 0
    }
    return result
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

func runSuspendEntryLoopWithContinuation(
    entryPointRaw: Int,
    continuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        outThrown?.pointee = 0
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
        var key: ObjectIdentifier
        init(key: ObjectIdentifier) { self.key = key }
    }
    let taskKeyBox = TaskKeyBox(key: currentTaskKey)

    loopBodyBox.body = {
        var thrownValue = 0
        let result = entryPoint(continuation, &thrownValue)
        if thrownValue != 0 {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            outThrown?.pointee = thrownValue
            RuntimeJobHandle.current = nil
            _ = kk_coroutine_state_exit(continuation, 0)
            // Record the thrown exception in the continuation state so callers
            // such as kk_kxmini_launch_with_exception_handler can reliably
            // distinguish a thrown exception from a normal (possibly non-zero)
            // return value without inspecting the object-pointer registry.
            contState?.thrownException = thrownValue
            resultBox.value = 0
            completionGate.signal()
            return
        }
        if result != suspendedToken {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            outThrown?.pointee = 0
            RuntimeJobHandle.current = nil
            resultBox.value = result
            completionGate.signal()
            return
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.removeKey()
            outThrown?.pointee = 0
            RuntimeJobHandle.current = nil
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
        // The current thread is released here — no blocking.
    }

    // Kick off the first iteration synchronously on the current thread.
    loopBodyBox.body?()

    // Block only at the outermost level until the coroutine completes.
    completionGate.wait()

    // Break the strong reference cycle: loopBodyBox -> closure -> loopBodyBox
    loopBodyBox.body = nil
    RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
    RuntimeContinuationState.removeState(forTask: currentTaskKey)
    RuntimeCoroutineScopeTaskKey.removeKey()
    RuntimeJobHandle.current = nil

    return resultBox.value
}

// MARK: - STDLIB-CORO-068: Suspend Function Invocation

/// Invoke a suspend function with 0 arguments using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke_0`.
@_silgen_name("kk_suspend_function_invoke_0")
public func kk_suspend_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let continuationState = RuntimeContinuationState.current else {
        // Not in a suspend context - this shouldn't happen for proper suspend functions
        outThrown?.pointee = 0
        return 0
    }

    // Install continuation for the suspend point
    var thrownException: Int = 0

    continuationState.installResumeContinuation {
        // When resumed, execute the suspend function
        let functionPtr = UnsafeMutableRawPointer(bitPattern: functionRaw)
        let callResult: Int
        let thrownException: Int
        if let functionPtr {
            // Call the suspend function (this will be a generated function that takes continuation)
            typealias SuspendFunctionType = @convention(c) (Int) -> Int
            let suspendFunction = unsafeBitCast(functionPtr, to: SuspendFunctionType.self)
            callResult = suspendFunction(Int(bitPattern: Unmanaged.passUnretained(continuationState).toOpaque()))
            thrownException = 0
        } else {
            callResult = 0
            thrownException = runtimeAllocateThrowable(message: "NullPointerException")
        }

        // Store results in continuation state
        continuationState.resume(with: callResult)
        if thrownException != 0 {
            continuationState.resume(withException: thrownException)
        }
    }

    // Kick the async body: otherwise waitForResumeSignal blocks with nothing to run the closure.
    continuationState.signalResume()

    // Suspend until the function completes
    continuationState.waitForResumeSignal()
    
    // Extract results
    thrownException = continuationState.thrownException
    if thrownException != 0 {
        outThrown?.pointee = thrownException
        return 0
    }
    
    return Int(continuationState.completion)
}


/// Invoke a suspend function with 1 argument using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke`.
@_silgen_name("kk_suspend_function_invoke")
public func kk_suspend_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let continuationState = RuntimeContinuationState.current else {
        // Not in a suspend context - this shouldn't happen for proper suspend functions
        outThrown?.pointee = 0
        return 0
    }

    // Install continuation for the suspend point
    var thrownException: Int = 0

    continuationState.installResumeContinuation {
        // When resumed, execute the suspend function
        let functionPtr = UnsafeMutableRawPointer(bitPattern: functionRaw)
        let callResult: Int
        let thrownException: Int
        if let functionPtr {
            // Call the suspend function (this will be a generated function that takes continuation)
            typealias SuspendFunctionType = @convention(c) (Int, Int) -> Int
            let suspendFunction = unsafeBitCast(functionPtr, to: SuspendFunctionType.self)
            callResult = suspendFunction(arg, Int(bitPattern: Unmanaged.passUnretained(continuationState).toOpaque()))
            thrownException = 0
        } else {
            callResult = 0
            thrownException = runtimeAllocateThrowable(message: "NullPointerException")
        }

        // Store results in continuation state
        continuationState.resume(with: callResult)
        if thrownException != 0 {
            continuationState.resume(withException: thrownException)
        }
    }

    continuationState.signalResume()

    // Suspend until the function completes
    continuationState.waitForResumeSignal()
    
    // Extract results
    thrownException = continuationState.thrownException
    if thrownException != 0 {
        outThrown?.pointee = thrownException
        return 0
    }
    
    return Int(continuationState.completion)
}

@_cdecl("kk_channel_send_suspending")
public func kk_channel_send_suspending(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return false }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else { return false }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }
    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(handle), isRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }
    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_send_suspending received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return channel.send(resolvedValue, continuation: continuation)
}
