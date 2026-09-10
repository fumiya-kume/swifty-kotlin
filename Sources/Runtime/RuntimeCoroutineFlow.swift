import Dispatch
import Foundation

// swiftlint:disable file_length

// Flow runtime (STDLIB-088 cold/lazy stream semantics) plus Flow
// terminal operators, Flow builders, and SharedFlow / StateFlow
// runtime entry points.
//
// Split out from `RuntimeCoroutine.swift` to keep each runtime source
// scoped to a single coroutine concern.

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
    case catchHandler = 6
    case retry = 7
    case retryWhen = 8
    case onErrorReturn = 9
    case onErrorResume = 10
    case transform = 11
    case takeWhile = 12
    case dropWhile = 13
    case buffer = 14
    case conflate = 15
    case flowOn = 16
    case debounce = 17
    case sample = 18
    case delayEach = 19
    case onCompletion = 20
}

struct RuntimeFlowEvent {
    let value: Int
    let timestamp: UInt64
}

private struct RuntimeFlowOp {
    let kind: RuntimeFlowTag
    let argument: Int
}

/// Factory for the channel used by one `channelFlow`/`callbackFlow` collect.
/// The template continuation is kept alive only to retain captured values;
/// every collection receives a fresh continuation and channel.
private final class RuntimeChannelProducer {
    let emitterFnPtr: Int
    let functionID: Int
    let templateState: RuntimeContinuationState?

    init(emitterFnPtr: Int, templateContinuation: Int) {
        self.emitterFnPtr = emitterFnPtr
        let state = runtimeContinuationState(from: templateContinuation)
        self.templateState = state
        self.functionID = state.map { Int($0.functionID) } ?? 0

        // The producer flow owns the state through `templateState`; release
        // the opaque continuation's original runtime retain now that it is
        // no longer used as an executable continuation.
        if state != nil, templateContinuation != 0 {
            _ = kk_coroutine_state_exit(templateContinuation, 0)
        }
    }

    func start() -> Int {
        let continuation = kk_coroutine_continuation_new(functionID)
        if let templateState,
           let state = runtimeContinuationState(from: continuation)
        {
            state.launcherArgs = templateState.launcherArgs.filter { $0.key != 0 }
        }
        return runtimeKxMiniProduceWithCont(
            emitterFnPtr,
            continuation,
            channelCapacity: 64
        )
    }
}

private enum RuntimeFlowSource {
    case emitter(fnPtr: Int, continuation: Int)
    case channelProducer(RuntimeChannelProducer)
    case fixed([RuntimeFlowEvent])
    case merge([Int])
    case zip(Int, Int, Int)
    case combine(Int, Int, Int)
    case flatMapConcat(Int, Int)
    case flatMapMerge(Int, Int)
    case flatMapLatest(Int, Int)
}

private enum RuntimeFlowErrorHandlerKind {
    case catchHandler(Int)
    case retry(Int)
    case retryWhen(Int)
    case onErrorReturn(Int)
    case onErrorResume(Int)
}

private struct RuntimeFlowStage {
    let normalOps: [RuntimeFlowOp]
    let handler: RuntimeFlowErrorHandlerKind?
}

private struct RuntimeFlowExecutionResult {
    var values: [Int]
    var failure: Int?
}

/// Collect context tracks the lazy pipeline state for a single collect call.
/// Each emitted value passes through the operator chain one at a time (lazy).
/// `cancelled` is reserved for future use by cancellation-aware operators
/// (e.g. coroutine-based emitters that check for cooperative cancellation).
/// Currently, short-circuiting is handled by `runtimeFlowTakeExhausted` after
/// each element delivery rather than through this flag.
final class RuntimeFlowCollectContext {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    var emittedValues: [Int] = []
    var emittedEvents: [RuntimeFlowEvent] = []
    var cancelled = false
    // A collector may synchronously collect another flow and emit into its
    // enclosing builder. In that case `kk_flow_emit(0, ...)` must skip this
    // context and target the nearest enclosing emitter context, otherwise the
    // collector is invoked recursively until the stack overflows.
    var invokingCollector = false
    var emitHandler: ((Int) -> Int)?
}

/// Opaque flow handle. Immutable operation chain; source emitter is re-executed
/// for every collect to guarantee cold-stream semantics.
/// When `fixedValues` is non-nil, the flow is backed by flowOf and the emitter
/// function pointer is ignored.
private final class RuntimeFlowHandle {
    let source: RuntimeFlowSource
    let opChain: [RuntimeFlowOp]
    let fixedValues: [Int]?

    var emitterFnPtr: Int {
        if case let .emitter(emitterFnPtr, _) = source {
            return emitterFnPtr
        }
        return 0
    }

    /// Continuation carrying captured values for a capturing `flow { }` builder.
    /// Zero for non-capturing builders, whose emitter is invoked directly.
    var emitterContinuation: Int {
        if case let .emitter(_, continuation) = source {
            return continuation
        }
        return 0
    }

    init(source: RuntimeFlowSource, opChain: [RuntimeFlowOp] = [], fixedValues: [Int]? = nil) {
        self.source = source
        self.opChain = opChain
        self.fixedValues = fixedValues
    }

    convenience init(
        emitterFnPtr: Int,
        emitterContinuation: Int = 0,
        opChain: [RuntimeFlowOp] = [],
        fixedValues: [Int]? = nil
    ) {
        if let fixedValues {
            let fixedEvents = fixedValues.enumerated().map { index, value in
                RuntimeFlowEvent(value: value, timestamp: UInt64(index))
            }
            self.init(source: .fixed(fixedEvents), opChain: opChain, fixedValues: fixedValues)
        } else {
            self.init(
                source: .emitter(fnPtr: emitterFnPtr, continuation: emitterContinuation),
                opChain: opChain,
                fixedValues: nil
            )
        }
    }
}

/// Invoke a flow builder emitter, honoring the closure-capture ABI.
///
/// A capturing `flow { }` builder is lowered to a launcher thunk plus a
/// continuation whose launcher-arg slots hold the captured values; the runtime
/// invokes the thunk with that continuation so the emitter receives its
/// captures. Non-capturing builders keep the direct `(outThrown)` ABI.
private func runtimeFlowInvokeEmitter(_ flow: RuntimeFlowHandle, outThrown: inout Int) {
    let continuation = flow.emitterContinuation
    if continuation != 0 {
        if let context = runtimeFlowCurrentCollectContext() {
            runtimeContinuationState(from: continuation)?.flowCollectContext = context
        }
        _ = runSuspendEntryLoopWithContinuation(
            entryPointRaw: flow.emitterFnPtr,
            continuation: continuation,
            outThrown: &outThrown
        )
    } else {
        let emitter = unsafeBitCast(
            flow.emitterFnPtr,
            to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self
        )
        _ = emitter(&outThrown)
    }
}

