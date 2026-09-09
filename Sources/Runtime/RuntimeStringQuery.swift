// String query and predicate functions (first/last/single,
// flat ifBlank/ifEmpty wrappers, get, compareTo, contentEquals, lines).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// CharSequence.get occupies method slot 0 and CharSequence.length occupies
// property getter slot 1. Runtime-created String boxes need both entries so
// interface-typed calls use the same dispatch contract as source-defined
// CharSequence implementations.
private let runtimeCharSequenceInterfaceTypeID: Int64 =
    runtimeStableNominalTypeID(fqName: "kotlin.CharSequence")
private let runtimeCharSequenceGetMethod: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, index, outThrown in
    kk_char_sequence_get(raw, index, outThrown)
}
private let runtimeCharSequenceLengthGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_char_sequence_length(raw)
}

func runtimeRegisterCharSequenceItable(_ raw: Int) {
    _ = kk_object_register_itable_iface(
        raw,
        Int(runtimeCharSequenceInterfaceTypeID),
        0
    )
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(runtimeCharSequenceGetMethod, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw,
        0,
        1,
        unsafeBitCast(runtimeCharSequenceLengthGetter, to: Int.self)
    )
}

@_cdecl("kk_char_sequence_length")
public func kk_char_sequence_length(_ raw: Int) -> Int {
    // KSP-817: Match Kotlin's UTF-16 CharSequence.length contract. The receiver
    // may be any CharSequence implementation (String or StringBuilder handles).
    if let text = runtimeCharSequenceText(from: raw) {
        return text.utf16.count
    }
    return runtimeStringFromRawOrPanic(raw, caller: #function).utf16.count
}

// MARK: - STDLIB-190: first / last / single / firstOrNull / lastOrNull

@_cdecl("kk_string_first")
public func kk_string_first(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_last")
public func kk_string_last(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_single")
public func kk_string_single(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        if codeUnits.isEmpty {
            runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        } else {
            runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Char sequence has more than one element."))
        }
        return 0
    }
    return kk_box_char(Int(codeUnits[0]))
}

@_cdecl("kk_string_firstOrNull")
public func kk_string_firstOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_lastOrNull")
public func kk_string_lastOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_singleOrNull")
public func kk_string_singleOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(codeUnits[0]))
}

@_cdecl("kk_string_getOrNull")
public func kk_string_getOrNull(_ strRaw: Int, _ index: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard index >= 0, index < codeUnits.count else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(codeUnits[index]))
}

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_ifBlank_flat")
public func kk_string_ifBlank_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ fnPtr: Int, _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return runtimeRegisterFlatString(source, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard fnPtr != 0 else {
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let raw = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifBlank defaultValue"
        )
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_ifEmpty_flat")
public func kk_string_ifEmpty_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ fnPtr: Int, _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard source.isEmpty else {
        return runtimeRegisterFlatString(source, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard fnPtr != 0 else {
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let raw = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifEmpty defaultValue"
        )
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(codeUnits.count)")
        )
        return 0
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_char_sequence_get")
public func kk_char_sequence_get(
    _ sequenceRaw: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let text = runtimeCharSequenceText(from: sequenceRaw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Value is not a CharSequence")
        )
        return 0
    }
    let codeUnits = Array(text.utf16)
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(codeUnits.count)")
        )
        return 0
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_string_get_flat")
public func kk_string_get_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(codeUnits.count)")
        )
        return 0
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_string_getOrNull_flat")
public func kk_string_getOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int
) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        return runtimeNullSentinelInt
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_string_compareTo_member")
public func kk_string_compareTo_member(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    return runtimeCompareStrings(lhs, rhs)
}

// KSP-413: compareTo(ignoreCase) and CharSequence?.contentEquals are bundled
// Kotlin source (Stdlib/kotlin/text/StringComparison.kt); the
// kk_string_compareToIgnoreCase / kk_string_contentEquals /
// kk_string_contentEquals_ignoreCase bridges were removed.
