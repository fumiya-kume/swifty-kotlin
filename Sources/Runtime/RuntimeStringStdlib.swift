import Foundation

// MARK: - STDLIB-006 String Functions

@_cdecl("kk_string_trim")
public func kk_string_trim(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_split")
public func kk_string_split(
    _ strRaw: Int,
    _ delimitersArrayRaw: Int,
    _ ignoreCase: Int,
    _ limit: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if limit < 0 {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: Limit must be non-negative, but was \(limit)."
        )
        return 0
    }

    let source = runtimeStringFromRaw(strRaw) ?? ""
    let delimiters = runtimeSplitDelimiters(from: delimitersArrayRaw)
    if delimiters.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    if delimiters.contains(where: \.isEmpty) {
        return runtimeMakeStringListRaw(runtimeSplitByEmptyDelimiter(source, limit: limit))
    }

    let shouldIgnoreCase = ignoreCase != 0
    let pieces = runtimeSplitByDelimiters(
        source,
        delimiters: delimiters,
        ignoreCase: shouldIgnoreCase,
        limit: limit
    )
    return runtimeMakeStringListRaw(pieces)
}

@_cdecl("kk_string_replace")
public func kk_string_replace(
    _ strRaw: Int,
    _ oldValueRaw: Int,
    _ newValueRaw: Int,
    _ ignoreCase: Int
) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let oldValue = runtimeStringFromRaw(oldValueRaw) ?? ""
    let newValue = runtimeStringFromRaw(newValueRaw) ?? ""
    let options: String.CompareOptions = ignoreCase != 0 ? [.caseInsensitive] : []
    let replaced = source.replacingOccurrences(
        of: oldValue,
        with: newValue,
        options: options,
        range: nil
    )
    return runtimeMakeStringRaw(replaced)
}

@_cdecl("kk_string_startsWith")
public func kk_string_startsWith(
    _ strRaw: Int,
    _ prefixRaw: Int,
    _ startIndex: Int,
    _ ignoreCase: Int
) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let prefix = runtimeStringFromRaw(prefixRaw) ?? ""
    let sourceNSString = source as NSString
    let prefixNSString = prefix as NSString
    let sourceLength = sourceNSString.length
    let prefixLength = prefixNSString.length
    if startIndex < 0 || startIndex > sourceLength {
        return 0
    }
    if prefixLength > sourceLength - startIndex {
        return 0
    }
    let options: NSString.CompareOptions = ignoreCase != 0 ? [.caseInsensitive] : []
    let compared = sourceNSString.compare(
        prefix,
        options: options,
        range: NSRange(location: startIndex, length: prefixLength)
    )
    return compared == .orderedSame ? 1 : 0
}

@_cdecl("kk_string_endsWith")
public func kk_string_endsWith(
    _ strRaw: Int,
    _ suffixRaw: Int,
    _ ignoreCase: Int
) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let suffix = runtimeStringFromRaw(suffixRaw) ?? ""
    let sourceNSString = source as NSString
    let suffixNSString = suffix as NSString
    let sourceLength = sourceNSString.length
    let suffixLength = suffixNSString.length
    if suffixLength > sourceLength {
        return 0
    }
    let options: NSString.CompareOptions = ignoreCase != 0 ? [.caseInsensitive] : []
    let compared = sourceNSString.compare(
        suffix,
        options: options,
        range: NSRange(location: sourceLength - suffixLength, length: suffixLength)
    )
    return compared == .orderedSame ? 1 : 0
}

@_cdecl("kk_string_contains")
public func kk_string_contains(
    _ strRaw: Int,
    _ needleRaw: Int,
    _ ignoreCase: Int
) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let needle = runtimeStringFromRaw(needleRaw) ?? ""
    if needle.isEmpty {
        return 1
    }
    let options: String.CompareOptions = ignoreCase != 0 ? [.caseInsensitive] : []
    return source.range(of: needle, options: options, range: nil, locale: nil) == nil ? 0 : 1
}