private func runtimeRegisterFlowHandle(_ flow: RuntimeFlowHandle) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(flow).toOpaque())
    let key = UInt(bitPattern: ptr)
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(key)
    }
    runtimeStorage.withFlowLock { state in
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
    return runtimeStorage.withFlowLock { state in
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

func runtimeFlowCurrentCollectContext() -> RuntimeFlowCollectContext? {
    runtimeFlowCollectStackBox().stack.last
}

private func runtimeFlowWithContinuationContext<T>(
    _ context: RuntimeFlowCollectContext,
    _ body: () -> T
) -> T {
    let previous = RuntimeContinuationState.current?.flowCollectContext
    RuntimeContinuationState.current?.flowCollectContext = context
    defer { RuntimeContinuationState.current?.flowCollectContext = previous }
    return body()
}

/// Select the context that owns the current emitter call. A flow collector
/// can collect a nested source, so the top stack frame may belong to the
/// source being consumed rather than to the builder that is currently
/// executing `emit`.
private func runtimeFlowCurrentEmitContext() -> RuntimeFlowCollectContext? {
    runtimeFlowCollectStackBox().stack.reversed().first { !$0.invokingCollector }
        ?? RuntimeContinuationState.current?.flowCollectContext
}

private func runtimeFlowSortEvents(_ events: [RuntimeFlowEvent]) -> [RuntimeFlowEvent] {
    events.enumerated().sorted { lhs, rhs in
        if lhs.element.timestamp == rhs.element.timestamp {
            return lhs.offset < rhs.offset
        }
        return lhs.element.timestamp < rhs.element.timestamp
    }.map(\.element)
}

private func runtimeFlowIsStreamLevelOp(_ kind: RuntimeFlowTag) -> Bool {
    switch kind {
    case .conflate, .flowOn, .debounce, .sample, .delayEach, .buffer:
        return true
    default:
        return false
    }
}

private func runtimeFlowApplyConflate(_ events: [RuntimeFlowEvent]) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    var conflated: [RuntimeFlowEvent] = []
    conflated.reserveCapacity(events.count)
    var pending = events[0]
    let bucketSizeNs: UInt64 = 1_000_000
    for event in events.dropFirst() {
        if event.timestamp / bucketSizeNs == pending.timestamp / bucketSizeNs {
            pending = event
        } else {
            conflated.append(pending)
            pending = event
        }
    }
    conflated.append(pending)
    return conflated
}

private func runtimeFlowApplyDebounce(_ events: [RuntimeFlowEvent], intervalMs: Int) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    let intervalNs = UInt64(max(0, intervalMs)) * 1_000_000
    guard intervalNs > 0 else { return events }
    var debounced: [RuntimeFlowEvent] = []
    debounced.reserveCapacity(events.count)
    for index in events.indices {
        let current = events[index]
        let nextTimestamp = index + 1 < events.count ? events[index + 1].timestamp : nil
        if let nextTimestamp, nextTimestamp <= current.timestamp + intervalNs {
            continue
        }
        debounced.append(RuntimeFlowEvent(value: current.value, timestamp: current.timestamp + intervalNs))
    }
    return debounced
}

private func runtimeFlowApplySample(_ events: [RuntimeFlowEvent], intervalMs: Int) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    let intervalNs = UInt64(max(1, intervalMs)) * 1_000_000
    let finalTimestamp = events.last!.timestamp
    var sampled: [RuntimeFlowEvent] = []
    var tick = intervalNs
    var startIndex = 0
    while tick <= finalTimestamp {
        var latest: RuntimeFlowEvent?
        var index = startIndex
        while index < events.count, events[index].timestamp <= tick {
            latest = events[index]
            index += 1
        }
        if let latest {
            sampled.append(RuntimeFlowEvent(value: latest.value, timestamp: tick))
            startIndex = index
        }
        tick += intervalNs
    }
    if let lastEvent = events.last, sampled.last?.value != lastEvent.value {
        sampled.append(RuntimeFlowEvent(value: lastEvent.value, timestamp: max(lastEvent.timestamp, sampled.last?.timestamp ?? 0)))
    }
    return sampled
}

private func runtimeFlowApplyStreamOps(
    _ events: [RuntimeFlowEvent],
    ops: [RuntimeFlowOp]
) -> [RuntimeFlowEvent]? {
    var currentEvents = runtimeFlowSortEvents(events)
    for op in ops {
        switch op.kind {
        case .conflate:
            currentEvents = runtimeFlowApplyConflate(currentEvents)
        case .debounce:
            currentEvents = runtimeFlowApplyDebounce(currentEvents, intervalMs: runtimeFlowMaybeUnbox(op.argument))
        case .sample:
            currentEvents = runtimeFlowApplySample(currentEvents, intervalMs: runtimeFlowMaybeUnbox(op.argument))
        case .delayEach:
            let intervalMs = max(0, runtimeFlowMaybeUnbox(op.argument))
            let intervalNs = UInt64(intervalMs) * 1_000_000
            var delayed: [RuntimeFlowEvent] = []
            delayed.reserveCapacity(currentEvents.count)

            // 遅延がある場合は実際に待機する
            if intervalMs > 0 {
                let group = DispatchGroup()

                // ThreadSafeなコンテナを使用
                class DelayedEventsContainer: @unchecked Sendable {
                    private var events: [RuntimeFlowEvent] = []
                    private let lock = NSLock()

                    func append(_ event: RuntimeFlowEvent) {
                        lock.lock()
                        events.append(event)
                        lock.unlock()
                    }

                    func getAll() -> [RuntimeFlowEvent] {
                        lock.lock()
                        let result = events
                        lock.unlock()
                        return result
                    }
                }

                let container = DelayedEventsContainer()

                // 並列実行で各イベントの遅延を計算
                for (index, event) in currentEvents.enumerated() {
                    group.enter()
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(intervalMs * index)) {
                        let delayedEvent = RuntimeFlowEvent(
                            value: event.value,
                            timestamp: event.timestamp + intervalNs * UInt64(index + 1)
                        )
                        container.append(delayedEvent)
                        group.leave()
                    }
                }
                group.wait()

                // 並列実行が完了したら、結果をメインのdelayedにコピー
                delayed = container.getAll()
            } else {  // 遅延がない場合はタイムスタンプのみ操作
                for event in currentEvents {
                    delayed.append(RuntimeFlowEvent(value: event.value, timestamp: event.timestamp + intervalNs))
                }
            }
            currentEvents = delayed
        case .buffer, .flowOn, .emit:
            continue
        default:
            continue
        }
    }
    return runtimeFlowSortEvents(currentEvents)
}

