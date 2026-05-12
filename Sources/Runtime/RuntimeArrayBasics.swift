import Foundation

/// Array / Pair / Triple runtime functions (STDLIB-001 + STDLIB-120/121)
/// plus primitive-array conversions (STDLIB-087, STDLIB-LIST-PRIM-ARRAY).
///
/// Split out from `RuntimeCollections.swift`.

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

@_cdecl("kk_array_size")
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
        // kk_array_size returning 0.  Avoids crashing on invalid input per
        // the project's "never crash on invalid input" design principle.
        return kk_box_bool(1)
    }
    return kk_box_bool(array.elements.isEmpty ? 1 : 0)
}

// MARK: - Pair Functions (FUNC-002)

@_cdecl("kk_pair_new")
public func kk_pair_new(_ first: Int, _ second: Int) -> Int {
    registerRuntimeObject(RuntimePairBox(first: first, second: second))
}

@_cdecl("kk_pair_first")
public func kk_pair_first(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_first")
    }
    return pairBox.first
}

@_cdecl("component1")
public func component1(_ pairRaw: Int) -> Int {
    kk_pair_first(pairRaw)
}

@_cdecl("kk_pair_second")
public func kk_pair_second(_ pairRaw: Int) -> Int {
    if pairRaw == runtimeNullSentinelInt {
        return runtimeNullSentinelInt
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_second")
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
    return kk_pair_new(pairBox.first, pairBox.second)
}

@_cdecl("kk_pair_to_string")
public func kk_pair_to_string(_ pairRaw: Int) -> UnsafeMutableRawPointer {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_to_string")
    }
    let firstStr = runtimeElementToString(pairBox.first)
    let secondStr = runtimeElementToString(pairBox.second)
    let str = "(\(firstStr), \(secondStr))"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Triple Functions (STDLIB-120)

@_cdecl("kk_triple_new")
public func kk_triple_new(_ first: Int, _ second: Int, _ third: Int) -> Int {
    let box = RuntimeTripleBox(first: first, second: second, third: third)
    return registerRuntimeObject(box)
}

@_cdecl("kk_triple_first")
public func kk_triple_first(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_first")
    }
    return tripleBox.first
}

@_cdecl("kk_triple_second")
public func kk_triple_second(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_second")
    }
    return tripleBox.second
}

@_cdecl("kk_triple_third")
public func kk_triple_third(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_third")
    }
    return tripleBox.third
}

@_cdecl("kk_triple_to_string")
public func kk_triple_to_string(_ tripleRaw: Int) -> UnsafeMutableRawPointer {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_to_string")
    }
    let firstStr = runtimeElementToString(tripleBox.first)
    let secondStr = runtimeElementToString(tripleBox.second)
    let thirdStr = runtimeElementToString(tripleBox.third)
    let str = "(\(firstStr), \(secondStr), \(thirdStr))"
    let utf8 = Array(str.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

// MARK: - Pair/Triple toList (STDLIB-121)

@_cdecl("kk_pair_toList")
public func kk_pair_toList(_ pairRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in kk_pair_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: [pairBox.first, pairBox.second]))
}

@_cdecl("kk_triple_toList")
public func kk_triple_toList(_ tripleRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: tripleRaw),
          let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Triple handle in kk_triple_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: [tripleBox.first, tripleBox.second, tripleBox.third]))
}

// MARK: - Array conversion functions (STDLIB-087)

@_cdecl("kk_array_toList")
public func kk_array_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

@_cdecl("kk_array_toMutableList")
public func kk_array_toMutableList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_toMutableList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

@_cdecl("kk_list_toTypedArray")
public func kk_list_toTypedArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toTypedArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = elem
    }
    return registerRuntimeObject(box)
}

// MARK: - List to primitive array conversions (STDLIB-LIST-PRIM-ARRAY)

