import Foundation

public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?

    public init(
        fqName: UnsafePointer<CChar>,
        instanceSize: UInt32,
        fieldCount: UInt32,
        fieldOffsets: UnsafePointer<UInt32>,
        vtableSize: UInt32,
        vtable: UnsafePointer<UnsafeRawPointer>,
        itable: UnsafeRawPointer?,
        gcDescriptor: UnsafeRawPointer?
    ) {
        self.fqName = fqName
        self.instanceSize = instanceSize
        self.fieldCount = fieldCount
        self.fieldOffsets = fieldOffsets
        self.vtableSize = vtableSize
        self.vtable = vtable
        self.itable = itable
        self.gcDescriptor = gcDescriptor
    }
}

struct KKObjHeader {
    var typeInfo: UnsafePointer<KTypeInfo>?
    var flags: UInt32
    var size: UInt32
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

typealias KKSuspendEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKThunkEntryPoint = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureThunkEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint1 = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint2 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint3 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKDelegateObserverEntryPoint = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

final class RuntimeStringBox {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

final class RuntimeThrowableBox {
    let message: String
    let cause: Int

    init(message: String, cause: Int = 0) {
        self.message = message
        self.cause = cause
    }
}

/// Distinct type used to identify CancellationException at runtime.
/// The runtime checks `is RuntimeCancellationBox` to distinguish cancellation from
/// regular throwables (CORO-002 / spec.md J17).
final class RuntimeCancellationBox {
    let message: String

    init(message: String = "CancellationException") {
        self.message = message
    }
}

class RuntimeArrayBox {
    var elements: [Int]

    init(length: Int) {
        elements = Array(repeating: 0, count: max(0, length))
    }
}

final class RuntimeObjectBox: RuntimeArrayBox {
    let classID: Int64

    init(length: Int, classID: Int64) {
        self.classID = classID
        super.init(length: length)
    }
}

final class RuntimePairBox {
    let first: Int
    let second: Int

    init(first: Int, second: Int) {
        self.first = first
        self.second = second
    }
}

final class RuntimeTripleBox {
    let first: Int
    let second: Int
    let third: Int

    init(first: Int, second: Int, third: Int) {
        self.first = first
        self.second = second
        self.third = third
    }
}

final class RuntimeIntBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeBoolBox {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

final class RuntimeLongBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeFloatBox {
    let value: Float

    init(_ value: Float) {
        self.value = value
    }
}

final class RuntimeDoubleBox {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }
}

final class RuntimeCharBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

enum RuntimeCallableRefKind {
    case function
    case property
}

struct RuntimeCallableRefMetadata {
    let nameRaw: Int
    let arity: Int
    let kind: RuntimeCallableRefKind
}

final class RuntimeFunctionValueBox {
    let fnPtr: Int
    let closureRaw: Int
    let arity: Int

    init(fnPtr: Int, closureRaw: Int, arity: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.arity = arity
    }
}

// MARK: - Collection Types (STDLIB-001)

/// Runtime box for `listOf(...)` / `mutableListOf(...)`.
/// Stores elements as an array of `Int` (opaque intptr_t values).
final class RuntimeListBox {
    private var storedElements: [Int]
    private let reversedViewBase: RuntimeListBox?

    init(elements: [Int]) {
        self.storedElements = elements
        self.reversedViewBase = nil
    }

    init(reversedViewOf base: RuntimeListBox) {
        self.storedElements = []
        self.reversedViewBase = base
    }

    var elements: [Int] {
        get {
            if let base = reversedViewBase {
                return Array(base.elements.reversed())
            }
            return storedElements
        }
        set {
            if let base = reversedViewBase {
                base.elements = Array(newValue.reversed())
            } else {
                storedElements = newValue
            }
        }
    }
}

/// Runtime box for `setOf(...)` / `mutableSetOf(...)`.
/// Stores unique elements in insertion order as an array of `Int`.
final class RuntimeSetBox {
    var elements: [Int]

    init(elements: [Int]) {
        self.elements = elements
    }
}

/// Runtime box for `mapOf(...)` / `mutableMapOf(...)`.
/// Stores keys and values as parallel arrays of `Int` (opaque intptr_t values).
final class RuntimeMapBox {
    var keys: [Int]
    var values: [Int]