private func runtimeFlowMaybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
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
    case thrown(Int)
    /// A short-circuiting op (e.g. take) signalled that collection is done.
    case done
}

private func runtimeFlowErrorHandler(for op: RuntimeFlowOp) -> RuntimeFlowErrorHandlerKind? {
    switch op.kind {
    case .catchHandler:
        return .catchHandler(op.argument)
    case .retry:
        return .retry(op.argument)
    case .retryWhen:
        return .retryWhen(op.argument)
    case .onErrorReturn:
        return .onErrorReturn(op.argument)
    case .onErrorResume:
        return .onErrorResume(op.argument)
    default:
        return nil
    }
}

private func runtimeFlowBuildStages(_ ops: [RuntimeFlowOp]) -> [RuntimeFlowStage] {
    var stages: [RuntimeFlowStage] = []
    var pendingNormalOps: [RuntimeFlowOp] = []

    for op in ops {
        if let handler = runtimeFlowErrorHandler(for: op) {
            stages.append(RuntimeFlowStage(normalOps: pendingNormalOps, handler: handler))
            pendingNormalOps.removeAll(keepingCapacity: true)
        } else {
            pendingNormalOps.append(op)
        }
    }

    if !pendingNormalOps.isEmpty || stages.isEmpty {
        stages.append(RuntimeFlowStage(normalOps: pendingNormalOps, handler: nil))
    }

    return stages
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
                return .thrown(thrown)
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
                return .thrown(thrown)
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
                return .thrown(thrown)
            }
            // onEach does not transform the value; pass it through.

        case .distinctUntilChanged:
            if let last = lastValues[index], last == current {
                return .filtered
            }
            lastValues[index] = current

        case .transform:
            guard op.argument != 0 else {
                return .filtered
            }
            // transform blocks have ABI (value, outThrown) — two args, not three.
            // Push a temporary collect context so that emit() calls inside the
            // transform block are captured rather than leaking to the outer context.
            let transformFn = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            let transformCtx = RuntimeFlowCollectContext()
            var transformedValues: [Int] = []
            transformCtx.emitHandler = { v in
                transformedValues.append(runtimeFlowMaybeUnbox(v))
                return v
            }
            runtimeFlowPushCollectContext(transformCtx)
            var thrown = 0
            _ = transformFn(current, &thrown)
            runtimeFlowPopCollectContext()
            if thrown != 0 {
                return .thrown(thrown)
            }
            // Use the first emitted value as `current` for the remainder of
            // the op chain.  Additional values are lost in this single-element
            // path; the multi-value case is handled by
            // runtimeFlowCollectStreamingWithTransform.
            guard let first = transformedValues.first else {
                return .filtered
            }
            current = first

        case .takeWhile:
            guard op.argument != 0 else {
                return .done
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            if runtimeFlowMaybeUnbox(decision) == 0 {
                return .done
            }

        case .dropWhile:
            guard op.argument != 0 else {
                continue
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            if runtimeFlowMaybeUnbox(decision) != 0 {
                return .filtered
            }

        case .catchHandler, .retry, .retryWhen, .onErrorReturn, .onErrorResume:
            continue

        case .onCompletion:
            // onCompletion is a completion-only handler; pass elements through unchanged.
            continue

        case .buffer, .conflate, .flowOn, .debounce, .sample, .delayEach:
            continue
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

private func runtimeFlowRunNormalStage(
    _ input: RuntimeFlowExecutionResult,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]
    var emitted: [Int] = []

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }

    for rawValue in input.values {
        let result = runtimeFlowApplyOpsLazy(
            rawValue,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            emitted.append(value)
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return RuntimeFlowExecutionResult(values: emitted, failure: nil)
            }
        case .filtered:
            continue
        case .thrown(let failure):
            return RuntimeFlowExecutionResult(values: emitted, failure: failure)
        case .done:
            return RuntimeFlowExecutionResult(values: emitted, failure: nil)
        }
    }

    return RuntimeFlowExecutionResult(values: emitted, failure: input.failure)
}

private func runtimeFlowRunSourceStage(
    _ flow: RuntimeFlowHandle,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]
    var emitted: [Int] = []
    var failure: Int?

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }

    let processValue: (Int) -> Int = { rawValue in
        let result = runtimeFlowApplyOpsLazy(
            rawValue,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            emitted.append(value)
            return runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) ? runtimeFlowStopSentinel : value
        case .filtered:
            return rawValue
        case .thrown(let thrown):
            failure = thrown
            return runtimeFlowStopSentinel
        case .done:
            return runtimeFlowStopSentinel
        }
    }

    if let fixedValues = flow.fixedValues {
        for value in fixedValues {
            // swiftlint:disable:next for_where
            if processValue(value) == runtimeFlowStopSentinel {
                break
            }
        }
        return RuntimeFlowExecutionResult(values: emitted, failure: failure)
    }

    if case let .channelProducer(producer) = flow.source {
        let channelHandle = producer.start()
        defer { _ = kk_channel_close(channelHandle) }

        var events: [RuntimeFlowEvent] = []
        while true {
            var value = 0
            let status = kk_channel_receive(channelHandle, 0, &value)
            guard status == kChannelResultSuccess else { break }
            events.append(RuntimeFlowEvent(
                value: runtimeFlowMaybeUnbox(value),
                timestamp: DispatchTime.now().uptimeNanoseconds
            ))
        }

        let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
        for event in processedEvents {
            if processValue(event.value) == runtimeFlowStopSentinel {
                break
            }
        }
        return RuntimeFlowExecutionResult(values: emitted, failure: failure)
    }

    guard flow.emitterFnPtr != 0 else {
        return RuntimeFlowExecutionResult(values: emitted, failure: failure)
    }

    let context = RuntimeFlowCollectContext()
    context.emitHandler = processValue
    runtimeFlowPushCollectContext(context)

    var outThrown = 0
    runtimeFlowWithContinuationContext(context) {
        runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
    }
    runtimeFlowPopCollectContext()

    if failure == nil, outThrown != 0 {
        failure = outThrown
    }
    return RuntimeFlowExecutionResult(values: emitted, failure: failure)
}

