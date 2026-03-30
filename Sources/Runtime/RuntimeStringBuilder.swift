import Foundation

// MARK: - StringBuilder Runtime Type (STDLIB-255/256/257)

final class RuntimeStringBuilderBox {
    var value: String
    init(_ initial: String = "") { self.value = initial }
}

private func runtimeStringBuilderBox(from raw: Int) -> RuntimeStringBuilderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isObject = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObject else { return nil }
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let obj = unmanaged.takeUnretainedValue()
    return obj as? RuntimeStringBuilderBox
}

private func sbMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - @_cdecl functions

@_cdecl("kk_string_builder_new")
public func kk_string_builder_new() -> Int {
    registerRuntimeObject(RuntimeStringBuilderBox())
}

@_cdecl("kk_string_builder_new_from_string")
public func kk_string_builder_new_from_string(_ strRaw: Int) -> Int {
    let initial: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
       let s = extractString(from: ptr) {
        initial = s
    } else {
        initial = ""
    }
    return registerRuntimeObject(RuntimeStringBuilderBox(initial))
}

@_cdecl("kk_string_builder_append_obj")
public func kk_string_builder_append_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(runtimeElementToString(valueRaw))
    return sbRaw
}

@_cdecl("kk_string_builder_toString")
public func kk_string_builder_toString(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else {
        return sbMakeStringRaw("")
    }
    return sbMakeStringRaw(sb.value)
}

@_cdecl("kk_string_builder_length_prop")
public func kk_string_builder_length_prop(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    return sb.value.utf8.count
}

// ABI note: The old camelCase symbols (kk_string_builder_appendLine_obj) were never part of
// a shipped/stable ABI. This rename to snake_case happened before any release, so there are
// no pre-existing compiled artifacts that reference the old names.
@_cdecl("kk_string_builder_append_line_obj")
public func kk_string_builder_append_line_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(runtimeElementToString(valueRaw))
    sb.value.append("\n")
    return sbRaw
}

// ABI note: Same as above — old camelCase symbol never shipped; rename is safe.
@_cdecl("kk_string_builder_append_line_noarg_obj")
public func kk_string_builder_append_line_noarg_obj(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append("\n")
    return sbRaw
}

@_cdecl("kk_string_builder_insert_obj")
public func kk_string_builder_insert_obj(_ sbRaw: Int, _ index: Int, _ valueRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index <= utf8Count else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    let str = runtimeElementToString(valueRaw)
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    let insertionPoint = String.Index(utf8Index, within: sb.value) ?? sb.value.endIndex
    sb.value.insert(contentsOf: str, at: insertionPoint)
    return sbRaw
}

@_cdecl("kk_string_builder_delete_obj")
public func kk_string_builder_delete_obj(_ sbRaw: Int, _ start: Int, _ end: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.utf8.count
    guard start >= 0, start <= len, end >= start, end <= len else {
        fatalError("StringIndexOutOfBoundsException: start=\(start), end=\(end), length=\(len)")
    }
    let startIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: start)
    let endIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: end)
    let sIdx = String.Index(startIdx, within: sb.value) ?? sb.value.endIndex
    let eIdx = String.Index(endIdx, within: sb.value) ?? sb.value.endIndex
    sb.value.removeSubrange(sIdx..<eIdx)
    return sbRaw
}

@_cdecl("kk_string_builder_clear")
public func kk_string_builder_clear(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = ""
    return sbRaw
}

@_cdecl("kk_string_builder_reverse")
public func kk_string_builder_reverse(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = String(sb.value.reversed())
    return sbRaw
}

@_cdecl("kk_string_builder_deleteCharAt")
public func kk_string_builder_deleteCharAt(_ sbRaw: Int, _ index: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    sb.value.remove(at: charIdx)
    return sbRaw
}

@_cdecl("kk_string_builder_appendRange_obj")
public func kk_string_builder_appendRange_obj(_ sbRaw: Int, _ csqRaw: Int, _ startIndex: Int, _ endIndex: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let csq = runtimeElementToString(csqRaw)
    // Use UTF-16 code unit indexing to match Kotlin CharSequence semantics.
    sb.value.append(runtimeUTF16Substring(csq, startIndex: startIndex, endIndex: endIndex))
    return sbRaw
}

// MARK: - STDLIB-STR-123: Additional StringBuilder methods

@_cdecl("kk_string_builder_replace_obj")
public func kk_string_builder_replace_obj(_ sbRaw: Int, _ start: Int, _ end: Int, _ strRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.utf8.count
    let clampedEnd = min(end, len)
    guard start >= 0, start <= len, clampedEnd >= start else {
        fatalError("StringIndexOutOfBoundsException: start=\(start), end=\(end), length=\(len)")
    }
    let replacement: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
       let s = extractString(from: ptr) {
        replacement = s
    } else {
        replacement = runtimeElementToString(strRaw)
    }
    let startIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: start)
    let endIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: clampedEnd)
    let sIdx = String.Index(startIdx, within: sb.value) ?? sb.value.endIndex
    let eIdx = String.Index(endIdx, within: sb.value) ?? sb.value.endIndex
    sb.value.replaceSubrange(sIdx..<eIdx, with: replacement)
    return sbRaw
}

@_cdecl("kk_string_builder_setCharAt")
public func kk_string_builder_setCharAt(_ sbRaw: Int, _ index: Int, _ charValue: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    // charValue is a boxed Char (unicode scalar value)
    let unboxed = kk_unbox_char(charValue)
    guard let scalar = Unicode.Scalar(unboxed) else { return sbRaw }
    sb.value.replaceSubrange(charIdx...charIdx, with: String(scalar))
    return sbRaw
}

@_cdecl("kk_string_builder_capacity")
public func kk_string_builder_capacity(_ sbRaw: Int) -> Int {
    // Swift Strings have no separate capacity concept; return length + 16 as a
    // reasonable default (mirrors the JVM default initial capacity of 16).
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 16 }
    return sb.value.utf8.count + 16
}

@_cdecl("kk_string_builder_ensureCapacity")
public func kk_string_builder_ensureCapacity(_ sbRaw: Int, _ minimumCapacity: Int) -> Int {
    // Swift Strings handle memory automatically; this is a no-op at runtime.
    return sbRaw
}

@_cdecl("kk_string_builder_trimToSize")
public func kk_string_builder_trimToSize(_ sbRaw: Int) -> Int {
    // Swift Strings handle memory automatically; this is a no-op at runtime.
    return sbRaw
}

@_cdecl("kk_string_builder_get")
public func kk_string_builder_get(_ sbRaw: Int, _ index: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        fatalError("StringIndexOutOfBoundsException: index=\(index), length=\(utf8Count)")
    }
    let charValue = Int(sb.value[charIdx].unicodeScalars.first?.value ?? 0)
    return kk_box_char(charValue)
}