    init(keys: [Int], values: [Int]) {
        self.keys = keys
        self.values = values
    }
}

/// Runtime box for `ArrayDeque<T>`.
/// Stores elements in a mutable array of `Int`.
final class RuntimeArrayDequeBox {
    var elements: [Int]

    init(elements: [Int]) {
        self.elements = elements
    }
}

/// Lazy wrapper for `withIndex()` result. Kotlin returns `IndexingIterable` with
/// default Object.toString() = "kotlin.collections.IndexingIterable@<hex>".
final class RuntimeIndexingIterableBox {
    let listRaw: Int

    init(listRaw: Int) {
        self.listRaw = listRaw
    }
}

/// Iterator for `withIndex()` result. Each call to `next()` yields an
/// `IndexedValue<E>` pair (index, element) represented as `RuntimePairBox`.
final class RuntimeIndexingIteratorBox {
    let elements: [Int]
    var index: Int

    init(elements: [Int]) {
        self.elements = elements
        index = 0
    }
}

/// Iterator box for `List` iteration via `for (x in list)`.
final class RuntimeListIteratorBox {
    let elements: [Int]
    var index: Int

    init(elements: [Int]) {
        self.elements = elements
        index = 0
    }
}

/// Iterator box for `String` iteration via `for (c in str)` (STDLIB-189).
final class RuntimeStringIteratorBox {
    let charRaws: [Int]
    var index: Int

    init(charRaws: [Int]) {
        self.charRaws = charRaws
        index = 0
    }
}

/// Lazy iterable view for `String.asIterable()` (STDLIB-317).
/// Stores only the string raw handle; characters are yielded on demand when
/// the iterable is consumed (e.g. via `iterator()`, `toList()`, or `for-in`).
/// In the current runtime the iterable delegates to the existing `kk_string_toList`
/// materialisation at consumption time, keeping the creation itself O(1).
final class RuntimeStringIterableBox {
    let strRaw: Int

    init(strRaw: Int) {
        self.strRaw = strRaw
    }
}

/// Iterator box for `Map` iteration via `for (entry in map)`.
final class RuntimeMapIteratorBox {
    let keys: [Int]
    let values: [Int]
    var index: Int

    init(keys: [Int], values: [Int]) {
        self.keys = keys
        self.values = values
        index = 0
    }
}

// MARK: - Sequence Types (STDLIB-003)

/// Represents a lazy operation in a sequence chain.
/// Each step stores its kind (source, map, filter, take) and a function pointer
/// for map/filter transformations. Lazy semantics: no evaluation until terminal.
enum SequenceStepKind {
    case source(elements: [Int])
    case stringSource(strRaw: Int)
    case mapStep(fnPtr: Int, closureRaw: Int)
    case filterStep(fnPtr: Int, closureRaw: Int)
    case filterNotStep(fnPtr: Int, closureRaw: Int)
    case takeStep(count: Int)
    case builder(elements: [Int])
    case generator(seed: Int, fnPtr: Int, closureRaw: Int)
    case dropStep(count: Int)
    case distinctStep
    case zipStep(otherElements: [Int])
    case takeWhileStep(fnPtr: Int, closureRaw: Int)
    case dropWhileStep(fnPtr: Int, closureRaw: Int)
    case onEachStep(fnPtr: Int, closureRaw: Int)
    /// STDLIB-HOF-022: Additional lazy transformation steps
    case mapNotNullStep(fnPtr: Int, closureRaw: Int)
    case filterNotNullStep
    case mapIndexedStep(fnPtr: Int, closureRaw: Int)
    case withIndexStep
    case flatMapStep(fnPtr: Int, closureRaw: Int)
    /// STDLIB-563: Lazy continuation-based builder.
    /// The coroutine runs the builder lambda on a background thread;
    /// each `yield()` suspends the producer until the consumer requests
    /// the next element.
    case lazyBuilder(coroutine: RuntimeSequenceCoroutine)
}

/// Runtime box for `Sequence<T>`.
/// Stores a chain of lazy steps that are only evaluated on terminal operations.
final class RuntimeSequenceBox {
    var steps: [SequenceStepKind]