private func runtimeFlowHasErrorHandlers(_ ops: [RuntimeFlowOp]) -> Bool {
    ops.contains { runtimeFlowErrorHandler(for: $0) != nil || $0.kind == .onCompletion }
}

/// Invoke all onCompletion handlers in the op chain.
/// `failure`: nil on success, non-zero exception pointer on error.
/// Returns the first exception thrown by a handler, or nil if all handlers completed normally.
@discardableResult
private func runtimeFlowFireCompletionHandlers(_ ops: [RuntimeFlowOp], failure: Int?) -> Int? {
    var firstThrown: Int?
    for op in ops where op.kind == .onCompletion {
        guard op.argument != 0 else { continue }
        let handler = unsafeBitCast(
            op.argument,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = handler(0, failure ?? 0, &thrown)
        if thrown != 0 && firstThrown == nil {
            firstThrown = thrown
        }
    }
    return firstThrown
}

private func runtimeFlowInvokeCatchHandler(_ handlerFnPtr: Int, failure: Int) -> Int? {
    guard handlerFnPtr != 0 else {
        return nil
    }
    let handler = unsafeBitCast(
        handlerFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    _ = handler(0, failure, &thrown)
    return thrown == 0 ? nil : thrown
}

private func runtimeFlowInvokeRetryWhenPredicate(
    _ predicateFnPtr: Int,
    failure: Int,
    attempt: Int
) -> (shouldRetry: Bool, failure: Int?) {
    guard predicateFnPtr != 0 else {
        return (false, failure)
    }
    let predicate = unsafeBitCast(
        predicateFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let decision = predicate(0, failure, attempt, &thrown)
    if thrown != 0 {
        return (false, thrown)
    }
    return (runtimeFlowMaybeUnbox(decision) != 0, nil)
}

private func runtimeFlowApplyErrorHandler(
    _ current: RuntimeFlowExecutionResult,
    handler: RuntimeFlowErrorHandlerKind,
    attemptProvider: () -> RuntimeFlowExecutionResult,
    stageOps: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let initialFailure = current.failure else {
        return current
    }

    switch handler {
    case .catchHandler(let handlerFnPtr):
        return RuntimeFlowExecutionResult(
            values: current.values,
            failure: runtimeFlowInvokeCatchHandler(handlerFnPtr, failure: initialFailure)
        )

    case .onErrorReturn(let fallbackValue):
        var values = current.values
        values.append(runtimeFlowMaybeUnbox(fallbackValue))
        return RuntimeFlowExecutionResult(values: values, failure: nil)

    case .onErrorResume(let fallbackFlowHandle):
        var values = current.values
        guard let fallbackFlow = runtimeFlowHandle(from: fallbackFlowHandle) else {
            return current
        }
        let resumed = runtimeFlowEvaluate(flow: fallbackFlow)
        values.append(contentsOf: resumed.values)
        return RuntimeFlowExecutionResult(values: values, failure: resumed.failure)

    case .retry(let retryCountRaw):
        let retryCount = max(0, runtimeFlowMaybeUnbox(retryCountRaw))
        var aggregate = current.values
        var failure: Int? = initialFailure
        var attempt = 0

        while failure != nil, attempt < retryCount {
            let retried = runtimeFlowRunNormalStage(attemptProvider(), ops: stageOps)
            aggregate.append(contentsOf: retried.values)
            failure = retried.failure
            attempt += 1
        }

        return RuntimeFlowExecutionResult(values: aggregate, failure: failure)

    case .retryWhen(let predicateFnPtr):
        var aggregate = current.values
        var failure: Int? = initialFailure
        var attempt = 0

        while let currentFailure = failure {
            let decision = runtimeFlowInvokeRetryWhenPredicate(
                predicateFnPtr,
                failure: currentFailure,
                attempt: attempt
            )
            if let predicateFailure = decision.failure {
                return RuntimeFlowExecutionResult(values: aggregate, failure: predicateFailure)
            }
            guard decision.shouldRetry else {
                return RuntimeFlowExecutionResult(values: aggregate, failure: currentFailure)
            }

            let retried = runtimeFlowRunNormalStage(attemptProvider(), ops: stageOps)
            aggregate.append(contentsOf: retried.values)
            failure = retried.failure
            attempt += 1
        }

        return RuntimeFlowExecutionResult(values: aggregate, failure: nil)
    }
}

private func runtimeFlowRunAdvancedSource(
    _ flow: RuntimeFlowHandle,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult? {
    switch flow.source {
    case .flatMapConcat(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapConcat(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .flatMapMerge(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapMerge(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .flatMapLatest(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapLatest(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .merge(let handles):
        return runtimeFlowEvaluateMerge(flowHandles: handles, ops: ops)
    case .zip(let left, let right, let combiner):
        return runtimeFlowEvaluateZip(leftHandle: left, rightHandle: right, combinerFnPtr: combiner, ops: ops)
    case .combine(let left, let right, let combiner):
        return runtimeFlowEvaluateCombine(leftHandle: left, rightHandle: right, combinerFnPtr: combiner, ops: ops)
    default:
        return nil
    }
}

private func runtimeFlowExecuteStages(
    flow: RuntimeFlowHandle,
    stages: [RuntimeFlowStage],
) -> RuntimeFlowExecutionResult {
    var current = RuntimeFlowExecutionResult(values: [], failure: nil)
    var stageAttemptProvider: () -> RuntimeFlowExecutionResult = { RuntimeFlowExecutionResult(values: [], failure: nil) }

    for (index, stage) in stages.enumerated() {
        if index == 0 {
            if let advancedResult = runtimeFlowRunAdvancedSource(flow, ops: stage.normalOps) {
                current = advancedResult
            } else {
                current = runtimeFlowRunSourceStage(flow, ops: stage.normalOps)
            }
            let capturedFlow = flow
            let capturedOps = stage.normalOps
            stageAttemptProvider = {
                if let advanced = runtimeFlowRunAdvancedSource(capturedFlow, ops: capturedOps) {
                    return advanced
                }
                return runtimeFlowRunSourceStage(capturedFlow, ops: capturedOps)
            }
        } else {
            current = runtimeFlowRunNormalStage(current, ops: stage.normalOps)
        }
        if let handler = stage.handler {
            current = runtimeFlowApplyErrorHandler(
                current,
                handler: handler,
                attemptProvider: stageAttemptProvider,
                stageOps: stage.normalOps
            )
        }
        let snapshot = current
        if index != 0 {
            stageAttemptProvider = { snapshot }
        }
    }

    return current
}

private func runtimeFlowEvaluate(flow: RuntimeFlowHandle) -> RuntimeFlowExecutionResult {
    runtimeFlowExecuteStages(flow: flow, stages: runtimeFlowBuildStages(flow.opChain))
}

/// Returns true when `flow` uses an advanced source type that requires the
/// evaluate path (flatMapConcat, flatMapMerge, flatMapLatest, merge, zip,
/// combine).  Simple `.emitter` and `.fixed` sources can use the faster
/// streaming path; advanced sources must go through runtimeFlowEvaluate.
private func runtimeFlowHasAdvancedSource(_ flow: RuntimeFlowHandle) -> Bool {
    switch flow.source {
    case .emitter, .channelProducer, .fixed:
        return false
    default:
        // .flatMapConcat, .flatMapMerge, .flatMapLatest, .merge, .zip, .combine
        return true
    }
}

/// Cold-stream collect: re-execute the source emitter, apply the operator chain,
/// then deliver the resulting values to the collector.
private func runtimeFlowCollectLazy(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    let hasOnCompletion = flow.opChain.contains { $0.kind == .onCompletion }
    // Advanced sources (flatMapConcat, flatMapMerge, merge, zip, combine, etc.)
    // are not handled by runtimeFlowCollectStreaming which only processes
    // .emitter and .fixed sources.  Route them through runtimeFlowEvaluate so
    // that they produce values correctly.
    if !runtimeFlowHasErrorHandlers(flow.opChain) && !runtimeFlowHasAdvancedSource(flow) {
        let retVal = runtimeFlowCollectStreaming(
            flow,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation
        )
        if hasOnCompletion {
            let streamingFailure: Int? = retVal != 0 ? retVal : nil
            if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: streamingFailure) {
                return handlerException
            }
        }
        return retVal
    }
    let result = runtimeFlowEvaluate(flow: flow)
    for value in result.values {
        let delivered = runtimeFlowDeliverValue(
            value,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation
        )
        if !delivered {
            if hasOnCompletion {
                if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure) {
                    return handlerException
                }
            }
            return 0
        }
    }
    if hasOnCompletion {
        if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure) {
            return handlerException
        }
    }
    return result.failure ?? 0
}

private func runtimeFlowCollectStreaming(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    let ops = flow.opChain
    let hasStreamLevelOps = ops.contains(where: { runtimeFlowIsStreamLevelOp($0.kind) })
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: Int] = [:]

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return 0
    }

    let deliverValue: (Int) -> Bool = { value in
        let delivered = runtimeFlowDeliverValue(
            value,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation
        )
        return delivered && !runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters)
    }

    if let fixedValues = flow.fixedValues {
        if hasStreamLevelOps {
            let events = fixedValues.enumerated().map { index, value in
                RuntimeFlowEvent(value: value, timestamp: UInt64(index))
            }
            let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) {
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

        for value in fixedValues {
            let result = runtimeFlowApplyOpsLazy(
                value,
                ops: ops,
                takeCounters: &takeCounters,
                lastValues: &lastValues
            )

            switch result {
            case .emit(let value):
                if !deliverValue(value) {
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

    if case let .channelProducer(producer) = flow.source {
        let channelHandle = producer.start()
        defer { _ = kk_channel_close(channelHandle) }

        if hasStreamLevelOps {
            var events: [RuntimeFlowEvent] = []
            while true {
                var value = 0
                let status = kk_channel_receive(channelHandle, 0, &value)
                guard status == kChannelResultSuccess else { break }
                events.append(RuntimeFlowEvent(
                    value: runtimeFlowMaybeUnbox(value),
                    timestamp: DispatchTime.now().uptimeNanoseconds
                ))
            }
            let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) { return 0 }
                case .filtered:
                    continue
                case .thrown, .done:
                    return 0
                }
            }
            return 0
        }

        while true {
            var value = 0
            let status = kk_channel_receive(channelHandle, 0, &value)
            guard status == kChannelResultSuccess else { break }
            switch runtimeFlowApplyOpsLazy(
                runtimeFlowMaybeUnbox(value),
                ops: ops,
                takeCounters: &takeCounters,
                lastValues: &lastValues
            ) {
            case .emit(let value):
                if !deliverValue(value) { return 0 }
            case .filtered:
                continue
            case .thrown, .done:
                return 0
            }
        }
        return 0
    }

    guard flow.emitterFnPtr != 0 else {
        return 0
    }

    if hasStreamLevelOps {
        let context = RuntimeFlowCollectContext()
        runtimeFlowPushCollectContext(context)

        var outThrown = 0
        runtimeFlowWithContinuationContext(context) {
            runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
        }
        runtimeFlowPopCollectContext()

        if outThrown == 0 {
            let processedEvents = runtimeFlowApplyStreamOps(context.emittedEvents, ops: ops) ?? context.emittedEvents
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) {
                        return 0
                    }
                case .filtered:
                    continue
                case .thrown, .done:
                    return 0
                }
            }
        }
        return 0
    }

    // If the op chain contains a transform op, use a specialised path that
    // correctly fans out the 1-to-many transform semantics.
    let hasTransformOp = ops.contains(where: { $0.kind == .transform })

    let context = RuntimeFlowCollectContext()
    context.emitHandler = { rawValue in
        if hasTransformOp {
            // Locate the first transform op and split the chain.
            guard let transformIdx = ops.firstIndex(where: { $0.kind == .transform }) else {
                return rawValue
            }
            let preOps  = Array(ops[..<transformIdx])
            let postOps = Array(ops[(transformIdx + 1)...])
            let transformFnPtr = ops[transformIdx].argument

            // Apply ops before the transform to filter/map the raw value.
            var preTakeCounters = runtimeFlowInitTakeCounters(preOps)
            var preLastValues: [Int: Int] = [:]
            let preResult = runtimeFlowApplyOpsLazy(
                rawValue, ops: preOps,
                takeCounters: &preTakeCounters,
                lastValues: &preLastValues
            )
            guard case .emit(let preValue) = preResult else {
                switch preResult {
                case .filtered: return rawValue
                case .thrown(let e): return e  // propagate
                case .done: return runtimeFlowStopSentinel
                case .emit: break
                }
                return rawValue
            }

            // Call the transform block with the correct 2-arg ABI and collect
            // all values it emits.
            guard transformFnPtr != 0 else { return rawValue }
            let transformFn = unsafeBitCast(
                transformFnPtr,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var transformedValues: [Int] = []
            let transformCtx = RuntimeFlowCollectContext()
            transformCtx.emitHandler = { v in
                transformedValues.append(runtimeFlowMaybeUnbox(v))
                return v
            }
            runtimeFlowPushCollectContext(transformCtx)
            var thrown = 0
            _ = transformFn(preValue, &thrown)
            runtimeFlowPopCollectContext()

            if thrown != 0 { return thrown }  // propagate exception

            // Apply post-transform ops to each emitted value and deliver.
            var stop = false
            for tv in transformedValues {
                let result = runtimeFlowApplyOpsLazy(
                    tv, ops: postOps,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    let delivered = runtimeFlowDeliverValue(
                        value,
                        collectorFnPtr: collectorFnPtr,
                        collectorEnvPtr: collectorEnvPtr,
                        continuation: continuation,
                        owningContext: context
                    )
                    if !delivered || runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                        stop = true
                        break
                    }
                case .filtered:
                    continue
                case .thrown, .done:
                    stop = true
                }
            }
            return stop ? runtimeFlowStopSentinel : rawValue
        }

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
                collectorEnvPtr: collectorEnvPtr,
                continuation: continuation,
                owningContext: context
            )
            if !delivered || runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return runtimeFlowStopSentinel
            }
            return value
        case .filtered:
            return rawValue
        case .thrown, .done:
            return runtimeFlowStopSentinel
        }
    }
    runtimeFlowPushCollectContext(context)

    var outThrown = 0
    runtimeFlowWithContinuationContext(context) {
        runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
    }
    runtimeFlowPopCollectContext()
    return 0
}