/// Collection<Boolean>.toBooleanArray(): BooleanArray
@_cdecl("kk_list_toBooleanArray")
public func kk_list_toBooleanArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toBooleanArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_bool(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Short>.toShortArray(): ShortArray
@_cdecl("kk_list_toShortArray")
public func kk_list_toShortArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toShortArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Double>.toDoubleArray(): DoubleArray
@_cdecl("kk_list_toDoubleArray")
public func kk_list_toDoubleArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toDoubleArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_double(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Float>.toFloatArray(): FloatArray
@_cdecl("kk_list_toFloatArray")
public func kk_list_toFloatArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toFloatArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_float(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Int>.toIntArray(): IntArray
@_cdecl("kk_list_toIntArray")
public func kk_list_toIntArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toIntArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Long>.toLongArray(): LongArray
@_cdecl("kk_list_toLongArray")
public func kk_list_toLongArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toLongArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_long(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<Byte>.toByteArray(): ByteArray
@_cdecl("kk_list_toByteArray")
public func kk_list_toByteArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toByteArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        // Byte values are stored as Int8-range integers (unboxed or raw);
        // preserve the sign-extended bit pattern as Kotlin Byte semantics require.
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UByte>.toUByteArray(): UByteArray
@_cdecl("kk_list_toUByteArray")
public func kk_list_toUByteArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUByteArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UShort>.toUShortArray(): UShortArray
@_cdecl("kk_list_toUShortArray")
public func kk_list_toUShortArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUShortArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<UInt>.toUIntArray(): UIntArray
@_cdecl("kk_list_toUIntArray")
public func kk_list_toUIntArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toUIntArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_int(elem)
    }
    return registerRuntimeObject(box)
}

/// Collection<ULong>.toULongArray(): ULongArray
@_cdecl("kk_list_toULongArray")
public func kk_list_toULongArray(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid list handle in kk_list_toULongArray")
    }
    let box = RuntimeArrayBox(length: list.elements.count)
    for (i, elem) in list.elements.enumerated() {
        box.elements[i] = kk_unbox_long(elem)
    }
    return registerRuntimeObject(box)
}

// MARK: - Primitive array to List conversions

/// IntArray.toList(): List<Int>
@_cdecl("kk_intArray_toList")
public func kk_intArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_intArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// LongArray.toList(): List<Long>
@_cdecl("kk_longArray_toList")
public func kk_longArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_longArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ByteArray.toList(): List<Byte>
@_cdecl("kk_byteArray_toList")
public func kk_byteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ShortArray.toList(): List<Short>
@_cdecl("kk_shortArray_toList")
public func kk_shortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_shortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UIntArray.toList(): List<UInt>
@_cdecl("kk_uIntArray_toList")
public func kk_uIntArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ULongArray.toList(): List<ULong>
@_cdecl("kk_uLongArray_toList")
public func kk_uLongArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// DoubleArray.toList(): List<Double>
@_cdecl("kk_doubleArray_toList")
public func kk_doubleArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_doubleArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// FloatArray.toList(): List<Float>
@_cdecl("kk_floatArray_toList")
public func kk_floatArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_floatArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// BooleanArray.toList(): List<Boolean>
@_cdecl("kk_booleanArray_toList")
public func kk_booleanArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_booleanArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// CharArray.toList(): List<Char>
@_cdecl("kk_charArray_toList")
public func kk_charArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_charArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UByteArray.toList(): List<UByte>
@_cdecl("kk_uByteArray_toList")
public func kk_uByteArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// UShortArray.toList(): List<UShort>
@_cdecl("kk_uShortArray_toList")
public func kk_uShortArray_toList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_toList")
    }
    return registerRuntimeObject(RuntimeListBox(elements: Array(array.elements)))
}

/// ByteArray.asUByteArray(): UByteArray view
@_cdecl("kk_byteArray_asUByteArray")
public func kk_byteArray_asUByteArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_asUByteArray")
    }
    return arrayRaw
}

/// ShortArray.asUShortArray(): UShortArray view
@_cdecl("kk_shortArray_asUShortArray")
public func kk_shortArray_asUShortArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_shortArray_asUShortArray")
    }
    return arrayRaw
}

/// IntArray.asUIntArray(): UIntArray view
@_cdecl("kk_intArray_asUIntArray")
public func kk_intArray_asUIntArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_intArray_asUIntArray")
    }
    return arrayRaw
}

/// LongArray.asULongArray(): ULongArray view
@_cdecl("kk_longArray_asULongArray")
public func kk_longArray_asULongArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_longArray_asULongArray")
    }
    return arrayRaw
}

/// UByteArray.asList(): List<UByte>
@_cdecl("kk_uByteArray_asList")
public func kk_uByteArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// UShortArray.asList(): List<UShort>
@_cdecl("kk_uShortArray_asList")
public func kk_uShortArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// UIntArray.asList(): List<UInt>
@_cdecl("kk_uIntArray_asList")
public func kk_uIntArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

/// ULongArray.asList(): List<ULong>
@_cdecl("kk_uLongArray_asList")
public func kk_uLongArray_asList(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_asList")
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
}

// MARK: - Unsigned primitive array to signed primitive array views
//
// Kotlin `asByteArray` / `asShortArray` (and the other width-matched pairs below) are
// *views* on the same storage: the signed and unsigned array types re-use the same
// underlying runtime array; mutations are shared and bit patterns are not reencoded.

/// UByteArray.asByteArray(): ByteArray
@_cdecl("kk_uByteArray_asByteArray")
public func kk_uByteArray_asByteArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_asByteArray")
    }
    return arrayRaw
}