    init(steps: [SequenceStepKind]) {
        self.steps = steps
    }
}

/// Runtime box for the `sequence { yield(x) }` builder.
/// Accumulates yielded elements during builder block execution.
/// Used as a fallback when the lazy coroutine path is not available.
final class RuntimeSequenceBuilderBox {
    var elements: [Int] = []
}

/// STDLIB-563: Continuation-based lazy sequence coroutine.
///
/// Runs the builder lambda on a background thread. Each call to `yield(value)`
/// suspends the producer (via `producerSemaphore`) until the consumer calls
/// `materializeAll()`, which signals the producer to continue.
///
/// The coroutine is started lazily on the first call to `materializeAll()`.
///
/// Thread protocol:
///   Producer thread (background):
///     1. Runs builder lambda
///     2. On yield(value): store value, signal consumer, wait on producer semaphore
///     3. On completion: set finished flag, signal consumer
///
///   Consumer thread (caller):
///     1. materializeAll(): signal producer, wait on consumer semaphore, read value
///     2. Returns when producer has finished
// TODO(CORO-004): The producer/consumer semaphore ping-pong blocks two GCD
// threads (one producer, one consumer) for the entire iteration.  To migrate:
// model yield() as a suspend point in the producer's coroutine entry loop and
// next()/hasNext() as suspend points in the consumer, using the continuation
// model so neither side blocks a thread while waiting for the other.
final class RuntimeSequenceCoroutine: @unchecked Sendable {
    /// The builder lambda function pointer (closureThunk convention).
    let fnPtr: Int

    /// Semaphore the producer waits on after yielding a value.
    /// Signaled by the consumer when it wants the next element.
    private let producerSemaphore = DispatchSemaphore(value: 0)

    /// Semaphore the consumer waits on when requesting a value.
    /// Signaled by the producer after yielding or finishing.
    private let consumerSemaphore = DispatchSemaphore(value: 0)

    /// Guard for mutable state access.
    private let stateLock = NSLock()

    /// The most recently yielded value (producer -> consumer).
    private var yieldedValue: Int = 0

    /// Whether the producer has finished (either completed or threw).
    private var finished = false

    /// Whether the coroutine background thread has been started.
    private var started = false

    /// All elements materialized so far (cache for re-iteration).
    private var materializedElements: [Int] = []

    /// Whether the coroutine has been fully exhausted.
    private var fullyMaterialized = false

    init(fnPtr: Int) {
        self.fnPtr = fnPtr
    }

    /// Called by the producer (background thread) to yield a value.
    /// Suspends the producer until the consumer requests the next element.
    func yieldValue(_ value: Int) {
        stateLock.lock()
        yieldedValue = value
        stateLock.unlock()

        // Signal the consumer that a value is available
        consumerSemaphore.signal()
        // Wait for the consumer to request the next element
        producerSemaphore.wait()
    }

    /// Called by the producer when it finishes (normally or via exception).
    func markFinished() {
        stateLock.lock()
        finished = true
        stateLock.unlock()
        consumerSemaphore.signal()
    }

    /// Result type for `nextElement()`: either a value or end-of-sequence.
    enum NextResult {
        case value(Int)
        case done
    }

    /// Request the next element from the coroutine, one at a time.
    ///
    /// If there are already-materialized elements beyond the current
    /// consumption index, return the cached element. Otherwise, resume the
    /// producer to compute the next value.
    ///
    /// Returns `.done` when the producer has finished and all cached
    /// elements have been consumed.
    private var consumptionIndex: Int = 0

    func nextElement() -> NextResult {
        stateLock.lock()
        // If we have cached elements beyond the current index, return them.
        if consumptionIndex < materializedElements.count {
            let elem = materializedElements[consumptionIndex]
            consumptionIndex += 1
            stateLock.unlock()
            return .value(elem)
        }
        // If fully materialized and no more cached elements, we're done.
        if fullyMaterialized {
            stateLock.unlock()
            return .done
        }
        stateLock.unlock()

        ensureStarted()

        // Request next element from producer
        producerSemaphore.signal()
        consumerSemaphore.wait()

        stateLock.lock()
        if finished {
            fullyMaterialized = true
            stateLock.unlock()
            return .done
        }
        let value = yieldedValue
        materializedElements.append(value)
        consumptionIndex += 1
        stateLock.unlock()
        return .value(value)
    }

