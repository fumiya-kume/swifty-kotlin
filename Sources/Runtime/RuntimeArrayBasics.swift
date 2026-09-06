
// Array / Pair / Triple runtime functions (STDLIB-001 + STDLIB-120/121)
// plus primitive-array conversions (STDLIB-087, STDLIB-LIST-PRIM-ARRAY).
//
// Split out from `RuntimeCollections.swift`.

// MARK: - Array Functions (STDLIB-001)

/// Creates a new array from existing elements (identity/tagging operation).
/// The array is already allocated by `kk_array_new`; this function simply
/// returns the handle so that the Swift runtime handles it consistently
/// instead of falling through to the C preamble stub.
/// - Parameters:
///   - arrayRaw: Opaque handle to a `RuntimeArrayBox` containing the elements.
///   - count: Number of elements in the array.
/// - Returns: Opaque handle (Int) to the array (passed through).
@_cdecl("kk_array_of")
public func kk_array_of(_ arrayRaw: Int, _: Int) -> Int {
    arrayRaw
}

@_cdecl("kk_empty_array")
public func kk_empty_array() -> Int {
    return kk_array_new(0)
}

@_cdecl("kk_array_of_nulls")
public func kk_array_of_nulls(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    box.elements = Array(repeating: runtimeNullSentinelInt, count: max(0, length))
    return registerRuntimeObject(box)
}

@_cdecl("__kk_array_size")
public func kk_array_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

@_cdecl("kk_array_is_empty")
public func kk_array_is_empty(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        // Gracefully return true (empty) for invalid handles, consistent with
        // __kk_array_size returning 0.  Avoids crashing on invalid input per
        // the project's "never crash on invalid input" design principle.
        return kk_box_bool(1)
    }
    return kk_box_bool(array.elements.isEmpty ? 1 : 0)
}

// MARK: - Pair Functions (FUNC-002)

/// Nominal type IDs of `kotlin.Pair`/`kotlin.Triple`, tagged onto every box
/// these constructors hand back to Kotlin.
///
/// Both classes are declared in bundled Kotlin source (`kotlin/Tuples.kt`) but
/// allocate through these bridges rather than `kk_object_new`, so without an
/// explicit tag their instances carry no nominal identity and `is Pair<*, *>`
/// answers false — which in turn breaks `Pair.equals`, whose first act is to
/// safe-cast `other`. This mirrors how `kotlin.String` recovers its identity
/// (`runtimeStringNominalTypeID`).
///
/// Only the constructors tag: `RuntimePairBox` doubles as an untyped 2-tuple
/// for internal runtime state (e.g. a Comparator's function/closure pair in
/// RuntimeComparator.swift), and those must stay invisible to `is`.
let runtimePairNominalTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Pair")
let runtimeTripleNominalTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Triple")

@_cdecl("__kk_pair_new")
public func kk_pair_new(_ first: Int, _ second: Int) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(first: first, second: second))
    runtimeRegisterObjectType(rawValue: raw, classID: runtimePairNominalTypeID)
    return raw
}

func runtimePairNew(firstValue: RuntimeValue, secondValue: RuntimeValue) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(firstValue: firstValue, secondValue: secondValue))
    runtimeRegisterObjectType(rawValue: raw, classID: runtimePairNominalTypeID)
    return raw
}

@_cdecl("__kk_pair_first")
public func kk_pair_first(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in __kk_pair_first")
    }
    if pairBox.mutableMapRaw != 0 {
        return pairBox.mutableMapKey
    }
    return pairBox.first
}

@_cdecl("component1")
public func component1(_ pairRaw: Int) -> Int {
    kk_pair_first(pairRaw)
}

@_cdecl("__kk_pair_second")
public func kk_pair_second(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in __kk_pair_second")
    }
    if pairBox.mutableMapRaw != 0 {
        return kk_map_get(pairBox.mutableMapRaw, pairBox.mutableMapKey)
    }
    return pairBox.second
}

