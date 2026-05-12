import Dispatch
import Foundation

/// `CoroutineContext` element runtime (STDLIB-CORO-077) and the
/// coroutine dispatcher scheduler (STDLIB-133).
///
/// Split out from `RuntimeCoroutine.swift`.

// MARK: - CoroutineContext Elements (STDLIB-CORO-077)

/// A coroutine context is a keyed collection of context elements.
/// Elements include: dispatcher, Job, CoroutineName, CoroutineExceptionHandler.
/// Contexts compose via the `+` operator (right-hand side wins for same key).
final class RuntimeCoroutineContext: @unchecked Sendable {
    var dispatcher: Int  // 0 means "inherit from parent"
    var name: String?
    var exceptionHandler: RuntimeExceptionHandlerBox?
    var jobHandleRaw: Int

    init(
        dispatcher: Int = 0,
        name: String? = nil,
        exceptionHandler: RuntimeExceptionHandlerBox? = nil,
        jobHandleRaw: Int = 0
    ) {
        self.dispatcher = dispatcher
        self.name = name
        self.exceptionHandler = exceptionHandler
        self.jobHandleRaw = jobHandleRaw
    }

    /// Merge another context into this one. Right-hand side wins for duplicate keys.
    func plus(_ other: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
        RuntimeCoroutineContext(
            dispatcher: other.dispatcher != 0 ? other.dispatcher : self.dispatcher,
            name: other.name ?? self.name,
            exceptionHandler: other.exceptionHandler ?? self.exceptionHandler,
            jobHandleRaw: other.jobHandleRaw != 0 ? other.jobHandleRaw : self.jobHandleRaw
        )
    }
}

/// A CoroutineName element wrapping a String name.
final class RuntimeCoroutineNameBox: @unchecked Sendable {
    let name: String
    init(name: String) {
        self.name = name
    }
}

/// Register a heap-allocated object in the runtime storage so it is not GC'd.
func runtimeRegisterObject<T: AnyObject>(_ object: T) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Create a CoroutineName context element.
/// nameRaw is a pointer to a runtime string (RuntimeStringBox or interned).
@_cdecl("kk_coroutine_name_create")
public func kk_coroutine_name_create(_ nameRaw: Int) -> Int {
    let nameStr: String
    if nameRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw) {
        if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
            nameStr = stringBox.value
        } else {
            nameStr = "coroutine"
        }
    } else {
        nameStr = "coroutine"
    }
    let box = RuntimeCoroutineNameBox(name: nameStr)
    return runtimeRegisterObject(box)
}

/// Get the name string from a CoroutineName handle.
/// Returns a RuntimeStringBox pointer.
@_cdecl("kk_coroutine_name_get")
public func kk_coroutine_name_get(_ handleRaw: Int) -> Int {
    guard handleRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: handleRaw),
          let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    else {
        let emptyBox = RuntimeStringBox("")
        return runtimeRegisterObject(emptyBox)
    }
    let resultBox = RuntimeStringBox(nameBox.name)
    return runtimeRegisterObject(resultBox)
}

/// Create a CoroutineExceptionHandler from a function pointer.
/// handlerFnPtr is an opaque callable reference (a block entry point) compiled
/// from the Kotlin lambda `{ context, exception -> ... }`.  Since the compiled
/// lambda follows the standard KK ABI (first arg = value, second arg = outThrown
/// pointer), we bitcast it to the 1-arg entry point and invoke it with the
/// exception raw pointer.  If the function pointer is invalid, the handler falls
/// back to printing the exception to stderr.
@_cdecl("kk_exception_handler_create")
public func kk_exception_handler_create(_ handlerFnPtr: Int) -> Int {
    let capturedFnPtr = handlerFnPtr
    let box = RuntimeExceptionHandlerBox { throwableRaw in
        if capturedFnPtr != 0 {
            let entryPoint: KKFunctionEntryPoint1 = unsafeBitCast(capturedFnPtr, to: KKFunctionEntryPoint1.self)
            _ = entryPoint(throwableRaw, nil)
        } else {
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
    }
    return runtimeRegisterObject(box)
}

/// Invoke a CoroutineExceptionHandler with a context and exception.
@_cdecl("kk_exception_handler_invoke")
public func kk_exception_handler_invoke(_ handlerRaw: Int, _ contextRaw: Int, _ exceptionRaw: Int) {
    guard handlerRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw),
          let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self)
    else {
        return
    }
    handler.handler(exceptionRaw)
}