/// Deliver a single value to the collector. Returns true on success, false if
/// the collector threw (signalling the flow should stop).
private func runtimeFlowDeliverValue(
    _ value: Int,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int,
    owningContext: RuntimeFlowCollectContext? = nil
) -> Bool {
    guard collectorFnPtr != 0 else {
        return true
    }
    let currentContext = owningContext ?? runtimeFlowCurrentCollectContext()
    currentContext?.invokingCollector = true
    defer { currentContext?.invokingCollector = false }

    if continuation == 0 {
        // Non-suspend collector ABI: (closureRaw, value, outThrown)
        let collector = unsafeBitCast(
            collectorFnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = collector(collectorEnvPtr, value, &thrown)
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
            let result = collector(collectorEnvPtr, value, cont, &thrown)
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
public func kk_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    runtimeRegisterFlowHandle(
        RuntimeFlowHandle(emitterFnPtr: emitterFnPtr, emitterContinuation: emitterContinuation)
    )
}

/// Create a cold Flow backed by a fresh runtime channel and a ProducerScope
/// receiver for each collection.
@_cdecl("kk_channel_flow_create")
public func kk_channel_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    return runtimeRegisterFlowHandle(
        RuntimeFlowHandle(
            source: .channelProducer(
                RuntimeChannelProducer(
                    emitterFnPtr: emitterFnPtr,
                    templateContinuation: emitterContinuation
                )
            )
        )
    )
}

/// `callbackFlow` shares the channel-backed implementation with `channelFlow`;
/// the distinct entry point preserves the public ABI surface.
@_cdecl("kk_callback_flow_create")
public func kk_callback_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    return runtimeRegisterFlowHandle(
        RuntimeFlowHandle(
            source: .channelProducer(
                RuntimeChannelProducer(
                    emitterFnPtr: emitterFnPtr,
                    templateContinuation: emitterContinuation
                )
            )
        )
    )
}