@_cdecl("kk_string_toInt")
public func kk_string_toInt(
    _ strRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
public func kk_string_toDouble(
    _ strRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
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
    let format = runtimeStringFromRaw(formatRaw) ?? ""
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.elements ?? []
    let characters = Array(format)
    var index = 0
    var argumentIndex = 0
    var output = ""

    while index < characters.count {
        let current = characters[index]
        if current != "%" {
            output.append(current)
            index += 1
            continue
        }
        if index + 1 < characters.count, characters[index + 1] == "%" {
            output.append("%")
            index += 2
            continue
        }

        let placeholderStart = index
        index += 1

        var leftJustified = false
        var zeroPadded = false
        while index < characters.count {
            let flag = characters[index]
            if flag == "-" {
                leftJustified = true
                index += 1
                continue
            }
            if flag == "0" {
                zeroPadded = true
                index += 1
                continue
            }
            break
        }

        var widthDigits = ""
        while index < characters.count, characters[index].wholeNumberValue != nil {
            widthDigits.append(characters[index])
            index += 1
        }
        let width = widthDigits.isEmpty ? nil : Int(widthDigits)

        var precision: Int?
        if index < characters.count, characters[index] == "." {
            index += 1
            var precisionDigits = ""
            while index < characters.count, characters[index].wholeNumberValue != nil {
                precisionDigits.append(characters[index])
                index += 1
            }
            precision = Int(precisionDigits) ?? 0
        }

        guard index < characters.count else {
            output.append(contentsOf: String(characters[placeholderStart...]))
            break
        }
        let specifier = characters[index]
        index += 1

        if !"sdifxXo".contains(specifier) {
            output.append(contentsOf: String(characters[placeholderStart ..< index]))
            continue
        }
        guard argumentIndex < arguments.count else {
            output.append(contentsOf: String(characters[placeholderStart ..< index]))
            continue
        }

        let argument = arguments[argumentIndex]
        argumentIndex += 1

        var piece = ""
        switch specifier {
        case "s":
            piece = runtimeElementToString(argument)
        case "d", "i":
            piece = String(runtimeFormatInteger(argument))
            piece = runtimeApplyIntegerPrecision(piece, precision: precision)
        case "x":
            piece = String(runtimeFormatUnsigned(argument), radix: 16, uppercase: false)
            piece = runtimeApplyIntegerPrecision(piece, precision: precision)
        case "X":
            piece = String(runtimeFormatUnsigned(argument), radix: 16, uppercase: true)
            piece = runtimeApplyIntegerPrecision(piece, precision: precision)
        case "o":
            piece = String(runtimeFormatUnsigned(argument), radix: 8, uppercase: false)
            piece = runtimeApplyIntegerPrecision(piece, precision: precision)
        case "f":
            let value = runtimeFormatDouble(argument)
            let precisionValue = precision ?? 6
            piece = String(format: "%.\(precisionValue)f", value)
        default:
            piece = String(characters[placeholderStart ..< index])
        }

        output += runtimeApplyWidth(
            piece,
            width: width,
            leftJustified: leftJustified,
            zeroPadded: zeroPadded && precision == nil && specifier != "s" && !leftJustified
        )
    }

    return runtimeMakeStringRaw(output)
}

// MARK: - Formatting Helpers

private func runtimeFormatInteger(_ raw: Int) -> Int {
    if raw == runtimeNullSentinelInt {
        return 0
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return raw
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return raw
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return raw
}

private func runtimeFormatUnsigned(_ raw: Int) -> UInt {
    UInt(bitPattern: runtimeFormatInteger(raw))
}

private func runtimeFormatDouble(_ raw: Int) -> Double {
    if raw == runtimeNullSentinelInt {
        return 0
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw) {
        let isObjectPointer = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
        if isObjectPointer {
            if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
                return Double(intBox.value)
            }
            if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
                return boolBox.value ? 1 : 0
            }
        }
    }
    if abs(raw) < (1 << 40) {
        return Double(raw)
    }
    let bits = UInt64(bitPattern: Int64(raw))
    return Double(bitPattern: bits)
}

private func runtimeApplyIntegerPrecision(_ value: String, precision: Int?) -> String {
    guard let precision else {
        return value
    }
    let isNegative = value.hasPrefix("-")
    let digits = isNegative ? String(value.dropFirst()) : value
    guard digits.count < precision else {
        return value
    }
    let padded = String(repeating: "0", count: precision - digits.count) + digits
    return isNegative ? "-" + padded : padded
}

private func runtimeApplyWidth(
    _ value: String,
    width: Int?,
    leftJustified: Bool,
    zeroPadded: Bool
) -> String {
    guard let width, width > value.count else {
        return value
    }
    let padCount = width - value.count
    let padCharacter = zeroPadded ? "0" : " "
    let padding = String(repeating: padCharacter, count: padCount)
    if leftJustified {
        return value + padding
    }
    return padding + value
}

// MARK: - Split Helpers

private func runtimeSplitDelimiters(from delimitersArrayRaw: Int) -> [String] {
    guard let delimitersArray = runtimeArrayBox(from: delimitersArrayRaw) else {
        return []
    }
    return delimitersArray.elements.map { runtimeStringFromRaw($0) ?? "" }
}

private func runtimeSplitByDelimiters(
    _ source: String,
    delimiters: [String],
    ignoreCase: Bool,
    limit: Int
) -> [String] {
    if limit == 1 {
        return [source]
    }
    var pieces: [String] = []
    var cursor = source.startIndex
    while true {
        if limit > 0, pieces.count == limit - 1 {
            break
        }
        guard let matched = runtimeFindNextDelimiter(
            in: source,
            from: cursor,
            delimiters: delimiters,
            ignoreCase: ignoreCase
        ) else {
            break
        }
        pieces.append(String(source[cursor ..< matched.lowerBound]))
        cursor = matched.upperBound
    }
    pieces.append(String(source[cursor...]))
    return pieces
}

private func runtimeFindNextDelimiter(
    in source: String,
    from start: String.Index,
    delimiters: [String],
    ignoreCase: Bool
) -> Range<String.Index>? {
    let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
    var bestMatch: Range<String.Index>?
    for delimiter in delimiters where !delimiter.isEmpty {
        guard let range = source.range(
            of: delimiter,
            options: options,
            range: start ..< source.endIndex,
            locale: nil
        ) else {
            continue
        }
        guard let best = bestMatch else {
            bestMatch = range
            continue
        }
        if range.lowerBound < best.lowerBound ||
            (range.lowerBound == best.lowerBound && range.upperBound > best.upperBound)
        {
            bestMatch = range
        }
    }
    return bestMatch
}

private func runtimeSplitByEmptyDelimiter(_ source: String, limit: Int) -> [String] {
    if limit == 1 {
        return [source]
    }
    let base = [""] + source.map { String($0) } + [""]
    if limit <= 0 {
        return base
    }
    let prefixCount = limit - 1
    if prefixCount >= base.count {
        return base
    }
    var result = Array(base.prefix(prefixCount))
    result.append(base.dropFirst(prefixCount).joined())
    return result
}

// MARK: - Runtime Box Helpers

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
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count + 1) { pointer in
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