    /// Reset the consumption index so re-iteration over the same coroutine
    /// replays from the beginning (using cached elements first, then resuming
    /// the producer if needed).
    func resetIteration() {
        stateLock.lock()
        consumptionIndex = 0
        stateLock.unlock()
    }

    /// Materialize all elements from the coroutine and return them.
    /// This is the main entry point for evaluateSequence.
    /// The coroutine is started lazily on the first call.
    func materializeAll() -> [Int] {
        stateLock.lock()
        if fullyMaterialized {
            let elems = materializedElements
            stateLock.unlock()
            return elems
        }
        stateLock.unlock()

        ensureStarted()

        while true {
            // Request next element from producer
            producerSemaphore.signal()
            consumerSemaphore.wait()

            stateLock.lock()
            if finished {
                fullyMaterialized = true
                let elems = materializedElements
                stateLock.unlock()
                return elems
            }
            materializedElements.append(yieldedValue)
            stateLock.unlock()
        }
    }

    /// Start the background thread if not already started.
    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        let coroutine = self
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait for the first consumer request before starting
            coroutine.producerSemaphore.wait()

            let builderHandle = registerRuntimeObject(
                RuntimeSequenceCoroutineBuilderProxy(coroutine: coroutine)
            )

            var thrown = 0
            let fn = unsafeBitCast(coroutine.fnPtr, to: KKClosureThunkEntryPoint.self)
            _ = fn(builderHandle, &thrown)

            if thrown != 0 {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
            }

            coroutine.markFinished()
        }
    }
}

/// Proxy object passed to the builder lambda as the "builder" handle.
/// When `kk_sequence_builder_yield` receives this handle, it delegates
/// to the coroutine's `yieldValue()` which suspends the producer thread.
final class RuntimeSequenceCoroutineBuilderProxy {
    let coroutine: RuntimeSequenceCoroutine

    init(coroutine: RuntimeSequenceCoroutine) {
        self.coroutine = coroutine
    }
}

/// Runtime box for the `iterator { yield(x) }` builder (STDLIB-331/564).
///
/// Implements **continuation-based lazy iteration** using a cooperative
/// producer-consumer pattern. The builder lambda runs on a background thread
/// and suspends on each `yield()` call until the consumer calls `next()`.
///
/// Protocol:
///   1. `kk_iterator_builder_build(fnPtr)` creates the box and spawns the
///      producer thread. The producer immediately blocks on `producerGate`
///      until the first `hasNext` / `next` call.
///   2. `hasNext` signals `producerGate` (let producer run), then waits on
///      `consumerGate`. When the producer yields a value or finishes, it
///      signals `consumerGate`.
///   3. `next` returns the most recently yielded value (already fetched by
///      `hasNext`).
///
/// Memory: The box is registered in the runtime object table; the background
/// thread retains the box via its closure capture. The thread exits naturally
/// when the builder lambda returns.
// TODO(CORO-004): Same semaphore ping-pong pattern as RuntimeSequenceCoroutine.
// Migrate to continuation model so neither producer nor consumer blocks a GCD thread.
final class RuntimeIteratorBuilderBox: @unchecked Sendable {
    /// Semaphore the producer blocks on; signalled by the consumer (`hasNext`).
    let producerGate = DispatchSemaphore(value: 0)
    /// Semaphore the consumer blocks on; signalled by the producer (`yield` or end).
    let consumerGate = DispatchSemaphore(value: 0)

    /// The most recently yielded value, valid when `state == .hasValue`.
    var yieldedValue: Int = 0
    /// Current state of the iterator.
    var state: IteratorState = .initial

    enum IteratorState {
        /// Producer has not yet been advanced.
        case initial
        /// Producer yielded a value; `yieldedValue` is valid.
        case hasValue
        /// Producer finished (lambda returned).
        case done
    }
}

/// Runtime box for `Grouping<T, K>` returned by `groupingBy`.
/// Stores the source elements and key selector function pointer/closure.
final class RuntimeGroupingBox {
    let sourceElements: [Int]
    let keyFnPtr: Int
    let keyClosureRaw: Int

