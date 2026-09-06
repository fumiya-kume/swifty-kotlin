import Foundation

func runtimeThrowableBox(from raw: Int) -> RuntimeThrowableBox? {
    guard raw != runtimeNullSentinelInt,
          raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private let runtimeThrowableToStringVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int =
    __kk_throwable_toString

private let runtimeThrowableStackTraceVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int =
    __kk_throwable_rawStackFrames

// Keep these slots aligned with the bundled Throwable layout. The native
// getStackTraceAddresses extension occupies slot 2, so toString is slot 1.
enum RuntimeThrowableVtableSlot {
    static let getStackTrace = 0
    static let toString = 1
}

func runtimeThrowableVtableMethodRaw(_ receiver: Int, slot: Int) -> Int? {
    guard runtimeIsThrowableRaw(receiver) else {
        return nil
    }
    if runtimeThrowableBox(from: receiver) == nil,
       let pointer = UnsafeMutableRawPointer(bitPattern: receiver)
    {
        let objectKey = UInt(bitPattern: pointer)
        if let registered = runtimeStorage.withMetadataLock({ state in
            state.objectVtableMethods[objectKey]?[slot]
        }), registered != 0 {
            return registered
        }
    }
    switch slot {
    case RuntimeThrowableVtableSlot.getStackTrace:
        return unsafeBitCast(runtimeThrowableStackTraceVtableMethod, to: Int.self)
    case RuntimeThrowableVtableSlot.toString:
        return unsafeBitCast(runtimeThrowableToStringVtableMethod, to: Int.self)
    default:
        return nil
    }
}

func runtimeThrowableToString(_ receiver: Int) -> String? {
    guard let methodRaw = runtimeThrowableVtableMethodRaw(
        receiver,
        slot: RuntimeThrowableVtableSlot.toString
    ) else {
        return nil
    }
    let method = unsafeBitCast(
        methodRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    guard let rendered = UnsafeMutableRawPointer(bitPattern: method(receiver, nil)) else {
        return nil
    }
    return extractString(from: rendered)
}

private func runtimeThrowableStackTraceText(from throwableRaw: Int) -> String {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return ""
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return ""
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return throwable.renderedMessage
    }
    if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        return cancellation.message ?? "CancellationException"
    }
    return ""
}

/// RuntimeObjectBox stores only the stable nominal type ID. Keep the names of
/// bundled throwable classes here because the hashed ID is intentionally not
/// reversible; user-defined types are resolved through registered metadata.
private let runtimeSourceThrowableNames = [
    ("kotlin.Error", "Error"),
    ("kotlin.Exception", "Exception"),
    ("kotlin.RuntimeException", "RuntimeException"),
    ("kotlin.IllegalArgumentException", "IllegalArgumentException"),
    ("kotlin.IllegalStateException", "IllegalStateException"),
    ("kotlin.ConcurrentModificationException", "ConcurrentModificationException"),
    ("kotlin.UnsupportedOperationException", "UnsupportedOperationException"),
    ("kotlin.NumberFormatException", "NumberFormatException"),
    ("kotlin.NullPointerException", "NullPointerException"),
    ("kotlin.ClassCastException", "ClassCastException"),
    ("kotlin.TypeCastException", "TypeCastException"),
    ("kotlin.AssertionError", "AssertionError"),
    ("kotlin.NoSuchElementException", "NoSuchElementException"),
    ("kotlin.ArithmeticException", "ArithmeticException"),
    ("kotlin.NoWhenBranchMatchedException", "NoWhenBranchMatchedException"),
    ("kotlin.UninitializedPropertyAccessException", "UninitializedPropertyAccessException"),
    ("kotlin.IndexOutOfBoundsException", "IndexOutOfBoundsException"),
    ("kotlin.ArrayIndexOutOfBoundsException", "ArrayIndexOutOfBoundsException"),
    ("kotlin.KotlinNothingValueException", "KotlinNothingValueException"),
    ("kotlin.OutOfMemoryError", "OutOfMemoryError"),
    ("kotlin.NotImplementedError", "NotImplementedError"),
    ("kotlin.text.CharacterCodingException", "CharacterCodingException"),
    ("kotlin.io.FileSystemException", "FileSystemException"),
    ("kotlin.io.FileAlreadyExistsException", "FileAlreadyExistsException"),
    ("kotlin.io.AccessDeniedException", "AccessDeniedException"),
    ("kotlin.io.NoSuchFileException", "NoSuchFileException"),
]

private let runtimeSourceThrowableSimpleNames: [Int64: String] = {
    Dictionary(uniqueKeysWithValues: runtimeSourceThrowableNames.map { entry in
        (runtimeStableNominalTypeID(fqName: entry.0), entry.1)
    })
}()

private let runtimeSourceThrowableQualifiedNames: [Int64: String] = {
    Dictionary(uniqueKeysWithValues: runtimeSourceThrowableNames.map { entry in
        (runtimeStableNominalTypeID(fqName: entry.0), entry.0)
    })
}()

private func runtimeSourceThrowableSimpleName(for classID: Int64) -> String {
    // Nominal type tokens use the same payload as classID, with the nominal
    // base and nullability bit encoded around it. KClass metadata therefore
    // provides the source name for user-defined throwable classes as well.
    let payloadMask: UInt64 = (1 << 55) - 1
    let tokenBits = (UInt64(bitPattern: classID) & payloadMask) << 9 | 6
    let typeToken = Int(truncatingIfNeeded: tokenBits)
    return runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.simpleName
        ?? runtimeSourceThrowableSimpleNames[classID]
        ?? "Throwable"
}

func runtimeSourceThrowableQualifiedName(for classID: Int64) -> String {
    // Nominal type tokens use the same payload as classID, with the nominal
    // base and nullability bit encoded around it. KClass metadata therefore
    // provides the source name for user-defined throwable classes as well.
    let payloadMask: UInt64 = (1 << 55) - 1
    let tokenBits = (UInt64(bitPattern: classID) & payloadMask) << 9 | 6
    let typeToken = Int(truncatingIfNeeded: tokenBits)
    return runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.qualifiedName
        ?? runtimeSourceThrowableQualifiedNames[classID]
        ?? "kotlin.Throwable"
}

func runtimeIsThrowableRaw(_ raw: Int) -> Bool {
    guard raw != runtimeNullSentinelInt, raw != 0 else {
        return false
    }
    if runtimeThrowableBox(from: raw) != nil {
        return true
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return false
    }
    let object: RuntimeObjectBox? = runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeObjectBox.self)
    }
    guard let object else {
        return false
    }
    return runtimeIsAssignable(
        sourceTypeID: object.classID,
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
    )
}

private func runtimeSourceThrowableHeader(from object: RuntimeObjectBox) -> String {
    let typeName = runtimeSourceThrowableSimpleName(for: object.classID)
    guard let message = object.throwableMessage else {
        return typeName
    }
    return "\(typeName): \(message)"
}

/// Raw stack-frame strings for a single throwable. The runtime only provides
/// the class-specific header line here; Kotlin-side formatting walks cause and
/// suppressed chains and adds prefixes (KSP-655).
private func runtimeThrowableRawStackFrameStrings(from throwableRaw: Int) -> [String] {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return []
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return []
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return [throwable.renderedMessage]
    }
    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        return [runtimeSourceThrowableHeader(from: object)]
    }
    return []
}

private func runtimeAllocateArrayBox(length: Int) -> Int {
    let arrayBox = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(arrayBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("__kk_throwable_new")
public func __kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message)
    let throwableInt = runtimeAllocateThrowable(message: text)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new: allocation returned null")
    }
    return ptr
}

