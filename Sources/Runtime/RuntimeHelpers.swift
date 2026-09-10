import Dispatch
import Foundation

// Coroutine handles (continuation / scope / job / task) are resolved against the
// liveness registry: generated code and the runtime keep raw handles past the
// point where the runtime releases the object, and casting a freed pointer either
// reads dangling memory or aliases whatever object later reuses the address.
func runtimeContinuationState(from continuation: Int) -> RuntimeContinuationState? {
    resolveLiveRuntimeHandle(continuation, as: RuntimeContinuationState.self)
}

func runtimeCoroutineScope(from scopeHandle: Int) -> RuntimeCoroutineScope? {
    resolveLiveRuntimeHandle(scopeHandle, as: RuntimeCoroutineScope.self)
}

func runtimeAsyncTask(from handle: Int) -> RuntimeAsyncTask? {
    resolveLiveRuntimeHandle(handle, as: RuntimeAsyncTask.self)
}

func runtimeJobHandle(from handle: Int) -> RuntimeJobHandle? {
    resolveLiveRuntimeHandle(handle, as: RuntimeJobHandle.self)
}

func suspendEntryPoint(from rawValue: Int) -> KKSuspendEntryPoint? {
    guard rawValue != 0 else {
        return nil
    }
    return unsafeBitCast(rawValue, to: KKSuspendEntryPoint.self)
}

func runtimeArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    guard let box = tryCast(ptr, to: RuntimeArrayBox.self) else {
        return nil
    }
    return box
}

func runtimeIsHeapObject(_ rawValue: Int) -> Bool {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return false
    }
    return runtimeStorage.withGCLock { state in
        state.heapObjects[UInt(bitPattern: ptr)] != nil
    }
}

func runtimeIsUnitBox(_ rawValue: Int) -> Bool {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return false
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return false
    }
    return tryCast(ptr, to: RuntimeUnitBox.self) != nil
}

func runtimeIsUnitValue(_ rawValue: Int) -> Bool {
    rawValue == 0 || runtimeIsUnitBox(rawValue)
}

func runtimeRegisterObjectType(rawValue: Int, classID: Int64) {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue), classID != 0 else {
        return
    }
    runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer[UInt(bitPattern: ptr)] = classID
    }
}

func runtimeObjectTypeID(rawValue: Int) -> Int64? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    return runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer[UInt(bitPattern: ptr)]
    }
}

func runtimeRegisterDataClass(classID: Int64) {
    guard classID != 0 else { return }
    runtimeStorage.withMetadataLock { state in
        state.dataClassIDs.insert(classID)
    }
}

func runtimeIsDataClass(classID: Int64) -> Bool {
    guard classID != 0 else { return false }
    return runtimeStorage.withMetadataLock { state in
        state.dataClassIDs.contains(classID)
    }
}

/// Registers a nominal class whose generated equality is structural.
///
/// The compiler emits this immediately after allocating a data-class instance,
/// before an Any-erased equality call can observe it. Plain classes deliberately
/// remain unregistered so their inherited Any.equals implementation can use
/// reference identity.
@_cdecl("kk_runtime_register_data_class")
public func kk_runtime_register_data_class(_ classID: Int) -> Int {
    runtimeRegisterDataClass(classID: Int64(classID))
    return 0
}

func runtimeRegisterTypeEdge(childTypeID: Int64, parentTypeID: Int64) {
    guard childTypeID != 0, parentTypeID != 0 else {
        return
    }
    runtimeStorage.withMetadataLock { state in
        var parents = state.typeParents[childTypeID] ?? []
        parents.insert(parentTypeID)
        state.typeParents[childTypeID] = parents
    }
}

func runtimeIsAssignable(sourceTypeID: Int64, targetTypeID: Int64) -> Bool {
    guard sourceTypeID != 0, targetTypeID != 0 else {
        return false
    }
    if sourceTypeID == targetTypeID {
        return true
    }
    return runtimeStorage.withMetadataLock { state in
        var visited: Set<Int64> = [sourceTypeID]
        var queue: [Int64] = [sourceTypeID]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            if current == targetTypeID {
                return true
            }
            guard let parents = state.typeParents[current] else {
                continue
            }
            for parent in parents where visited.insert(parent).inserted {
                queue.append(parent)
            }
        }
        return false
    }
}