    init(sourceElements: [Int], keyFnPtr: Int, keyClosureRaw: Int) {
        self.sourceElements = sourceElements
        self.keyFnPtr = keyFnPtr
        self.keyClosureRaw = keyClosureRaw
    }
}

// MARK: - Stdlib Delegate Types (P5-80)

/// Thread-safety mode for `lazy` delegate.
enum LazyThreadSafetyMode: Int {
    case synchronized = 1
    case none = 0
}

/// Runtime box for `kotlin.lazy {}` delegate.
/// Holds an initializer function pointer and caches the computed value.
final class RuntimeLazyBox {
    private let initializerFnPtr: Int
    private var cachedValue: Int?
    private let mode: LazyThreadSafetyMode
    private let lock = NSLock()

    init(initializerFnPtr: Int, mode: LazyThreadSafetyMode) {
        self.initializerFnPtr = initializerFnPtr
        self.mode = mode
    }

    func getValue() -> Int {
        switch mode {
        case .synchronized:
            lock.lock()
            defer { lock.unlock() }
            return getValueUnsafe()
        case .none:
            return getValueUnsafe()
        }
    }

    private func getValueUnsafe() -> Int {
        if let cached = cachedValue {
            return cached
        }
        let fnPtr = unsafeBitCast(initializerFnPtr, to: KKThunkEntryPoint.self)
        var thrown = 0
        let value = fnPtr(&thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: lazy initializer threw")
        }
        cachedValue = value
        return value
    }

    var isInitialized: Bool {
        switch mode {
        case .synchronized:
            lock.lock()
            defer { lock.unlock() }
            return cachedValue != nil
        case .none:
            return cachedValue != nil
        }
    }
}

/// Runtime box for `Delegates.observable(initialValue) { ... }` delegate.
/// Stores a mutable value and invokes a callback after each set.
final class RuntimeObservableBox {
    var currentValue: Int
    let callbackFnPtr: Int

    init(initialValue: Int, callbackFnPtr: Int) {
        currentValue = initialValue
        self.callbackFnPtr = callbackFnPtr
    }
}

/// Runtime box for `Delegates.vetoable(initialValue) { ... }` delegate.
/// Stores a mutable value and invokes a callback before each set;
/// the callback returns non-zero to accept the change, zero to veto.
final class RuntimeVetoableBox {
    var currentValue: Int
    let callbackFnPtr: Int

    init(initialValue: Int, callbackFnPtr: Int) {
        currentValue = initialValue
        self.callbackFnPtr = callbackFnPtr
    }
}

/// Runtime box for `Delegates.notNull<T>()` delegate.
/// Throws `IllegalStateException` if accessed before being assigned.
final class RuntimeNotNullBox {
    var currentValue: Int?
}

/// Runtime reflection metadata record stored in the global registry.
/// Populated from the binary metadata blob emitted by `RuntimeReflectionMetadataEmitter`.
/// Each entry corresponds to a type or declaration that can be queried via `KClass` at runtime.
struct RuntimeKClassMetadataEntry {
    let qualifiedName: String
    let simpleName: String
    let supertypeName: String?
    let isDataClass: Bool
    let isSealedClass: Bool
    let isValueClass: Bool
    let isInterface: Bool
    let isObject: Bool
    let isEnumClass: Bool
    let isAnnotationClass: Bool
    let isAbstract: Bool
    let fieldCount: Int
    let memberCount: Int
    let constructorCount: Int
}

/// Global registry mapping type tokens to runtime metadata entries.
/// Populated during module initialization via `kk_kclass_register_metadata`.
final class RuntimeKClassMetadataRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: RuntimeKClassMetadataEntry] = [:]

    func register(typeToken: Int, entry: RuntimeKClassMetadataEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken] = entry
    }

    func lookup(typeToken: Int) -> RuntimeKClassMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken]
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

let runtimeKClassMetadataRegistry = RuntimeKClassMetadataRegistry()

/// Runtime box for `KClass<T>` metadata references produced by `T::class`.
/// Stores the type token and an optional name-hint pointer so that
/// `.simpleName` / `.qualifiedName` can be resolved at runtime.
/// When metadata has been registered via `kk_kclass_register_metadata`,
/// additional properties (isData, isSealed, qualifiedName, etc.) are
/// available through the global metadata registry.
final class RuntimeKClassBox {
    let typeToken: Int
    let nameHint: Int

