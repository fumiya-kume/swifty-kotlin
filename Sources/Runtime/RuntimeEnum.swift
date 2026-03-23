import Foundation

// Runtime support for enum valueOf (STDLIB-173) and enum name/ordinal helpers.
// kk_string_equals and kk_enum_valueOf_throw are used by synthesized valueOf(String).

@_cdecl("kk_string_equals")
public func kk_string_equals(_ aRaw: Int, _ bRaw: Int) -> Int {
    if bRaw == runtimeNullSentinelInt {
        return 0
    }
    guard let aPtr = UnsafeMutableRawPointer(bitPattern: aRaw),
          let a = extractString(from: aPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid string pointer in kk_string_equals (aRaw=0x\(String(aRaw, radix: 16)))")
    }
    guard let bPtr = UnsafeMutableRawPointer(bitPattern: bRaw),
          let b = extractString(from: bPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid string pointer in kk_string_equals (bRaw=0x\(String(bRaw, radix: 16)))")
    }
    return a == b ? 1 : 0
}

@_cdecl("kk_enum_valueOf_throw")
public func kk_enum_valueOf_throw(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) ?? "null"
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "IllegalArgumentException: No enum constant \(name)"
    )
    return 0
}

/// Creates an `Array` of enum instances for `enumValues<T>()` and `T.values()`.
///
/// The lowering stage builds an array of enum singleton objects (`RuntimeArrayBox`) and
/// passes it to this runtime helper together with the declared size.
/// Returns `RuntimeArrayBox` to match Kotlin JVM's `Array<T>` return type.
@_cdecl("kk_enum_make_values_array")
public func kk_enum_make_values_array(_ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }

    let safeCount = max(0, min(count, values.elements.count))
    let box = RuntimeArrayBox(length: safeCount)
    for i in 0..<safeCount {
        box.elements[i] = values.elements[i]
    }
    return registerRuntimeObject(box)
}

/// Creates a `List` of enum instances for `T.entries`.
///
/// `entries` returns `EnumEntries<T>` in Kotlin, which extends `List<E>`.
/// Returns `RuntimeListBox` to match the List-based API.
@_cdecl("kk_enum_make_entries_list")
public func kk_enum_make_entries_list(_ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let safeCount = max(0, min(count, values.elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(values.elements.prefix(safeCount))))
}