@_cdecl("__kk_throwable_new_with_cause")
public func __kk_throwable_new_with_cause(_ message: UnsafeMutableRawPointer?, _ causeRaw: Int) -> UnsafeMutableRawPointer {
    let text = extractString(from: message)
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let throwableInt = runtimeAllocateThrowable(message: text, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new_with_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("__kk_throwable_new_cause")
public func __kk_throwable_new_cause(_ causeRaw: Int) -> UnsafeMutableRawPointer {
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let message = runtimeCauseToString(from: cause)
    let throwableInt = runtimeAllocateThrowable(message: message, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_new_cause")
public func kk_throwable_new_cause(_ causeRaw: Int) -> UnsafeMutableRawPointer {
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let message = runtimeThrowableStackTraceText(from: cause)
    let throwableInt = runtimeAllocateThrowable(message: message.isEmpty ? "Throwable" : message, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("kk_throwable_new_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_is_cancellation")
public func kk_throwable_is_cancellation(_ throwableRaw: Int) -> Int {
    kk_is_cancellation_exception(throwableRaw)
}

@_cdecl("__kk_throwable_message")
public func __kk_throwable_message(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    let message: String?
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        message = throwable.message
    } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        message = cancellation.message
    } else if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        message = object.throwableMessage
    } else {
        return runtimeNullSentinelInt
    }
    guard let message else { return runtimeNullSentinelInt }
    let box = RuntimeStringBox(message)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Stores a message for a Kotlin-defined Throwable subclass allocated through
/// the ordinary object path rather than a RuntimeThrowableBox bridge.
@_cdecl("__kk_throwable_setMessage")
public func __kk_throwable_setMessage(_ throwableRaw: Int, _ messageRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt,
          throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let object = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return throwableRaw
    }
    object.throwableMessage = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw))
    runtimeRegisterTypeEdge(
        childTypeID: object.classID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
    )
    return throwableRaw
}

@_cdecl("__kk_throwable_cause")
public func __kk_throwable_cause(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return throwable.cause == 0 ? runtimeNullSentinelInt : throwable.cause
    }
    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        return object.throwableCause == 0 ? runtimeNullSentinelInt : object.throwableCause
    }
    return runtimeNullSentinelInt
}

@_cdecl("__kk_throwable_rawStackFrames")
public func __kk_throwable_rawStackFrames(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    let frameStrings = runtimeThrowableRawStackFrameStrings(from: throwableRaw)
    let arrayRaw = kk_array_new(frameStrings.count)
    guard let arrayBox = runtimeArrayBox(from: arrayRaw) else {
        runtimeStructuredPanic("__kk_throwable_rawStackFrames: array allocation failed")
    }
    for (i, frame) in frameStrings.enumerated() {
        arrayBox.elements[i] = registerRuntimeObject(RuntimeStringBox(frame))
    }
    return arrayRaw
}

@_cdecl("__kk_throwable_toString")
public func __kk_throwable_toString(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    let typeName: String
    let message: String?
    if let throwable = runtimeThrowableBox(from: throwableRaw) {
        typeName = runtimeJVMExceptionFQName(from: throwable.exceptionFQName)
        message = throwable.message
    } else if let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) {
        let object: RuntimeObjectBox? = runtimeStorage.withGCLock { state in
            guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
                return nil
            }
            return tryCast(ptr, to: RuntimeObjectBox.self)
        }
        if let object {
            typeName = runtimeSourceThrowableQualifiedName(for: object.classID)
            message = object.throwableMessage
        } else {
            typeName = "kotlin.Throwable"
            message = nil
        }
    } else {
        typeName = "kotlin.Throwable"
        message = nil
    }
    return Int(bitPattern: runtimeMakeStringPointer(runtimeRenderedExceptionMessage(typeName, message)))
}

@_cdecl("__kk_print_raw")
public func __kk_print_raw(_ messageRaw: Int) {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "null"
    Swift.print(message, terminator: "")
}

@_cdecl("__kk_println_raw")
public func __kk_println_raw(_ messageRaw: Int) {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "null"
    Swift.print(message, terminator: "\n")
}

@_cdecl("__kk_printStderr")
public func __kk_printStderr(_ messageRaw: Int) -> Int {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? ""
    FileHandle.standardError.write(Data(message.utf8))
    return 0
}

// MARK: - Advanced exception features (STDLIB-EXCEPT-105)

/// Storage bridge for `Throwable.initCause`: overwrites the cause slot.
@_cdecl("__kk_throwable_setCause")
public func __kk_throwable_setCause(_ throwableRaw: Int, _ causeRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt, throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw)
    else {
        return throwableRaw
    }
    let causeValue = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        throwable.cause = causeValue
    } else if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        object.throwableCause = causeValue
        runtimeRegisterTypeEdge(
            childTypeID: object.classID,
            parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
        )
    }
    return throwableRaw
}

/// Storage bridge for `Throwable.addSuppressed`: appends to the suppressed list.
@_cdecl("__kk_throwable_appendSuppressed")
public func __kk_throwable_appendSuppressed(_ throwableRaw: Int, _ suppressedRaw: Int) -> Int {
    guard let suppressedPtr = UnsafeMutableRawPointer(bitPattern: suppressedRaw),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: suppressedPtr))
          }),
          (tryCast(suppressedPtr, to: RuntimeThrowableBox.self) != nil
              || tryCast(suppressedPtr, to: RuntimeObjectBox.self) != nil)
    else {
        return 0
    }

    guard let throwablePtr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: throwablePtr))
          })
    else {
        return 0
    }

    // Match Kotlin/JVM's major behavior by rejecting self-suppression while
    // remaining ABI-compatible with this non-throwing runtime entrypoint.
    guard throwableRaw != suppressedRaw else { return 0 }
    if let throwable = tryCast(throwablePtr, to: RuntimeThrowableBox.self) {
        throwable.suppressed.append(suppressedRaw)
    } else if let throwable = tryCast(throwablePtr, to: RuntimeObjectBox.self) {
        throwable.throwableSuppressed.append(suppressedRaw)
    } else {
        return 0
    }

    return 0
}

/// Storage bridge for `Throwable.getSuppressed`: the raw `Array<Throwable>`.
@_cdecl("__kk_throwable_suppressedRaw")
public func __kk_throwable_suppressedRaw(_ throwableRaw: Int) -> Int {
    let suppressed: [Int]
    if let throwable = runtimeThrowableBox(from: throwableRaw) {
        suppressed = throwable.suppressed
    } else if let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
              let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        suppressed = object.throwableSuppressed
    } else {
        return runtimeAllocateArrayBox(length: 0)
    }

    let arrayBox = RuntimeArrayBox(length: suppressed.count)
    for (i, elem) in suppressed.enumerated() {
        arrayBox.elements[i] = elem
    }
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(arrayBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_abort_unreachable")
public func kk_abort_unreachable(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    runtimeStructuredPanic("reached unreachable code")
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

func runtimeStructuredPanicMessage(_ message: String) -> String {
    "KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(message)"
}

@inline(__always)
func runtimeStructuredPanic(_ message: @autoclosure () -> String) -> Never {
    fatalError(runtimeStructuredPanicMessage(message()))
}

private enum RuntimeTypeTokenEncoding {
    static let baseMask: Int64 = 0xFF
    static let nullableBit: Int64 = 0x100
    static let payloadShift: Int64 = 9
    static let payloadMask: Int64 = (1 << 55) - 1
    static let anyBase: Int64 = 1
    static let stringBase: Int64 = 2
    static let intBase: Int64 = 3
    static let booleanBase: Int64 = 4
    static let nullBase: Int64 = 5
    static let nominalBase: Int64 = 6
    static let uintBase: Int64 = 7
    static let ulongBase: Int64 = 8
    static let ubyteBase: Int64 = 9
    static let ushortBase: Int64 = 10
    static let byteBase: Int64 = 16
    static let shortBase: Int64 = 17
    // REFL-002: Additional primitive bases for Long, Double, Float, Char.
    static let longBase: Int64 = 11
    static let doubleBase: Int64 = 12
    static let floatBase: Int64 = 13
    static let charBase: Int64 = 14
    // STDLIB-REFLECT-ABI-001: Unit::class token base.
    static let unitBase: Int64 = 15
}

func runtimePanicMessage(fromCString cstr: UnsafePointer<CChar>) -> String {
    runtimeStructuredPanicMessage(String(cString: cstr))
}

private final class RuntimeFlatStringStorage: @unchecked Sendable {
    let data: UnsafeMutablePointer<UInt8>
    let length: Int
    let byteCount: Int
    let hash: Int

    init(_ value: String) {
        let bytes = Array(value.utf8)
        // `length` is the UTF-16 code-unit count used by Kotlin String/CharSequence;
        // `byteCount` is the UTF-8 byte count used by the flat ABI.
        self.length = value.utf16.count
        self.byteCount = bytes.count
        self.hash = 0
        self.data = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
        if bytes.isEmpty {
            data.initialize(to: 0)
        } else {
            data.initialize(from: bytes, count: bytes.count)
        }
    }

    deinit {
        data.deallocate()
    }
}

private final class RuntimeFlatStringStorageRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RuntimeFlatStringStorage] = []

    func append(_ entry: RuntimeFlatStringStorage) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }
}

