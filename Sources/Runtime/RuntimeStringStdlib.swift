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

@_cdecl("kk_string_format")
public func kk_string_format(_ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let template = runtimeStringFromRaw(formatRaw) ?? ""
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.elements ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, arguments: arguments))
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

    let lhsValue = maybeUnbox(lhsRaw)
    let rhsValue = maybeUnbox(rhsRaw)
    if lhsValue != lhsRaw || rhsValue != rhsRaw ||
        (UnsafeMutableRawPointer(bitPattern: lhsRaw) == nil && UnsafeMutableRawPointer(bitPattern: rhsRaw) == nil)
    {
        if lhsValue == rhsValue {
            return 0
        }
        return lhsValue < rhsValue ? -1 : 1
    }

    return lhsRaw < rhsRaw ? -1 : 1
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

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#", ",", "("]
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
        let value = Int32(truncatingIfNeeded: runtimeFormatIntegerValue(argument))
        return String(format: specifier.cStyleToken, value)
    case "x", "o":
        let value = UInt32(truncatingIfNeeded: runtimeFormatIntegerValue(argument))
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
        if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
            return Double(intBox.value)
        }
        if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
            return boolBox.value ? 1 : 0
        }
        if let stringBox = tryCast(pointer, to: RuntimeStringBox.self) {
            return Double(stringBox.value) ?? 0
        }
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