/// Compose two CoroutineContext elements using the + operator.
/// Each argument can be a RuntimeCoroutineContext, a dispatcher tag,
/// a RuntimeCoroutineNameBox, or a RuntimeExceptionHandlerBox.
@_cdecl("kk_context_plus")
public func kk_context_plus(_ leftRaw: Int, _ rightRaw: Int) -> Int {
    let leftCtx = resolveToCoroutineContext(leftRaw)
    let rightCtx = resolveToCoroutineContext(rightRaw)
    let merged = leftCtx.plus(rightCtx)
    return runtimeRegisterObject(merged)
}

/// Fetch a context element by key.
/// The current runtime recognizes the closed set of coroutine element handles
/// already modeled in RuntimeCoroutineContext.
@_cdecl("kk_context_get")
public func kk_context_get(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    if let match = runtimeCoroutineContextElementHandle(for: keyRaw, in: ctx) {
        return match
    }
    return 0
}

/// Fold the known coroutine context elements from left to right.
@_cdecl("kk_context_fold")
public func kk_context_fold(
    _ contextRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    let ctx = resolveToCoroutineContext(contextRaw)
    var acc = initial
    for elementRaw in runtimeCoroutineContextElementHandles(in: ctx) {
        var thrown = 0
        acc = maybeUnbox(lambda(closureRaw, acc, elementRaw, &thrown))
        if thrown != 0 {
            outThrown?.pointee = thrown
            return initial
        }
    }
    return acc
}

/// Remove a context element by key.
@_cdecl("kk_context_minusKey")
public func kk_context_minusKey(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let resolved = resolveToCoroutineContext(contextRaw)
    let reduced = runtimeCoroutineContextRemovingElement(for: keyRaw, from: resolved)
    return runtimeRegisterObject(reduced)
}

/// Extract the dispatcher from a CoroutineContext.
/// Returns a dispatcher tag (or 0 if none).
@_cdecl("kk_context_get_dispatcher")
public func kk_context_get_dispatcher(_ contextRaw: Int) -> Int {
    if isDispatcherTag(contextRaw) {
        return contextRaw
    }
    if contextRaw != 0,
       isRegisteredRuntimeObjectPointer(contextRaw),
       let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
       let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self)
    {
        return ctx.dispatcher
    }
    return 0
}

/// Intercept a continuation using its dispatcher-backed context, if any.
@_cdecl("kk_continuation_intercepted")
public func kk_continuation_intercepted(_ continuationRaw: Int) -> Int {
    guard continuationRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: continuationRaw)
    else {
        return 0
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    guard let continuation = object as? KKContinuation else {
        return continuationRaw
    }
    let intercepted = runtimeInterceptedContinuation(continuation)
    let interceptedObject = intercepted as AnyObject
    if interceptedObject === object {
        return continuationRaw
    }
    return runtimeRegisterObject(interceptedObject)
}

/// Intercept a continuation using an explicit interceptor object.
@_cdecl("kk_continuation_interceptor_intercept_continuation")
public func kk_continuation_interceptor_intercept_continuation(
    _ interceptorRaw: Int,
    _ continuationRaw: Int
) -> Int {
    let dispatcherTag = kk_context_get_dispatcher(interceptorRaw)
    guard dispatcherTag != 0,
          continuationRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: continuationRaw)
    else {
        return continuationRaw
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    guard let continuation = object as? KKContinuation else {
        return continuationRaw
    }
    let intercepted = runtimeInterceptedContinuation(using: dispatcherTag, continuation: continuation)
    let interceptedObject = intercepted as AnyObject
    if interceptedObject === object {
        return continuationRaw
    }
    return runtimeRegisterObject(interceptedObject)
}

