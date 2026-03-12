import Foundation

private let runtimeDefaultTrimMarginPrefixRaw = runtimeMakeStringRaw("|")

private func runtimeStringScalars(_ raw: Int) -> [UnicodeScalar] {
    Array((runtimeStringFromRaw(raw) ?? "").unicodeScalars)
}

private func runtimeStringFromScalars(_ scalars: some Sequence<UnicodeScalar>) -> String {
    String(String.UnicodeScalarView(scalars))
}

// MARK: - STDLIB-006/009/013 String Functions

@_cdecl("kk_string_trim")
public func kk_string_trim(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_lowercase")
public func kk_string_lowercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    return runtimeMakeStringRaw(source.lowercased())
}

@_cdecl("kk_string_uppercase")
public func kk_string_uppercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    return runtimeMakeStringRaw(source.uppercased())
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

@_cdecl("kk_string_substring")
public func kk_string_substring(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ hasEndRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let hasEnd = hasEndRaw != 0
    let end = hasEnd ? endRaw : length

    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            message:
            "StringIndexOutOfBoundsException: start=\(start), end=\(hasEnd ? end : length), length=\(length)"
        )
        return 0
    }

    let result = runtimeStringFromScalars(scalars[start ..< end])
    return runtimeMakeStringRaw(result)
}

@_cdecl("kk_string_padStart")
public func kk_string_padStart(_ strRaw: Int, _ lengthRaw: Int, _ padCharRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let sourceLength = source.unicodeScalars.count
    guard lengthRaw > sourceLength else {
        return runtimeMakeStringRaw(source)
    }
    let padCharacter = runtimeCharacterFromRaw(padCharRaw)
    let padCount = lengthRaw - sourceLength
    if padCount <= 0 {
        return runtimeMakeStringRaw(source)
    }
    let padding = String(repeating: padCharacter, count: padCount)
    return runtimeMakeStringRaw(padding + source)
}

@_cdecl("kk_string_padEnd")
public func kk_string_padEnd(_ strRaw: Int, _ lengthRaw: Int, _ padCharRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let sourceLength = source.unicodeScalars.count
    guard lengthRaw > sourceLength else {
        return runtimeMakeStringRaw(source)
    }
    let padCharacter = runtimeCharacterFromRaw(padCharRaw)
    let padCount = lengthRaw - sourceLength
    if padCount <= 0 {
        return runtimeMakeStringRaw(source)
    }
    let padding = String(repeating: padCharacter, count: padCount)
    return runtimeMakeStringRaw(source + padding)
}

@_cdecl("kk_string_repeat")
public func kk_string_repeat(_ strRaw: Int, _ countRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    outThrown?.pointee = 0
    if countRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Count 'n' must be non-negative, but was \(countRaw).")
        return 0
    }
    guard countRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(String(repeating: source, count: countRaw))
}

@_cdecl("kk_string_reversed")
public func kk_string_reversed(_ strRaw: Int) -> Int {
    let reversed = runtimeStringFromScalars(runtimeStringScalars(strRaw).reversed())
    return runtimeMakeStringRaw(reversed)
}

@_cdecl("kk_string_toList")
public func kk_string_toList(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeListRaw(charRaws)
}

@_cdecl("kk_string_toCharArray")
public func kk_string_toCharArray(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeListRaw(charRaws)
}

@_cdecl("kk_string_take")
public func kk_string_take(_ strRaw: Int, _ nRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    guard nRaw < scalars.count else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< nRaw]))
}

@_cdecl("kk_string_takeLast")
public func kk_string_takeLast(_ strRaw: Int, _ nRaw: Int) -> Int {
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    let start = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start ..< scalars.count]))
}

@_cdecl("kk_string_drop")
public func kk_string_drop(_ strRaw: Int, _ nRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw(source)
    }
    if nRaw >= scalars.count {
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[nRaw ..< scalars.count]))
}

@_cdecl("kk_string_dropLast")
public func kk_string_dropLast(_ strRaw: Int, _ nRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw(source)
    }
    let end = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< end]))
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
    if other.isEmpty {
        return kk_box_bool(1)
    }
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