@_cdecl("component2")
public func component2(_ pairRaw: Int) -> Int {
    kk_pair_second(pairRaw)
}

@_cdecl("kk_map_entry_to_pair")
public func kk_map_entry_to_pair(_ entryRaw: Int) -> Int {
    if entryRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: entryRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Map.Entry handle in kk_map_entry_to_pair")
    }
    return runtimePairNew(firstValue: pairBox.firstValue, secondValue: pairBox.secondValue)
}

// MARK: - Triple Functions (STDLIB-120)

@_cdecl("__kk_triple_new")
public func kk_triple_new(_ first: Int, _ second: Int, _ third: Int) -> Int {
    let box = RuntimeTripleBox(first: first, second: second, third: third)
    let raw = registerRuntimeObject(box)
    runtimeRegisterObjectType(rawValue: raw, classID: runtimeTripleNominalTypeID)
    return raw
}

@_cdecl("__kk_triple_first")
public func kk_triple_first(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in __kk_triple_first")
    }
    return tripleBox.first
}

@_cdecl("__kk_triple_second")
public func kk_triple_second(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in __kk_triple_second")
    }
    return tripleBox.second
}

@_cdecl("__kk_triple_third")
public func kk_triple_third(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in __kk_triple_third")
    }
    return tripleBox.third
}

// MARK: - Array conversion functions (STDLIB-087)

@_cdecl("__kk_array_toList")
public func kk_array_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_array_toList")
    }
    return registerRuntimeObject(RuntimeListBox(values: Array(array.values)))
}

@_cdecl("kk_array_toMutableList")
public func kk_array_toMutableList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_toMutableList")
    }
    return registerRuntimeObject(RuntimeListBox(values: Array(array.values)))
}

// MARK: - Primitive array to List conversions

/// IntArray.toList(): List<Int>
@_cdecl("__kk_intArray_toList")
public func kk_intArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_intArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// LongArray.toList(): List<Long>
///
/// Boxes elements eagerly for the same reason as __kk_uLongArray_toList below:
/// a raw Long word equal to Long.MIN_VALUE is bit-identical to
/// runtimeNullSentinelInt, so generic Any-dispatch (toString/equals/`is`)
/// would otherwise misreport it as null. kk_box_long_nonnull is safe because
/// LongArray elements are never null.
@_cdecl("__kk_longArray_toList")
public func kk_longArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_longArray_toList")
    }
    let boxed = array.elements.map { kk_box_long_nonnull($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// ByteArray.toList(): List<Byte>
@_cdecl("__kk_byteArray_toList")
public func kk_byteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_byteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ShortArray.toList(): List<Short>
@_cdecl("__kk_shortArray_toList")
public func kk_shortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_shortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UIntArray.toList(): List<UInt>
@_cdecl("__kk_uIntArray_toList")
public func kk_uIntArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_uIntArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ULongArray.toList(): List<ULong>
///
/// Unlike the other `*Array.toList()` conversions above, elements must be
/// boxed eagerly here rather than copied raw: a raw ULong word with the high
/// bit set is bit-identical to a negative Long, and generic Any-dispatch
/// (toString/equals/`is`) has no per-element static type to disambiguate it
/// with, unlike a direct typed `list[i]` access. kk_box_ulong_nonnull is safe
/// because ULongArray elements are never null.
@_cdecl("__kk_uLongArray_toList")
public func kk_uLongArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_uLongArray_toList")
    }
    let boxed = array.elements.map { kk_box_ulong_nonnull($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// DoubleArray.toList(): List<Double>
///
/// Boxes elements eagerly for the same reason as __kk_longArray_toList above:
/// a raw Double word holding -0.0 is bit-identical to runtimeNullSentinelInt,
/// so generic Any-dispatch (toString/equals/`is`) would otherwise misreport it
/// as null. kk_box_double_nonnull is safe because DoubleArray elements are
/// never null.
@_cdecl("__kk_doubleArray_toList")
public func kk_doubleArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_doubleArray_toList")
    }
    let boxed = array.elements.map { kk_box_double_nonnull($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// FloatArray.toList(): List<Float>
@_cdecl("__kk_floatArray_toList")
public func kk_floatArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_floatArray_toList")
    }
    let boxed = array.elements.map { kk_box_float($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// BooleanArray.toList(): List<Boolean>
@_cdecl("__kk_booleanArray_toList")
public func kk_booleanArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_booleanArray_toList")
    }
    let boxed = array.elements.map { kk_box_bool($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// CharArray.toList(): List<Char>
@_cdecl("__kk_charArray_toList")
public func kk_charArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_charArray_toList")
    }
    let boxed = array.elements.map { kk_box_char($0) }
    return registerRuntimeObject(RuntimeListBox(elements: boxed))
}

/// UByteArray.toList(): List<UByte>
@_cdecl("__kk_uByteArray_toList")
public func kk_uByteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_uByteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UShortArray.toList(): List<UShort>
@_cdecl("__kk_uShortArray_toList")
public func kk_uShortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_uShortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ByteArray.asUByteArray(): UByteArray view
@_cdecl("__kk_byteArray_asUByteArray")
public func kk_byteArray_asUByteArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_asUByteArray")
    }
    return arrayRaw
}

/// ShortArray.asUShortArray(): UShortArray view
@_cdecl("__kk_shortArray_asUShortArray")
public func kk_shortArray_asUShortArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_shortArray_asUShortArray")
    }
    return arrayRaw
}

