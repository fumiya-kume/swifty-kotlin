import Foundation

@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let throwableInt = runtimeAllocateThrowable(message: text)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        fatalError("kk_throwable_new: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_new_with_cause")
public func kk_throwable_new_with_cause(_ message: UnsafeMutableRawPointer?, _ causeRaw: Int) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let throwableInt = runtimeAllocateThrowable(message: text, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        fatalError("kk_throwable_new_with_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_is_cancellation")
public func kk_throwable_is_cancellation(_ throwableRaw: Int) -> Int {
    kk_is_cancellation_exception(throwableRaw)
}

@_cdecl("kk_throwable_message")
public func kk_throwable_message(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    let message: String
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        message = throwable.message
    } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        message = cancellation.message
    } else {
        return runtimeNullSentinelInt
    }
    let box = RuntimeStringBox(message)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_throwable_cause")
public func kk_throwable_cause(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return throwable.cause == 0 ? runtimeNullSentinelInt : throwable.cause
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_throwable_stackTraceToString")
public func kk_throwable_stackTraceToString(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        let box = RuntimeStringBox("")
        let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        runtimeStorage.withLock { state in
            state.objectPointers.insert(UInt(bitPattern: opaque))
        }
        return Int(bitPattern: opaque)
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        let box = RuntimeStringBox("")
        let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        runtimeStorage.withLock { state in
            state.objectPointers.insert(UInt(bitPattern: opaque))
        }
        return Int(bitPattern: opaque)
    }
    let message: String = if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        throwable.renderedMessage
    } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        cancellation.message
    } else {
        ""
    }
    let box = RuntimeStringBox(message)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

// MARK: - Advanced exception features (STDLIB-EXCEPT-105)

/// initCause(cause: Throwable?): Throwable — sets the cause on a throwable, returns the throwable.
@_cdecl("kk_throwable_initCause")
public func kk_throwable_initCause(_ throwableRaw: Int, _ causeRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt, throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    else {
        return throwableRaw
    }
    let causeValue = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    throwable.cause = causeValue
    return throwableRaw
}

/// addSuppressed(exception: Throwable): Unit — adds a suppressed exception.
@_cdecl("kk_throwable_addSuppressed")
public func kk_throwable_addSuppressed(_ throwableRaw: Int, _ suppressedRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt, throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    else {
        return 0
    }
    if suppressedRaw != runtimeNullSentinelInt && suppressedRaw != 0 {
        throwable.suppressed.append(suppressedRaw)
    }
    return 0
}

/// getSuppressed(): Array<Throwable> — returns the suppressed exceptions as an array.
@_cdecl("kk_throwable_getSuppressed")
public func kk_throwable_getSuppressed(_ throwableRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt, throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    else {
        let emptyArray = RuntimeArrayBox(length: 0)
        let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(emptyArray).toOpaque())
        runtimeStorage.withLock { state in
            state.objectPointers.insert(UInt(bitPattern: opaque))
        }
        return Int(bitPattern: opaque)
    }
    let arrayBox = RuntimeArrayBox(length: throwable.suppressed.count)
    for (i, elem) in throwable.suppressed.enumerated() {
        arrayBox.elements[i] = elem
    }
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(arrayBox).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never {
    fatalError(runtimePanicMessage(fromCString: cstr))
}

@_cdecl("kk_abort_unreachable")
public func kk_abort_unreachable(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: reached unreachable code")
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

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
    // REFL-002: Additional primitive bases for Long, Double, Float, Char.
    static let longBase: Int64 = 11
    static let doubleBase: Int64 = 12
    static let floatBase: Int64 = 13
    static let charBase: Int64 = 14
}

func runtimePanicMessage(fromCString cstr: UnsafePointer<CChar>) -> String {
    let message = String(cString: cstr)
    return "KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(message)"
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = String(decoding: buffer, as: UTF8.self)
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
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

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let lhs = extractString(from: normalizeNullableRuntimePointer(a)) ?? ""
    let rhs = extractString(from: normalizeNullableRuntimePointer(b)) ?? ""
    let box = RuntimeStringBox(lhs + rhs)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return opaque
}