/// Return the raw handle for a known context element matching the supplied key.
private func runtimeCoroutineContextElementHandle(for keyRaw: Int, in ctx: RuntimeCoroutineContext) -> Int? {
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self)
    {
        return ctx.dispatcher == dispatcher.tag ? ctx.dispatcher : nil
    }
    if isDispatcherTag(keyRaw) {
        return ctx.dispatcher == keyRaw ? ctx.dispatcher : nil
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    {
        return ctx.name == nameBox.name ? runtimeRegisterObject(RuntimeCoroutineNameBox(name: nameBox.name)) : nil
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       tryCast(ptr, to: RuntimeExceptionHandlerBox.self) != nil
    {
        return ctx.exceptionHandler.map { Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained($0).toOpaque())) }
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       tryCast(ptr, to: RuntimeJobHandle.self) != nil
    {
        guard ctx.jobHandleRaw == keyRaw else { return nil }
        return keyRaw
    }
    return nil
}

/// Return the raw handles for the known elements stored in the context.
private func runtimeCoroutineContextElementHandles(in ctx: RuntimeCoroutineContext) -> [Int] {
    var handles: [Int] = []
    if ctx.dispatcher != 0 {
        handles.append(ctx.dispatcher)
    }
    if let name = ctx.name {
        handles.append(runtimeRegisterObject(RuntimeCoroutineNameBox(name: name)))
    }
    if let handler = ctx.exceptionHandler {
        handles.append(Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())))
    }
    if ctx.jobHandleRaw != 0 {
        handles.append(ctx.jobHandleRaw)
    }
    return handles
}

/// Remove any known element that matches the supplied key handle.
private func runtimeCoroutineContextRemovingElement(for keyRaw: Int, from ctx: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    let next = RuntimeCoroutineContext(
        dispatcher: ctx.dispatcher,
        name: ctx.name,
        exceptionHandler: ctx.exceptionHandler,
        jobHandleRaw: ctx.jobHandleRaw
    )
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self)
    {
        if next.dispatcher == dispatcher.tag {
            next.dispatcher = 0
        }
        return next
    }
    if isDispatcherTag(keyRaw) {
        if next.dispatcher == keyRaw {
            next.dispatcher = 0
        }
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    {
        if next.name == nameBox.name {
            next.name = nil
        }
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self)
    {
        if next.exceptionHandler === handler {
            next.exceptionHandler = nil
        }
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       tryCast(ptr, to: RuntimeJobHandle.self) != nil
    {
        if next.jobHandleRaw == keyRaw {
            next.jobHandleRaw = 0
        }
        return next
    }
    return next
}

/// Extract the CoroutineName from a CoroutineContext.
/// Returns a RuntimeStringBox pointer (or 0 if no name).
@_cdecl("kk_context_get_name")
public func kk_context_get_name(_ contextRaw: Int) -> Int {
    guard contextRaw != 0,
          isRegisteredRuntimeObjectPointer(contextRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
          let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self),
          let name = ctx.name
    else {
        return 0
    }
    let resultBox = RuntimeStringBox(name)
    return runtimeRegisterObject(resultBox)
}

/// Extract the CoroutineExceptionHandler from a CoroutineContext.
/// Returns handler handle (or 0 if none).
@_cdecl("kk_context_get_exception_handler")
public func kk_context_get_exception_handler(_ contextRaw: Int) -> Int {
    guard contextRaw != 0,
          isRegisteredRuntimeObjectPointer(contextRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
          let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self),
          let handler = ctx.exceptionHandler
    else {
        return 0
    }
    let handlerPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
    return Int(bitPattern: handlerPtr)
}

/// Release a CoroutineContext (decrement reference count).
@_cdecl("kk_context_release")
public func kk_context_release(_ contextRaw: Int) {
    guard contextRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw)
    else {
        return
    }
    runtimeStorage.withLock { state in
        state.objectPointers.remove(UInt(bitPattern: ptr))
    }
    Unmanaged<AnyObject>.fromOpaque(ptr).release()
}