@_cdecl("kk_string_toIntOrNull")
public func kk_string_toIntOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    guard let value = Int32(source) else {
        return runtimeNullSentinelInt
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

@_cdecl("kk_string_toDoubleOrNull")
public func kk_string_toDoubleOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
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
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: parsed.bitPattern))
}

@_cdecl("kk_string_indexOf")
public func kk_string_indexOf(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)

    if other.isEmpty {
        return 0
    }
    if other.count > source.count {
        return -1
    }

    for offset in 0 ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        return offset
    }
    return -1
}

@_cdecl("kk_string_lastIndexOf")
public func kk_string_lastIndexOf(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)

    if other.isEmpty {
        return source.count
    }
    if other.count > source.count {
        return -1
    }

    var lastIndex = -1
    for offset in 0 ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        lastIndex = offset
    }
    return lastIndex
}

@_cdecl("kk_string_format")
public func kk_string_format(_ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let template = runtimeStringFromRaw(formatRaw) ?? ""
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.elements ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, arguments: arguments))
}

@_cdecl("kk_string_trimIndent")
public func kk_string_trimIndent(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    return runtimeMakeStringRaw(runtimeTrimIndent(source))
}

@_cdecl("kk_string_trimMargin_default")
public func kk_string_trimMargin_default(_ strRaw: Int) -> Int {
    kk_string_trimMargin(strRaw, runtimeDefaultTrimMarginPrefixRaw)
}

@_cdecl("kk_string_trimMargin")
public func kk_string_trimMargin(_ strRaw: Int, _ marginPrefixRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let marginPrefix = runtimeStringFromRaw(marginPrefixRaw) ?? "|"
    return runtimeMakeStringRaw(runtimeTrimMargin(source, marginPrefix: marginPrefix))
}

// MARK: - STDLIB-140 String.get(index)

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: String index out of range: \(indexRaw)"
        )
        return 0
    }
    return kk_box_char(Int(scalars[indexRaw].value))
}

// MARK: - STDLIB-141 String.compareTo

@_cdecl("kk_string_compareTo_member")
public func kk_string_compareTo_member(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeStringFromRaw(strRaw) ?? ""
    let rhs = runtimeStringFromRaw(otherRaw) ?? ""
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}

@_cdecl("kk_string_compareToIgnoreCase")
public func kk_string_compareToIgnoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let lhs = runtimeStringFromRaw(strRaw) ?? ""
    let rhs = runtimeStringFromRaw(otherRaw) ?? ""
    let ignoreCase = ignoreCaseRaw != 0
    if ignoreCase {
        let lhsLower = lhs.lowercased()
        let rhsLower = rhs.lowercased()
        if lhsLower < rhsLower { return -1 }
        if lhsLower > rhsLower { return 1 }
        return 0
    }
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}

// MARK: - STDLIB-142 String.toBoolean / toBooleanStrict

@_cdecl("kk_string_toBoolean")
public func kk_string_toBoolean(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    return kk_box_bool(source.lowercased() == "true" ? 1 : 0)
}

@_cdecl("kk_string_toBooleanStrict")
public func kk_string_toBooleanStrict(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRaw(strRaw) ?? ""
    switch source {
    case "true":
        return kk_box_bool(1)
    case "false":
        return kk_box_bool(0)
    default:
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: The string doesn't represent a boolean value: \(source)"
        )
        return 0
    }
}

// MARK: - STDLIB-143 String.lines

@_cdecl("kk_string_lines")
public func kk_string_lines(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let normalized = source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return runtimeMakeStringListRaw(lines)
}

// MARK: - STDLIB-144 String.trimStart / trimEnd