    init(typeToken: Int, nameHint: Int) {
        self.typeToken = typeToken
        self.nameHint = nameHint
    }

    /// Looks up the associated metadata entry from the global registry.
    var metadata: RuntimeKClassMetadataEntry? {
        runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    }
}

// MARK: - kotlin.reflect.KType (REFL-005)

/// Runtime box for `kotlin.reflect.KType`.
/// Represents a Kotlin type at runtime, as returned by `typeOf<T>()`.
final class RuntimeKTypeBox {
    /// The classifier — typically a `KClass` raw handle.
    let classifierRaw: Int
    /// Type arguments as `RuntimeKTypeProjectionBox` raw handles.
    let argumentRaws: [Int]
    /// Whether the type is marked nullable (`T?`).
    let isMarkedNullable: Bool

    init(classifierRaw: Int, argumentRaws: [Int], isMarkedNullable: Bool) {
        self.classifierRaw = classifierRaw
        self.argumentRaws = argumentRaws
        self.isMarkedNullable = isMarkedNullable
    }
}

/// Runtime representation of `kotlin.reflect.KVariance`.
/// Matches the Kotlin enum ordinals: IN=0, OUT=1, INVARIANT=2.
enum RuntimeKVariance: Int {
    case `in` = 0
    case out = 1
    case invariant = 2
}

/// Runtime box for `kotlin.reflect.KTypeProjection`.
/// Represents a type argument with optional variance.
final class RuntimeKTypeProjectionBox {
    /// The projected type as a `RuntimeKTypeBox` raw handle, or 0 for star projection.
    let typeRaw: Int
    /// The variance (nil for star projection).
    let variance: RuntimeKVariance?

    init(typeRaw: Int, variance: RuntimeKVariance?) {
        self.typeRaw = typeRaw
        self.variance = variance
    }
}

/// Runtime box for `kotlin.reflect.KCallable<*>`.
/// Represents a member (property or function) of a class.
final class RuntimeKCallableBox {
    let nameRaw: Int
    let kind: RuntimeCallableRefKind

    init(nameRaw: Int, kind: RuntimeCallableRefKind) {
        self.nameRaw = nameRaw
        self.kind = kind
    }
}

/// Runtime box for `kotlin.reflect.KFunction<T>`.
/// Represents a constructor or function member.
final class RuntimeKFunctionBox {
    let nameRaw: Int
    let arity: Int

    init(nameRaw: Int, arity: Int) {
        self.nameRaw = nameRaw
        self.arity = arity
    }
}

// MARK: - BufferedReader (STDLIB-567)

/// Runtime box for `java.io.BufferedReader` returned by `File.bufferedReader()`.
/// Wraps a streaming file reader, supporting `readLine()` and `readLines()`.
final class RuntimeBufferedReaderBox {
    private var fileHandle: FileHandle?
    private var pendingData: Data
    private var closed: Bool
    private var reachedEOF: Bool
    private let chunkSize: Int

    init(fileHandle: FileHandle, chunkSize: Int = 4096) {
        self.fileHandle = fileHandle
        self.pendingData = Data()
        self.closed = false
        self.reachedEOF = false
        self.chunkSize = max(1, chunkSize)
    }

    /// Returns the next line, or `nil` when all lines have been consumed.
    func readLine() -> String? {
        guard !closed else { return nil }

        while true {
            if let (lineLength, terminatorLength) = locateLineTerminator() {
                let lineData = pendingData.prefix(lineLength)
                pendingData.removeFirst(lineLength + terminatorLength)
                return String(decoding: lineData, as: UTF8.self)
            }

            if reachedEOF {
                guard !pendingData.isEmpty else { return nil }
                let line = String(decoding: pendingData, as: UTF8.self)
                pendingData.removeAll(keepingCapacity: false)
                return line
            }

            if !readNextChunk() {
                reachedEOF = true
            }
        }
    }

    /// Returns all remaining lines as an array.
    func readLines() -> [String] {
        guard !closed else { return [] }
        var remaining: [String] = []
        while let line = readLine() {
            remaining.append(line)
        }
        return remaining
    }