@_cdecl("kk_string_compareTo")
public func kk_string_compareTo(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> Int {
    let lhs = extractString(from: normalizeNullableRuntimePointer(a)) ?? ""
    let rhs = extractString(from: normalizeNullableRuntimePointer(b)) ?? ""
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}

@_cdecl("kk_string_length")
public func kk_string_length(_ strRaw: Int) -> Int {
    if strRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return runtimeNullSentinelInt
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer, let stringBox = tryCast(ptr, to: RuntimeStringBox.self) else {
        return runtimeNullSentinelInt
    }
    return stringBox.value.utf8.count
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
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isObjectPointer else {
            return 0
        }
        return tryCast(ptr, to: RuntimeStringBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.uintBase,
         RuntimeTypeTokenEncoding.ulongBase,
         RuntimeTypeTokenEncoding.ubyteBase,
         RuntimeTypeTokenEncoding.ushortBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return 1
        }
        return tryCast(ptr, to: RuntimeIntBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.longBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeLongBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.doubleBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeDoubleBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.floatBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeFloatBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.charBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeCharBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.booleanBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return (value == 0 || value == 1) ? 1 : 0
        }
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return (value == 0 || value == 1) ? 1 : 0
        }
        return tryCast(ptr, to: RuntimeBoolBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.nullBase:
        return 0

    case RuntimeTypeTokenEncoding.nominalBase:
        if let sourceTypeID = runtimeObjectTypeID(rawValue: value) {
            return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: payload) ? 1 : 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        let throwable = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
                ? tryCast(ptr, to: RuntimeThrowableBox.self)
                : nil
        }
        guard let throwable else {
            return 0
        }
        if runtimeThrowableMatchesNominalTypeID(throwable, targetTypeID: payload) {
            return 1
        }
        // RuntimeThrowableBox objects from external/runtime calls usually do not
        // have registered type IDs. Preserve the broad throwable fallback for
        // unknown nominal tokens so existing catch-path behaviour does not regress.
        return 1

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
    outThrown?.pointee = runtimeAllocateThrowable(message: "ClassCastException")
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
        return set.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0
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
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_object_new")
public func kk_object_new(_ length: Int, _ classId: Int) -> Int {
    let box = RuntimeObjectBox(length: length, classID: Int64(classId))
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        let key = UInt(bitPattern: opaque)
        state.objectPointers.insert(key)
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
@_cdecl("kk_type_token_simple_name")
public func kk_type_token_simple_name(_ typeToken: Int, _ nameHint: Int) -> Int {
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
@_cdecl("kk_type_token_qualified_name")
public func kk_type_token_qualified_name(_ typeToken: Int, _ nameHint: Int) -> Int {
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
    case RuntimeTypeTokenEncoding.booleanBase: "kotlin.Boolean"
    case RuntimeTypeTokenEncoding.longBase:    "kotlin.Long"
    case RuntimeTypeTokenEncoding.doubleBase:  "kotlin.Double"
    case RuntimeTypeTokenEncoding.floatBase:   "kotlin.Float"
    case RuntimeTypeTokenEncoding.charBase:    "kotlin.Char"
    case RuntimeTypeTokenEncoding.nullBase:    "kotlin.Nothing"
    default: nil
    }
    if let qualifiedName {
        let utf8 = Array(qualifiedName.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }
    // For nominal types the nameHint carries the fully-qualified name.
    return kk_type_token_simple_name(typeToken, nameHint)
}

private func runtimeKClassBox(from raw: Int) -> RuntimeKClassBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withLock { state in
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
@_cdecl("kk_kclass_create")
public func kk_kclass_create(_ typeToken: Int, _ nameHint: Int) -> Int {
    let cacheKey = KClassCacheKey(typeToken: typeToken)
    return runtimeStorage.withLock { state in
        if let cached = state.kClassBoxCache[cacheKey] {
            return cached
        }
        let box = RuntimeKClassBox(typeToken: typeToken, nameHint: nameHint)
        let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        state.objectPointers.insert(UInt(bitPattern: opaque))
        let result = Int(bitPattern: opaque)
        state.kClassBoxCache[cacheKey] = result
        return result
    }
}

/// Returns the `simpleName` of a `KClass<T>` metadata object.
/// Delegates to `kk_type_token_simple_name` using the stored token and hint.
@_cdecl("kk_kclass_simple_name")
public func kk_kclass_simple_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return kk_type_token_simple_name(box.typeToken, box.nameHint)
}

/// Returns the `qualifiedName` of a `KClass<T>` metadata object.
/// When binary metadata has been registered via `kk_kclass_register_metadata`,
/// returns the fully-qualified name (e.g. "com.example.Foo"). Otherwise
/// falls back to `kk_type_token_qualified_name` which returns the simple name.
@_cdecl("kk_kclass_qualified_name")
public func kk_kclass_qualified_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    // Try the metadata registry first for proper qualified names.
    if let metadata = box.metadata {
        let utf8 = Array(metadata.qualifiedName.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }
    return kk_type_token_qualified_name(box.typeToken, box.nameHint)
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
@_cdecl("kk_kclass_register_metadata")
public func kk_kclass_register_metadata(
    _ typeToken: Int,
    _ qualifiedNameRaw: Int,
    _ simpleNameRaw: Int,
    _ supertypeNameRaw: Int,
    _ flags: Int,
    _ fieldCount: Int,
    _ memberCount: Int,
    _ constructorCount: Int
) -> Int {
    return kk_kclass_register_metadata_v2(
        typeToken, qualifiedNameRaw, simpleNameRaw, supertypeNameRaw,
        flags, fieldCount, memberCount, constructorCount, 0, 0
    )
}

/// STDLIB-REFLECT-060: Extended metadata registration with visibility and type parameter count.
/// - visibilityRaw: Runtime string pointer for visibility ("PUBLIC", "INTERNAL", etc.), 0 if unknown.
/// - typeParameterCount: Number of type parameters on the class.
/// Flags bit layout: bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///   bit 3=interface, bit 4=object, bit 5=enumClass, bit 6=annotationClass,
///   bit 7=abstract, bit 8=final, bit 9=open.
@_cdecl("kk_kclass_register_metadata_v2")
public func kk_kclass_register_metadata_v2(
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
        typeParameterCount: typeParameterCount
    )
    runtimeKClassMetadataRegistry.register(typeToken: typeToken, entry: entry)
    return 0
}

/// Returns 1 if the KClass represents a data class, 0 otherwise.
@_cdecl("kk_kclass_is_data")
public func kk_kclass_is_data(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isDataClass ? 1 : 0
}

/// Returns 1 if the KClass represents a sealed class, 0 otherwise.
@_cdecl("kk_kclass_is_sealed")
public func kk_kclass_is_sealed(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isSealedClass ? 1 : 0
}

/// Returns 1 if the KClass represents a value (inline) class, 0 otherwise.
@_cdecl("kk_kclass_is_value")
public func kk_kclass_is_value(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isValueClass ? 1 : 0
}

/// Returns 1 if the KClass represents an interface, 0 otherwise.
@_cdecl("kk_kclass_is_interface")
public func kk_kclass_is_interface(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isInterface ? 1 : 0
}

/// Returns 1 if the KClass represents an object declaration, 0 otherwise.
@_cdecl("kk_kclass_is_object")
public func kk_kclass_is_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isObject ? 1 : 0
}

/// Returns 1 if the KClass represents an enum class, 0 otherwise.
@_cdecl("kk_kclass_is_enum")
public func kk_kclass_is_enum(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isEnumClass ? 1 : 0
}

/// Returns 1 if the KClass represents an abstract class, 0 otherwise.
@_cdecl("kk_kclass_is_abstract")
public func kk_kclass_is_abstract(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isAbstract ? 1 : 0
}

// MARK: - STDLIB-REFLECT-060: KClass basic reflection features

/// Returns 1 if the KClass represents a final class, 0 otherwise.
/// A class is final if it is not abstract, not open, and not an interface.
@_cdecl("kk_kclass_is_final")
public func kk_kclass_is_final(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isFinal ? 1 : 0
}

/// Returns 1 if the KClass represents an open class, 0 otherwise.
@_cdecl("kk_kclass_is_open")
public func kk_kclass_is_open(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isOpen ? 1 : 0
}

/// Returns the visibility of this KClass as a runtime string ("PUBLIC", "INTERNAL", "PRIVATE", "PROTECTED").
/// Returns null sentinel if unknown.
@_cdecl("kk_kclass_visibility")
public func kk_kclass_visibility(_ kclassRaw: Int) -> Int {
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
@_cdecl("kk_kclass_type_parameters")
public func kk_kclass_type_parameters(_ kclassRaw: Int) -> Int {
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
@_cdecl("kk_kclass_supertypes")
public func kk_kclass_supertypes(_ kclassRaw: Int) -> Int {
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

/// Returns the supertype name as a runtime string pointer, or null sentinel if none.
@_cdecl("kk_kclass_supertype_name")
public func kk_kclass_supertype_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata,
          let superName = metadata.supertypeName else {
        return runtimeNullSentinelInt
    }
    let utf8 = Array(superName.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Returns the number of declared members, or -1 if unknown.
@_cdecl("kk_kclass_members_count")
public func kk_kclass_members_count(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return -1
    }
    return metadata.memberCount
}

// MARK: - REFL-005: KClass.isInstance, members, constructors

/// Checks if a value is an instance of the type represented by this KClass.
/// Delegates to the existing `kk_op_is` runtime type check using the KClass
/// box's type token.
/// Returns 1 (true) if the value is an instance, 0 (false) otherwise.
@_cdecl("kk_kclass_isInstance")
public func kk_kclass_isInstance(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kk_op_is(valueRaw, box.typeToken)
}

/// Returns the members of this KClass as a runtime list of KCallable boxes.
/// The current implementation returns an empty list; member metadata will be
/// populated by a future metadata emission pass.
@_cdecl("kk_kclass_members")
public func kk_kclass_members(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Return a list with `memberCount` placeholder elements so that .size is correct.
    let count = box.metadata?.memberCount ?? 0
    let placeholders = (0..<max(count, 0)).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the constructors of this KClass as a runtime list of KFunction boxes.
/// The current implementation returns an empty list; constructor metadata will be
/// populated by a future metadata emission pass.
@_cdecl("kk_kclass_constructors")
public func kk_kclass_constructors(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Return a list with `constructorCount` placeholder elements so that .size is correct.
    let count = box.metadata?.constructorCount ?? 0
    let placeholders = (0..<max(count, 0)).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the primary constructor of this KClass as a KConstructor box, or null sentinel if none.
/// STDLIB-REFLECT-064
@_cdecl("kk_kclass_primary_constructor")
public func kk_kclass_primary_constructor(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return runtimeNullSentinelInt
    }
    // The primary constructor metadata is populated via kk_kconstructor_create
    // during the metadata emission pass. If not available, return null.
    return runtimeNullSentinelInt
}

// MARK: - STDLIB-REFLECT-061: KClass member access (properties, functions, etc.)

/// Returns all properties (including inherited) of this KClass as a runtime list.
/// Returns a list of `RuntimeKCallableBox` elements representing each property.
/// The count is derived from metadata when available; otherwise an empty list is returned.
@_cdecl("kk_kclass_properties")
public func kk_kclass_properties(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Use fieldCount for total properties (fields represent properties in the metadata).
    let count = box.metadata?.fieldCount ?? 0
    let placeholders = (0..<max(count, 0)).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the non-extension member properties of this KClass as a runtime list.
/// These are the properties declared directly in the class or its superclasses,
/// excluding extension properties.
@_cdecl("kk_kclass_member_properties")
public func kk_kclass_member_properties(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // fieldCount corresponds to the number of declared data fields / member properties.
    let count = box.metadata?.fieldCount ?? 0
    let placeholders = (0..<max(count, 0)).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the declared member properties of this KClass (own class only, not inherited).
/// These are properties explicitly declared in this class, excluding superclass properties.
@_cdecl("kk_kclass_declared_member_properties")
public func kk_kclass_declared_member_properties(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // fieldCount represents fields declared in the class itself.
    let count = box.metadata?.fieldCount ?? 0
    let placeholders = (0..<max(count, 0)).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns all functions (including inherited) of this KClass as a runtime list.
/// Returns a list of `RuntimeKFunctionBox`-compatible elements representing each function.
@_cdecl("kk_kclass_functions")
public func kk_kclass_functions(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Derive function count as memberCount minus fieldCount (properties are fields).
    let memberCount = box.metadata?.memberCount ?? 0
    let fieldCount = box.metadata?.fieldCount ?? 0
    let count = max(0, memberCount - fieldCount)
    let placeholders = (0..<count).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the non-extension member functions of this KClass as a runtime list.
/// These are functions declared in the class or its superclasses, excluding extensions.
@_cdecl("kk_kclass_member_functions")
public func kk_kclass_member_functions(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Derive function count as memberCount minus fieldCount (approximate).
    let memberCount = box.metadata?.memberCount ?? 0
    let fieldCount = box.metadata?.fieldCount ?? 0
    let functionCount = max(0, memberCount - fieldCount)
    let placeholders = (0..<functionCount).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Returns the declared member functions of this KClass (own class only, not inherited).
/// These are functions explicitly declared in this class, excluding superclass functions.
@_cdecl("kk_kclass_declared_member_functions")
public func kk_kclass_declared_member_functions(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // Derive declared function count as memberCount minus fieldCount (approximate).
    let memberCount = box.metadata?.memberCount ?? 0
    let fieldCount = box.metadata?.fieldCount ?? 0
    let functionCount = max(0, memberCount - fieldCount)
    let placeholders = (0..<functionCount).map { _ in 0 }
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

// MARK: - REFL-005: KType and typeOf<T>()

/// Creates a KType runtime object from a KClass classifier, type argument
/// projections, and nullability flag.
/// Parameters:
/// - classifierRaw: opaque handle to a KClass box (or 0 for no classifier)
/// - argsRaw: opaque handle to a runtime list of KTypeProjection handles (or 0 for empty)
/// - isNullable: 1 if the type is marked nullable, 0 otherwise
@_cdecl("kk_ktype_create")
public func kk_ktype_create(_ classifierRaw: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    var argumentRaws: [Int] = []
    if argsRaw != 0 && argsRaw != runtimeNullSentinelInt,
       let ptr = UnsafeMutableRawPointer(bitPattern: argsRaw) {
        let isObj = runtimeStorage.withLock { state in
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
    return registerRuntimeObject(box)
}

/// Returns the classifier (KClass) raw handle from a KType, or null sentinel.
@_cdecl("kk_ktype_classifier")
public func kk_ktype_classifier(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return runtimeNullSentinelInt
    }
    return box.classifierRaw
}

/// Returns the list of type arguments (KTypeProjection handles) from a KType.
@_cdecl("kk_ktype_arguments")
public func kk_ktype_arguments(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.argumentRaws))
}

/// Returns 1 if the KType is marked nullable, 0 otherwise.
@_cdecl("kk_ktype_isMarkedNullable")
public func kk_ktype_isMarkedNullable(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return 0
    }
    return box.isMarkedNullable ? 1 : 0
}

/// Creates a KTypeProjection from a KType raw handle and variance ordinal.
/// variance: 0=IN, 1=OUT, 2=INVARIANT, -1=STAR (type is ignored for STAR)
@_cdecl("kk_ktypeprojection_create")
public func kk_ktypeprojection_create(_ typeRaw: Int, _ varianceOrdinal: Int) -> Int {
    let variance: RuntimeKVariance?
    if varianceOrdinal == -1 {
        variance = nil // STAR projection
    } else {
        variance = RuntimeKVariance(rawValue: varianceOrdinal) ?? .invariant
    }
    let box = RuntimeKTypeProjectionBox(typeRaw: typeRaw, variance: variance)
    return registerRuntimeObject(box)
}

/// Returns the type raw handle from a KTypeProjection, or null sentinel for STAR.
@_cdecl("kk_ktypeprojection_type")
public func kk_ktypeprojection_type(_ projRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projRaw) else {
        return runtimeNullSentinelInt
    }
    if box.variance == nil {
        return runtimeNullSentinelInt // STAR projection has no type
    }
    return box.typeRaw
}

/// Returns the variance ordinal from a KTypeProjection.
/// 0=IN, 1=OUT, 2=INVARIANT, -1=STAR (null variance).
@_cdecl("kk_ktypeprojection_variance")
public func kk_ktypeprojection_variance(_ projRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projRaw) else {
        return -1
    }
    guard let variance = box.variance else {
        return -1 // STAR
    }
    return variance.rawValue
}

/// Implements `typeOf<T>()` — creates a KType for the given type token.
/// This is the reified inline function entry point. The compiler emits the
/// type token and nullability at the call site.
@_cdecl("kk_typeof")
public func kk_typeof(_ typeToken: Int, _ nameHint: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    // Create the KClass classifier for this type.
    let classifierRaw = kk_kclass_create(typeToken, nameHint)
    return kk_ktype_create(classifierRaw, argsRaw, isNullable)
}

// MARK: - KType / KTypeProjection Box Helpers

private func runtimeKTypeBox(from raw: Int) -> RuntimeKTypeBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKTypeBox.self)
    }
}

private func runtimeKTypeProjectionBox(from raw: Int) -> RuntimeKTypeProjectionBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKTypeProjectionBox.self)
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
    runtimeStorage.withLock { state in
        var methods = state.objectItableMethods[objectKey] ?? [:]
        methods[dispatchKey] = functionRaw
        state.objectItableMethods[objectKey] = methods
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
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    return array.elements[index]
}

@_cdecl("kk_array_get_inbounds")
public func kk_array_get_inbounds(_ arrayRaw: Int, _ index: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          array.elements.indices.contains(index)
    else {
        fatalError("kk_array_get_inbounds precondition failed")
    }
    return array.elements[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard array.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array index \(index) out of bounds for length \(array.elements.count).")
        return 0
    }
    array.elements[index] = value
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

@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    let intValue = if let ptr = obj {
        Int(bitPattern: ptr)
    } else {
        0
    }
    if intValue == runtimeNullSentinelInt {
        Swift.print("null")
        return
    }
    guard let raw = obj else {
        Swift.print(intValue)
        return
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    if !isObjectPointer {
        Swift.print(intValue)
        return
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        Swift.print(boolBox.value ? "true" : "false")
        return
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        Swift.print(intBox.value)
        return
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        Swift.print(stringBox.value)
        return
    }
    if let doubleBox = tryCast(raw, to: RuntimeDoubleBox.self) {
        Swift.print(runtimeFormatFloatingPoint(doubleBox.value))
        return
    }
    if let floatBox = tryCast(raw, to: RuntimeFloatBox.self) {
        Swift.print(runtimeFormatFloatingPoint(floatBox.value))
        return
    }
    if let longBox = tryCast(raw, to: RuntimeLongBox.self) {
        Swift.print(longBox.value)
        return
    }
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.renderedMessage))")
        return
    }
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        if let scalar = UnicodeScalar(charBox.value) {
            Swift.print(Character(scalar))
        } else {
            Swift.print("�")
        }
        return
    }
    if let listBox = tryCast(raw, to: RuntimeListBox.self) {
        let rendered = listBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        let rendered = setBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        Swift.print("{\(rendered)}")
        return
    }
    if tryCast(raw, to: RuntimeRangeBox.self) != nil {
        Swift.print(runtimeElementToString(intValue))
        return
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.first)
        let second = runtimeRenderAnyForPrint(pairBox.second)
        if runtimeIsMapEntry(rawValue: intValue) {
            Swift.print("\(first)=\(second)")
        } else {
            Swift.print("(\(first), \(second))")
        }
        return
    }
    if let tripleBox = tryCast(raw, to: RuntimeTripleBox.self) {
        let first = runtimeRenderAnyForPrint(tripleBox.first)
        let second = runtimeRenderAnyForPrint(tripleBox.second)
        let third = runtimeRenderAnyForPrint(tripleBox.third)
        Swift.print("(\(first), \(second), \(third))")
        return
    }
    if tryCast(raw, to: RuntimeIndexingIterableBox.self) != nil {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        Swift.print("kotlin.collections.IndexingIterable@\(hex)")
        return
    }
    if let iterableBox = tryCast(raw, to: RuntimeStringIterableBox.self) {
        Swift.print(runtimeRenderStringIterableForPrint(iterableBox.strRaw))
        return
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        let rendered = arrayBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", ")
        Swift.print("[\(rendered)]")
        return
    }
    if let sbBox = tryCast(raw, to: RuntimeStringBuilderBox.self) {
        Swift.print(sbBox.value)
        return
    }
    // STDLIB-REFLECT-066: KType toString
    if let ktypeBox = tryCast(raw, to: RuntimeKTypeBox.self) {
        let str = runtimeKTypeToString(ktypeBox)
        Swift.print(str)
        return
    }
    Swift.print("<object \(raw)>")
}

