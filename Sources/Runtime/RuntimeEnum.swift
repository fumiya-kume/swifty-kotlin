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

/// Creates a `List` of enum instances for `enumValues<T>()`.
///
/// The lowering stage builds an array of enum singleton objects (`RuntimeArrayBox`) and
/// passes it to this runtime helper together with the declared size.
@_cdecl("kk_enum_make_values_array")
public func kk_enum_make_values_array(_ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let safeCount = max(0, min(count, values.elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(values.elements.prefix(safeCount))))
}
