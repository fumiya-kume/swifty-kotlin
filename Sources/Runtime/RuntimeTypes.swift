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
    case takeStep(count: Int)
    case builder(elements: [Int])
    case generator(seed: Int, fnPtr: Int, closureRaw: Int)
    case dropStep(count: Int)
    case distinctStep
    case zipStep(otherElements: [Int])
    case takeWhileStep(fnPtr: Int, closureRaw: Int)
    case dropWhileStep(fnPtr: Int, closureRaw: Int)
    case onEachStep(fnPtr: Int, closureRaw: Int)
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
final class RuntimeSequenceBuilderBox {
    var elements: [Int] = []
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
final class RuntimeIteratorBuilderBox {
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

/// Runtime box for `KClass<T>` metadata references produced by `T::class`.
/// Stores the type token and an optional name-hint pointer so that
/// `.simpleName` / `.qualifiedName` can be resolved at runtime.
final class RuntimeKClassBox {
    let typeToken: Int
    let nameHint: Int

    init(typeToken: Int, nameHint: Int) {
        self.typeToken = typeToken
        self.nameHint = nameHint
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