/// IntArray.asUIntArray(): UIntArray view
@_cdecl("__kk_intArray_asUIntArray")
public func kk_intArray_asUIntArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_intArray_asUIntArray")
    }
    return arrayRaw
}

/// LongArray.asULongArray(): ULongArray view
@_cdecl("__kk_longArray_asULongArray")
public func kk_longArray_asULongArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_longArray_asULongArray")
    }
    return arrayRaw
}

@inline(__always)
private func kk_uarray_asList(_ arrayRaw: Int, functionName: String) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

@inline(__always)
private func kk_array_asList(_ arrayRaw: Int, functionName: String) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// Array.asList(): List<T>
@_cdecl("__kk_array_asList")
public func kk_array_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_array_asList")
}

/// IntArray.asList(): List<Int>
@_cdecl("__kk_intArray_asList")
public func kk_intArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_intArray_asList")
}

/// LongArray.asList(): List<Long>
@_cdecl("__kk_longArray_asList")
public func kk_longArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_longArray_asList")
}

/// ShortArray.asList(): List<Short>
@_cdecl("__kk_shortArray_asList")
public func kk_shortArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_shortArray_asList")
}

/// ByteArray.asList(): List<Byte>
@_cdecl("__kk_byteArray_asList")
public func kk_byteArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_byteArray_asList")
}

/// CharArray.asList(): List<Char>
@_cdecl("__kk_charArray_asList")
public func kk_charArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_charArray_asList")
}

/// BooleanArray.asList(): List<Boolean>
@_cdecl("__kk_booleanArray_asList")
public func kk_booleanArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_booleanArray_asList")
}

/// DoubleArray.asList(): List<Double>
@_cdecl("__kk_doubleArray_asList")
public func kk_doubleArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_doubleArray_asList")
}

/// FloatArray.asList(): List<Float>
@_cdecl("__kk_floatArray_asList")
public func kk_floatArray_asList(_ arrayRaw: Int) -> Int {
    kk_array_asList(arrayRaw, functionName: "__kk_floatArray_asList")
}

/// UByteArray.asList(): List<UByte>
@_cdecl("__kk_uByteArray_asList")
public func kk_uByteArray_asList(_ arrayRaw: Int) -> Int {
    kk_uarray_asList(arrayRaw, functionName: "__kk_uByteArray_asList")
}