private let runtimeFlatStringStorageRegistry = RuntimeFlatStringStorageRegistry()

func runtimeStringFromFlatFields(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    _ = (length, hash)
    guard let data, byteCount >= 0 else {
        return ""
    }
    let buffer = UnsafeBufferPointer(start: data, count: byteCount)
    return String(decoding: buffer, as: UTF8.self)
}

func runtimeRegisterFlatString(
    _ value: String,
    outLength: UnsafeMutablePointer<Int>?,
    outByteCount: UnsafeMutablePointer<Int>?,
    outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let storage = RuntimeFlatStringStorage(value)
    outLength?.pointee = storage.length
    outByteCount?.pointee = storage.byteCount
    outHash?.pointee = storage.hash
    let data = storage.data
    runtimeFlatStringStorageRegistry.append(storage)
    return data
}

@_cdecl("kk_string_from_flat")
public func kk_string_from_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard data != nil else {
        return 0
    }
    let string = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return registerRuntimeObject(RuntimeStringBox(string))
}

@_cdecl("kk_string_to_flat")
public func kk_string_to_flat(
    _ raw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    guard raw != runtimeNullSentinelInt,
          raw != 0,
          let string = extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    else {
        outLength?.pointee = 0
        outByteCount?.pointee = 0
        outHash?.pointee = 0
        return nil
    }
    return runtimeRegisterFlatString(
        string,
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = String(decoding: buffer, as: UTF8.self)
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    // Native string construction is also used for temporary CharSequence
    // windows created by bundled text helpers. Keep those boxes on the same
    // interface-property itable path as registerRuntimeObject.
    runtimeRegisterCharSequenceItable(Int(bitPattern: opaque))
    return opaque
}

@_cdecl("kk_int_toString_radix")
public func kk_int_toString_radix(_ value: Int, _ radix: Int) -> UnsafeMutableRawPointer {
    let clampedRadix = max(2, min(36, radix))
    let str = String(value, radix: clampedRadix)
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_string_concat_flat")
public func kk_string_concat_flat(
    _ lhsData: UnsafePointer<UInt8>?,
    _ lhsLength: Int,
    _ lhsByteCount: Int,
    _ lhsHash: Int,
    _ rhsData: UnsafePointer<UInt8>?,
    _ rhsLength: Int,
    _ rhsByteCount: Int,
    _ rhsHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let lhs = runtimeStringFromFlatFields(
        data: lhsData,
        length: lhsLength,
        byteCount: lhsByteCount,
        hash: lhsHash
    )
    let rhs = runtimeStringFromFlatFields(
        data: rhsData,
        length: rhsLength,
        byteCount: rhsByteCount,
        hash: rhsHash
    )
    return runtimeRegisterFlatString(
        lhs + rhs,
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_compareTo_flat")
public func kk_string_compareTo_flat(
    _ lhsData: UnsafePointer<UInt8>?,
    _ lhsLength: Int,
    _ lhsByteCount: Int,
    _ lhsHash: Int,
    _ rhsData: UnsafePointer<UInt8>?,
    _ rhsLength: Int,
    _ rhsByteCount: Int,
    _ rhsHash: Int
) -> Int {
    let lhs = runtimeStringFromFlatFields(
        data: lhsData,
        length: lhsLength,
        byteCount: lhsByteCount,
        hash: lhsHash
    )
    let rhs = runtimeStringFromFlatFields(
        data: rhsData,
        length: rhsLength,
        byteCount: rhsByteCount,
        hash: rhsHash
    )
    return runtimeCompareStrings(lhs, rhs)
}

// STDLIB-TEXT-FN-043: String?.plus(other: Any?): String
// Receiver is passed as Int (intptr) so null receivers produce "null".
// Primitives passed as `other` are already boxed by the ABI lowering pass
// when widened to Any?, so runtimeElementToString handles them correctly.
@_cdecl("kk_string_plus")
public func kk_string_plus(_ receiverRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeElementToString(receiverRaw)
    let rhs = runtimeElementToString(otherRaw)
    return runtimeMakeStringRaw(lhs + rhs)
}

/// Stable nominal type ID of `kotlin.String`, with String's interface
/// supertype edges registered on first use (BUG-153). Strings never reach
/// `kk_object_new`, so this is the only place those edges get installed.
let runtimeStringNominalTypeID: Int64 = {
    let stringTypeID = runtimeStableNominalTypeID(fqName: "kotlin.String")
    runtimeRegisterTypeEdge(
        childTypeID: stringTypeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.CharSequence")
    )
    runtimeRegisterTypeEdge(
        childTypeID: stringTypeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
    )
    return stringTypeID
}()

/// True when `ptr` is a live runtime object pointer holding a `RuntimeStringBox`.
func runtimeIsStringBoxPointer(_ ptr: UnsafeMutableRawPointer) -> Bool {
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return false
    }
    return tryCast(ptr, to: RuntimeStringBox.self) != nil
}

@_cdecl("kk_op_is")
public func kk_op_is(_ value: Int, _ typeToken: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let isNullableTarget = (token & RuntimeTypeTokenEncoding.nullableBit) != 0
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask

    if value == runtimeNullSentinelInt {
        if isNullableTarget || base == RuntimeTypeTokenEncoding.nullBase {
            return 1
        }
        return 0
    }

    switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        return 1

    case RuntimeTypeTokenEncoding.stringBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        return runtimeIsStringBoxPointer(ptr) ? 1 : 0

    case RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.uintBase,
         RuntimeTypeTokenEncoding.ubyteBase,
         RuntimeTypeTokenEncoding.ushortBase,
         RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase:
        // NOTE: an unboxed (non-object-pointer) value here is treated as a
        // match. That's unsound in general — Int/UInt/UByte/UShort share no
        // value-range heuristic that distinguishes them from Long/Double/
        // Float/Char once unboxed (all reinterpret the same 64-bit word) — but
        // some existing callers (e.g. Sequence element storage) still hand
        // kk_op_is genuinely unboxed primitives, so tightening this to a
        // mismatch regresses them. The `is`/`as`/`as?` call sites themselves
        // are fixed to always box their operand before reaching here (see
        // ABILoweringPass's typeCheckValueCallees); see also the follow-up
        // tracking sequenceOf's missing element boxing.
        //
        // Even when boxed, Int/UInt/UByte/UShort all box via kk_box_int into
        // the same RuntimeIntBox (see BoxingCalleeTable), so they remain
        // indistinguishable from each other here — a separate, pre-existing
        // limitation of the box representation itself, not fixed by this check.
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return 1
        }
        // A box tagged with a nominal type ID (kk_tag_value_class_box) represents
        // a boxed value class, which is a distinct type from its underlying
        // primitive even though it shares the same physical box.
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeIntBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.longBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeLongBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.ulongBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeULongBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.doubleBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeDoubleBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.floatBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeFloatBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.charBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeCharBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.booleanBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return (value == 0 || value == 1) ? 1 : 0
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return (value == 0 || value == 1) ? 1 : 0
        }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeBoolBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.nullBase:
        return 0

    case RuntimeTypeTokenEncoding.unitBase:
        // Direct Unit values remain integer 0; Any-erased Unit values use the
        // runtime box so they remain distinguishable from other raw values.
        return runtimeIsUnitValue(value) ? 1 : 0

    case RuntimeTypeTokenEncoding.nominalBase:
        if let sourceTypeID = runtimeObjectTypeID(rawValue: value) {
            return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: payload) ? 1 : 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        // BUG-153: String values are allocated through the flat-string fast
        // paths (kk_string_from_flat / kk_string_from_utf8 / concatenation /
        // toString()), never through kk_object_new, so they carry no object
        // type ID and can't answer an interface check (`is CharSequence`,
        // `is Comparable<*>`) via the registered supertype graph. Recover
        // String's identity from the box itself instead of tagging every
        // allocation site, then reuse the ordinary assignability walk over
        // kotlin.String's supertype edges.
        if runtimeIsStringBoxPointer(ptr) {
            return runtimeIsAssignable(
                sourceTypeID: runtimeStringNominalTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        let throwable = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
                ? tryCast(ptr, to: RuntimeThrowableBox.self)
                : nil
        }
        guard let throwable else {
            return 0
        }
        // Every built-in exception class now allocates a RuntimeThrowableBox
        // subclass with a correctly populated exceptionHierarchyFQNames (see
        // RuntimeAssertions.swift / RuntimeTypes.swift), so this hierarchy check
        // is authoritative: a real mismatch must not be treated as a match, or
        // `catch (e: T)` would incorrectly catch any unrelated sibling exception.
        if runtimeThrowableMatchesNominalTypeID(throwable, targetTypeID: payload) {
            return 1
        }
        // A base RuntimeThrowableBox has no Kotlin-level type information. Keep
        // the historical broad catch fallback for those internal throwables,
        // while typed subclasses must obey their explicit hierarchy above.
        return throwable.exceptionHierarchyFQNames == ["kotlin.Throwable"] ? 1 : 0

    default:
        return 0
    }
}

@_cdecl("kk_op_cast")
public func kk_op_cast(_ value: Int, _ typeToken: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if kk_op_is(value, typeToken) != 0 {
        return value
    }
    outThrown?.pointee = runtimeAllocateClassCastException(message: "ClassCastException")
    return 0
}

@_cdecl("kk_op_safe_cast")
public func kk_op_safe_cast(_ value: Int, _ typeToken: Int) -> Int {
    kk_op_is(value, typeToken) != 0 ? value : runtimeNullSentinelInt
}

@_cdecl("kk_op_contains")
public func kk_op_contains(_ container: Int, _ element: Int) -> Int {
    // Range check first
    if let range = runtimeRangeBox(from: container) {
        if range.step > 0 {
            guard element >= range.first, element <= range.last else { return 0 }
            return (element - range.first) % range.step == 0 ? 1 : 0
        } else if range.step < 0 {
            guard element <= range.first, element >= range.last else { return 0 }
            return (range.first - element) % (-range.step) == 0 ? 1 : 0
        }
        return 0
    }
    // List check
    if let list = runtimeListBox(from: container) {
        return list.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0
    }
    // Set check
    if let set = runtimeSetBox(from: container) {
        return set.contains(rawValue: element) ? 1 : 0
    }
    // Array check
    guard let array = runtimeArrayBox(from: container) else {
        return 0
    }
    return array.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0
}

@_cdecl("kk_array_new")
public func kk_array_new(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Same as `kk_array_new`, but validates `length` first and throws
/// `NegativeArraySizeException` for negative sizes instead of silently
/// clamping to an empty array. Used by the `Array(size) { init }` family of
/// pseudo-constructors (Array, IntArray, ByteArray, ...), which must reject
/// negative sizes the way real Kotlin does.
@_cdecl("kk_array_new_checked")
public func kk_array_new_checked(_ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard length >= 0 else {
        runtimeSetThrown(outThrown, runtimeAllocateNegativeArraySizeException(message: "\(length)"))
        return 0
    }
    return kk_array_new(length)
}

@_cdecl("kk_object_new")
public func kk_object_new(_ length: Int, _ classId: Int) -> Int {
    let box = RuntimeObjectBox(length: length, classID: Int64(classId))
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    let key = UInt(bitPattern: opaque)
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(key)
    }
    runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer[key] = Int64(classId)
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_object_type_id")
public func kk_object_type_id(_ objectRaw: Int) -> Int {
    Int(runtimeObjectTypeID(rawValue: objectRaw) ?? 0)
}

/// Returns the simple name of the type encoded in the given type token as a
/// runtime string pointer.  For builtin types the name is derived from the
/// token base; for nominal types the compiler supplies a `nameHint` string
/// pointer that is returned directly (the hint carries the simple name that
/// was known at compile-time after inline expansion).
@_cdecl("__kk_type_token_simple_name")
public func __kk_type_token_simple_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    // If a compiler-provided name hint is available, use it directly.
    if nameHint != 0, nameHint != runtimeNullSentinelInt {
        return nameHint
    }
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let name = switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        "Any"
    case RuntimeTypeTokenEncoding.stringBase:
        "String"
    case RuntimeTypeTokenEncoding.intBase:
        "Int"
    case RuntimeTypeTokenEncoding.uintBase:
        "UInt"
    case RuntimeTypeTokenEncoding.ulongBase:
        "ULong"
    case RuntimeTypeTokenEncoding.ubyteBase:
        "UByte"
    case RuntimeTypeTokenEncoding.ushortBase:
        "UShort"
    case RuntimeTypeTokenEncoding.byteBase:
        "Byte"
    case RuntimeTypeTokenEncoding.shortBase:
        "Short"
    case RuntimeTypeTokenEncoding.booleanBase:
        "Boolean"
    // REFL-002: Additional primitive bases for accurate simpleName.
    case RuntimeTypeTokenEncoding.longBase:
        "Long"
    case RuntimeTypeTokenEncoding.doubleBase:
        "Double"
    case RuntimeTypeTokenEncoding.floatBase:
        "Float"
    case RuntimeTypeTokenEncoding.charBase:
        "Char"
    case RuntimeTypeTokenEncoding.nullBase:
        "Nothing"
    case RuntimeTypeTokenEncoding.unitBase:
        "Unit"
    default:
        "Unknown"
    }
    let utf8 = Array(name.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Returns the qualified name of the type encoded in the given type token.
/// For built-in Kotlin stdlib types (Any, String, Int, Boolean, etc.) this
/// returns the fully-qualified "kotlin.X" name as Kotlin reflection specifies.
/// For nominal (user-defined) types the compiler-supplied name hint already
/// carries the fully-qualified name, so it is returned unchanged.
@_cdecl("__kk_type_token_qualified_name")
public func __kk_type_token_qualified_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    // Built-in stdlib types always live in the `kotlin` package.
    let qualifiedName: String? = switch base {
    case RuntimeTypeTokenEncoding.anyBase:     "kotlin.Any"
    case RuntimeTypeTokenEncoding.stringBase:  "kotlin.String"
    case RuntimeTypeTokenEncoding.intBase:     "kotlin.Int"
    case RuntimeTypeTokenEncoding.uintBase:    "kotlin.UInt"
    case RuntimeTypeTokenEncoding.ulongBase:   "kotlin.ULong"
    case RuntimeTypeTokenEncoding.ubyteBase:   "kotlin.UByte"
    case RuntimeTypeTokenEncoding.ushortBase:  "kotlin.UShort"
    case RuntimeTypeTokenEncoding.byteBase:     "kotlin.Byte"
    case RuntimeTypeTokenEncoding.shortBase:    "kotlin.Short"
    case RuntimeTypeTokenEncoding.booleanBase: "kotlin.Boolean"
    case RuntimeTypeTokenEncoding.longBase:    "kotlin.Long"
    case RuntimeTypeTokenEncoding.doubleBase:  "kotlin.Double"
    case RuntimeTypeTokenEncoding.floatBase:   "kotlin.Float"
    case RuntimeTypeTokenEncoding.charBase:    "kotlin.Char"
    case RuntimeTypeTokenEncoding.nullBase:    "kotlin.Nothing"
    case RuntimeTypeTokenEncoding.unitBase:    "kotlin.Unit"
    default: nil
    }
    if let qualifiedName {
        let utf8 = Array(qualifiedName.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }
    // For nominal types the nameHint carries the fully-qualified name.
    return __kk_type_token_simple_name(typeToken, nameHint)
}

func runtimeKClassBox(from raw: Int) -> RuntimeKClassBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKClassBox.self)
    }
}