/// Return the flow-stop sentinel pointer. This is a unique object pointer that
/// cannot collide with any legitimate `Int` value (unlike the previous `Int.min`
/// approach). Emitters should compare the return value of `kk_flow_emit` against
/// `__kk_flow_stopped()` to detect pipeline termination.
@_cdecl("__kk_flow_stopped")
public func __kk_flow_stopped() -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.flowStopSentinelBox).toOpaque())
    runtimeStorage.withGCLock { state in
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
private let runtimeFlowStopSentinel: Int = __kk_flow_stopped()

@_cdecl("kk_flow_emit")
public func kk_flow_emit(_ flowHandle: Int, _ value: Int, _ tag: Int) -> Int {
    if tag == RuntimeFlowTag.emit.rawValue {
        let context = runtimeFlowCurrentEmitContext()
        if let context, !context.cancelled {
            let unboxed = runtimeFlowMaybeUnbox(value)
            let timestamp = DispatchTime.now().uptimeNanoseconds - context.startedAt
            context.emittedValues.append(unboxed)
            context.emittedEvents.append(RuntimeFlowEvent(value: unboxed, timestamp: timestamp))
            if let emitHandler = context.emitHandler {
                return emitHandler(unboxed)
            }
        }
        return value
    }
    guard let opKind = RuntimeFlowTag(rawValue: tag) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received unknown op tag \(tag)")
    }
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received invalid flow handle")
    }
    let source: RuntimeFlowSource = switch flow.source {
    case let .channelProducer(producer):
        .channelProducer(producer)
    case .emitter, .fixed, .merge, .zip, .combine, .flatMapConcat, .flatMapMerge, .flatMapLatest:
        .emitter(fnPtr: flow.emitterFnPtr, continuation: flow.emitterContinuation)
    }
    let derived = RuntimeFlowHandle(
        source: source,
        opChain: flow.opChain + [RuntimeFlowOp(kind: opKind, argument: value)],
        fixedValues: flow.fixedValues
    )
    return runtimeRegisterFlowHandle(derived)
}