    func close() {
        guard !closed else { return }
        try? fileHandle?.close()
        fileHandle = nil
        pendingData.removeAll(keepingCapacity: false)
        closed = true
    }

    deinit {
        close()
    }

    private func readNextChunk() -> Bool {
        guard let fileHandle else { return false }
        guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
            return false
        }
        pendingData.append(chunk)
        return true
    }

    private func locateLineTerminator() -> (lineLength: Int, terminatorLength: Int)? {
        var index = pendingData.startIndex
        while index < pendingData.endIndex {
            let byte = pendingData[index]
            if byte == 0x0A {
                return (pendingData.distance(from: pendingData.startIndex, to: index), 1)
            }
            if byte == 0x0D {
                let nextIndex = pendingData.index(after: index)
                if nextIndex < pendingData.endIndex {
                    let lineLength = pendingData.distance(from: pendingData.startIndex, to: index)
                    return (lineLength, pendingData[nextIndex] == 0x0A ? 2 : 1)
                }
                if reachedEOF {
                    return (pendingData.distance(from: pendingData.startIndex, to: index), 1)
                }
                return nil
            }
            index = pendingData.index(after: index)
        }
        return nil
    }
}

// MARK: - InputStream / OutputStream (STDLIB-IO-092)

final class RuntimeInputStreamBox {
    private let data: Data
    private var offset: Int
    private var closed: Bool
    private var markOffset: Int
    private var markLimit: Int

    init(data: Data) {
        self.data = data
        self.offset = 0
        self.closed = false
        self.markOffset = 0
        self.markLimit = 0
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        guard offset < data.count else { return -1 }
        defer { offset += 1 }
        return Int(data[offset])
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return max(0, data.count - offset)
    }

    func skip(_ count: Int) -> Int {
        guard !closed else { return 0 }
        let bounded = max(0, min(count, available()))
        offset += bounded
        return bounded
    }

    func read(into list: RuntimeListBox) -> Int {
        guard !closed else { return -1 }
        let writableCount = min(list.elements.count, available())
        guard writableCount > 0 else { return -1 }
        var newElements = list.elements
        for index in 0 ..< writableCount {
            newElements[index] = Int(Int8(bitPattern: data[offset + index]))
        }
        list.elements = newElements
        offset += writableCount
        return writableCount
    }

    func mark(readLimit: Int) {
        guard !closed else { return }
        markOffset = offset
        markLimit = readLimit
    }

    func markSupported() -> Bool { true }

    func reset() {
        guard !closed else { return }
        offset = markOffset
    }

    func close() {
        closed = true
    }
}

/// Runtime box for `java.io.SequenceInputStream` — chains two InputStreams.
final class RuntimeSequenceInputStreamBox {
    private var first: RuntimeInputStreamBox?
    private var second: RuntimeInputStreamBox?
    private var closed: Bool

    init(first: RuntimeInputStreamBox, second: RuntimeInputStreamBox) {
        self.first = first
        self.second = second
        self.closed = false
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        if let s1 = first {
            let b = s1.readByte()
            if b != -1 { return b }
            // first stream exhausted — move to second
            s1.close()
            first = nil
        }
        return second?.readByte() ?? -1
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return (first?.available() ?? 0) + (second?.available() ?? 0)
    }

    func close() {
        guard !closed else { return }
        first?.close()
        second?.close()
        first = nil
        second = nil
        closed = true
    }
}

final class RuntimeOutputStreamBox {
    private let fileHandle: FileHandle
    private var closed: Bool

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.closed = false
    }

    func writeByte(_ value: Int) throws {
        guard !closed else { return }
        let byte = UInt8(truncatingIfNeeded: value)
        try fileHandle.write(contentsOf: Data([byte]))
    }

    func writeBytes(_ values: [Int]) throws {
        guard !closed else { return }
        let bytes = values.map { UInt8(truncatingIfNeeded: $0) }
        try fileHandle.write(contentsOf: Data(bytes))
    }

    func flush() throws {
        guard !closed else { return }
        try fileHandle.synchronize()
    }

    func close() {
        guard !closed else { return }
        try? fileHandle.close()
        closed = true
    }
}