/// Creates a `KClass<T>` metadata object from a type token and name hint.
/// Returns an opaque pointer to a `RuntimeKClassBox`.
///
/// KClass boxes are interned: repeated calls with the same `typeToken`
/// return the same pointer without allocating a new box. This avoids
/// unbounded memory growth when `T::class` is evaluated in a loop. The boxes
/// are tracked in `runtimeStorage.kClassBoxCache` and are cleared on
/// `resetRuntimeLocked` (e.g. between test runs).
@_cdecl("__kk_kclass_create")
public func __kk_kclass_create(_ typeToken: Int, _ nameHint: Int) -> Int {
    let cacheKey = KClassCacheKey(typeToken: typeToken)
    if let cached = runtimeStorage.withMetadataLock({ state in state.kClassBoxCache[cacheKey] }) {
        return cached
    }
    let box = RuntimeKClassBox(typeToken: typeToken, nameHint: nameHint)
    registerReflectionRuntimeTypeMetadata()
    let result = registerRuntimeObject(box, typeID: kClassRuntimeTypeID)
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let existing = state.kClassBoxCache[cacheKey] {
            return existing
        }
        state.kClassBoxCache[cacheKey] = result
        return result
    }
    if winner != result {
        guard let opaque = UnsafeMutableRawPointer(bitPattern: result) else {
            return winner
        }
        runtimeStorage.withGCLock { state in
            state.objectPointers.remove(UInt(bitPattern: opaque))
        }
        runtimeStorage.withMetadataLock { state in
            state.objectTypeByPointer.removeValue(forKey: UInt(bitPattern: opaque))
        }
        Unmanaged<RuntimeKClassBox>.fromOpaque(opaque).release()
    }
    return winner
}

