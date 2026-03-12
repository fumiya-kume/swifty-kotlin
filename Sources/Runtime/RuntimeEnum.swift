import Foundation

// Runtime support for enum valueOf (STDLIB-173) and enum name/ordinal helpers.
// kk_string_equals and kk_enum_valueOf_throw are used by synthesized valueOf(String).

@_cdecl("kk_string_equals")
public func kk_string_equals(_ aRaw: Int, _ bRaw: Int) -> Int {
    if bRaw == runtimeNullSentinelInt {
        return 0
    }
    let a = extractString(from: UnsafeMutableRawPointer(bitPattern: aRaw)) ?? ""
    let b = extractString(from: UnsafeMutableRawPointer(bitPattern: bRaw)) ?? ""
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

/// Creates a List of enum ordinals [0, 1, ..., count-1] for enumValues<T>().
/// Each element is a boxed Int (ordinal). Used by enumValues<Color>().map { it.name } etc.
@_cdecl("kk_enum_make_values_array")
public func kk_enum_make_values_array(_ count: Int) -> Int {
    var elements: [Int] = []
    elements.reserveCapacity(max(0, count))
    for i in 0 ..< count {
        elements.append(kk_box_int(i))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}
