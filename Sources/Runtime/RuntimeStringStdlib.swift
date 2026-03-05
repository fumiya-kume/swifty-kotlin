import Foundation

// MARK: - STDLIB-006 String Functions

@_cdecl("kk_string_trim")
public func kk_string_trim(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_split")
public func kk_string_split(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let delimiter = runtimeStringFromRaw(delimRaw) ?? ""

    if delimiter.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    return runtimeMakeStringListRaw(runtimeSplitString(source, delimiter: delimiter))
}

@_cdecl("kk_string_replace")
public func kk_string_replace(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let oldValue = runtimeStringFromRaw(oldRaw) ?? ""
    let newValue = runtimeStringFromRaw(newRaw) ?? ""
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldValue, with: newValue))
}

@_cdecl("kk_string_startsWith")
public func kk_string_startsWith(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let prefix = runtimeStringFromRaw(prefixRaw) ?? ""
    return kk_box_bool(source.hasPrefix(prefix) ? 1 : 0)
}

@_cdecl("kk_string_endsWith")
public func kk_string_endsWith(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let suffix = runtimeStringFromRaw(suffixRaw) ?? ""
    return kk_box_bool(source.hasSuffix(suffix) ? 1 : 0)
}

@_cdecl("kk_string_contains_str")
public func kk_string_contains_str(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let other = runtimeStringFromRaw(otherRaw) ?? ""
    return kk_box_bool(source.contains(other) ? 1 : 0)
}

@_cdecl("kk_string_toInt")
public func kk_string_toInt(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRaw(strRaw) ?? ""
    guard let value = Int32(source) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("kk_string_toDouble")
public func kk_string_toDouble(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        runtimeSetThrown(outThrown, message: "NumberFormatException: empty String")
        return 0
    }

    let value: Double? = switch trimmed {
    case "NaN":
        .nan
    case "Infinity", "+Infinity":
        .infinity
    case "-Infinity":
        -.infinity
    default:
        Double(trimmed)
    }
    guard let parsed = value else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(trimmed)\""
        )
        return 0
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: parsed.bitPattern))
}

private func runtimeSplitString(_ source: String, delimiter: String) -> [String] {
    if source.isEmpty {
        return [""]
    }

    var result: [String] = []
    var cursor = source.startIndex
    while true {
        guard let match = source.range(of: delimiter, range: cursor ..< source.endIndex) else {
            result.append(String(source[cursor...]))
            return result
        }
        result.append(String(source[cursor ..< match.lowerBound]))
        cursor = match.upperBound
    }
}

private func runtimeStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: pointer)
}

private func runtimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeMakeStringListRaw(_ values: [String]) -> Int {
    let elementRaws = values.map(runtimeMakeStringRaw)
    let box = RuntimeListBox(elements: elementRaws)
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

private func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, message: String) {
    outThrown?.pointee = runtimeAllocateThrowable(message: message)
}