// MARK: - KSP-496: KClass-handle-based simpleName / qualifiedName bridges
//
// Unlike `__kk_type_token_simple_name`/`__kk_type_token_qualified_name` (which take
// a bare type token + name hint known at the `T::class` call site), these take
// the KClass box handle itself so the Kotlin-source `simpleName`/`qualifiedName`
// properties (Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt) can
// be ordinary extension properties dispatched on `this`, without requiring
// reified static type information at the call site.

@_cdecl("__kk_kclass_simple_name")
public func __kk_kclass_simple_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return __kk_type_token_simple_name(box.typeToken, box.nameHint)
}

@_cdecl("__kk_kclass_qualified_name")
public func __kk_kclass_qualified_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return __kk_type_token_qualified_name(box.typeToken, box.nameHint)
}

// MARK: - REFL-004: KClass Binary Metadata Accessors

/// Registers runtime reflection metadata for a type identified by `typeToken`.
/// Called during module initialization to populate the global metadata registry
/// from the binary metadata blob emitted by `RuntimeReflectionMetadataEmitter`.
///
/// Parameters are passed as intptr_t values:
/// - typeToken: The type token identifying the type.
/// - qualifiedNameRaw: Runtime string pointer for the qualified name.
/// - simpleNameRaw: Runtime string pointer for the simple name.
/// - supertypeNameRaw: Runtime string pointer for the supertype name (0 if none).
/// - flags: Bit-packed flags (bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///          bit 3=interface, bit 4=object, bit 5=enumClass, bit 6=annotationClass,
///          bit 7=abstract).
/// - fieldCount: Number of declared fields (-1 if unknown).
/// - memberCount: Number of declared members (-1 if unknown).
@_cdecl("__kk_kclass_register_metadata")
public func __kk_kclass_register_metadata(
    _ typeToken: Int,
    _ qualifiedNameRaw: Int,
    _ simpleNameRaw: Int,
    _ supertypeNameRaw: Int,
    _ flags: Int,
    _ fieldCount: Int,
    _ memberCount: Int,
    _ constructorCount: Int
) -> Int {
    return __kk_kclass_register_metadata_v2(
        typeToken, qualifiedNameRaw, simpleNameRaw, supertypeNameRaw,
        flags, fieldCount, memberCount, constructorCount, 0, 0
    )
}

/// STDLIB-REFLECT-060: Extended metadata registration with visibility and type parameter count.
/// - visibilityRaw: Runtime string pointer for visibility ("PUBLIC", "INTERNAL", etc.), 0 if unknown.
/// - typeParameterCount: Number of type parameters on the class.
/// Flags bit layout: bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///   bit 3=interface, bit 4=object, bit 5=enumClass, bit 6=annotationClass,
///   bit 7=abstract, bit 8=final, bit 9=open,
///   bit 10=inner, bit 11=companion, bit 12=funInterface. (STDLIB-REFLECT-067)
@_cdecl("__kk_kclass_register_metadata_v2")
public func __kk_kclass_register_metadata_v2(
    _ typeToken: Int,
    _ qualifiedNameRaw: Int,
    _ simpleNameRaw: Int,
    _ supertypeNameRaw: Int,
    _ flags: Int,
    _ fieldCount: Int,
    _ memberCount: Int,
    _ constructorCount: Int,
    _ visibilityRaw: Int,
    _ typeParameterCount: Int
) -> Int {
    let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw)) ?? "Unknown"
    let simpleName = extractString(from: UnsafeMutableRawPointer(bitPattern: simpleNameRaw)) ?? "Unknown"
    let supertypeName: String?
    if supertypeNameRaw != 0, supertypeNameRaw != runtimeNullSentinelInt {
        supertypeName = extractString(from: UnsafeMutableRawPointer(bitPattern: supertypeNameRaw))
    } else {
        supertypeName = nil
    }

    let visibility: String
    if visibilityRaw != 0, visibilityRaw != runtimeNullSentinelInt,
       let visStr = extractString(from: UnsafeMutableRawPointer(bitPattern: visibilityRaw))
    {
        visibility = visStr
    } else {
        visibility = "PUBLIC"
    }

    let entry = RuntimeKClassMetadataEntry(
        qualifiedName: qualifiedName,
        simpleName: simpleName,
        supertypeName: supertypeName,
        isDataClass: (flags & (1 << 0)) != 0,
        isSealedClass: (flags & (1 << 1)) != 0,
        isValueClass: (flags & (1 << 2)) != 0,
        isInterface: (flags & (1 << 3)) != 0,
        isObject: (flags & (1 << 4)) != 0,
        isEnumClass: (flags & (1 << 5)) != 0,
        isAnnotationClass: (flags & (1 << 6)) != 0,
        isAbstract: (flags & (1 << 7)) != 0,
        fieldCount: fieldCount,
        memberCount: memberCount,
        constructorCount: constructorCount,
        isFinal: (flags & (1 << 8)) != 0,
        isOpen: (flags & (1 << 9)) != 0,
        visibility: visibility,
        typeParameterCount: typeParameterCount,
        isInner: (flags & (1 << 10)) != 0,
        isCompanion: (flags & (1 << 11)) != 0,
        isFunInterface: (flags & (1 << 12)) != 0
    )
    runtimeKClassMetadataRegistry.register(typeToken: typeToken, entry: entry)
    return 0
}

/// Returns 1 if the KClass represents a data class, 0 otherwise.
@_cdecl("__kk_kclass_is_data")
public func __kk_kclass_is_data(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isDataClass ? 1 : 0
}

/// Returns 1 if the KClass represents a sealed class, 0 otherwise.
@_cdecl("__kk_kclass_is_sealed")
public func __kk_kclass_is_sealed(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isSealedClass ? 1 : 0
}

/// Returns 1 if the KClass represents a value (inline) class, 0 otherwise.
@_cdecl("__kk_kclass_is_value")
public func __kk_kclass_is_value(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isValueClass ? 1 : 0
}

/// Returns 1 if the KClass represents an interface, 0 otherwise.
@_cdecl("__kk_kclass_is_interface")
public func __kk_kclass_is_interface(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isInterface ? 1 : 0
}

/// Returns 1 if the KClass represents an object declaration, 0 otherwise.
@_cdecl("__kk_kclass_is_object")
public func __kk_kclass_is_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isObject ? 1 : 0
}

/// Returns 1 if the KClass represents an enum class, 0 otherwise.
@_cdecl("__kk_kclass_is_enum")
public func __kk_kclass_is_enum(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isEnumClass ? 1 : 0
}

// MARK: - STDLIB-REFLECT-067: KClass type-kind introspection

/// Returns 1 if the KClass represents an inner class, 0 otherwise.
@_cdecl("__kk_kclass_is_inner")
public func __kk_kclass_is_inner(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isInner ? 1 : 0
}

/// Returns 1 if the KClass represents a companion object, 0 otherwise.
@_cdecl("__kk_kclass_is_companion")
public func __kk_kclass_is_companion(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isCompanion ? 1 : 0
}

/// Returns 1 if the KClass represents a functional interface (fun interface), 0 otherwise.
@_cdecl("__kk_kclass_is_fun")
public func __kk_kclass_is_fun(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isFunInterface ? 1 : 0
}

/// Returns 1 if the KClass represents an abstract class, 0 otherwise.
@_cdecl("__kk_kclass_is_abstract")
public func __kk_kclass_is_abstract(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isAbstract ? 1 : 0
}

// MARK: - STDLIB-REFLECT-060: KClass basic reflection features

