import Foundation
import Dispatch

internal final class RuntimeContinuationState {
    var functionID: Int64
    var label: Int64
    var completion: Int64
    var spillSlots: [Int64: Int64]
    var launcherArgs: [Int64: Int64]
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

internal final class RuntimeAsyncTask {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0

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
internal final class RuntimeJobHandle {
    private let lock = NSLock()
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private(set) var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0
    weak var continuationState: RuntimeContinuationState?

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
        let wasCompleted = isCompleted
        if !wasCompleted {
            isCompleted = true
        }
        let state = continuationState
        lock.unlock()
        if !wasCompleted {
            completionSemaphore.signal()
        }
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
internal final class RuntimeCoroutineScope {
    private let lock = NSLock()
    private var children: [Int] = []  // opaque handles (RuntimeJobHandle or RuntimeAsyncTask)
    private var consumedHandles: Set<Int> = []  // handles whose passRetained was consumed by user code
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

    /// Mark a child handle as consumed (its original passRetained was released by user code).
    func markConsumed(_ handle: Int) {
        lock.lock()
        consumedHandles.insert(handle)
        lock.unlock()
    }

    func waitForChildren() {
        lock.lock()
        let currentChildren = children
        let currentConsumed = consumedHandles
        children.removeAll()
        consumedHandles.removeAll()
        lock.unlock()
        for child in currentChildren {
            _ = runtimeJoinChild(child)
            if let ptr = UnsafeMutableRawPointer(bitPattern: child) {
                // Release the extra retain taken in registerChild
                Unmanaged<AnyObject>.fromOpaque(ptr).release()
                // Release the original passRetained only if user code hasn't already consumed it
                // (via kk_job_join or kk_kxmini_async_await)
                if !currentConsumed.contains(child) {
                    Unmanaged<AnyObject>.fromOpaque(ptr).release()
                    // Clean up from RuntimeStorage
                    RuntimeStorage.lock.lock()
                    RuntimeStorage.objectPointers.remove(UInt(bitPattern: ptr))
                    RuntimeStorage.lock.unlock()
                }
            }
        }
    }
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(RuntimeStorage.coroutineSuspendedBox).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return ptr
}

@_cdecl("kk_coroutine_continuation_new")
public func kk_coroutine_continuation_new(_ functionID: Int) -> Int {
    let state = RuntimeContinuationState(functionID: Int64(functionID))
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(state).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
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
        RuntimeStorage.lock.lock()
        RuntimeStorage.objectPointers.remove(UInt(bitPattern: continuationPtr))
        RuntimeStorage.lock.unlock()
        Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).release()
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
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: jobPtr))
    RuntimeStorage.lock.unlock()

    // Register with current scope if any
    if let scope = RuntimeCoroutineScope.current {
        scope.registerChild(Int(bitPattern: jobPtr))
    }

    KxMiniRuntime.launch {
        let result = runSuspendEntryLoop(entryPointRaw: entryPointRaw, functionID: functionID, jobHandle: job)
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
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: jobPtr))
    RuntimeStorage.lock.unlock()

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
    // Notify the current scope that this handle's passRetained is being consumed
    RuntimeCoroutineScope.current?.markConsumed(handle)
    let task = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeRetainedValue()
    return task.awaitResult()
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

/// Opaque handle wrapping a flow emitter function pointer and its continuation.
internal final class RuntimeFlowHandle {
    let emitterFnPtr: Int
    var collectedValues: [Int] = []

    init(emitterFnPtr: Int) {
        self.emitterFnPtr = emitterFnPtr
    }
}

@_cdecl("kk_flow_create")
public func kk_flow_create(_ emitterFnPtr: Int, _ continuation: Int) -> Int {
    let flow = RuntimeFlowHandle(emitterFnPtr: emitterFnPtr)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(flow).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: ptr)
}

@_cdecl("kk_flow_emit")
public func kk_flow_emit(_ flowHandle: Int, _ value: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        return 0
    }
    let flow = Unmanaged<RuntimeFlowHandle>.fromOpaque(ptr).takeUnretainedValue()
    flow.collectedValues.append(value)
    return value
}

@_cdecl("kk_flow_collect")
public func kk_flow_collect(_ flowHandle: Int, _ collectorFnPtr: Int, _ continuation: Int) -> Int {
    // Stub: invoke collector on each emitted value; full suspend semantics deferred
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        return 0
    }
    let flow = Unmanaged<RuntimeFlowHandle>.fromOpaque(ptr).takeUnretainedValue()
    // Collect emitted values — actual suspend-based collection is a future lowering task
    _ = flow.collectedValues
    return 0
}

// MARK: - Dispatcher Runtime Stubs (P5-133)

/// Dispatcher tag constants used as opaque handles.
private enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B4401  // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B4402        // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B4403      // "KKD\x03"
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
public func kk_with_context(_ dispatcher: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    // Stub: execute blockFnPtr on the appropriate dispatch queue.
    // For now, all dispatchers execute synchronously on the current thread.
    guard let entryPoint = suspendEntryPoint(from: blockFnPtr) else {
        return 0
    }
    var outThrown: Int = 0
    let result = entryPoint(continuation, &outThrown)
    if outThrown != 0 {
        return 0
    }
    return result
}

// MARK: - Channel Runtime Stubs (P5-134)

/// Channel with rendezvous (capacity 0) and buffered (capacity > 0) semantics.
internal final class RuntimeChannelHandle {
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
        if capacity > 0 && buffer.count >= capacity {
            lock.unlock()
            return 0
        }
        if capacity == 0 && !buffer.isEmpty {
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
        if closed && buffer.isEmpty {
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
        for _ in 0..<receiversToWake {
            receiveSemaphore.signal()
        }
        for _ in 0..<sendersToWake {
            sendSemaphore.signal()
        }
    }
}

@_cdecl("kk_channel_create")
public func kk_channel_create(_ capacity: Int) -> Int {
    let channel = RuntimeChannelHandle(capacity: capacity)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: ptr)
}

@_cdecl("kk_channel_send")
public func kk_channel_send(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.send(value)
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(_ handle: Int, _ continuation: Int) -> Int {
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
    var lastResult: Int = 0
    for i in 0..<count {
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
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
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
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()

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
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.remove(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
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
    // Notify the current scope that this handle's passRetained is being consumed
    RuntimeCoroutineScope.current?.markConsumed(jobHandle)
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    let result: Int
    if let job = obj as? RuntimeJobHandle {
        result = job.join()
    } else if let task = obj as? RuntimeAsyncTask {
        result = task.awaitResult()
    } else {
        result = 0
    }
    // Release the original passRetained from launch
    Unmanaged<AnyObject>.fromOpaque(ptr).release()
    // Clean up from RuntimeStorage
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.remove(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
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
internal func runtimeCancelChild(_ handle: Int) {
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
internal func runtimeJoinChild(_ handle: Int) -> Int {
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

// MARK: - Suspend Entry Loop

internal func runSuspendEntryLoop(entryPointRaw: Int, functionID: Int, jobHandle: RuntimeJobHandle? = nil) -> Int {
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

internal func runSuspendEntryLoopWithContinuation(entryPointRaw: Int, continuation: Int) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var outThrown: Int = 0

    while true {
        // Check cancellation before each resume (cooperative cancellation)
        if let state = runtimeContinuationState(from: continuation),
           let job = state.jobHandle, job.cancellationSnapshot() {
            _ = kk_coroutine_state_exit(continuation, 0)
            return 0
        }

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