/// Runtime support for kotlin.io.print(message) (no newline).
@_cdecl("kk_print_any")
public func kk_print_any(_ obj: UnsafeMutableRawPointer?) {
    let intValue = if let ptr = obj { Int(bitPattern: ptr) } else { 0 }
    Swift.print(runtimeRenderAnyForPrint(intValue), terminator: "")
}

/// Runtime support for kotlin.io.print() with no arguments (STDLIB-572).
/// Prints nothing (no output, no newline).
@_cdecl("kk_print_noarg")
public func kk_print_noarg() {
    // Intentionally empty — Kotlin's print() with no args is a no-op.
}

/// Runtime support for kotlin.io.println() (STDLIB-063).
/// Prints a newline with no arguments.
@_cdecl("kk_println_newline")
public func kk_println_newline() {
    Swift.print()
}

/// Runtime support for kotlin.io.readLine() (STDLIB-063).
/// Reads a line from stdin. Returns null (runtimeNullSentinelInt) on EOF.
@_cdecl("kk_readline")
public func kk_readline() -> Int {
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

/// Runtime support for kotlin.io.readln() (STDLIB-130).
@_cdecl("kk_readln")
public func kk_readln(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let line = readLine() else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "EOF has already been reached")
        return 0
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

/// Runtime support for kotlin.io.readlnOrNull() (STDLIB-571).
/// Reads a line from stdin. Returns null (runtimeNullSentinelInt) on EOF
/// instead of throwing.
@_cdecl("kk_readlnOrNull")
public func kk_readlnOrNull() -> Int {
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
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    guard isObjectPointer else {
        return String(value)
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        return String(intBox.value)
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
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        if let scalar = UnicodeScalar(charBox.value) {
            return String(Character(scalar))
        }
        return "�"
    }
    if let throwable = tryCast(raw, to: RuntimeThrowableBox.self) {
        return "Throwable(\(throwable.renderedMessage))"
    }
    if let listBox = tryCast(raw, to: RuntimeListBox.self) {
        return "[\(listBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        return "[\(setBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        return "{\(rendered)}"
    }
    if tryCast(raw, to: RuntimeRangeBox.self) != nil {
        return runtimeElementToString(value)
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.first)
        let second = runtimeRenderAnyForPrint(pairBox.second)
        if runtimeIsMapEntry(rawValue: value) {
            return "\(first)=\(second)"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(raw, to: RuntimeTripleBox.self) {
        let first = runtimeRenderAnyForPrint(tripleBox.first)
        let second = runtimeRenderAnyForPrint(tripleBox.second)
        let third = runtimeRenderAnyForPrint(tripleBox.third)
        return "(\(first), \(second), \(third))"
    }
    if tryCast(raw, to: RuntimeIndexingIterableBox.self) != nil {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        return "kotlin.collections.IndexingIterable@\(hex)"
    }
    if let iterableBox = tryCast(raw, to: RuntimeStringIterableBox.self) {
        return runtimeRenderStringIterableForPrint(iterableBox.strRaw)
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        return "[\(arrayBox.elements.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let sbBox = tryCast(raw, to: RuntimeStringBuilderBox.self) {
        return sbBox.value
    }
    // STDLIB-REFLECT-066: KType rendering
    if let ktypeBox = tryCast(raw, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    return "<object \(raw)>"
}

private func runtimeRenderStringIterableForPrint(_ strRaw: Int) -> String {
    guard let raw = UnsafeMutableRawPointer(bitPattern: strRaw),
          let string = extractString(from: raw)
    else {
        return "<invalid String iterable>"
    }
    let rendered = string.unicodeScalars.map { String(Character($0)) }.joined(separator: ", ")
    return "[\(rendered)]"
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

private func runtimeFormatFloatingPointCore(
    _ value: Double
) -> String {
    if value.isNaN {
        return "NaN"
    }
    if value == .infinity {
        return "Infinity"
    }
    if value == -.infinity {
        return "-Infinity"
    }
    let rendered = String(describing: value)
    if rendered.contains("e") || rendered.contains("E") {
        return runtimeNormalizeScientificExponent(rendered)
    }
    let magnitude = abs(value)
    if magnitude != 0, magnitude >= 1e7 || magnitude < 1e-3 {
        return runtimeScientificString(fromFixed: rendered)
    }
    return rendered
}

func runtimeFormatFloatingPoint(_ value: Double) -> String {
    runtimeFormatFloatingPointCore(value)
}

func runtimeFormatFloatingPoint(_ value: Float) -> String {
    if value.isNaN {
        return "NaN"
    }
    if value == .infinity {
        return "Infinity"
    }
    if value == -.infinity {
        return "-Infinity"
    }
    let rendered = String(describing: value)
    if rendered.contains("e") || rendered.contains("E") {
        return runtimeNormalizeScientificExponent(rendered)
    }
    return rendered
}

// MARK: - String nullable receiver helpers

@_cdecl("kk_string_isNullOrEmpty")
public func kk_string_isNullOrEmpty(_ strRaw: Int) -> Int {
    guard let rawPointer = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return kk_box_bool(1)
    }
    guard let str = extractString(from: rawPointer) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(str.isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNullOrBlank")
public func kk_string_isNullOrBlank(_ strRaw: Int) -> Int {
    guard let rawPointer = UnsafeMutableRawPointer(bitPattern: strRaw) else {
        return kk_box_bool(1)
    }
    guard let str = extractString(from: rawPointer) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(str.allSatisfy(\.isWhitespace) ? 1 : 0)
}

// MARK: - STDLIB-534: String?.orEmpty()

@_cdecl("kk_string_orEmpty")
public func kk_string_orEmpty(_ strRaw: Int) -> Int {
    if strRaw == runtimeNullSentinelInt || strRaw == 0 {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return strRaw
}