/// withContext with a full CoroutineContext (not just a dispatcher tag).
/// Extracts the dispatcher from the context and delegates to the dispatcher-
/// aware withContext, while propagating context elements (name, handler).
@_cdecl("kk_with_context_full")
public func kk_with_context_full(_ contextRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    let resolvedCtx = resolveToCoroutineContext(contextRaw)
    let dispatcherTag = resolvedCtx.dispatcher != 0
        ? resolvedCtx.dispatcher
        : RuntimeDispatcherTag.defaultDispatcher

    if let contState = runtimeContinuationState(from: continuation) {
        if let name = resolvedCtx.name, let scope = contState.scope {
            scope.name = name
        }
    }

    return kk_with_context(dispatcherTag, blockFnPtr, continuation)
}

/// Check if a raw Int value is a known dispatcher tag.
private func isDispatcherTag(_ raw: Int) -> Bool {
    raw == RuntimeDispatcherTag.defaultDispatcher ||
    raw == RuntimeDispatcherTag.ioDispatcher ||
    raw == RuntimeDispatcherTag.mainDispatcher
}

private func isRegisteredRuntimeObjectPointer(_ raw: Int) -> Bool {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return false
    }
    return runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
}

/// Convert any context-like raw value to a RuntimeCoroutineContext.
/// Handles: RuntimeCoroutineContext, dispatcher tags, RuntimeCoroutineNameBox,
/// RuntimeExceptionHandlerBox.
func resolveToCoroutineContext(_ raw: Int) -> RuntimeCoroutineContext {
    if raw == 0 {
        return RuntimeCoroutineContext()
    }
    if isDispatcherTag(raw) {
        return RuntimeCoroutineContext(dispatcher: raw)
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return RuntimeCoroutineContext()
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return RuntimeCoroutineContext(dispatcher: RuntimeDispatcherTag.defaultDispatcher)
    }
    if let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self) {
        return ctx
    }
    if let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self) {
        return RuntimeCoroutineContext(name: nameBox.name)
    }
    if let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self) {
        return RuntimeCoroutineContext(exceptionHandler: handler)
    }
    if tryCast(ptr, to: RuntimeJobHandle.self) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    if tryCast(ptr, to: RuntimeAsyncTask.self) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    return RuntimeCoroutineContext(dispatcher: raw)
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
func dispatchQueue(for dispatcherTag: Int) -> DispatchQueue {
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
///
/// STDLIB-CORO-077: Also handles RuntimeCoroutineContext objects. If dispatcherRaw
/// is a pointer to a RuntimeCoroutineContext, the dispatcher is extracted from it
/// and context elements (name, exception handler) are propagated.
@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    // STDLIB-CORO-077: If dispatcherRaw is a RuntimeCoroutineContext, delegate
    // to kk_with_context_full which handles context element propagation.
    if !isDispatcherTag(dispatcherRaw), dispatcherRaw != 0,
       isRegisteredRuntimeObjectPointer(dispatcherRaw),
       let ptr = UnsafeMutableRawPointer(bitPattern: dispatcherRaw),
       runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
       tryCast(ptr, to: RuntimeCoroutineContext.self) != nil
    {
        return kk_with_context_full(dispatcherRaw, blockFnPtr, continuation)
    }

    let resolvedDispatcher = switch dispatcherRaw {
    case RuntimeDispatcherTag.defaultDispatcher,
         RuntimeDispatcherTag.ioDispatcher,
         RuntimeDispatcherTag.mainDispatcher:
        dispatcherRaw
    default:
        RuntimeDispatcherTag.defaultDispatcher
    }
    let dispatcher = runtimeResolveDispatcher(from: resolvedDispatcher)

    guard suspendEntryPoint(from: blockFnPtr) != nil else {
        // Clean up the continuation to avoid leaking coroutine state.
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

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
    if dispatcher.tag == RuntimeDispatcherTag.mainDispatcher && Thread.isMainThread {
        let savedScope = RuntimeCoroutineScope.current
        let savedDispatcher = RuntimeDispatcher.current
        defer { RuntimeCoroutineScope.current = savedScope }
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = parentScope
        RuntimeDispatcher.current = dispatcher
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

    dispatcher.dispatchAsync {
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