/// Returns 1 if the KClass represents a final class, 0 otherwise.
/// A class is final if it is not abstract, not open, and not an interface.
@_cdecl("__kk_kclass_is_final")
public func __kk_kclass_is_final(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isFinal ? 1 : 0
}

/// Returns 1 if the KClass represents an open class, 0 otherwise.
@_cdecl("__kk_kclass_is_open")
public func __kk_kclass_is_open(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isOpen ? 1 : 0
}

/// Returns the visibility of this KClass as a runtime string ("PUBLIC", "INTERNAL", "PRIVATE", "PROTECTED").
/// Returns null sentinel if unknown.
@_cdecl("__kk_kclass_visibility")
public func __kk_kclass_visibility(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return runtimeNullSentinelInt
    }
    let utf8 = Array(metadata.visibility.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Returns the type parameters of this KClass as a runtime list.
/// Each element is an integer representing the type parameter index.
/// Returns an empty list if no type parameters.
@_cdecl("__kk_kclass_type_parameters")
public func __kk_kclass_type_parameters(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let count = max(0, metadata.typeParameterCount)
    let indices = (0..<count).map { $0 }
    return registerRuntimeObject(RuntimeListBox(elements: indices))
}

/// Returns the supertypes of this KClass as a runtime list of strings.
/// Currently returns a list with the single supertype name if present.
@_cdecl("__kk_kclass_supertypes")
public func __kk_kclass_supertypes(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata,
          let superName = metadata.supertypeName else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let utf8 = Array(superName.utf8)
    let nameRaw = utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
    return registerRuntimeObject(RuntimeListBox(elements: [nameRaw]))
}

// MARK: - REFL-005: KClass.isInstance, members, constructors

/// Checks if a value is an instance of the type represented by this KClass.
/// Delegates to the existing `kk_op_is` runtime type check using the KClass
/// box's type token.
/// Returns 1 (true) if the value is an instance, 0 (false) otherwise.
@_cdecl("__kk_kclass_isInstance")
public func __kk_kclass_isInstance(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kk_op_is(valueRaw, box.typeToken)
}

/// Registers a single member (KFunction or KPropertyStub) for a KClass (STDLIB-REFLECT-ABI-002).
/// Called during module initialization to attach compile-time member data.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass returned by `__kk_kclass_create`.
///   - memberRaw: Opaque handle to the member callable (KFunction or KPropertyStub).
/// - Returns: 0 on success.
@_cdecl("__kk_kclass_register_member")
public func __kk_kclass_register_member(_ kclassRaw: Int, _ memberRaw: Int) -> Int {
    runtimeKMemberRegistry.register(classRaw: kclassRaw, memberRaw: memberRaw)
    return 0
}

/// Returns the members of this KClass as a runtime list of KCallable handles.
/// When members have been registered via `__kk_kclass_register_member`, the list
/// contains the actual KFunction / KPropertyStub handles (STDLIB-REFLECT-ABI-002).
@_cdecl("__kk_kclass_members")
public func __kk_kclass_members(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.members(for: kclassRaw)))
}

/// Returns the constructors of this KClass as a runtime list of KFunction boxes.
/// Only constructors registered through `__kk_kconstructor_create` are returned.
@_cdecl("__kk_kclass_constructors")
public func __kk_kclass_constructors(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKConstructorRegistry.constructors(for: kclassRaw)))
}

/// Returns the nested classes of this KClass as a runtime list of KClass handles.
/// Currently returns an empty list; nested class metadata registration is not yet
/// emitted by the compiler (MIGRATION-REFLECT-002).
@_cdecl("__kk_kclass_nested_classes")
public func __kk_kclass_nested_classes(_ kclassRaw: Int) -> Int {
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

/// Returns the primary constructor of this KClass as a KConstructor box, or null sentinel if none.
/// STDLIB-REFLECT-064
@_cdecl("__kk_kclass_primary_constructor")
public func __kk_kclass_primary_constructor(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return runtimeNullSentinelInt
    }
    return runtimeKConstructorRegistry.primaryConstructor(for: kclassRaw) ?? runtimeNullSentinelInt
}

// MARK: - STDLIB-REFLECT-061: KClass member access (properties, functions, etc.)

/// Returns all properties (including inherited) of this KClass as a runtime list.
/// Returns registered `RuntimeKPropertyStub` handles only.
@_cdecl("__kk_kclass_properties")
public func __kk_kclass_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns the non-extension member properties of this KClass as a runtime list.
/// These are the properties declared directly in the class or its superclasses,
/// excluding extension properties.
@_cdecl("__kk_kclass_member_properties")
public func __kk_kclass_member_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns the declared member properties of this KClass (own class only, not inherited).
/// These are properties explicitly declared in this class, excluding superclass properties.
@_cdecl("__kk_kclass_declared_member_properties")
public func __kk_kclass_declared_member_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns all functions (including inherited) of this KClass as a runtime list.
/// Returns registered `RuntimeKFunctionBox` handles only.
@_cdecl("__kk_kclass_functions")
public func __kk_kclass_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

/// Returns the non-extension member functions of this KClass as a runtime list.
/// These are functions declared in the class or its superclasses, excluding extensions.
@_cdecl("__kk_kclass_member_functions")
public func __kk_kclass_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

/// Returns the declared member functions of this KClass (own class only, not inherited).
/// These are functions explicitly declared in this class, excluding superclass functions.
@_cdecl("__kk_kclass_declared_member_functions")
public func __kk_kclass_declared_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

// MARK: - STDLIB-REFLECT-ABI-003: KClass.cast / KClass.safeCast

/// Casts `valueRaw` to the type represented by this KClass.
/// If the value is an instance of the type, returns it unchanged.
/// If not, sets `outThrown` to a `ClassCastException` and returns the null sentinel.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass.
///   - valueRaw: The value to cast.
///   - outThrown: Out-pointer for the thrown exception (nullable).
/// - Returns: `valueRaw` on success, or `runtimeNullSentinelInt` on failure.
@_cdecl("__kk_kclass_cast")
public func __kk_kclass_cast(
    _ kclassRaw: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        outThrown?.pointee = runtimeAllocateClassCastException(
            message: "Invalid KClass handle."
        )
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    if isInstance != 0 {
        return valueRaw
    }
    let typeName: String
    if let metadata = box.metadata {
        typeName = metadata.qualifiedName.isEmpty ? metadata.simpleName : metadata.qualifiedName
    } else {
        typeName = "Unknown"
    }
    outThrown?.pointee = runtimeAllocateClassCastException(
        message: "Value cannot be cast to \(typeName)."
    )
    return runtimeNullSentinelInt
}

/// Tries to cast `valueRaw` to the type represented by this KClass.
/// Returns `valueRaw` if the value is an instance, or the null sentinel if not.
/// Never throws; equivalent to Kotlin's `safeCast` (`value as? T`).
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass.
///   - valueRaw: The value to cast.
/// - Returns: `valueRaw` on success, or `runtimeNullSentinelInt` if not an instance.
@_cdecl("__kk_kclass_safeCast")
public func __kk_kclass_safeCast(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    return isInstance != 0 ? valueRaw : runtimeNullSentinelInt
}

// MARK: - REFL-005: KType and typeOf<T>()

private func runtimeKTypeCreate(_ classifierRaw: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    var argumentRaws: [Int] = []
    if argsRaw != 0 && argsRaw != runtimeNullSentinelInt,
       let ptr = UnsafeMutableRawPointer(bitPattern: argsRaw) {
        let isObj = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObj, let listBox = tryCast(ptr, to: RuntimeListBox.self) {
            argumentRaws = listBox.elements
        }
    }
    let box = RuntimeKTypeBox(
        classifierRaw: classifierRaw,
        argumentRaws: argumentRaws,
        isMarkedNullable: isNullable != 0
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kTypeRuntimeTypeID)
}

/// Returns the classifier (KClass) raw handle from a KType, or null sentinel.
@_cdecl("__kk_ktype_classifier")
public func __kk_ktype_classifier(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return runtimeNullSentinelInt
    }
    return box.classifierRaw
}

/// Returns the list of type arguments (KTypeProjection handles) from a KType.
@_cdecl("__kk_ktype_arguments")
public func __kk_ktype_arguments(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.argumentRaws))
}

/// Returns 1 if the KType is marked nullable, 0 otherwise.
@_cdecl("__kk_ktype_isMarkedNullable")
public func __kk_ktype_isMarkedNullable(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return 0
    }
    return box.isMarkedNullable ? 1 : 0
}