/// UShortArray.asShortArray(): ShortArray
@_cdecl("kk_uShortArray_asShortArray")
public func kk_uShortArray_asShortArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uShortArray_asShortArray")
    }
    return arrayRaw
}

/// UIntArray.asIntArray(): IntArray view
@_cdecl("kk_uIntArray_asIntArray")
public func kk_uIntArray_asIntArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_asIntArray")
    }
    return arrayRaw
}

/// ULongArray.asLongArray(): LongArray view
@_cdecl("kk_uLongArray_asLongArray")
public func kk_uLongArray_asLongArray(_ arrayRaw: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_asLongArray")
    }
    return arrayRaw
}

// MARK: - Primitive array size property

/// IntArray.size: Int
@_cdecl("kk_intArray_size")
public func kk_intArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// LongArray.size: Int
@_cdecl("kk_longArray_size")
public func kk_longArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ByteArray.size: Int
@_cdecl("kk_byteArray_size")
public func kk_byteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ShortArray.size: Int
@_cdecl("kk_shortArray_size")
public func kk_shortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UIntArray.size: Int
@_cdecl("kk_uIntArray_size")
public func kk_uIntArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// ULongArray.size: Int
@_cdecl("kk_uLongArray_size")
public func kk_uLongArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// DoubleArray.size: Int
@_cdecl("kk_doubleArray_size")
public func kk_doubleArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// FloatArray.size: Int
@_cdecl("kk_floatArray_size")
public func kk_floatArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// BooleanArray.size: Int
@_cdecl("kk_booleanArray_size")
public func kk_booleanArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// CharArray.size: Int
@_cdecl("kk_charArray_size")
public func kk_charArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UByteArray.size: Int
@_cdecl("kk_uByteArray_size")
public func kk_uByteArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

/// UShortArray.size: Int
@_cdecl("kk_uShortArray_size")
public func kk_uShortArray_size(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    return array.elements.count
}

// MARK: - Array binarySearch overloads (TYPE-103)

@inline(__always)
private func runtimeArrayBinarySearch(
    _ arrayRaw: Int,
    element: Int,
    fromIndex: Int,
    toIndex: Int,
    compare: (Int, Int) -> Int,
    functionName: String
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    return runtimeBinarySearch(
        elements: array.elements,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: compare
    )
}

@_cdecl("kk_array_binarySearch")
public func kk_array_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: runtimeCompareValues,
        functionName: "kk_array_binarySearch"
    )
}

@_cdecl("kk_intArray_binarySearch")
public func kk_intArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_intArray_binarySearch"
    )
}

@_cdecl("kk_longArray_binarySearch")
public func kk_longArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .long) },
        functionName: "kk_longArray_binarySearch"
    )
}

@_cdecl("kk_byteArray_binarySearch")
public func kk_byteArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_byteArray_binarySearch"
    )
}

@_cdecl("kk_shortArray_binarySearch")
public func kk_shortArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .int) },
        functionName: "kk_shortArray_binarySearch"
    )
}

@_cdecl("kk_uIntArray_binarySearch")
public func kk_uIntArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uIntArray_binarySearch"
    )
}

@_cdecl("kk_uLongArray_binarySearch")
public func kk_uLongArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .ulong) },
        functionName: "kk_uLongArray_binarySearch"
    )
}

@_cdecl("kk_doubleArray_binarySearch")
public func kk_doubleArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .double) },
        functionName: "kk_doubleArray_binarySearch"
    )
}

@_cdecl("kk_floatArray_binarySearch")
public func kk_floatArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .float) },
        functionName: "kk_floatArray_binarySearch"
    )
}

@_cdecl("kk_booleanArray_binarySearch")
public func kk_booleanArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .boolean) },
        functionName: "kk_booleanArray_binarySearch"
    )
}

@_cdecl("kk_charArray_binarySearch")
public func kk_charArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .char) },
        functionName: "kk_charArray_binarySearch"
    )
}

@_cdecl("kk_uByteArray_binarySearch")
public func kk_uByteArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uByteArray_binarySearch"
    )
}

@_cdecl("kk_uShortArray_binarySearch")
public func kk_uShortArray_binarySearch(_ arrayRaw: Int, _ element: Int, _ fromIndex: Int, _ toIndex: Int) -> Int {
    runtimeArrayBinarySearch(
        arrayRaw,
        element: element,
        fromIndex: fromIndex,
        toIndex: toIndex,
        compare: { lhs, rhs in runtimeComparePrimitiveValues(lhs, rhs, kind: .uint) },
        functionName: "kk_uShortArray_binarySearch"
    )
}