// (a) RF-DEAD-002: Internal compatibility helpers for the bundled Flow source.
@_cdecl("__kk_flow_emit_with_timestamp")
public func __kk_flow_emit_with_timestamp(_ flowHandle: Int, _ value: Int, _ tag: Int, _ timestamp: UInt64) -> Int {
    if tag == RuntimeFlowTag.emit.rawValue {
        let context = runtimeFlowCurrentEmitContext()
        if let context, !context.cancelled {
            let unboxed = runtimeFlowMaybeUnbox(value)
            context.emittedValues.append(unboxed)
            context.emittedEvents.append(RuntimeFlowEvent(value: unboxed, timestamp: timestamp))
            if let emitHandler = context.emitHandler {
                return emitHandler(unboxed)
            }
        }
        return value
    }
    return kk_flow_emit(flowHandle, value, tag)
}

@_cdecl("kk_flow_collect")
public func kk_flow_collect(_ flowHandle: Int, _ collectorFnPtr: Int, _ collectorEnvPtr: Int, _ continuation: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    // Cold-stream semantics: re-execute source emitter and lazily push each
    // emitted value through the operator chain on every collect call.
    // For flowOf-backed flows (fixedValues != nil), the fixed values are used
    // directly without running an emitter function.
    return runtimeFlowCollectLazy(flow, collectorFnPtr: collectorFnPtr, collectorEnvPtr: collectorEnvPtr, continuation: continuation)
}

// `collectLatest` should cancel an in-flight collector invocation when a new
// value arrives and only run the collector to completion for the last value.
// The emitter/collector pipeline here delivers values synchronously (one
// collector call fully returns before the next value is produced), so there
// is no in-flight invocation to cancel; every delivered value already runs
// to completion in emission order, same as `collect`. This keeps the final
// collected/observed values correct while the true concurrent-cancellation
// semantics remain unimplemented.
@_cdecl("__kk_flow_collectLatest")
public func __kk_flow_collectLatest(_ flowHandle: Int, _ collectorFnPtr: Int, _ collectorEnvPtr: Int, _ continuation: Int) -> Int {
    kk_flow_collect(flowHandle, collectorFnPtr, collectorEnvPtr, continuation)
}

@_cdecl("__kk_flow_retain")
public func __kk_flow_retain(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_retain received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withFlowLock { state in
        guard state.flowHandles[key] != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_retain received unregistered flow handle")
        }
        state.flowRetainCounts[key, default: 0] += 1
        return flowHandle
    }
}

@_cdecl("__kk_flow_release")
public func __kk_flow_release(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_release received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    let shouldRemoveFromGC = runtimeStorage.withFlowLock { state -> Bool in
        guard let count = state.flowRetainCounts[key] else {
            return false
        }
        let nextCount = count - 1
        if nextCount <= 0 {
            state.flowRetainCounts.removeValue(forKey: key)
            state.flowHandles.removeValue(forKey: key)
            return true
        } else {
            state.flowRetainCounts[key] = nextCount
            return false
        }
    }
    if shouldRemoveFromGC {
        runtimeStorage.withGCLock { state in
            state.objectPointers.remove(key)
        }
    }
    return 0
}

// MARK: - Flow Terminal Operators (STDLIB-088)

/// Prepare take counters for the given op chain.
private func runtimeFlowInitTakeCounters(_ ops: [RuntimeFlowOp]) -> [Int: Int] {
    var takeCounters: [Int: Int] = [:]
    for (index, op) in ops.enumerated() where op.kind == .take {
        takeCounters[index] = max(0, runtimeFlowMaybeUnbox(op.argument))
    }
    return takeCounters
}

/// Collect all emitted values into a list and return the list handle.
@_cdecl("__kk_flow_to_list")
public func __kk_flow_to_list(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return registerRuntimeObject(RuntimeListBox(elements: result.values))
}

/// Return the first emitted value after applying the operator chain, or 0 if empty.
@_cdecl("__kk_flow_first")
public func __kk_flow_first(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return result.values.first ?? 0
}

@_cdecl("__kk_flow_single")
public func __kk_flow_single(_ flowHandle: Int, _: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    guard result.values.count == 1 else {
        if result.values.isEmpty {
            outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "Flow is empty.")
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Flow has more than one element."
            )
        }
        return 0
    }
    return result.values[0]
}

/// Count the number of elements emitted after applying the operator chain.
@_cdecl("__kk_flow_count")
public func __kk_flow_count(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return result.values.count
}

/// Fold: accumulate values with an initial value and an operation.
/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
@_cdecl("__kk_flow_fold")
public func __kk_flow_fold(_ flowHandle: Int, _ initial: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return initial
    }

    guard operationFnPtr != 0 else {
        return initial
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let result = runtimeFlowEvaluate(flow: flow)
    var accumulator = initial
    for value in result.values {
        var thrown = 0
        accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
        if thrown != 0 {
            runtimeFlowFireCompletionHandlers(flow.opChain, failure: thrown)
            return accumulator
        }
    }
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return accumulator
}

/// Reduce: like fold but uses the first element as the initial accumulator.
/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
@_cdecl("__kk_flow_reduce")
public func __kk_flow_reduce(_ flowHandle: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    guard operationFnPtr != 0 else {
        return 0
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let values = runtimeFlowEvaluate(flow: flow).values
    guard let first = values.first else {
        return 0
    }

    var accumulator = first
    var thrownOnReduce: Int?
    for value in values.dropFirst() {
        var thrown = 0
        accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
        if thrown != 0 {
            thrownOnReduce = thrown
            break
        }
    }
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: thrownOnReduce)
    return accumulator
}

// KSP-674: kk_flow_of / kk_flow_empty / kk_flow_as_flow removed. flowOf /
// emptyFlow / Iterable.asFlow are now Kotlin source (kotlinx.coroutines.flow)
// composed from `flow { }` (kk_flow_create) + `emit` (kk_flow_emit).

// KSP-676: StateFlow / MutableStateFlow and Flow.stateIn are now Kotlin source
// (Stdlib/kotlinx/coroutines/flow/StateFlow.kt), so the runtime handle and
// kk_mutable_state_flow_* / kk_state_flow_value / kk_flow_state_in C bridges
// have been removed.

// MARK: - Advanced Flow Operators (STDLIB-FLOW-176)