func runtimeTypeAncestors(of typeID: Int64) -> Set<Int64> {
    guard typeID != 0 else {
        return []
    }
    return runtimeStorage.withMetadataLock { state in
        var visited: Set<Int64> = [typeID]
        var queue: [Int64] = [typeID]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            guard let parents = state.typeParents[current] else {
                continue
            }
            for parent in parents where visited.insert(parent).inserted {
                queue.append(parent)
            }
        }
        return visited
    }
}

/// Reports whether `rhs` is guaranteed to satisfy the parameter type of the
/// `compareTo` reached through `lhs`, so a virtual dispatch on `lhs` is safe.
///
/// Operands related by inheritance qualify, as do siblings sharing a Comparable
/// supertype more specific than `kotlin.Comparable` itself (e.g. two classes
/// implementing `Ranked : Comparable<Ranked>`). Merely both being Comparable is
/// not enough: `Version : Comparable<Version>` and `Money : Comparable<Money>`
/// have incompatible `compareTo` parameters.
func runtimeComparableOperandsAreCompatible(
    lhsTypeID: Int64,
    rhsTypeID: Int64,
    comparableTypeID: Int64
) -> Bool {
    if lhsTypeID == rhsTypeID {
        return true
    }
    if runtimeIsAssignable(sourceTypeID: rhsTypeID, targetTypeID: lhsTypeID)
        || runtimeIsAssignable(sourceTypeID: lhsTypeID, targetTypeID: rhsTypeID)
    {
        return true
    }
    let rhsAncestors = runtimeTypeAncestors(of: rhsTypeID)
    return runtimeTypeAncestors(of: lhsTypeID).contains { ancestor in
        ancestor != comparableTypeID
            && rhsAncestors.contains(ancestor)
            && runtimeIsAssignable(sourceTypeID: ancestor, targetTypeID: comparableTypeID)
    }
}

func runtimeAllocateThrowable(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeThrowableBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateUninitializedPropertyAccessException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeUninitializedPropertyAccessExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeStableNominalTypeID(fqName: String) -> Int64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in fqName.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}

func runtimeThrowableMatchesNominalTypeID(_ throwable: RuntimeThrowableBox, targetTypeID: Int64) -> Bool {
    throwable.exceptionHierarchyFQNames.contains { fqName in
        runtimeStableNominalTypeID(fqName: fqName) == targetTypeID
    }
}

/// Allocates a CancellationException as a RuntimeCancellationBox (CORO-002 / spec.md J17).
/// The returned opaque pointer can be stored in `outThrown` and later detected via
/// `kk_is_cancellation_exception`.
func runtimeAllocateCancellationException(message: String? = "CancellationException", cause: Int = 0) -> Int {
    let cancellation = RuntimeCancellationBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(cancellation).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func tryCast<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, to _: T.Type) -> T? {
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let anyObject = unmanaged.takeUnretainedValue()
    return anyObject as? T
}

// MARK: - UTF-16 Substring Helper (Kotlin-compatible indexing)

/// Extracts a substring from `source` using UTF-16 code unit indices,
/// approximating Kotlin's `CharSequence.subSequence(startIndex, endIndex)` semantics.
///
/// Kotlin `StringBuilder.appendRange` and `CharSequence` use UTF-16 code unit indexing.
/// Swift `String.Index` is based on `Character` (extended grapheme clusters) by default,
/// which differs for non-BMP characters (emoji, surrogate pairs). This helper bridges the
/// gap by operating on the `.utf16` view directly.
///
/// **Limitation:** Swift `String` cannot represent unpaired UTF-16 surrogates. When
/// `startIndex` or `endIndex` splits a surrogate pair (e.g., slicing in the middle of
/// an emoji), `String(decoding:as:)` replaces the ill-formed code unit with U+FFFD
/// (replacement character). This diverges from JVM Kotlin, where unpaired surrogates
/// are preserved as `Char` values. For well-formed UTF-16 input (the common case),
/// behavior is identical. Callers/tests should not assume full fidelity for these
/// edge cases.
///
/// - Parameters:
///   - source: The Swift string to slice.
///   - startIndex: Start offset in UTF-16 code units (inclusive).
///   - endIndex: End offset in UTF-16 code units (exclusive).
/// - Returns: The substring, or triggers `fatalError` on out-of-bounds.
func runtimeUTF16Substring(_ source: String, startIndex: Int, endIndex: Int) -> String {
    let utf16 = source.utf16
    let length = utf16.count
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= length else {
        fatalError("StringIndexOutOfBoundsException: startIndex=\(startIndex), endIndex=\(endIndex), length=\(length)")
    }
    let start = utf16.index(utf16.startIndex, offsetBy: startIndex)
    let end = utf16.index(utf16.startIndex, offsetBy: endIndex)
    return String(decoding: utf16[start..<end], as: UTF16.self)
}