/// Creates a KTypeProjection from a KType raw handle and variance ordinal.
/// variance: 0=IN, 1=OUT, 2=INVARIANT, -1=STAR (type is ignored for STAR)
@_cdecl("__kk_ktypeprojection_create")
public func __kk_ktypeprojection_create(_ typeRaw: Int, _ varianceOrdinal: Int) -> Int {
    let variance: RuntimeKVariance?
    if varianceOrdinal == -1 {
        variance = nil // STAR projection
    } else {
        variance = RuntimeKVariance(rawValue: varianceOrdinal) ?? .invariant
    }
    let box = RuntimeKTypeProjectionBox(typeRaw: typeRaw, variance: variance)
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kTypeProjectionRuntimeTypeID)
}

/// Creates a KTypeProjection through its public constructor.
/// The Kotlin constructor accepts either two nulls (a star projection) or
/// two non-null values; every other pair throws IllegalArgumentException.
@_cdecl("__kk_ktypeprojection_create_checked")
public func __kk_ktypeprojection_create_checked(
    _ varianceOrdinal: Int,
    _ typeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    let varianceIsNull = varianceOrdinal == runtimeNullSentinelInt
    let typeIsNull = typeRaw == 0 || typeRaw == runtimeNullSentinelInt
    // Nullable enum arguments cross the runtime ABI as boxed Int handles.
    // Preserve the null sentinel before unboxing; kk_unbox_int maps null to 0.
    let kotlinVarianceOrdinal = varianceIsNull ? -1 : kk_unbox_int(varianceOrdinal)
    // KVariance declares INVARIANT, IN, OUT, while RuntimeKVariance keeps the
    // existing typeOf bridge's internal order IN, OUT, INVARIANT.
    let decodedVarianceOrdinal: Int = switch kotlinVarianceOrdinal {
    case 0: 2 // INVARIANT
    case 1: 0 // IN
    case 2: 1 // OUT
    default: kotlinVarianceOrdinal
    }
    guard varianceIsNull == typeIsNull else {
        let message: String
        if varianceIsNull {
            message = "Star projection must have no type specified."
        } else {
            let varianceName: String = switch RuntimeKVariance(rawValue: decodedVarianceOrdinal) {
            case .in: "IN"
            case .out: "OUT"
            case .invariant: "INVARIANT"
            case nil: "INVARIANT"
            }
            message = "The projection variance \(varianceName) requires type to be specified."
        }
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: message)
        return 0
    }

    return __kk_ktypeprojection_create(typeIsNull ? 0 : typeRaw, decodedVarianceOrdinal)
}

/// Implements `typeOf<T>()` — creates a KType for the given type token.
/// This is the reified inline function entry point. The compiler emits the
/// type token and nullability at the call site.
@_cdecl("kk_typeof")
public func kk_typeof(_ typeToken: Int, _ nameHint: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    let classifierRaw = __kk_kclass_create(typeToken, nameHint)
    return runtimeKTypeCreate(classifierRaw, argsRaw, isNullable)
}

// MARK: - KType / KTypeProjection Box Helpers

private func runtimeKTypeBox(from raw: Int) -> RuntimeKTypeBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKTypeBox.self)
    }
}

@_cdecl("kk_type_register_super")
public func kk_type_register_super(_ childTypeId: Int, _ superTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(superTypeId))
    return 0
}

@_cdecl("kk_type_register_iface")
public func kk_type_register_iface(_ childTypeId: Int, _ ifaceTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(ifaceTypeId))
    return 0
}

@_cdecl("kk_object_register_itable_iface")
public func kk_object_register_itable_iface(
    _ objectRaw: Int,
    _ ifaceTypeId: Int,
    _ ifaceSlot: Int
) -> Int {
    guard ifaceTypeId != 0,
          ifaceSlot >= 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        var slots = state.objectInterfaceSlots[objectKey] ?? [:]
        slots[Int64(ifaceTypeId)] = ifaceSlot
        state.objectInterfaceSlots[objectKey] = slots
    }
    return 0
}

@_cdecl("kk_object_register_itable_method")
public func kk_object_register_itable_method(
    _ objectRaw: Int,
    _ ifaceSlot: Int,
    _ methodSlot: Int,
    _ functionRaw: Int
) -> Int {
    guard ifaceSlot >= 0,
          methodSlot >= 0,
          functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    let dispatchKey = (UInt64(UInt32(ifaceSlot)) << 32) | UInt64(UInt32(methodSlot))
    runtimeStorage.withMetadataLock { state in
        var methods = state.objectItableMethods[objectKey] ?? [:]
        methods[dispatchKey] = functionRaw
        state.objectItableMethods[objectKey] = methods
    }
    return 0
}

@_cdecl("kk_object_register_vtable_method")
public func kk_object_register_vtable_method(
    _ objectRaw: Int,
    _ methodSlot: Int,
    _ functionRaw: Int
) -> Int {
    guard methodSlot >= 0,
          functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        var methods = state.objectVtableMethods[objectKey] ?? [:]
        methods[methodSlot] = functionRaw
        state.objectVtableMethods[objectKey] = methods
    }
    return 0
}

@_cdecl("kk_array_get")
public func kk_array_get(_ arrayRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard index >= 0, index < array.count else {
        outThrown?.pointee = runtimeAllocateArrayIndexOutOfBoundsException(
            message: "Array index \(index) out of bounds for length \(array.count)."
        )
        return 0
    }
    return array[index]
}