private func runtimeFlowEvaluateFlatMapConcat(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let sourceFlow = runtimeFlowHandle(from: sourceHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    guard mapperFnPtr != 0 else {
        return runtimeFlowEvaluate(flow: sourceFlow)
    }
    let mapper = unsafeBitCast(
        mapperFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let sourceResult = runtimeFlowEvaluate(flow: sourceFlow)
    if let failure = sourceResult.failure {
        return RuntimeFlowExecutionResult(values: [], failure: failure)
    }
    var all: [Int] = []
    for value in sourceResult.values {
        var thrown = 0
        let innerHandle = mapper(0, value, &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        if let innerFlow = runtimeFlowHandle(from: innerHandle) {
            let inner = runtimeFlowEvaluate(flow: innerFlow)
            all.append(contentsOf: inner.values)
            if let f = inner.failure {
                return RuntimeFlowExecutionResult(values: all, failure: f)
            }
        }
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateFlatMapMerge(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    // In the synchronous cold-stream model, merge degenerates to concat.
    runtimeFlowEvaluateFlatMapConcat(sourceHandle: sourceHandle, mapperFnPtr: mapperFnPtr, ops: ops)
}

private func runtimeFlowEvaluateFlatMapLatest(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let sourceFlow = runtimeFlowHandle(from: sourceHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    guard mapperFnPtr != 0 else {
        return runtimeFlowEvaluate(flow: sourceFlow)
    }
    let mapper = unsafeBitCast(
        mapperFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let sourceResult = runtimeFlowEvaluate(flow: sourceFlow)
    if let failure = sourceResult.failure {
        return RuntimeFlowExecutionResult(values: [], failure: failure)
    }
    var lastInnerHandle: Int = 0
    for value in sourceResult.values {
        var thrown = 0
        let innerHandle = mapper(0, value, &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: [], failure: thrown)
        }
        lastInnerHandle = innerHandle
    }
    guard lastInnerHandle != 0, let lastFlow = runtimeFlowHandle(from: lastInnerHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let inner = runtimeFlowEvaluate(flow: lastFlow)
    return runtimeFlowRunNormalStage(inner, ops: ops)
}

private func runtimeFlowEvaluateMerge(
    flowHandles: [Int],
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var all: [Int] = []
    for handle in flowHandles {
        guard let flow = runtimeFlowHandle(from: handle) else { continue }
        let result = runtimeFlowEvaluate(flow: flow)
        all.append(contentsOf: result.values)
        if let f = result.failure {
            return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: f), ops: ops)
        }
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateZip(
    leftHandle: Int,
    rightHandle: Int,
    combinerFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let leftFlow = runtimeFlowHandle(from: leftHandle),
          let rightFlow = runtimeFlowHandle(from: rightHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let leftResult  = runtimeFlowEvaluate(flow: leftFlow)
    let rightResult = runtimeFlowEvaluate(flow: rightFlow)
    if let f = leftResult.failure  { return RuntimeFlowExecutionResult(values: [], failure: f) }
    if let f = rightResult.failure { return RuntimeFlowExecutionResult(values: [], failure: f) }
    guard combinerFnPtr != 0 else { return runtimeFlowRunNormalStage(leftResult, ops: ops) }
    let combiner = unsafeBitCast(
        combinerFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let count = min(leftResult.values.count, rightResult.values.count)
    var all: [Int] = []
    all.reserveCapacity(count)
    for i in 0 ..< count {
        var thrown = 0
        let combined = combiner(0, leftResult.values[i], rightResult.values[i], &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        all.append(runtimeFlowMaybeUnbox(combined))
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateCombine(
    leftHandle: Int,
    rightHandle: Int,
    combinerFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let leftFlow = runtimeFlowHandle(from: leftHandle),
          let rightFlow = runtimeFlowHandle(from: rightHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let leftResult  = runtimeFlowEvaluate(flow: leftFlow)
    let rightResult = runtimeFlowEvaluate(flow: rightFlow)
    if let f = leftResult.failure  { return RuntimeFlowExecutionResult(values: [], failure: f) }
    if let f = rightResult.failure { return RuntimeFlowExecutionResult(values: [], failure: f) }
    guard combinerFnPtr != 0 else { return runtimeFlowRunNormalStage(leftResult, ops: ops) }
    guard !leftResult.values.isEmpty, !rightResult.values.isEmpty else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let combiner = unsafeBitCast(
        combinerFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let count = max(leftResult.values.count, rightResult.values.count)
    var all: [Int] = []
    all.reserveCapacity(count)
    for i in 0 ..< count {
        let lv = leftResult.values[min(i, leftResult.values.count - 1)]
        let rv = rightResult.values[min(i, rightResult.values.count - 1)]
        var thrown = 0
        let combined = combiner(0, lv, rv, &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        all.append(runtimeFlowMaybeUnbox(combined))
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

// MARK: @_cdecl exports

/// Create a flow that represents flatMapConcat applied to an existing flow.
/// mapperFnPtr: (closureRaw, value, outThrown) -> innerFlowHandle
@_cdecl("__kk_flow_flat_map_concat")
public func __kk_flow_flat_map_concat(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapConcat(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// Create a flow that represents flatMapMerge applied to an existing flow.
@_cdecl("__kk_flow_flat_map_merge")
public func __kk_flow_flat_map_merge(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapMerge(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// Create a flow that represents flatMapLatest applied to an existing flow.
@_cdecl("__kk_flow_flat_map_latest")
public func __kk_flow_flat_map_latest(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapLatest(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// Create a flow that merges N independent flows.
/// flowArrayHandle: handle to an array of flow handles; count: element count.
@_cdecl("__kk_flow_merge")
public func __kk_flow_merge(_ flowArrayHandle: Int, _ count: Int, _: Int) -> Int {
    var handles: [Int] = []
    handles.reserveCapacity(count)
    for i in 0 ..< count {
        let h = runtimeReadArrayElement(arrayRaw: flowArrayHandle, index: i)
        if h != 0 { handles.append(h) }
    }
    let derived = RuntimeFlowHandle(
        source: .merge(handles),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// zip two flows together with a combining function.
/// combinerFnPtr: (closureRaw, lhs, rhs, outThrown) -> result
@_cdecl("__kk_flow_zip")
public func __kk_flow_zip(_ leftHandle: Int, _ rightHandle: Int, _ combinerFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .zip(leftHandle, rightHandle, combinerFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// combine two flows with a combining function.
/// combinerFnPtr: (closureRaw, lhs, rhs, outThrown) -> result
@_cdecl("__kk_flow_combine")
public func __kk_flow_combine(_ leftHandle: Int, _ rightHandle: Int, _ combinerFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .combine(leftHandle, rightHandle, combinerFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}