func extractString(from ptr: UnsafeMutableRawPointer?) -> String? {
    guard let ptr = normalizeNullableRuntimePointer(ptr) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    guard let box = tryCast(ptr, to: RuntimeStringBox.self) else {
        return nil
    }
    return box.value
}

/// Text of a value whose static type is `CharSequence`: either a String box or
/// a StringBuilder box. Returns nil for null sentinels and unrelated handles.
func runtimeCharSequenceText(from raw: Int) -> String? {
    guard let ptr = normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let stringBox = object as? RuntimeStringBox {
        return stringBox.value
    }
    if let builderBox = object as? RuntimeStringBuilderBox {
        return builderBox.value
    }
    return nil
}

let runtimeNullSentinelInt64 = Int64.min
let runtimeNullSentinelInt = Int(truncatingIfNeeded: runtimeNullSentinelInt64)
let runtimeExceptionCaughtSentinel = Int(truncatingIfNeeded: Int64.min + 1)

func normalizeNullableRuntimePointer(_ ptr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let ptr else {
        return nil
    }
    if UInt(bitPattern: ptr) == UInt(bitPattern: runtimeNullSentinelInt) {
        return nil
    }
    return ptr
}

private final class KKInterceptedContinuation: KKContinuation, @unchecked Sendable {
    public let context: UnsafeMutableRawPointer?
    private let continuation: KKContinuation
    private let dispatcher: RuntimeDispatcher

    init(
        context: UnsafeMutableRawPointer?,
        continuation: KKContinuation,
        dispatcher: RuntimeDispatcher
    ) {
        self.context = context
        self.continuation = continuation
        self.dispatcher = dispatcher
    }

    func resumeWith(_ result: UnsafeMutableRawPointer?) {
        let resultRaw = Int(bitPattern: result)
        dispatcher.dispatchAsync {
            self.continuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw))
        }
    }
}

func runtimeInterceptedContinuation(_ continuation: KKContinuation) -> KKContinuation {
    guard let context = continuation.context else {
        return continuation
    }
    let dispatcherTag = kk_context_get_dispatcher(Int(bitPattern: context))
    return runtimeInterceptedContinuation(using: dispatcherTag, continuation: continuation)
}

func runtimeInterceptedContinuation(using dispatcherTag: Int, continuation: KKContinuation) -> KKContinuation {
    guard dispatcherTag != 0 else {
        return continuation
    }
    if continuation is KKInterceptedContinuation {
        return continuation
    }
    return KKInterceptedContinuation(
        context: continuation.context,
        continuation: continuation,
        dispatcher: runtimeResolveDispatcher(from: dispatcherTag)
    )
}

public extension KKContinuation {
    func intercepted() -> KKContinuation {
        runtimeInterceptedContinuation(self)
    }
}

public final class KKDispatchContinuation: KKContinuation {
    public let context: UnsafeMutableRawPointer?
    private let callback: (UnsafeMutableRawPointer?) -> Void

    public init(context: UnsafeMutableRawPointer?, callback: @escaping (UnsafeMutableRawPointer?) -> Void) {
        self.context = context
        self.callback = callback
    }

    public func resumeWith(_ result: UnsafeMutableRawPointer?) {
        callback(result)
    }
}

public enum KxMiniRuntime {
    public static func runBlocking(_ block: (@escaping (UnsafeMutableRawPointer?) -> Void) -> Void) {
        let group = DispatchGroup()
        group.enter()
        block { _ in group.leave() }
        group.wait()
    }

    public static func launch(_ block: @escaping () -> Void) {
        DispatchQueue.global().async(execute: DispatchWorkItem(block: block))
    }

    public static func launch(workItem: DispatchWorkItem) {
        DispatchQueue.global().async(execute: workItem)
    }

    static func launch(on dispatcher: RuntimeDispatcher, block: @Sendable @escaping () -> Void) {
        dispatcher.queue.async {
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = dispatcher
            block()
            RuntimeDispatcher.current = saved
        }
    }

    public static func async(_ block: @escaping () -> UnsafeMutableRawPointer?) -> KKContinuation {
        KKDispatchContinuation(context: nil) { _ in
            _ = block()
        }
    }

    public static func delay(milliseconds: Int, continuation: KKContinuation) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler {
            continuation.resumeWith(nil)
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
        timer.resume()
    }
}
