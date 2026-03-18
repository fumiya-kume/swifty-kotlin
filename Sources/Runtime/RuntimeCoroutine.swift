import Dispatch
import Foundation

final class RuntimeContinuationState {
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
    private let stateLock = NSLock()
    private let resumeSemaphore = DispatchSemaphore(value: 0)
    private var delayTimers: [ObjectIdentifier: DispatchSourceTimer]

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

    func waitForResumeSignal() {
        resumeSemaphore.wait()
    }

    func signalResume() {
        resumeSemaphore.signal()
    }

    private func completeDelayTimer(timerID: ObjectIdentifier) {
        stateLock.lock()
        delayTimers.removeValue(forKey: timerID)
        stateLock.unlock()
        resumeSemaphore.signal()
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

    func join() -> Int {
        lock.lock()
        if isCompleted {
            let value = result
            lock.unlock()
            return value
        }
        lock.unlock()
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

    func waitForChildren() {
        lock.lock()
        let currentChildren = children
        children.removeAll()
        lock.unlock()
        for child in currentChildren {
            _ = runtimeJoinChild(child)
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
    }
}

/// CORO-003: Per-thread task key used to index into the task-scope map.
///
/// Each thread participating in a suspend-entry loop gets a unique sentinel
/// object stored in its thread dictionary.  This is *not* the scope itself --
/// it is only a key that lets `RuntimeCoroutineScope.current` find which scope
/// is active on this thread.  The actual scope lives in the continuation
/// context and is propagated to child coroutines explicitly.
enum RuntimeCoroutineScopeTaskKey {
    private static let tlsKey = "kk_coro_task_key"

    /// A lightweight sentinel whose only purpose is to provide a stable
    /// `ObjectIdentifier` for the lifetime of a suspend-entry loop invocation.
    private final class Token {}

    /// Get-or-create a task key for the current thread.
    static var currentTaskKey: ObjectIdentifier {
        if let existing = Thread.current.threadDictionary[tlsKey] as? Token {
            return ObjectIdentifier(existing)
        }
        let token = Token()
        Thread.current.threadDictionary[tlsKey] = token
        return ObjectIdentifier(token)
    }

    /// Install a fresh task key for this thread and return it.
    /// Called at the top of each suspend-entry loop invocation.
    static func installFreshKey() -> ObjectIdentifier {
        let token = Token()
        Thread.current.threadDictionary[tlsKey] = token
        return ObjectIdentifier(token)
    }

    /// Remove the task key for this thread.
    static func removeKey() {
        Thread.current.threadDictionary.removeObject(forKey: tlsKey)
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
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation
        )
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
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
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
        let result = runSuspendEntryLoopWithContinuation(entryPointRaw: entryPointRaw, continuation: continuation)
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
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

@_cdecl("kk_kxmini_delay")
public func kk_kxmini_delay(_ milliseconds: Int, _ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_kxmini_delay received invalid continuation handle")
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - Flow Runtime (STDLIB-088: Cold/Lazy Stream Semantics)

private let runtimeFlowCollectStackKey = "kk_flow_collect_stack"

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


private func runtimeFlowCollectStack() -> [RuntimeFlowCollectContext] {
    Thread.current.threadDictionary[runtimeFlowCollectStackKey] as? [RuntimeFlowCollectContext] ?? []
}

private func runtimeFlowPushCollectContext(_ context: RuntimeFlowCollectContext) {
    var stack = runtimeFlowCollectStack()
    stack.append(context)
    Thread.current.threadDictionary[runtimeFlowCollectStackKey] = stack
}

private func runtimeFlowPopCollectContext() {
    var stack = runtimeFlowCollectStack()
    guard !stack.isEmpty else {
        return
    }
    _ = stack.popLast()
    Thread.current.threadDictionary[runtimeFlowCollectStackKey] = stack
}

private func runtimeFlowCurrentCollectContext() -> RuntimeFlowCollectContext? {
    runtimeFlowCollectStack().last
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

// MARK: - Dispatcher Runtime Stubs (P5-133)

/// Dispatcher tag constants used as opaque handles.
private enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B_4401 // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B_4402 // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B_4403 // "KKD\x03"
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

    let semaphore = DispatchSemaphore(value: 0)
    // Use a heap-allocated pointer as a thread-safe container for the result.
    // The DispatchSemaphore provides a happens-before relationship: the write
    // to `resultPtr.pointee` inside `queue.async` is guaranteed to complete
    // before `semaphore.signal()`, and `semaphore.wait()` ensures the read
    // on the calling thread observes the written value. This makes the
    // cross-thread mutation safe and unambiguous to the concurrency checker.
    let resultPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    resultPtr.initialize(to: 0)
    defer { resultPtr.deallocate() }

    queue.async {
        // Propagate the coroutine scope to the target thread.
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = parentScope
        defer { RuntimeCoroutineScope.current = savedScope }

        resultPtr.pointee = runSuspendEntryLoopWithContinuation(
            entryPointRaw: blockFnPtr,
            continuation: continuation
        )
        semaphore.signal()
    }

    semaphore.wait()
    return resultPtr.pointee
}

// MARK: - Channel Runtime Stubs (P5-134)

/// Channel with rendezvous (capacity 0) and buffered (capacity > 0) semantics.
final class RuntimeChannelHandle {
    private let lock = NSLock()
    private var buffer: [Int] = []
    private let capacity: Int
    private var closed = false
    private var waitingReceivers = 0
    private var waitingSenders = 0
    private let sendSemaphore = DispatchSemaphore(value: 0)
    private let receiveSemaphore = DispatchSemaphore(value: 0)

    init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    func send(_ value: Int) -> Int {
        lock.lock()
        if closed {
            lock.unlock()
            return 0
        }
        // For buffered channels, drop when full; for rendezvous, allow exactly one item
        if capacity > 0, buffer.count >= capacity {
            lock.unlock()
            return 0
        }
        if capacity == 0, !buffer.isEmpty {
            lock.unlock()
            return 0
        }
        buffer.append(value)
        if capacity == 0 {
            waitingSenders += 1
        }
        lock.unlock()
        receiveSemaphore.signal()
        if capacity == 0 {
            sendSemaphore.wait()
            lock.lock()
            waitingSenders -= 1
            lock.unlock()
        }
        return value
    }

    func receive() -> Int {
        lock.lock()
        if closed, buffer.isEmpty {
            lock.unlock()
            return 0
        }
        waitingReceivers += 1
        lock.unlock()
        receiveSemaphore.wait()
        lock.lock()
        waitingReceivers -= 1
        // After waking, check if closed with empty buffer (close() woke us)
        if buffer.isEmpty {
            lock.unlock()
            return 0
        }
        let value = buffer.removeFirst()
        let shouldSignalSender = capacity == 0 && waitingSenders > 0
        lock.unlock()
        if shouldSignalSender {
            sendSemaphore.signal()
        }
        return value
    }

    func close() {
        lock.lock()
        closed = true
        let receiversToWake = waitingReceivers
        let sendersToWake = waitingSenders
        lock.unlock()
        // Wake all blocked receivers and senders
        for _ in 0 ..< receiversToWake {
            receiveSemaphore.signal()
        }
        for _ in 0 ..< sendersToWake {
            sendSemaphore.signal()
        }
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
public func kk_channel_send(_ handle: Int, _ value: Int, _: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.send(value)
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(_ handle: Int, _: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.receive()
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    channel.close()
    return 0
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
    scope.waitForChildren()

    // Pop: restore parent scope in the task-scope map (CORO-003)
    RuntimeCoroutineScope.current = scope.parent

    // Release the scope
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).release()
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
    _ = kk_coroutine_scope_wait(scopeHandle)
    return result
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

    // CORO-003: Install the scope carried by this continuation into the
    // task-scope map so that child launches dispatched on this thread can
    // discover their parent scope without TLS.
    let contState = runtimeContinuationState(from: continuation)
    var currentTaskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(contState?.scope, forTask: currentTaskKey)

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var outThrown = 0

    while true {
        outThrown = 0
        let result = entryPoint(continuation, &outThrown)
        if outThrown != 0 {
            RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
            RuntimeCoroutineScopeTaskKey.removeKey()
            _ = kk_coroutine_state_exit(continuation, 0)
            return 0
        }
        if result != suspendedToken {
            RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
            RuntimeCoroutineScopeTaskKey.removeKey()
            return result
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
            RuntimeCoroutineScopeTaskKey.removeKey()
            return 0
        }
        state.waitForResumeSignal()
        // CORO-003: After suspend/resume we may be on a different thread.
        // Re-install the task key so the scope map lookup still works.
        RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
        currentTaskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        RuntimeCoroutineScope.installScope(state.scope, forTask: currentTaskKey)
    }
}
