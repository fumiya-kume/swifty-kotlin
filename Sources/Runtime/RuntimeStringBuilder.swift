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
    return sb.value.count
}

@_cdecl("kk_string_builder_appendLine_obj")
public func kk_string_builder_appendLine_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(runtimeElementToString(valueRaw))
    sb.value.append("\n")
    return sbRaw
}

@_cdecl("kk_string_builder_appendLine_noarg_obj")
public func kk_string_builder_appendLine_noarg_obj(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append("\n")
    return sbRaw
}

@_cdecl("kk_string_builder_insert_obj")
public func kk_string_builder_insert_obj(_ sbRaw: Int, _ index: Int, _ valueRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let str = runtimeElementToString(valueRaw)
    let clampedIndex = max(0, min(index, sb.value.count))
    let insertionPoint = sb.value.index(sb.value.startIndex, offsetBy: clampedIndex)
    sb.value.insert(contentsOf: str, at: insertionPoint)
    return sbRaw
}

@_cdecl("kk_string_builder_delete_obj")
public func kk_string_builder_delete_obj(_ sbRaw: Int, _ start: Int, _ end: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.count
    let s = max(0, min(start, len))
    let e = max(s, min(end, len))
    let startIdx = sb.value.index(sb.value.startIndex, offsetBy: s)
    let endIdx = sb.value.index(sb.value.startIndex, offsetBy: e)
    sb.value.removeSubrange(startIdx..<endIdx)
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
    guard index >= 0, index < sb.value.count else { return sbRaw }
    let idx = sb.value.index(sb.value.startIndex, offsetBy: index)
    sb.value.remove(at: idx)
    return sbRaw
}

@_cdecl("kk_string_builder_get")
public func kk_string_builder_get(_ sbRaw: Int, _ index: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    guard index >= 0, index < sb.value.count else { return 0 }
    let idx = sb.value.index(sb.value.startIndex, offsetBy: index)
    let charValue = Int(sb.value[idx].unicodeScalars.first?.value ?? 0)
    return kk_box_char(charValue)
}