@_cdecl("kk_array_get_inbounds")
public func kk_array_get_inbounds(_ arrayRaw: Int, _ index: Int) -> Int {
    // Uses the O(1) subscript rather than `elements`, which copies the whole
    // backing store on every access. This is the hot path for object field
    // reads as well as array indexing.
    guard let array = runtimeArrayBox(from: arrayRaw),
          index >= 0, index < array.count
    else {
        runtimeStructuredPanic("kk_array_get_inbounds precondition failed")
    }
    return array[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard index >= 0, index < array.count else {
        outThrown?.pointee = runtimeAllocateArrayIndexOutOfBoundsException(
            message: "Array index \(index) out of bounds for length \(array.count)."
        )
        return 0
    }
    array[index] = value
    return value
}

@_cdecl("kk_vararg_spread_concat")
public func kk_vararg_spread_concat(_ pairsArrayRaw: Int, _ pairCount: Int) -> Int {
    guard let pairs = runtimeArrayBox(from: pairsArrayRaw),
          pairCount > 0,
          pairs.elements.count >= pairCount * 2 else { return kk_array_new(0) }
    var totalCount = 0
    for i in 0 ..< pairCount {
        let marker = pairs.elements[i * 2]
        let value = pairs.elements[i * 2 + 1]
        if marker == -1 {
            if let array = runtimeArrayBox(from: value) {
                totalCount += array.elements.count
            }
        } else {
            totalCount += 1
        }
    }
    let result = kk_array_new(totalCount)
    if let box = runtimeArrayBox(from: result) {
        var writeIndex = 0
        for i in 0 ..< pairCount {
            let marker = pairs.elements[i * 2]
            let value = pairs.elements[i * 2 + 1]
            if marker == -1 {
                if let array = runtimeArrayBox(from: value) {
                    for elem in array.elements {
                        box.elements[writeIndex] = elem
                        writeIndex += 1
                    }
                }
            } else {
                box.elements[writeIndex] = value
                writeIndex += 1
            }
        }
    }
    return result
}

/// Runtime support for kotlin.io.DEFAULT_BUFFER_SIZE.
@_cdecl("kk_io_default_buffer_size")
public func kk_io_default_buffer_size() -> Int {
    8192
}

/// KSP-615: single low-level console input bridge behind `kotlin.io.readLine` /
/// `readln` / `readlnOrNull`. Reads a line from stdin. Returns a pointer to a
/// runtime string on success, or `runtimeNullSentinelInt` on EOF; nullability
/// and the `readln` EOF throw live in `Stdlib/kotlin/io/Console.kt`.
@_cdecl("__kk_readline_raw")
public func __kk_readline_raw() -> Int {
    guard let line = readLine() else {
        return runtimeNullSentinelInt
    }
    let utf8 = Array(line.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

func runtimeRenderAnyForPrint(_ value: Int) -> String {
    if value == runtimeNullSentinelInt {
        return "null"
    }
    guard let raw = UnsafeMutableRawPointer(bitPattern: value) else {
        return String(value)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    guard isObjectPointer else {
        return String(value)
    }
    if runtimeIsUnitBox(value) {
        return "kotlin.Unit"
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        return intBox.enumEntryName ?? String(intBox.value)
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let doubleBox = tryCast(raw, to: RuntimeDoubleBox.self) {
        return runtimeFormatFloatingPoint(doubleBox.value)
    }
    if let floatBox = tryCast(raw, to: RuntimeFloatBox.self) {
        return runtimeFormatFloatingPoint(floatBox.value)
    }
    if let longBox = tryCast(raw, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let ulongBox = tryCast(raw, to: RuntimeULongBox.self) {
        return String(UInt(bitPattern: ulongBox.value))
    }
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        if let scalar = UnicodeScalar(charBox.value) {
            return String(Character(scalar))
        }
        return "?"
    }
    if let throwableString = runtimeThrowableToString(value) {
        return throwableString
    }
    if let instantBox = tryCast(raw, to: RuntimeInstantBox.self) {
        return runtimeInstantToString(instantBox)
    }
    if let listBox = tryCast(raw, to: RuntimeListBox.self) {
        return "[\(listBox.values.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        return "[\(setBox.values.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keyValues, mapBox.entryValues).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        return "{\(rendered)}"
    }
    if tryCast(raw, to: RuntimeRangeBox.self) != nil {
        return runtimeElementToString(value)
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.firstValue)
        let second = runtimeRenderAnyForPrint(pairBox.secondValue)
        if runtimeIsMapEntry(rawValue: value) {
            return "\(first)=\(second)"
        }
        if runtimeObjectTypeID(rawValue: value) == indexedValueRuntimeTypeID {
            return "IndexedValue(index=\(first), value=\(second))"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(raw, to: RuntimeTripleBox.self) {
        let first = runtimeRenderAnyForPrint(tripleBox.firstValue)
        let second = runtimeRenderAnyForPrint(tripleBox.secondValue)
        let third = runtimeRenderAnyForPrint(tripleBox.thirdValue)
        return "(\(first), \(second), \(third))"
    }
    if tryCast(raw, to: RuntimeIndexingIterableBox.self) != nil {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        return "kotlin.collections.IndexingIterable@\(hex)"
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        return "[\(arrayBox.values.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let sbBox = tryCast(raw, to: RuntimeStringBuilderBox.self) {
        return sbBox.value
    }
    if let ktypeProjectionBox = tryCast(raw, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionToString(ktypeProjectionBox)
    }
    // STDLIB-REFLECT-066: KType rendering
    if let ktypeBox = tryCast(raw, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    if let rendered = runtimeRenderIndexedValueObject(value, render: runtimeRenderAnyForPrint) {
        return rendered
    }
    return "<object \(raw)>"
}

func runtimeRenderAnyForPrint(_ value: RuntimeValue) -> String {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return "null"
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.charTag:
        return UnicodeScalar(value.payload0).map { String(Character($0)) } ?? "?"
    default:
        return runtimeRenderAnyForPrint(value.payload0)
    }
}

private func runtimeNormalizeScientificExponent(_ rendered: String) -> String {
    guard let exponentIndex = rendered.firstIndex(of: "E") ?? rendered.firstIndex(of: "e") else {
        return rendered
    }
    let mantissa = runtimeNormalizeScientificMantissa(String(rendered[..<exponentIndex]))
    var exponent = String(rendered[rendered.index(after: exponentIndex)...])
    if exponent.hasPrefix("+") {
        exponent.removeFirst()
    }
    while exponent.count > 1, exponent.first == "0" {
        exponent.removeFirst()
    }
    if exponent.hasPrefix("-0"), exponent.count > 2 {
        exponent.remove(at: exponent.index(after: exponent.startIndex))
    }
    return "\(mantissa)E\(exponent)"
}

private func runtimeNormalizeScientificMantissa(_ mantissa: String) -> String {
    guard let dotIndex = mantissa.firstIndex(of: ".") else {
        return mantissa + ".0"
    }
    let integerPart = String(mantissa[..<dotIndex])
    var fractionalPart = String(mantissa[mantissa.index(after: dotIndex)...])
    while fractionalPart.last == "0" {
        fractionalPart.removeLast()
    }
    if fractionalPart.isEmpty {
        fractionalPart = "0"
    }
    return "\(integerPart).\(fractionalPart)"
}

private func runtimeScientificString(fromFixed rendered: String) -> String {
    var body = rendered
    var sign = ""
    if body.hasPrefix("-") {
        sign = "-"
        body.removeFirst()
    } else if body.hasPrefix("+") {
        body.removeFirst()
    }

    let components = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integerPart = String(components.first ?? "")
    let fractionalPart = components.count > 1 ? String(components[1]) : ""

    let trimmedInteger = integerPart.drop(while: { $0 == "0" })
    let exponent: Int
    let significantDigits: String

    if !trimmedInteger.isEmpty {
        exponent = trimmedInteger.count - 1
        significantDigits = String(trimmedInteger) + fractionalPart
    } else if let firstNonZeroFraction = fractionalPart.firstIndex(where: { $0 != "0" }) {
        exponent = -fractionalPart.distance(from: fractionalPart.startIndex, to: firstNonZeroFraction) - 1
        significantDigits = String(fractionalPart[firstNonZeroFraction...])
    } else {
        return sign + "0.0E0"
    }

    let firstDigit = String(significantDigits.prefix(1))
    var mantissaFraction = String(significantDigits.dropFirst())
    while mantissaFraction.last == "0" {
        mantissaFraction.removeLast()
    }
    if mantissaFraction.isEmpty {
        mantissaFraction = "0"
    }
    return "\(sign)\(firstDigit).\(mantissaFraction)E\(exponent)"
}

/// Applies Kotlin's decimal/scientific notation rules to an already-rendered
/// shortest-round-trip string. Kotlin (matching java.lang.Double/Float.toString)
/// uses scientific notation when the magnitude is >= 1e7 or < 1e-3.
private func runtimeFinishFloatingPointFormat(rendered: String, useScientific: Bool) -> String {
    if rendered.contains("e") || rendered.contains("E") {
        return runtimeNormalizeScientificExponent(rendered)
    }
    if useScientific {
        return runtimeScientificString(fromFixed: rendered)
    }
    return rendered
}

func runtimeFormatFloatingPoint(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    // Explicit guard: String(describing:) may drop the sign of -0.0 on some platforms.
    if value == 0.0 && value.sign == .minus { return "-0.0" }
    // Swift's Ryu selects the 1-significant-digit form (5e-324) for the minimum
    // subnormal, but Java's FloatingDecimal emits 4.9E-324.  Both strings
    // round-trip to the same bit pattern, but we must match the Java convention.
    if value == Double.leastNonzeroMagnitude { return "4.9E-324" }
    if value == -Double.leastNonzeroMagnitude { return "-4.9E-324" }
    let magnitude = abs(value)
    return runtimeFinishFloatingPointFormat(
        rendered: String(describing: value),
        useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
    )
}

func runtimeFormatFloatingPoint(_ value: Float) -> String {
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    // Explicit guard: String(describing:) may drop the sign of -0.0 on some platforms.
    if value == 0.0 && value.sign == .minus { return "-0.0" }
    // Same issue for Float: Ryu gives 1e-45, Java gives 1.4E-45.
    if value == Float.leastNonzeroMagnitude { return "1.4E-45" }
    if value == -Float.leastNonzeroMagnitude { return "-1.4E-45" }
    let magnitude = abs(value)
    return runtimeFinishFloatingPointFormat(
        rendered: String(describing: value),
        useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
    )
}

// MARK: - String nullable receiver helpers

@_cdecl("kk_string_isNullOrEmpty_flat")
public func kk_string_isNullOrEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard data != nil else {
        return 1
    }
    let str = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return str.isEmpty ? 1 : 0
}

@_cdecl("kk_string_isNullOrBlank_flat")
public func kk_string_isNullOrBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard data != nil else {
        return 1
    }
    let str = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return str.allSatisfy(\.isWhitespace) ? 1 : 0
}

// MARK: - STDLIB-534: String?.orEmpty()

@_cdecl("kk_string_orEmpty_flat")
public func kk_string_orEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let value = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return runtimeRegisterFlatString(
        value,
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}