@_cdecl("kk_string_trimStart")
public func kk_string_trimStart(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = String(source.drop { $0.isWhitespace })
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_trimEnd")
public func kk_string_trimEnd(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    var end = source.endIndex
    while end > source.startIndex {
        let prev = source.index(before: end)
        guard source[prev].isWhitespace else { break }
        end = prev
    }
    return runtimeMakeStringRaw(String(source[source.startIndex ..< end]))
}

// MARK: - STDLIB-145 String.toByteArray / encodeToByteArray

@_cdecl("kk_string_toByteArray")
public func kk_string_toByteArray(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let bytes = Array(source.utf8).map { Int($0) }
    return runtimeMakeListRaw(bytes)
}

@_cdecl("kk_compare_any")
public func kk_compare_any(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    if lhsRaw == rhsRaw {
        return 0
    }
    if lhsRaw == runtimeNullSentinelInt {
        return -1
    }
    if rhsRaw == runtimeNullSentinelInt {
        return 1
    }
    if let lhsString = runtimeStringFromRaw(lhsRaw),
       let rhsString = runtimeStringFromRaw(rhsRaw)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }

    if let lhsValue = runtimeComparableScalar(from: lhsRaw),
       let rhsValue = runtimeComparableScalar(from: rhsRaw)
    {
        switch (lhsValue, rhsValue) {
        case let (.floating(lhs), .floating(rhs)):
            return runtimeCompareFloating(lhs, rhs)
        case let (.floating(lhs), .integer(rhs)):
            return runtimeCompareFloating(lhs, Double(rhs))
        case let (.integer(lhs), .floating(rhs)):
            return runtimeCompareFloating(Double(lhs), rhs)
        case let (.integer(lhs), .integer(rhs)):
            if lhs == rhs {
                return 0
            }
            return lhs < rhs ? -1 : 1
        }
    }

    return lhsRaw < rhsRaw ? -1 : 1
}

private enum RuntimeComparableScalar {
    case integer(Int)
    case floating(Double)
}

