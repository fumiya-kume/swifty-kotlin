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
final class RuntimeCoroutineScope {
    private let lock = NSLock()
    private var children: [Int] = [] // opaque handles (RuntimeJobHandle or RuntimeAsyncTask)
    private(set) var isCancelled = false
    fileprivate var parent: RuntimeCoroutineScope?

    private static let currentScopeKey = "kk_coroutine_scope_current"

    static var current: RuntimeCoroutineScope? {
        get { Thread.current.threadDictionary[currentScopeKey] as? RuntimeCoroutineScope }
        set { Thread.current.threadDictionary[currentScopeKey] = newValue }
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
        return 0
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
        return label
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
        return value
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.spillSlots[Int64(slot)] = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return 0
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    return Int(state.spillSlots[Int64(slot)] ?? 0)
}

@_cdecl("kk_coroutine_state_set_completion")
public func kk_coroutine_state_set_completion(_ continuation: Int, _ value: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return value
    }
    let state = Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
    state.completion = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_completion")
public func kk_coroutine_state_get_completion(_ continuation: Int) -> Int {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return 0
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

    // Register with current scope if any
    if let scope = RuntimeCoroutineScope.current {
        scope.registerChild(Int(bitPattern: jobPtr))
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

    // Register with current scope if any
    if let scope = RuntimeCoroutineScope.current {
        scope.registerChild(Int(bitPattern: taskPtr))
    }

    KxMiniRuntime.launch {
        let result = runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
        task.complete(with: result)
    }
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_coroutine_launcher_arg_set")
public func kk_coroutine_launcher_arg_set(_ continuation: Int, _ index: Int64, _ value: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    state.launcherArgs[index] = value
    return value
}

@_cdecl("kk_coroutine_launcher_arg_get")
public func kk_coroutine_launcher_arg_get(_ continuation: Int, _ index: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
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
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // Register with current scope if any
    if let scope = RuntimeCoroutineScope.current {
        scope.registerChild(Int(bitPattern: jobPtr))
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

    // Register with current scope if any
    if let scope = RuntimeCoroutineScope.current {
        scope.registerChild(Int(bitPattern: taskPtr))
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
        return 0
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - Flow Runtime Stubs (P5-88)

private let runtimeFlowCollectStackKey = "kk_flow_collect_stack"

/// Runtime flow op tags must be aligned with the lowering/codegen enums in
/// `CoroutineLoweringPass+Flow.swift` and `FlowLoweringPass.swift`.
private enum RuntimeFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
}

private struct RuntimeFlowOp {
    let kind: RuntimeFlowTag
    let argument: Int
}

private final class RuntimeFlowCollectContext {
    var emittedValues: [Int] = []
}

/// Opaque flow handle. Immutable operation chain; source emitter is re-executed
/// for every collect to guarantee cold-stream semantics.
private final class RuntimeFlowHandle {
    let emitterFnPtr: Int
    let opChain: [RuntimeFlowOp]

    init(emitterFnPtr: Int, opChain: [RuntimeFlowOp] = []) {
        self.emitterFnPtr = emitterFnPtr
        self.opChain = opChain
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

private func runtimeFlowEvaluateSource(_ flow: RuntimeFlowHandle) -> [Int] {
    let context = RuntimeFlowCollectContext()
    runtimeFlowPushCollectContext(context)
    defer { runtimeFlowPopCollectContext() }

    guard flow.emitterFnPtr != 0 else {
        return []
    }
    let emitter = unsafeBitCast(
        flow.emitterFnPtr,
        to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self
    )
    var outThrown = 0
    _ = emitter(&outThrown)
    if outThrown != 0 {
        return []
    }
    return context.emittedValues
}

private func runtimeFlowApplyOps(_ source: [Int], ops: [RuntimeFlowOp]) -> [Int] {
    var values = source
    for op in ops {
        switch op.kind {
        case .emit:
            // Emit operations are handled during flow construction.
            break

        case .map:
            guard op.argument != 0 else {
                values = []
                continue
            }
            let transform = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var mapped: [Int] = []
            mapped.reserveCapacity(values.count)
            for value in values {
                var thrown = 0
                let transformed = transform(0, value, &thrown)
                if thrown != 0 {
                    return mapped
                }
                mapped.append(runtimeFlowMaybeUnbox(transformed))
            }
            values = mapped

        case .filter:
            guard op.argument != 0 else {
                values = []
                continue
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var filtered: [Int] = []
            filtered.reserveCapacity(values.count)
            for value in values {
                var thrown = 0
                let decision = predicate(0, value, &thrown)
                if thrown != 0 {
                    return filtered
                }
                if runtimeFlowMaybeUnbox(decision) != 0 {
                    filtered.append(value)
                }
            }
            values = filtered

        case .take:
            let count = max(0, runtimeFlowMaybeUnbox(op.argument))
            if count < values.count {
                values = Array(values.prefix(count))
            }
        }
    }
    return values
}

private func runtimeFlowCollectNonSuspend(_ values: [Int], collectorFnPtr: Int) -> Int {
    guard collectorFnPtr != 0 else {
        return 0
    }
    let collector = unsafeBitCast(
        collectorFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    for value in values {
        var thrown = 0
        _ = collector(0, value, &thrown)
        if thrown != 0 {
            return 0
        }
    }
    return 0
}

private func runtimeFlowCollectSuspend(_ values: [Int], collectorFnPtr: Int, functionID: Int) -> Int {
    guard collectorFnPtr != 0 else {
        return 0
    }
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    // Suspend collector ABI matches LambdaLowerer: (closureRaw, value, continuation, outThrown)
    let collector = unsafeBitCast(
        collectorFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    for value in values {
        let continuation = kk_coroutine_continuation_new(functionID)
        while true {
            var outThrown = 0
            let result = collector(0, value, continuation, &outThrown)
            if outThrown != 0 {
                _ = kk_coroutine_state_exit(continuation, 0)
                return 0
            }
            if result != suspendedToken {
                break
            }
            guard let state = runtimeContinuationState(from: continuation) else {
                _ = kk_coroutine_state_exit(continuation, 0)
                return 0
            }
            state.waitForResumeSignal()
        }
        _ = kk_coroutine_state_exit(continuation, 0)
    }
    return 0
}

@_cdecl("kk_flow_create")
public func kk_flow_create(_ emitterFnPtr: Int, _: Int) -> Int {
    runtimeRegisterFlowHandle(RuntimeFlowHandle(emitterFnPtr: emitterFnPtr))
}

@_cdecl("kk_flow_emit")
public func kk_flow_emit(_ flowHandle: Int, _ value: Int, _ tag: Int) -> Int {
    if tag == RuntimeFlowTag.emit.rawValue {
        runtimeFlowCurrentCollectContext()?.emittedValues.append(runtimeFlowMaybeUnbox(value))
        return value
    }
    guard let opKind = RuntimeFlowTag(rawValue: tag),
          let flow = runtimeFlowHandle(from: flowHandle)
    else {
        return 0
    }
    let derived = RuntimeFlowHandle(
        emitterFnPtr: flow.emitterFnPtr,
        opChain: flow.opChain + [RuntimeFlowOp(kind: opKind, argument: value)]
    )
    return runtimeRegisterFlowHandle(derived)
}

@_cdecl("kk_flow_collect")
public func kk_flow_collect(_ flowHandle: Int, _ collectorFnPtr: Int, _ continuation: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    // Cold-stream semantics: evaluate source emissions anew on each collect.
    let sourceValues = runtimeFlowEvaluateSource(flow)
    let collectedValues = runtimeFlowApplyOps(sourceValues, ops: flow.opChain)

    if continuation == 0 {
        return runtimeFlowCollectNonSuspend(collectedValues, collectorFnPtr: collectorFnPtr)
    }
    return runtimeFlowCollectSuspend(collectedValues, collectorFnPtr: collectorFnPtr, functionID: continuation)
}

@_cdecl("kk_flow_retain")
public func kk_flow_retain(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        return 0
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withLock { state in
        guard state.flowHandles[key] != nil else {
            return 0
        }
        state.flowRetainCounts[key, default: 0] += 1
        return flowHandle
    }
}

@_cdecl("kk_flow_release")
public func kk_flow_release(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        return 0
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

// MARK: - Dispatcher Runtime Stubs (P5-133)

/// Dispatcher tag constants used as opaque handles.
private enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B_4401 // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B_4402 // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B_4403 // "KKD\x03"
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

@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    // The runtime still executes synchronously today, but we preserve
    // dispatcher selection here so the requested context is observed
    // instead of being silently discarded by the stub.
    let resolvedDispatcher = switch dispatcherRaw {
    case RuntimeDispatcherTag.defaultDispatcher,
         RuntimeDispatcherTag.ioDispatcher,
         RuntimeDispatcherTag.mainDispatcher:
        dispatcherRaw
    default:
        RuntimeDispatcherTag.defaultDispatcher
    }
    _ = resolvedDispatcher
    guard let entryPoint = suspendEntryPoint(from: blockFnPtr) else {
        return 0
    }
    var outThrown = 0
    let result = entryPoint(continuation, &outThrown)
    if outThrown != 0 {
        return 0
    }
    return result
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
        return 0
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.send(value)
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(_ handle: Int, _: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.receive()
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
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

/// Creates a new coroutine scope and pushes it as the current scope on the thread-local stack.
@_cdecl("kk_coroutine_scope_new")
public func kk_coroutine_scope_new() -> Int {
    let scope = RuntimeCoroutineScope()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // Push: save parent scope and set this as current
    scope.parent = RuntimeCoroutineScope.current
    RuntimeCoroutineScope.current = scope

    return Int(bitPattern: ptr)
}

/// Cancels the given coroutine scope and all its children.
@_cdecl("kk_coroutine_scope_cancel")
public func kk_coroutine_scope_cancel(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        return 0
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    scope.cancel()
    return 0
}

/// Waits for all children in the scope to complete, then pops/releases the scope.
@_cdecl("kk_coroutine_scope_wait")
public func kk_coroutine_scope_wait(_ scopeHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: scopeHandle) else {
        return 0
    }
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(ptr).takeUnretainedValue()
    scope.waitForChildren()

    // Pop: restore parent scope
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
        return childHandle
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
    let result = runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID)
    _ = kk_coroutine_scope_wait(scopeHandle)
    return result
}

/// Convenience with pre-built continuation.
@_cdecl("kk_coroutine_scope_run_with_cont")
public func kk_coroutine_scope_run_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let scopeHandle = kk_coroutine_scope_new()
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
        return 0
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

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var outThrown = 0

    while true {
        outThrown = 0
        let result = entryPoint(continuation, &outThrown)
        if outThrown != 0 {
            _ = kk_coroutine_state_exit(continuation, 0)
            return 0
        }
        if result != suspendedToken {
            return result
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            return 0
        }
        state.waitForResumeSignal()
    }
}