/// UShortArray.asList(): List<UShort>
@_cdecl("__kk_uShortArray_asList")
public func kk_uShortArray_asList(_ arrayRaw: Int) -> Int {
    kk_uarray_asList(arrayRaw, functionName: "__kk_uShortArray_asList")
}

/// UIntArray.asList(): List<UInt>
@_cdecl("__kk_uIntArray_asList")
public func kk_uIntArray_asList(_ arrayRaw: Int) -> Int {
    kk_uarray_asList(arrayRaw, functionName: "__kk_uIntArray_asList")
}

/// ULongArray.asList(): List<ULong>
@_cdecl("__kk_uLongArray_asList")
public func kk_uLongArray_asList(_ arrayRaw: Int) -> Int {
    kk_uarray_asList(arrayRaw, functionName: "__kk_uLongArray_asList")
}

// MARK: - Unsigned primitive array to signed primitive array views
//
// Kotlin `asByteArray` / `asShortArray` (and the other width-matched pairs below) are
// *views* on the same storage: the signed and unsigned array types re-use the same
// underlying runtime array; mutations are shared and bit patterns are not reencoded.

@inline(__always)
private func kk_unsignedArray_asSignedArrayView(_ arrayRaw: Int, functionName: String) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    return arrayRaw
}

/// UByteArray.asByteArray(): ByteArray
@_cdecl("__kk_uByteArray_asByteArray")
public func kk_uByteArray_asByteArray(_ arrayRaw: Int) -> Int {
    kk_unsignedArray_asSignedArrayView(arrayRaw, functionName: "kk_uByteArray_asByteArray")
}

/// UShortArray.asShortArray(): ShortArray
@_cdecl("__kk_uShortArray_asShortArray")
public func kk_uShortArray_asShortArray(_ arrayRaw: Int) -> Int {
    kk_unsignedArray_asSignedArrayView(arrayRaw, functionName: "kk_uShortArray_asShortArray")
}

/// UIntArray.asIntArray(): IntArray view
@_cdecl("__kk_uIntArray_asIntArray")
public func kk_uIntArray_asIntArray(_ arrayRaw: Int) -> Int {
    kk_unsignedArray_asSignedArrayView(arrayRaw, functionName: "kk_uIntArray_asIntArray")
}

/// ULongArray.asLongArray(): LongArray view
@_cdecl("__kk_uLongArray_asLongArray")
public func kk_uLongArray_asLongArray(_ arrayRaw: Int) -> Int {
    kk_unsignedArray_asSignedArrayView(arrayRaw, functionName: "kk_uLongArray_asLongArray")
}

// MARK: - Primitive array size property

/// IntArray.size: Int
@_cdecl("__kk_intArray_size")
public func kk_intArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// LongArray.size: Int
@_cdecl("__kk_longArray_size")
public func kk_longArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ByteArray.size: Int
@_cdecl("__kk_byteArray_size")
public func kk_byteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ShortArray.size: Int
@_cdecl("__kk_shortArray_size")
public func kk_shortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UIntArray.size: Int
@_cdecl("__kk_uIntArray_size")
public func kk_uIntArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ULongArray.size: Int
@_cdecl("__kk_uLongArray_size")
public func kk_uLongArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// DoubleArray.size: Int
@_cdecl("__kk_doubleArray_size")
public func kk_doubleArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// FloatArray.size: Int
@_cdecl("__kk_floatArray_size")
public func kk_floatArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// BooleanArray.size: Int
@_cdecl("__kk_booleanArray_size")
public func kk_booleanArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// CharArray.size: Int
@_cdecl("__kk_charArray_size")
public func kk_charArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UByteArray.size: Int
@_cdecl("__kk_uByteArray_size")
public func kk_uByteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UShortArray.size: Int
@_cdecl("__kk_uShortArray_size")
public func kk_uShortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}