private func runtimeCompareFloating(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs.isNaN {
        return rhs.isNaN ? 0 : 1
    }
    if rhs.isNaN {
        return -1
    }
    if lhs == rhs {
        return 0
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeComparableScalar(from raw: Int) -> RuntimeComparableScalar? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return .integer(raw)
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return .integer(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return .floating(Double(floatBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return .floating(doubleBox.value)
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return .integer(intBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return .integer(boolBox.value ? 1 : 0)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return .integer(longBox.value)
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return .integer(charBox.value)
    }
    return nil
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

private func runtimeCompareStrings(_ lhs: String, _ rhs: String) -> Int {
    if lhs == rhs {
        return 0
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeNormalizedMultilineString(_ source: String) -> [String] {
    source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

private func runtimeTrimBlankEdges(_ lines: [String]) -> ArraySlice<String> {
    var start = lines.startIndex
    var end = lines.endIndex
    while start < end, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
        start += 1
    }
    while end > start, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
        end -= 1
    }
    return lines[start ..< end]
}

private func runtimeLeadingIndentCount(_ line: String) -> Int {
    line.prefix { $0 == " " || $0 == "\t" }.count
}

private func runtimeTrimIndent(_ source: String) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    let minimumIndent = lines
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map(runtimeLeadingIndentCount)
        .min() ?? 0
    return lines.map { line in
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ""
        }
        return String(line.dropFirst(minimumIndent))
    }.joined(separator: "\n")
}

private func runtimeTrimMargin(_ source: String, marginPrefix: String) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    return lines.map { line in
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(marginPrefix) else {
            return line
        }
        return String(trimmedLeading.dropFirst(marginPrefix.count))
    }.joined(separator: "\n")
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

private func runtimeCharacterFromRaw(_ raw: Int) -> String {
    guard let scalar = runtimeUnicodeScalarFromRaw(raw) else {
        return "\u{FFFD}"
    }
    return String(scalar)
}

private func runtimeUnicodeScalarFromRaw(_ raw: Int) -> UnicodeScalar? {
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       runtimeIsObjectPointer(pointer),
       let charBox = tryCast(pointer, to: RuntimeCharBox.self)
    {
        return UnicodeScalar(charBox.value)
    }
    return UnicodeScalar(UInt32(truncatingIfNeeded: raw))
}

private func runtimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeMakeListRaw(_ values: [Int]) -> Int {
    let box = RuntimeListBox(elements: values)
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

private func runtimeMakeStringListRaw(_ values: [String]) -> Int {
    runtimeMakeListRaw(values.map(runtimeMakeStringRaw))
}

private func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, message: String) {
    outThrown?.pointee = runtimeAllocateThrowable(message: message)
}

private struct RuntimeFormatSpecifier {
    let explicitArgumentIndex: Int?
    let flags: String
    let width: Int?
    let precision: Int?
    let conversion: Character

    var normalizedConversion: Character {
        Character(String(conversion).lowercased())
    }

    var cStyleToken: String {
        let supportedFlags = flags.filter { "-+ #0".contains($0) }
        var token = "%"
        token += supportedFlags
        if let width {
            token += String(width)
        }
        if let precision {
            token += ".\(precision)"
        }
        switch normalizedConversion {
        case "d", "i", "x", "o":
            token += "ll"
        default:
            break
        }
        token.append(conversion)
        return token
    }
}

private enum RuntimeParsedFormatToken {
    case escapedPercent(next: Int)
    case newline(next: Int)
    case specifier(RuntimeFormatSpecifier, next: Int)
    case invalid
}

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#"]
private let runtimeFormatLengthCharacters: Set<Character> = ["h", "l", "L", "z", "j", "t"]
private let runtimeSupportedFormatConversions: Set<Character> = [
    "s", "S", "b", "B", "d", "i", "x", "X", "o", "f", "e", "E", "g", "G", "c", "C",
]

private func runtimeFormatString(_ template: String, arguments: [Int]) -> String {
    let characters = Array(template)
    var cursor = 0
    var implicitArgumentIndex = 0
    var result = ""

    while cursor < characters.count {
        guard characters[cursor] == "%" else {
            result.append(characters[cursor])
            cursor += 1
            continue
        }

        switch runtimeParseFormatToken(characters, start: cursor) {
        case let .escapedPercent(next):
            result.append("%")
            cursor = next
        case let .newline(next):
            result.append("\n")
            cursor = next
        case let .specifier(specifier, next):
            let argumentIndex = specifier.explicitArgumentIndex ?? implicitArgumentIndex
            if specifier.explicitArgumentIndex == nil {
                implicitArgumentIndex += 1
            }
            let argument = arguments.indices.contains(argumentIndex)
                ? arguments[argumentIndex]
                : runtimeNullSentinelInt
            result += runtimeRenderFormattedArgument(argument, specifier: specifier)
            cursor = next
        case .invalid:
            result.append("%")
            cursor += 1
        }
    }

    return result
}

private func runtimeParseFormatToken(_ characters: [Character], start: Int) -> RuntimeParsedFormatToken {
    var cursor = start + 1
    guard cursor < characters.count else {
        return .invalid
    }
    if characters[cursor] == "%" {
        return .escapedPercent(next: cursor + 1)
    }
    if characters[cursor] == "n" {
        return .newline(next: cursor + 1)
    }

    let initialDigitsStart = cursor
    while cursor < characters.count, characters[cursor].isNumber {
        cursor += 1
    }
    var explicitArgumentIndex: Int?
    if cursor < characters.count, characters[cursor] == "$", initialDigitsStart < cursor {
        explicitArgumentIndex = Int(String(characters[initialDigitsStart ..< cursor])).map { $0 - 1 }
        cursor += 1
    } else {
        cursor = initialDigitsStart
    }

    let flagsStart = cursor
    while cursor < characters.count, runtimeFormatFlagCharacters.contains(characters[cursor]) {
        cursor += 1
    }
    let flags = String(characters[flagsStart ..< cursor])

    let widthStart = cursor
    while cursor < characters.count, characters[cursor].isNumber {
        cursor += 1
    }
    let width = widthStart < cursor ? Int(String(characters[widthStart ..< cursor])) : nil

    var precision: Int?
    if cursor < characters.count, characters[cursor] == "." {
        cursor += 1
        let precisionStart = cursor
        while cursor < characters.count, characters[cursor].isNumber {
            cursor += 1
        }
        let precisionDigits = String(characters[precisionStart ..< cursor])
        precision = Int(precisionDigits) ?? 0
    }

    while cursor < characters.count, runtimeFormatLengthCharacters.contains(characters[cursor]) {
        cursor += 1
    }
    guard cursor < characters.count else {
        return .invalid
    }

    let conversion = characters[cursor]
    guard runtimeSupportedFormatConversions.contains(conversion) else {
        return .invalid
    }

    return .specifier(
        RuntimeFormatSpecifier(
            explicitArgumentIndex: explicitArgumentIndex,
            flags: flags,
            width: width,
            precision: precision,
            conversion: conversion
        ),
        next: cursor + 1
    )
}

private func runtimeRenderFormattedArgument(_ argument: Int, specifier: RuntimeFormatSpecifier) -> String {
    switch specifier.normalizedConversion {
    case "s":
        let value = runtimeFormatStringValue(argument, specifier: specifier)
        return runtimeApplyStringWidth(value, specifier: specifier)
    case "b":
        let value = runtimeFormatBooleanValue(argument)
        let normalized = specifier.conversion.isUppercase ? value.uppercased() : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    case "d", "i":
        let value = Int64(runtimeFormatIntegerValue(argument))
        return String(format: specifier.cStyleToken, value)
    case "x", "o":
        let value = UInt64(bitPattern: Int64(runtimeFormatIntegerValue(argument)))
        return String(format: specifier.cStyleToken, value)
    case "f", "e", "g":
        return String(format: specifier.cStyleToken, runtimeFormatDoubleValue(argument))
    case "c":
        let value = runtimeFormatCharacterValue(argument)
        return runtimeApplyStringWidth(value, specifier: specifier)
    default:
        return runtimeApplyStringWidth(runtimeFormatStringValue(argument, specifier: specifier), specifier: specifier)
    }
}

private func runtimeFormatStringValue(_ argument: Int, specifier: RuntimeFormatSpecifier) -> String {
    var value = runtimeElementToString(argument)
    if let precision = specifier.precision, value.count > precision {
        value = String(value.prefix(precision))
    }
    if specifier.conversion.isUppercase {
        value = value.uppercased()
    }
    return value
}

private func runtimeFormatBooleanValue(_ argument: Int) -> String {
    if argument == runtimeNullSentinelInt {
        return "false"
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: argument),
       runtimeIsObjectPointer(pointer),
       let boolBox = tryCast(pointer, to: RuntimeBoolBox.self)
    {
        return boolBox.value ? "true" : "false"
    }
    return switch argument {
    case 0:
        "false"
    case 1:
        "true"
    default:
        "true"
    }
}

private func runtimeFormatIntegerValue(_ argument: Int) -> Int {
    maybeUnbox(argument)
}

private func runtimeFormatDoubleValue(_ argument: Int) -> Double {
    if argument == runtimeNullSentinelInt {
        return 0
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: argument),
       runtimeIsObjectPointer(pointer)
    {
        if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
            return Double(floatBox.value)
        }
        if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
            return doubleBox.value
        }
        if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
            return Double(intBox.value)
        }
        if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
            return boolBox.value ? 1 : 0
        }
        if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
            return Double(longBox.value)
        }
        if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
            return Double(charBox.value)
        }
        if let stringBox = tryCast(pointer, to: RuntimeStringBox.self) {
            return Double(stringBox.value) ?? 0
        }
    }
    if argument > -0x1_0000_0000, argument < 0x1_0000_0000 {
        return Double(argument)
    }
    return Double(bitPattern: UInt64(bitPattern: Int64(argument)))
}

private func runtimeFormatCharacterValue(_ argument: Int) -> String {
    let scalarValue = UInt32(truncatingIfNeeded: runtimeFormatIntegerValue(argument))
    guard let scalar = UnicodeScalar(scalarValue) else {
        return "?"
    }
    return String(scalar)
}

private func runtimeApplyStringWidth(_ value: String, specifier: RuntimeFormatSpecifier) -> String {
    guard let width = specifier.width, value.count < width else {
        return value
    }
    let padding = String(repeating: " ", count: width - value.count)
    if specifier.flags.contains("-") {
        return value + padding
    }
    return padding + value
}

private func runtimeIsObjectPointer(_ pointer: UnsafeMutableRawPointer) -> Bool {
    runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
}
