import Foundation

private let runtimeDefaultTrimMarginPrefixRaw = runtimeMakeStringRaw("|")

private func runtimeStringScalars(_ raw: Int) -> [UnicodeScalar] {
    Array(runtimeStringFromRawOrPanic(raw, caller: #function).unicodeScalars)
}

private func runtimeStringUTF16CodeUnits(_ raw: Int) -> [UInt16] {
    Array(runtimeStringFromRawOrPanic(raw, caller: #function).utf16)
}

private func runtimeStringFromScalars(_ scalars: some Sequence<UnicodeScalar>) -> String {
    String(String.UnicodeScalarView(scalars))
}

private func runtimeStringTrimWithPredicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    trimLeading: Bool,
    trimTrailing: Bool,
    context: String
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars))
    }

    func shouldTrim(_ scalar: UnicodeScalar) -> Bool? {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: context)
            return nil
        }
        return maybeUnbox(result) != 0
    }

    var start = 0
    var end = scalars.count
    if trimLeading {
        while start < end {
            guard let matches = shouldTrim(scalars[start]) else {
                return runtimeMakeStringRaw("")
            }
            guard matches else { break }
            start += 1
        }
    }
    if trimTrailing {
        while end > start {
            guard let matches = shouldTrim(scalars[end - 1]) else {
                return runtimeMakeStringRaw("")
            }
            guard matches else { break }
            end -= 1
        }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start ..< end]))
}

// MARK: - STDLIB-006/009/013 String Functions

@_cdecl("kk_string_trim")
public func kk_string_trim(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_trim_predicate")
public func kk_string_trim_predicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringTrimWithPredicate(
        strRaw,
        fnPtr,
        closureRaw,
        outThrown,
        trimLeading: true,
        trimTrailing: true,
        context: "trim predicate"
    )
}

@_cdecl("kk_string_lowercase")
public func kk_string_lowercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(source.lowercased())
}

@_cdecl("kk_string_uppercase")
public func kk_string_uppercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(source.uppercased())
}

@_cdecl("kk_string_lowercase_locale")
public func kk_string_lowercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        return runtimeMakeStringRaw(source.lowercased())
    }
    return runtimeMakeStringRaw(source.lowercased(with: box.locale))
}

@_cdecl("kk_string_uppercase_locale")
public func kk_string_uppercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        return runtimeMakeStringRaw(source.uppercased())
    }
    return runtimeMakeStringRaw(source.uppercased(with: box.locale))
}

@_cdecl("kk_string_compareTo_locale")
public func kk_string_compareTo_locale(_ lhsRaw: Int, _ rhsRaw: Int, _ localeRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(lhsRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(rhsRaw, caller: #function)
    let locale: Locale = runtimeLocaleBox(from: localeRaw)?.locale ?? Locale.current
    switch lhs.compare(rhs, options: [], range: nil, locale: locale) {
    case .orderedAscending:
        return -1
    case .orderedDescending:
        return 1
    case .orderedSame:
        return 0
    }
}

private enum NormalizationFormTag: Int {
    case nfc = 0
    case nfd = 1
    case nfkc = 2
    case nfkd = 3
}

@_cdecl("kk_normalization_form_nfc")
public func kk_normalization_form_nfc() -> Int { NormalizationFormTag.nfc.rawValue }

@_cdecl("kk_normalization_form_nfd")
public func kk_normalization_form_nfd() -> Int { NormalizationFormTag.nfd.rawValue }

@_cdecl("kk_normalization_form_nfkc")
public func kk_normalization_form_nfkc() -> Int { NormalizationFormTag.nfkc.rawValue }

@_cdecl("kk_normalization_form_nfkd")
public func kk_normalization_form_nfkd() -> Int { NormalizationFormTag.nfkd.rawValue }

private func runtimeNormalizedString(_ source: String, formTagRaw: Int) -> String {
    guard let form = NormalizationFormTag(rawValue: formTagRaw) else {
        return source
    }
    switch form {
    case .nfc:
        return source.precomposedStringWithCanonicalMapping
    case .nfd:
        return source.decomposedStringWithCanonicalMapping
    case .nfkc:
        return source.precomposedStringWithCompatibilityMapping
    case .nfkd:
        return source.decomposedStringWithCompatibilityMapping
    }
}

@_cdecl("kk_string_normalize")
public func kk_string_normalize(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeNormalizedString(source, formTagRaw: formTagRaw))
}

@_cdecl("kk_string_isNormalized")
public func kk_string_isNormalized(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let normalized = runtimeNormalizedString(source, formTagRaw: formTagRaw)
    return normalized.unicodeScalars.elementsEqual(source.unicodeScalars) ? 1 : 0
}


@_cdecl("kk_string_split")
public func kk_string_split(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)

    if delimiter.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    return runtimeMakeStringListRaw(runtimeSplitString(source, delimiter: delimiter))
}

// MARK: - STDLIB-TEXT-EDGE-001: CharSequence.split with ignoreCase and limit

@_cdecl("kk_string_split_limit")
public func kk_string_split_limit(_ strRaw: Int, _ delimRaw: Int, _ ignoreCaseRaw: Int, _ limitRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0
    let limit = limitRaw

    if delimiter.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    return runtimeMakeStringListRaw(
        runtimeSplitStringLimit(source, delimiter: delimiter, ignoreCase: ignoreCase, limit: limit)
    )
}

@_cdecl("kk_string_replace")
public func kk_string_replace(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
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

@_cdecl("kk_string_subSequence")
public func kk_string_subSequence(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_substring(strRaw, startRaw, endRaw, 1, outThrown)
}

/// Unicode code point for space (U+0020), the default pad character in Kotlin.
private let kDefaultPadCharRaw: Int = 0x20

@_cdecl("kk_string_padStart_default")
public func kk_string_padStart_default(_ strRaw: Int, _ lengthRaw: Int) -> Int {
    return kk_string_padStart(strRaw, lengthRaw, kDefaultPadCharRaw)
}

@_cdecl("kk_string_padEnd_default")
public func kk_string_padEnd_default(_ strRaw: Int, _ lengthRaw: Int) -> Int {
    return kk_string_padEnd(strRaw, lengthRaw, kDefaultPadCharRaw)
}

@_cdecl("kk_string_padStart")
public func kk_string_padStart(_ strRaw: Int, _ lengthRaw: Int, _ padCharRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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
    return runtimeMakeArrayRaw(charRaws)
}

// MARK: - STDLIB-640: CharArray.concatToString()

/// Converts a `CharArray` to a `String` by concatenating all characters.
/// This is the inverse of `String.toCharArray()`.
@_cdecl("kk_chararray_concatToString")
public func kk_chararray_concatToString(_ arrRaw: Int) -> Int {
    guard let box = runtimeArrayBox(from: arrRaw) else {
        return runtimeMakeStringRaw("")
    }
    var scalars = String.UnicodeScalarView()
    for i in 0..<box.elements.count {
        let charValue = kk_unbox_char(box.elements[i])
        if let scalar = UnicodeScalar(charValue) {
            scalars.append(scalar)
        }
    }
    return runtimeMakeStringRaw(String(scalars))
}

// MARK: - STDLIB-317: String.asIterable() — lazy Iterable<Char> view

/// Returns a lazy `Iterable<Char>` wrapper around the given string.
/// Character materialisation is deferred until the iterable is actually consumed
/// (e.g. via `iterator()`, `toList()`, or `for-in`).  Creation is O(1).
@_cdecl("kk_string_asIterable")
public func kk_string_asIterable(_ strRaw: Int) -> Int {
    let box = RuntimeStringIterableBox(strRaw: strRaw)
    return registerRuntimeObject(box)
}

/// Materialise the lazy string-iterable into a `List<Char>`.
/// Called when `toList()` is invoked on the iterable returned by `asIterable()`,
/// or when the for-in lowering needs a concrete list.
@_cdecl("kk_string_iterable_toList")
public func kk_string_iterable_toList(_ iterableRaw: Int) -> Int {
    guard let box = runtimeStringIterableBox(from: iterableRaw) else {
        // Validate that the raw value is a valid string handle before falling
        // back, to avoid reinterpreting an unrelated object pointer as a string.
        if extractString(from: UnsafeMutableRawPointer(bitPattern: iterableRaw)) != nil {
            return kk_string_toList(iterableRaw)
        }
        // Unrecognised input — return an empty list.
        return kk_string_toList(runtimeMakeStringRaw(""))
    }
    return kk_string_toList(box.strRaw)
}

/// Create an iterator from a lazy string iterable (for `for (c in str.asIterable())`).
@_cdecl("kk_string_iterable_iterator")
public func kk_string_iterable_iterator(_ iterableRaw: Int) -> Int {
    if let box = runtimeStringIterableBox(from: iterableRaw) {
        return kk_string_iterator(box.strRaw)
    }
    // Validate that the raw value is a valid string handle before falling
    // back, to avoid reinterpreting an unrelated object pointer as a string.
    if extractString(from: UnsafeMutableRawPointer(bitPattern: iterableRaw)) != nil {
        return kk_string_iterator(iterableRaw)
    }
    // Return an empty iterator for unrecognised inputs (including null
    // sentinel) rather than misinterpreting them as string handles.
    let box = RuntimeStringIteratorBox(charRaws: [])
    return registerRuntimeObject(box)
}

@_cdecl("kk_string_asSequence")
public func kk_string_asSequence(_ strRaw: Int) -> Int {
    // Lazy: store only the string handle; characters are yielded on demand
    let seq = RuntimeSequenceBox(steps: [.stringSource(strRaw: strRaw)])
    return registerRuntimeObject(seq)
}

// MARK: - STDLIB-189: String iterator and HOF (filter, map, count, any, all, none)

@_cdecl("kk_string_iterator")
public func kk_string_iterator(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    let box = RuntimeStringIteratorBox(charRaws: charRaws)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_string_iterator_hasNext")
public func kk_string_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeStringIteratorBox(from: iterRaw) else { return 0 }
    return iter.index < iter.charRaws.count ? 1 : 0
}

@_cdecl("kk_string_iterator_next")
public func kk_string_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeStringIteratorBox(from: iterRaw) else { return 0 }
    guard iter.index < iter.charRaws.count else { return 0 }
    let value = iter.charRaws[iter.index]
    iter.index += 1
    return value
}

@_cdecl("kk_string_filter")
public func kk_string_filter(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_map")
public func kk_string_map(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mappedElements: [Int] = []
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        mappedElements.append(result)
    }
    return runtimeMakeListRaw(mappedElements)
}

@_cdecl("kk_string_count")
public func kk_string_count(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.count }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_string_any")
public func kk_string_any(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.isEmpty ? 0 : 1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_string_all")
public func kk_string_all(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return 1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_string_none")
public func kk_string_none(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.isEmpty ? 1 : 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { return 0 }
    }
    return 1
}

// MARK: - STDLIB-315: String.replaceFirstChar

@_cdecl("kk_string_replaceFirstChar")
public func kk_string_replaceFirstChar(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else { return runtimeMakeStringRaw("") }
    guard fnPtr != 0 else { return strRaw }
    let firstCharRaw = Int(scalars[0].value)
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, firstCharRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "replaceFirstChar transform"
        )
        return runtimeMakeStringRaw("")
    }
    let replacement = runtimeUnicodeScalarFromRaw(result) ?? scalars[0]
    let tail = scalars.dropFirst()
    var rebuilt = String.UnicodeScalarView()
    rebuilt.append(replacement)
    rebuilt.append(contentsOf: tail)
    return runtimeMakeStringRaw(String(rebuilt))
}

@_cdecl("kk_string_take")
public func kk_string_take(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    guard nRaw < scalars.count else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< nRaw]))
}

// MARK: - STDLIB-185: removePrefix / removeSuffix / removeSurrounding

@_cdecl("kk_string_removePrefix")
public func kk_string_removePrefix(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    guard source.hasPrefix(prefix) else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(String(source.dropFirst(prefix.count)))
}

@_cdecl("kk_string_removeSuffix")
public func kk_string_removeSuffix(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    guard source.hasSuffix(suffix) else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(String(source.dropLast(suffix.count)))
}

@_cdecl("kk_string_removeSurrounding")
public func kk_string_removeSurrounding(_ strRaw: Int, _ delimiterRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    guard !delimiter.isEmpty,
          source.hasPrefix(delimiter),
          source.hasSuffix(delimiter),
          source.count >= delimiter.count * 2
    else {
        return runtimeMakeStringRaw(source)
    }
    let start = source.index(source.startIndex, offsetBy: delimiter.count)
    let end = source.index(source.endIndex, offsetBy: -delimiter.count)
    return runtimeMakeStringRaw(String(source[start ..< end]))
}

@_cdecl("kk_string_removeSurrounding_pair")
public func kk_string_removeSurrounding_pair(
    _ strRaw: Int,
    _ prefixRaw: Int,
    _ suffixRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    guard source.hasPrefix(prefix),
          source.hasSuffix(suffix),
          source.count >= prefix.count + suffix.count
    else {
        return runtimeMakeStringRaw(source)
    }
    let start = source.index(source.startIndex, offsetBy: prefix.count)
    let end = source.index(source.endIndex, offsetBy: -suffix.count)
    return runtimeMakeStringRaw(String(source[start ..< end]))
}

@_cdecl("kk_string_takeLast")
public func kk_string_takeLast(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    let start = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start ..< scalars.count]))
}

@_cdecl("kk_string_drop")
public func kk_string_drop(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
        return runtimeMakeStringRaw("")
    }
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
public func kk_string_dropLast(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw(source)
    }
    let end = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< end]))
}

@_cdecl("kk_string_startsWith")
public func kk_string_startsWith(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    return kk_box_bool(source.hasPrefix(prefix) ? 1 : 0)
}

@_cdecl("kk_string_endsWith")
public func kk_string_endsWith(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    return kk_box_bool(source.hasSuffix(suffix) ? 1 : 0)
}

@_cdecl("kk_string_contains_str")
public func kk_string_contains_str(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    if other.isEmpty {
        return kk_box_bool(1)
    }
    return kk_box_bool(source.contains(other) ? 1 : 0)
}

@_cdecl("kk_string_toInt")
public func kk_string_toInt(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int32(source) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("kk_string_toInt_radix")
public func kk_string_toInt_radix(_ strRaw: Int, _ radix: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return 0
    }
    guard let value = Int32(source, radix: radix) else {
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
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int32(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toIntOrNull_radix")
public func kk_string_toIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return runtimeNullSentinelInt
    }
    guard let value = Int32(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toUByteOrNull_radix")
public func kk_string_toUByteOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return runtimeNullSentinelInt
    }
    guard let value = UInt8(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toUShortOrNull_radix")
public func kk_string_toUShortOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return runtimeNullSentinelInt
    }
    guard let value = UInt16(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toUIntOrNull_radix")
public func kk_string_toUIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return runtimeNullSentinelInt
    }
    guard let value = UInt32(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toULongOrNull_radix")
public func kk_string_toULongOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            message: "IllegalArgumentException: radix \(radix) was not in valid range 2..36"
        )
        return runtimeNullSentinelInt
    }
    guard let value = UInt64(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
}

@_cdecl("kk_string_toDouble")
public func kk_string_toDouble(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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

// MARK: - STDLIB-420 String.toLong / toLongOrNull / toFloat / toFloatOrNull

#if !arch(arm64) && !arch(x86_64)
#error("Long conversion assumes 64-bit Int")
#endif

/// Shared helper: parse a trimmed string into a Float, handling NaN/Infinity literals.
private func runtimeParseFloat(_ trimmed: String) -> Float? {
    switch trimmed {
    case "NaN":
        return .nan
    case "Infinity", "+Infinity":
        return .infinity
    case "-Infinity":
        return -.infinity
    default:
        return Float(trimmed)
    }
}

/// Convert a Float's bit pattern to Int in an architecture-safe manner.
private func runtimeFloatBitsToInt(_ f: Float) -> Int {
    Int(bitPattern: UInt(f.bitPattern))
}

@_cdecl("kk_string_toLong")
public func kk_string_toLong(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int64(source) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(source)\""
        )
        return 0
    }
    return Int(truncatingIfNeeded: value)
}

@_cdecl("kk_string_toLongOrNull")
public func kk_string_toLongOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int64(source) else {
        return runtimeNullSentinelInt
    }
    return Int(truncatingIfNeeded: value)
}

@_cdecl("kk_string_toFloat")
public func kk_string_toFloat(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        runtimeSetThrown(outThrown, message: "NumberFormatException: empty String")
        return 0
    }

    guard let parsed = runtimeParseFloat(trimmed) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(trimmed)\""
        )
        return 0
    }
    return runtimeFloatBitsToInt(parsed)
}

@_cdecl("kk_string_toFloatOrNull")
public func kk_string_toFloatOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
    }

    guard let parsed = runtimeParseFloat(trimmed) else {
        return runtimeNullSentinelInt
    }
    return runtimeFloatBitsToInt(parsed)
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

// MARK: - String.indexOf(String, startIndex) / indexOfFirst / indexOfLast

@_cdecl("kk_string_indexOf_from")
public func kk_string_indexOf_from(_ strRaw: Int, _ otherRaw: Int, _ startIndex: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)

    let start = max(0, min(startIndex, source.count))
    if other.isEmpty {
        return start
    }
    if other.count > source.count - start {
        return -1
    }

    for offset in start ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        return offset
    }
    return -1
}

@_cdecl("kk_string_indexOfAny_chars")
public func kk_string_indexOfAny_chars(_ strRaw: Int, _ charsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let chars = runtimeArrayBox(from: charsRaw), !source.isEmpty, !chars.elements.isEmpty else {
        return -1
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let needles = chars.elements.compactMap { UnicodeScalar(kk_unbox_char($0)) }
    guard !needles.isEmpty else {
        return -1
    }
    for offset in start..<source.count {
        let scalar = source[offset]
        if needles.contains(where: { needle in
            if !ignoreCase { return scalar == needle }
            return String(scalar).caseInsensitiveCompare(String(needle)) == .orderedSame
        }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_indexOfAny_strings")
public func kk_string_indexOfAny_strings(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return -1
    }
    let needles = elements.map { runtimeStringScalars($0) }
    let clampedStart = max(0, min(startIndex, source.count))
    if needles.contains(where: \.isEmpty) {
        return clampedStart
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in start..<source.count {
        if needles.contains(where: { matches($0, at: offset) }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOfAny_chars")
public func kk_string_lastIndexOfAny_chars(_ strRaw: Int, _ charsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let chars = runtimeArrayBox(from: charsRaw), !source.isEmpty, !chars.elements.isEmpty else {
        return -1
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let needles = chars.elements.compactMap { UnicodeScalar(kk_unbox_char($0)) }
    guard !needles.isEmpty else {
        return -1
    }
    for offset in stride(from: start, through: 0, by: -1) {
        let scalar = source[offset]
        if needles.contains(where: { needle in
            if !ignoreCase { return scalar == needle }
            return String(scalar).caseInsensitiveCompare(String(needle)) == .orderedSame
        }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOfAny_strings")
public func kk_string_lastIndexOfAny_strings(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return -1
    }
    let needles = elements.map { runtimeStringScalars($0) }
    let clampedStart = min(startIndex, source.count)
    if needles.contains(where: \.isEmpty) {
        return clampedStart >= 0 ? clampedStart : -1
    }
    guard !source.isEmpty else {
        return -1
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in stride(from: start, through: 0, by: -1) {
        if needles.contains(where: { matches($0, at: offset) }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_findAnyOf")
public func kk_string_findAnyOf(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    let needles = elements.map { (raw: $0, scalars: runtimeStringScalars($0)) }
    let clampedStart = max(0, min(startIndex, source.count))
    if let emptyNeedle = needles.first(where: { $0.scalars.isEmpty }) {
        return kk_pair_new(clampedStart, emptyNeedle.raw)
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return runtimeNullSentinelInt
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in start..<source.count {
        for needle in needles where matches(needle.scalars, at: offset) {
            return kk_pair_new(offset, needle.raw)
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_findLastAnyOf")
public func kk_string_findLastAnyOf(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    let needles = elements.map { (raw: $0, scalars: runtimeStringScalars($0)) }
    let clampedStart = min(startIndex, source.count)
    if let emptyNeedle = needles.first(where: { $0.scalars.isEmpty }) {
        return clampedStart >= 0 ? kk_pair_new(clampedStart, emptyNeedle.raw) : runtimeNullSentinelInt
    }
    guard !source.isEmpty else {
        return runtimeNullSentinelInt
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return runtimeNullSentinelInt
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in stride(from: start, through: 0, by: -1) {
        for needle in needles where matches(needle.scalars, at: offset) {
            return kk_pair_new(offset, needle.raw)
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_indexOfFirst")
public func kk_string_indexOfFirst(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (index, scalar) in scalars.enumerated() {
        let charRaw = Int(scalar.value)
        var thrown = 0
        let result = lambda(closureRaw, charRaw, &thrown)
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "indexOfFirst predicate")
            return -1
        }
        if maybeUnbox(result) != 0 {
            return index
        }
    }
    return -1
}

@_cdecl("kk_string_indexOfLast")
public func kk_string_indexOfLast(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastIndex = -1
    for (index, scalar) in scalars.enumerated() {
        let charRaw = Int(scalar.value)
        var thrown = 0
        let result = lambda(closureRaw, charRaw, &thrown)
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "indexOfLast predicate")
            return -1
        }
        if maybeUnbox(result) != 0 {
            lastIndex = index
        }
    }
    return lastIndex
}

// MARK: - STDLIB-190: first / last / single / firstOrNull / lastOrNull

@_cdecl("kk_string_first")
public func kk_string_first(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        runtimeSetThrown(outThrown, message: "Char sequence is empty.")
        return 0
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_last")
public func kk_string_last(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        runtimeSetThrown(outThrown, message: "Char sequence is empty.")
        return 0
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_single")
public func kk_string_single(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        let msg = codeUnits.isEmpty
            ? "Char sequence is empty."
            : "Char sequence has more than one element."
        runtimeSetThrown(outThrown, message: msg)
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
    let scalars = runtimeStringScalars(strRaw)
    guard index >= 0, index < scalars.count else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(scalars[index].value))
}

// MARK: - STDLIB-187: isEmpty / isNotEmpty / isBlank / isNotBlank

@_cdecl("kk_string_isEmpty")
public func kk_string_isEmpty(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNotEmpty")
public func kk_string_isNotEmpty(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.isEmpty ? 0 : 1)
}

@_cdecl("kk_string_isBlank")
public func kk_string_isBlank(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNotBlank")
public func kk_string_isNotBlank(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
}

// MARK: - STDLIB-TEXT-EDGE-004: CharSequence.ifBlank(defaultValue)

@_cdecl("kk_string_ifBlank")
public func kk_string_ifBlank(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return strRaw
    }
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw("")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifBlank defaultValue"
        )
        return runtimeMakeStringRaw("")
    }
    return result
}

// MARK: - STDLIB-TEXT-EDGE-005: CharSequence.ifEmpty(defaultValue)

@_cdecl("kk_string_ifEmpty")
public func kk_string_ifEmpty(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard source.isEmpty else {
        return strRaw
    }
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw("")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifEmpty defaultValue"
        )
        return runtimeMakeStringRaw("")
    }
    return result
}

// MARK: - STDLIB-186: substringBefore / substringAfter / substringBeforeLast / substringAfterLast
//
// STDLIB-TEXT-FN-076: `String.substringBefore(delimiter, missingDelimiterValue)` is the
// public Kotlin signature. We expose four runtime helpers per direction (before/after
// and before-last/after-last), one for `String` delimiters and one for `Char`. Each
// accepts an optional `missingDelimiterValueRaw` boxed string; passing `0` means the
// Kotlin default (`this`) should be returned when no match is found.

@_cdecl("kk_string_substringBefore")
public func kk_string_substringBefore(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = kk_string_indexOf(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
}

@_cdecl("kk_string_substringBefore_char")
public func kk_string_substringBefore_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.firstIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_substringAfter")
public func kk_string_substringAfter(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = kk_string_indexOf(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    let delimScalars = runtimeStringScalars(delimiterRaw)
    let start = idx + delimScalars.count
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start...]))
}

@_cdecl("kk_string_substringAfter_char")
public func kk_string_substringAfter_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.firstIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[(idx + 1)...]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_substringBeforeLast")
public func kk_string_substringBeforeLast(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = kk_string_lastIndexOf(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
}

@_cdecl("kk_string_substringBeforeLast_char")
public func kk_string_substringBeforeLast_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.lastIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_substringAfterLast")
public func kk_string_substringAfterLast(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = kk_string_lastIndexOf(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    let delimScalars = runtimeStringScalars(delimiterRaw)
    let start = idx + delimScalars.count
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start...]))
}

@_cdecl("kk_string_substringAfterLast_char")
public func kk_string_substringAfterLast_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.lastIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[(idx + 1)...]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@inline(__always)
private func runtimeSubstringMissingDelimiterValue(
    sourceRaw: Int,
    source: String,
    missingDelimiterValueRaw: Int,
    caller: StaticString
) -> String {
    if missingDelimiterValueRaw == 0 || missingDelimiterValueRaw == sourceRaw {
        return source
    }
    return runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: caller)
}

@_cdecl("kk_string_replaceAfter")
public func kk_string_replaceAfter(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfter(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfter_char")
public func kk_string_replaceAfter_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfter(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfterLast")
public func kk_string_replaceAfterLast(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfterLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfterLast_char")
public func kk_string_replaceAfterLast_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfterLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBefore")
public func kk_string_replaceBefore(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBefore(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBefore_char")
public func kk_string_replaceBefore_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBefore(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBeforeLast")
public func kk_string_replaceBeforeLast(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBeforeLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBeforeLast_char")
public func kk_string_replaceBeforeLast_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBeforeLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
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

// MARK: - STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase

@_cdecl("kk_string_indexOf_ignoreCase")
public func kk_string_indexOf_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0

    if other.isEmpty {
        let start = max(0, min(startIndexRaw, source.unicodeScalars.count))
        return start
    }

    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)
    let start = max(0, min(startIndexRaw, sourceScalars.count))

    if otherScalars.count > sourceScalars.count - start {
        return -1
    }

    for offset in start ... (sourceScalars.count - otherScalars.count) {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches: Bool
        if ignoreCase {
            matches = zip(slice, otherScalars).allSatisfy {
                String($0).caseInsensitiveCompare(String($1)) == .orderedSame
            }
        } else {
            matches = slice.elementsEqual(otherScalars)
        }
        if matches { return offset }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOf_ignoreCase")
public func kk_string_lastIndexOf_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0

    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)

    if other.isEmpty {
        let start = max(0, min(startIndexRaw, sourceScalars.count))
        return start
    }
    if otherScalars.count > sourceScalars.count {
        return -1
    }

    let maxOffset = sourceScalars.count - otherScalars.count
    let start = max(0, min(startIndexRaw, maxOffset))

    var lastIndex = -1
    for offset in 0 ... start {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches: Bool
        if ignoreCase {
            matches = zip(slice, otherScalars).allSatisfy {
                String($0).caseInsensitiveCompare(String($1)) == .orderedSame
            }
        } else {
            matches = slice.elementsEqual(otherScalars)
        }
        if matches { lastIndex = offset }
    }
    return lastIndex
}

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: index=\(indexRaw), length=\(scalars.count)"
        )
        return 0
    }
    return Int(scalars[indexRaw].value)
}

@_cdecl("kk_string_compareTo_member")
public func kk_string_compareTo_member(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    return runtimeCompareStrings(lhs, rhs)
}

@_cdecl("kk_string_compareToIgnoreCase")
public func kk_string_compareToIgnoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    if ignoreCaseRaw == 0 {
        return runtimeCompareStrings(lhs, rhs)
    }
    let comparison = lhs.caseInsensitiveCompare(rhs)
    switch comparison {
    case .orderedAscending:
        return -1
    case .orderedDescending:
        return 1
    case .orderedSame:
        return 0
    }
}

// MARK: - STDLIB-TEXT-EDGE-009: CharSequence?.contentEquals

@_cdecl("kk_string_contentEquals")
public func kk_string_contentEquals(_ receiverRaw: Int, _ otherRaw: Int) -> Int {
    let receiverIsNull = (receiverRaw == runtimeNullSentinelInt)
    let otherIsNull = (otherRaw == runtimeNullSentinelInt)
    if receiverIsNull && otherIsNull {
        return kk_box_bool(1)
    }
    if receiverIsNull || otherIsNull {
        return kk_box_bool(0)
    }
    guard let receiverStr = runtimeStringFromRaw(receiverRaw),
          let otherStr = runtimeStringFromRaw(otherRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(receiverStr == otherStr ? 1 : 0)
}

@_cdecl("kk_string_contentEquals_ignoreCase")
public func kk_string_contentEquals_ignoreCase(_ receiverRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let receiverIsNull = (receiverRaw == runtimeNullSentinelInt)
    let otherIsNull = (otherRaw == runtimeNullSentinelInt)
    if receiverIsNull && otherIsNull {
        return kk_box_bool(1)
    }
    if receiverIsNull || otherIsNull {
        return kk_box_bool(0)
    }
    guard let receiverStr = runtimeStringFromRaw(receiverRaw),
          let otherStr = runtimeStringFromRaw(otherRaw) else {
        return kk_box_bool(0)
    }
    if ignoreCaseRaw == 0 {
        return kk_box_bool(receiverStr == otherStr ? 1 : 0)
    }
    return kk_box_bool(receiverStr.caseInsensitiveCompare(otherStr) == .orderedSame ? 1 : 0)
}

@_cdecl("kk_string_toBoolean")
public func kk_string_toBoolean(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0)
}

@_cdecl("kk_string_toBooleanStrict")
public func kk_string_toBooleanStrict(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    switch source {
    case "true":
        return kk_box_bool(1)
    case "false":
        return kk_box_bool(0)
    default:
        runtimeSetThrown(
            outThrown,
            message: "The string doesn't represent a boolean value: \(source)"
        )
        return 0
    }
}

@_cdecl("kk_string_toBooleanStrictOrNull")
public func kk_string_toBooleanStrictOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    switch source {
    case "true":
        return 1
    case "false":
        return 0
    default:
        return runtimeNullSentinelInt
    }
}

@_cdecl("kk_string_toShort")
public func kk_string_toShort(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int16(source) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("kk_string_toShortOrNull")
public func kk_string_toShortOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int16(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_toByte")
public func kk_string_toByte(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int8(source) else {
        runtimeSetThrown(
            outThrown,
            message: "NumberFormatException: For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("kk_string_toByteOrNull")
public func kk_string_toByteOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int8(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("kk_string_lines")
public func kk_string_lines(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringListRaw(runtimeNormalizedMultilineString(source))
}

@_cdecl("kk_string_lineSequence")
public func kk_string_lineSequence(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let lineRaws = runtimeNormalizedMultilineString(source).map(runtimeMakeStringRaw)
    let seq = RuntimeSequenceBox(steps: [.source(elements: lineRaws)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_string_trimStart")
public func kk_string_trimStart(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(String(source.drop { $0.isWhitespace }))
}

@_cdecl("kk_string_trimStart_predicate")
public func kk_string_trimStart_predicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringTrimWithPredicate(
        strRaw,
        fnPtr,
        closureRaw,
        outThrown,
        trimLeading: true,
        trimTrailing: false,
        context: "trimStart predicate"
    )
}

@_cdecl("kk_string_trimEnd")
public func kk_string_trimEnd(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(String(source.reversed().drop { $0.isWhitespace }.reversed()))
}

@_cdecl("kk_string_trimEnd_predicate")
public func kk_string_trimEnd_predicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringTrimWithPredicate(
        strRaw,
        fnPtr,
        closureRaw,
        outThrown,
        trimLeading: false,
        trimTrailing: true,
        context: "trimEnd predicate"
    )
}

@_cdecl("kk_string_toByteArray")
public func kk_string_toByteArray(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeListRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-581: Charset tag constants (mirrors Charsets.* singleton properties)
private enum CharsetTag: Int {
    case utf8 = 0
    case iso8859_1 = 1
    case usASCII = 2
    case utf16 = 3
    case utf16be = 4
    case utf16le = 5
    case utf32 = 6
    case utf32be = 7
    case utf32le = 8
}

@_cdecl("kk_charset_utf_8")
public func kk_charset_utf_8() -> Int { CharsetTag.utf8.rawValue }

@_cdecl("kk_charset_iso_8859_1")
public func kk_charset_iso_8859_1() -> Int { CharsetTag.iso8859_1.rawValue }

@_cdecl("kk_charset_us_ascii")
public func kk_charset_us_ascii() -> Int { CharsetTag.usASCII.rawValue }

@_cdecl("kk_charset_utf_16")
public func kk_charset_utf_16() -> Int { CharsetTag.utf16.rawValue }

@_cdecl("kk_charset_utf_16be")
public func kk_charset_utf_16be() -> Int { CharsetTag.utf16be.rawValue }

@_cdecl("kk_charset_utf_16le")
public func kk_charset_utf_16le() -> Int { CharsetTag.utf16le.rawValue }

@_cdecl("kk_charset_utf_32")
public func kk_charset_utf_32() -> Int { CharsetTag.utf32.rawValue }

@_cdecl("kk_charset_utf_32be")
public func kk_charset_utf_32be() -> Int { CharsetTag.utf32be.rawValue }

@_cdecl("kk_charset_utf_32le")
public func kk_charset_utf_32le() -> Int { CharsetTag.utf32le.rawValue }

// STDLIB-581: String.toByteArray(charset: Charset)
@_cdecl("kk_string_toByteArray_charset")
public func kk_string_toByteArray_charset(_ strRaw: Int, _ charsetTag: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        // Unknown charset — fall back to UTF-8
        return runtimeMakeListRaw(source.utf8.map(Int.init))
    }
    let bytes: [Int]
    switch tag {
    case .utf8:
        bytes = source.utf8.map(Int.init)
    case .iso8859_1:
        // ISO-8859-1: each UTF-16 code unit <= 0xFF maps 1:1; others replaced with '?'
        // Using utf16 (not unicodeScalars) to match Kotlin/JVM semantics where
        // non-BMP characters produce two surrogate code units, each replaced.
        bytes = source.utf16.map { unit in
            unit <= 0xFF ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .usASCII:
        // US-ASCII: each UTF-16 code unit <= 0x7F maps 1:1; others replaced with '?'
        bytes = source.utf16.map { unit in
            unit <= 0x7F ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .utf16:
        // UTF-16 with BOM (big-endian BOM then big-endian data, matching Kotlin/JVM)
        var result: [Int] = [0xFE, 0xFF] // BOM
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16be:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16le:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit & 0xFF))
            result.append(Int(unit >> 8))
        }
        bytes = result
    case .utf32:
        // UTF-32 with BOM (big-endian)
        var result: [Int] = [0x00, 0x00, 0xFE, 0xFF] // BOM
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32be:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32le:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int(v & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 24) & 0xFF))
        }
        bytes = result
    }
    return runtimeMakeListRaw(bytes)
}

// STDLIB-573: String.encodeToByteArray()
// Delegates to kk_string_toByteArray to avoid behavioral drift (single source of truth).
@_cdecl("kk_string_encodeToByteArray")
public func kk_string_encodeToByteArray(_ strRaw: Int) -> Int {
    kk_string_toByteArray(strRaw)
}

// STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
// Slices by UTF-16 code unit range to match Kotlin String indexing semantics.
@_cdecl("kk_string_encodeToByteArray_range")
public func kk_string_encodeToByteArray_range(_ strRaw: Int, _ startIndex: Int, _ endIndex: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let slice = runtimeUTF16Substring(source, startIndex: startIndex, endIndex: endIndex)
    return runtimeMakeListRaw(slice.utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-573: String.encodeToByteArray(charset) — charset-aware overload.
// Delegates to kk_string_toByteArray_charset which uses CharsetTag enum for
// consistent charset ID mapping across all charset-aware runtime functions.
@_cdecl("kk_string_encodeToByteArray_charset")
public func kk_string_encodeToByteArray_charset(_ strRaw: Int, _ charsetID: Int) -> Int {
    kk_string_toByteArray_charset(strRaw, charsetID)
}

private func runtimeByteArrayElements(from raw: Int) -> [Int]? {
    if let list = runtimeListBox(from: raw) {
        return list.elements
    }
    if let array = runtimeArrayBox(from: raw) {
        return array.elements
    }
    return nil
}

private func runtimeByteArrayRangeError(
    startIndex: Int,
    endIndex: Int,
    size: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "IndexOutOfBoundsException: startIndex=\(startIndex), endIndex=\(endIndex), size=\(size)"
    )
    return runtimeMakeStringRaw("")
}

private func runtimeDecodeUTF8Bytes(
    _ bytes: [UInt8],
    throwOnInvalidSequence: Bool,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if throwOnInvalidSequence {
        if let decoded = String(data: Data(bytes), encoding: .utf8) {
            return runtimeMakeStringRaw(decoded)
        }
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MalformedInputException: Input byte array has malformed UTF-8 sequence"
        )
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(String(decoding: bytes, as: UTF8.self))
}

private func runtimeDecodeByteArrayRange(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    throwOnInvalidSequence: Bool,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: String
) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid byte array handle \(arrRaw)")
    }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= elements.count else {
        return runtimeByteArrayRangeError(
            startIndex: startIndex,
            endIndex: endIndex,
            size: elements.count,
            outThrown: outThrown
        )
    }
    let bytes = elements[startIndex..<endIndex].map { UInt8(truncatingIfNeeded: $0) }
    return runtimeDecodeUTF8Bytes(
        bytes,
        throwOnInvalidSequence: throwOnInvalidSequence,
        outThrown: outThrown
    )
}

// STDLIB-574: ByteArray.decodeToString()
@_cdecl("kk_bytearray_decodeToString")
public func kk_bytearray_decodeToString(_ arrRaw: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString received invalid byte array handle \(arrRaw)")
    }
    // Use truncating conversion to match Kotlin's signed-byte semantics:
    // negative values (e.g. -1) become their unsigned equivalent (255).
    let bytes = elements.map { UInt8(truncatingIfNeeded: $0) }
    // Use String(decoding:as:) for UTF-8 replacement decoding: malformed
    // sequences produce U+FFFD instead of returning nil/empty.
    let decoded = String(decoding: bytes, as: UTF8.self)
    return runtimeMakeStringRaw(decoded)
}

// STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex)
@_cdecl("kk_bytearray_decodeToString_range")
public func kk_bytearray_decodeToString_range(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeDecodeByteArrayRange(
        arrRaw,
        startIndex,
        endIndex,
        throwOnInvalidSequence: false,
        outThrown: outThrown,
        caller: #function
    )
}

// STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, throwOnInvalidSequence)
@_cdecl("kk_bytearray_decodeToString_range_throw")
public func kk_bytearray_decodeToString_range_throw(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ throwOnInvalidSequence: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeDecodeByteArrayRange(
        arrRaw,
        startIndex,
        endIndex,
        throwOnInvalidSequence: throwOnInvalidSequence != 0,
        outThrown: outThrown,
        caller: #function
    )
}

// STDLIB-574: ByteArray.decodeToString(charset)
// Charset IDs follow CharsetTag: 0 = UTF-8, 1 = ISO-8859-1 (Latin-1), 2 = US-ASCII
@_cdecl("kk_bytearray_decodeToString_charset")
public func kk_bytearray_decodeToString_charset(_ arrRaw: Int, _ charsetId: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString_charset received invalid byte array handle \(arrRaw)")
    }
    let bytes = elements.map { UInt8(truncatingIfNeeded: $0) }
    let decoded: String
    switch charsetId {
    case 0: // Charsets.UTF_8
        decoded = String(decoding: bytes, as: UTF8.self)
    case 1: // Charsets.ISO_8859_1 (Latin-1)
        // ISO-8859-1: each byte maps directly to its Unicode code point (0x00..0xFF)
        decoded = String(bytes.map { Character(Unicode.Scalar($0)) })
    case 2: // Charsets.US_ASCII
        // ASCII: bytes > 127 become replacement character U+FFFD
        decoded = String(bytes.map { $0 <= 127 ? Character(Unicode.Scalar($0)) : "\u{FFFD}" })
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString_charset unsupported charset ID \(charsetId)")
    }
    return runtimeMakeStringRaw(decoded)
}

@_cdecl("kk_string_format")
public func kk_string_format(_ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let template = runtimeStringFromRawOrPanic(formatRaw, caller: #function)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.elements
        ?? runtimeListBox(from: argsArrayRaw)?.elements
        ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, arguments: arguments))
}

@_cdecl("kk_string_format_locale")
public func kk_string_format_locale(_ localeRaw: Int, _ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let locale: Locale?
    if localeRaw == runtimeNullSentinelInt {
        locale = nil
    } else {
        guard let box = runtimeLocaleBox(from: localeRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_string_format_locale received invalid Locale handle")
        }
        locale = box.locale
    }

    let template = runtimeStringFromRawOrPanic(formatRaw, caller: #function)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.elements
        ?? runtimeListBox(from: argsArrayRaw)?.elements
        ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, arguments: arguments, locale: locale))
}

@_cdecl("kk_string_trimIndent")
public func kk_string_trimIndent(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeTrimIndent(source))
}

@_cdecl("kk_string_trimMargin_default")
public func kk_string_trimMargin_default(_ strRaw: Int) -> Int {
    kk_string_trimMargin(strRaw, runtimeDefaultTrimMarginPrefixRaw)
}

@_cdecl("kk_string_trimMargin")
public func kk_string_trimMargin(_ strRaw: Int, _ marginPrefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let marginPrefix = runtimeStringFromRaw(marginPrefixRaw) ?? "|"
    return runtimeMakeStringRaw(runtimeTrimMargin(source, marginPrefix: marginPrefix))
}

// MARK: - STDLIB-191: prependIndent / replaceIndent

private let runtimeDefaultPrependIndentRaw = runtimeMakeStringRaw(" ")
private let runtimeDefaultReplaceIndentRaw = runtimeMakeStringRaw("")

@_cdecl("kk_string_prependIndent_default")
public func kk_string_prependIndent_default(_ strRaw: Int) -> Int {
    kk_string_prependIndent(strRaw, runtimeDefaultPrependIndentRaw)
}

@_cdecl("kk_string_replaceIndent_default")
public func kk_string_replaceIndent_default(_ strRaw: Int) -> Int {
    kk_string_replaceIndent(strRaw, runtimeDefaultReplaceIndentRaw)
}

@_cdecl("kk_string_prependIndent")
public func kk_string_prependIndent(_ strRaw: Int, _ indentRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let indent = runtimeStringFromRaw(indentRaw) ?? " "
    return runtimeMakeStringRaw(runtimePrependIndent(source, indent: indent))
}

@_cdecl("kk_string_replaceIndent")
public func kk_string_replaceIndent(_ strRaw: Int, _ newIndentRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let newIndent = runtimeStringFromRawOrPanic(newIndentRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeReplaceIndent(source, newIndent: newIndent))
}

@_cdecl("kk_string_replaceIndentByMargin")
public func kk_string_replaceIndentByMargin(_ strRaw: Int, _ newIndentRaw: Int, _ marginPrefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let newIndent = runtimeStringFromRaw(newIndentRaw) ?? ""
    let marginPrefix = runtimeStringFromRaw(marginPrefixRaw) ?? "|"
    return runtimeMakeStringRaw(
        runtimeReplaceIndentByMargin(source, newIndent: newIndent, marginPrefix: marginPrefix)
    )
}

// MARK: - STDLIB-316: String.chunked / String.windowed

@_cdecl("kk_string_chunked")
public func kk_string_chunked(_ strRaw: Int, _ size: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard size > 0 else {
        return runtimeMakeStringListRaw([])
    }
    let scalars = Array(source.unicodeScalars)
    var chunks: [String] = []
    var i = 0
    while i < scalars.count {
        let end = Swift.min(i + size, scalars.count)
        chunks.append(runtimeStringFromScalars(scalars[i ..< end]))
        i = end
    }
    return runtimeMakeStringListRaw(chunks)
}

@_cdecl("kk_string_chunked_sequence")
public func kk_string_chunked_sequence(_ strRaw: Int, _ size: Int) -> Int {
    let chunksRaw = kk_string_chunked(strRaw, size)
    return kk_list_asSequence(chunksRaw)
}

@_cdecl("kk_string_chunked_sequence_transform")
public func kk_string_chunked_sequence_transform(
    _ strRaw: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let chunkSize = max(1, size)
    let scalars = Array(source.unicodeScalars)
    let estimatedChunks = scalars.isEmpty ? 0 : (scalars.count + chunkSize - 1) / chunkSize
    var results: [Int] = []
    results.reserveCapacity(estimatedChunks)
    var index = 0
    while index < scalars.count {
        let end = Swift.min(index + chunkSize, scalars.count)
        let chunkRaw = runtimeMakeStringRaw(runtimeStringFromScalars(scalars[index ..< end]))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        results.append(maybeUnbox(transformed))
        index = end
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

@_cdecl("kk_string_windowed_default")
public func kk_string_windowed_default(_ strRaw: Int, _ size: Int) -> Int {
    return kk_string_windowed(strRaw, size, 1)
}

@_cdecl("kk_string_windowed")
public func kk_string_windowed(_ strRaw: Int, _ size: Int, _ step: Int) -> Int {
    // Validate handle before any early return so invalid handles always trap
    // consistently with other string runtime entry points.
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    // Return an empty list for non-positive size/step to preserve the
    // original 2-arg overload semantics (Kotlin throws IllegalArgumentException,
    // but this runtime returns empty for resilience).
    guard size > 0, step > 0 else {
        return runtimeMakeStringListRaw([])
    }
    let scalars = Array(source.unicodeScalars)
    var windows: [String] = []
    var i = 0
    while i + size <= scalars.count {
        windows.append(runtimeStringFromScalars(scalars[i ..< i + size]))
        i += step
    }
    return runtimeMakeStringListRaw(windows)
}

@_cdecl("kk_string_windowed_partial")
public func kk_string_windowed_partial(_ strRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    // Clamp non-positive size/step to 1, matching list windowed_partial behaviour (kk_list_windowed_partial).
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let scalars = Array(source.unicodeScalars)
    let partial = partialWindows != 0
    var windows: [String] = []
    var i = 0
    while i < scalars.count {
        let end = min(i + clampedSize, scalars.count)
        if !partial && end - i < clampedSize { break }
        windows.append(runtimeStringFromScalars(scalars[i ..< end]))
        i += clampedStep
    }
    return runtimeMakeStringListRaw(windows)
}

@_cdecl("kk_string_windowedSequence_partial")
public func kk_string_windowedSequence_partial(_ strRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let scalars = Array(source.unicodeScalars)
    let partial = partialWindows != 0
    var windows: [Int] = []
    var i = 0
    while i < scalars.count {
        let end = min(i + clampedSize, scalars.count)
        if !partial && end - i < clampedSize { break }
        windows.append(runtimeMakeStringRaw(runtimeStringFromScalars(scalars[i ..< end])))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: windows)]))
}

@_cdecl("kk_string_windowedSequence_transform")
public func kk_string_windowedSequence_transform(
    _ strRaw: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let scalars = Array(source.unicodeScalars)
    let partial = partialWindows != 0
    var results: [Int] = []
    var i = 0
    while i < scalars.count {
        let end = min(i + clampedSize, scalars.count)
        if !partial && end - i < clampedSize { break }
        let windowRaw = runtimeMakeStringRaw(runtimeStringFromScalars(scalars[i ..< end]))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: windowRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        results.append(maybeUnbox(transformed))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: results)]))
}

// MARK: - STDLIB-318: String.commonPrefixWith / commonSuffixWith

@_cdecl("kk_string_commonPrefixWith")
public func kk_string_commonPrefixWith(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let s = runtimeStringFromRaw(strRaw) ?? ""
    let other = runtimeStringFromRaw(otherRaw) ?? ""
    var prefix = ""
    for (a, b) in zip(s, other) {
        if a == b { prefix.append(a) } else { break }
    }
    return runtimeMakeStringRaw(prefix)
}

@_cdecl("kk_string_commonSuffixWith")
public func kk_string_commonSuffixWith(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let s = runtimeStringFromRaw(strRaw) ?? ""
    let other = runtimeStringFromRaw(otherRaw) ?? ""
    var suffix = ""
    for (a, b) in zip(s.reversed(), other.reversed()) {
        if a == b { suffix.insert(a, at: suffix.startIndex) } else { break }
    }
    return runtimeMakeStringRaw(suffix)
}

// MARK: - STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)

@_cdecl("kk_string_commonPrefixWith_ignoreCase")
public func kk_string_commonPrefixWith_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let s = runtimeStringFromRaw(strRaw) ?? ""
    let other = runtimeStringFromRaw(otherRaw) ?? ""
    let ignoreCase = ignoreCaseRaw != 0
    var prefix = ""
    for (a, b) in zip(s, other) {
        if ignoreCase
            ? String(a).caseInsensitiveCompare(String(b)) == .orderedSame
            : a == b
        {
            prefix.append(a)
        } else {
            break
        }
    }
    return runtimeMakeStringRaw(prefix)
}

@_cdecl("kk_string_commonSuffixWith_ignoreCase")
public func kk_string_commonSuffixWith_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let s = runtimeStringFromRaw(strRaw) ?? ""
    let other = runtimeStringFromRaw(otherRaw) ?? ""
    let ignoreCase = ignoreCaseRaw != 0
    var reversed: [Character] = []
    for (a, b) in zip(s.reversed(), other.reversed()) {
        if ignoreCase
            ? String(a).caseInsensitiveCompare(String(b)) == .orderedSame
            : a == b
        {
            reversed.append(a)
        } else {
            break
        }
    }
    return runtimeMakeStringRaw(String(reversed.reversed()))
}

// MARK: - STDLIB-316: String.zipWithNext()

@_cdecl("kk_string_zipWithNext")
public func kk_string_zipWithNext(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    guard source.unicodeScalars.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let scalars = Array(source.unicodeScalars)
    var pairs: [Int] = []
    for i in 0 ..< scalars.count - 1 {
        let a = kk_box_char(Int(scalars[i].value))
        let b = kk_box_char(Int(scalars[i + 1].value))
        pairs.append(kk_pair_new(a, b))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_string_zipWithNextTransform")
public func kk_string_zipWithNextTransform(_ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let scalars = Array(source.unicodeScalars)
    guard scalars.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var results: [Int] = []
    results.reserveCapacity(scalars.count - 1)
    for i in 0 ..< scalars.count - 1 {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: kk_box_char(Int(scalars[i].value)),
            rhs: kk_box_char(Int(scalars[i + 1].value)),
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return 0
        }
        results.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// MARK: - STDLIB-192: equals(other, ignoreCase)

@_cdecl("kk_string_equalsIgnoreCase")
public func kk_string_equalsIgnoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    if otherRaw == runtimeNullSentinelInt {
        return kk_box_bool(0)
    }
    let cmp = kk_string_compareToIgnoreCase(strRaw, otherRaw, ignoreCaseRaw)
    return kk_box_bool(cmp == 0 ? 1 : 0)
}

// MARK: - STDLIB-188: replaceFirst / replaceRange

@_cdecl("kk_string_replaceFirst")
public func kk_string_replaceFirst(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    guard let range = source.range(of: oldValue) else {
        return runtimeMakeStringRaw(source)
    }
    var result = source
    result.replaceSubrange(range, with: newValue)
    return runtimeMakeStringRaw(result)
}

@_cdecl("kk_string_replaceRange")
public func kk_string_replaceRange(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, message: "Invalid range for replaceRange")
        return 0
    }
    let first = range.first
    let last = range.last
    let length = scalars.count
    if first < 0 || first > length || last < -1 || last >= length || first > last + 1 {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: start=\(first), end=\(last + 1), length=\(length)"
        )
        return 0
    }
    let endIndex = last + 1
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let before = runtimeStringFromScalars(scalars[0 ..< first])
    let after = runtimeStringFromScalars(scalars[endIndex...])
    return runtimeMakeStringRaw(before + replacement + after)
}

// MARK: - STDLIB-TEXT-EDGE-008: removeRange

@_cdecl("kk_string_removeRange")
public func kk_string_removeRange(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let end = endRaw
    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: start=\(start), end=\(end), length=\(length)"
        )
        return 0
    }
    let before = runtimeStringFromScalars(scalars[0 ..< start])
    let after = runtimeStringFromScalars(scalars[end...])
    return runtimeMakeStringRaw(before + after)
}

@_cdecl("kk_string_removeRange_range")
public func kk_string_removeRange_range(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, message: "Invalid range for removeRange")
        return 0
    }
    return kk_string_removeRange(strRaw, range.first, range.last + 1, outThrown)
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
    let isObjectPointer = runtimeStorage.withGCLock { state in
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

private func runtimeSplitString(_ source: String, delimiter: String, limit: Int = 0) -> [String] {
    if source.isEmpty {
        return [""]
    }

    var result: [String] = []
    var cursor = source.startIndex
    while true {
        // When limit > 0 and we have already collected (limit - 1) parts,
        // append the remainder as the last element and stop.
        if limit > 0 && result.count == limit - 1 {
            result.append(String(source[cursor...]))
            return result
        }
        guard let match = source.range(of: delimiter, range: cursor ..< source.endIndex) else {
            result.append(String(source[cursor...]))
            return result
        }
        result.append(String(source[cursor ..< match.lowerBound]))
        cursor = match.upperBound
    }
}

private func runtimeSplitStringLimit(
    _ source: String,
    delimiter: String,
    ignoreCase: Bool,
    limit: Int
) -> [String] {
    if source.isEmpty {
        return [""]
    }

    let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
    var result: [String] = []
    var cursor = source.startIndex
    while true {
        if limit > 0, result.count == limit - 1 {
            result.append(String(source[cursor...]))
            return result
        }
        guard let match = source.range(of: delimiter, options: options, range: cursor ..< source.endIndex) else {
            result.append(String(source[cursor...]))
            return result
        }
        result.append(String(source[cursor ..< match.lowerBound]))
        cursor = match.upperBound
    }
}

private func runtimeCompareStrings(_ lhs: String, _ rhs: String) -> Int {
    let lhsScalars = Array(lhs.unicodeScalars)
    let rhsScalars = Array(rhs.unicodeScalars)
    let sharedCount = Swift.min(lhsScalars.count, rhsScalars.count)
    for index in 0 ..< sharedCount {
        let difference = Int(lhsScalars[index].value) - Int(rhsScalars[index].value)
        if difference != 0 {
            return difference
        }
    }
    return lhsScalars.count - rhsScalars.count
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

private func runtimePrependIndent(_ source: String, indent: String) -> String {
    let lines = runtimeNormalizedMultilineString(source)
    return lines.map { indent + $0 }.joined(separator: "\n")
}

private func runtimeReplaceIndent(_ source: String, newIndent: String) -> String {
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
        return newIndent + String(line.dropFirst(minimumIndent))
    }.joined(separator: "\n")
}

private func runtimeReplaceIndentByMargin(
    _ source: String,
    newIndent: String,
    marginPrefix: String
) -> String {
    if marginPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
        fatalError("IllegalArgumentException: marginPrefix must be non-blank string.")
    }
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    return lines.map { line in
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(marginPrefix) else {
            return line
        }
        return newIndent + String(trimmedLeading.dropFirst(marginPrefix.count))
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

/// Fail-fast variant that panics on invalid string handles instead of returning nil.
/// Use this instead of `runtimeStringFromRaw(...) ?? ""` to distinguish
/// invalid handles from legitimately empty strings.
/// Internal so that other runtime files (e.g. RuntimeSequence.swift) can share
/// this helper without duplicating the safety check and panic message.
func runtimeStringFromRawOrPanic(_ raw: Int, caller: StaticString) -> String {
    if let s = runtimeStringFromRaw(raw) {
        return s
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
}

private func runtimeCharacterFromRaw(_ raw: Int) -> String {
    guard let scalar = runtimeUnicodeScalarFromRaw(raw) else {
        return "?"
    }
    return String(scalar)
}

private func runtimeStringReplaceAfter(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        return replacement
    }
    guard let range = source.range(of: delimiter) else {
        return missingDelimiterValue
    }
    return String(source[..<range.upperBound]) + replacement
}

private func runtimeStringReplaceAfterLast(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        guard !source.isEmpty else {
            return missingDelimiterValue
        }
        return runtimeStringFromScalars(source.unicodeScalars.dropLast()) + replacement
    }
    guard let range = source.range(of: delimiter, options: .backwards) else {
        return missingDelimiterValue
    }
    return String(source[..<range.upperBound]) + replacement
}

private func runtimeStringReplaceBefore(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        return replacement + source
    }
    guard let range = source.range(of: delimiter) else {
        return missingDelimiterValue
    }
    return replacement + String(source[range.lowerBound...])
}

private func runtimeStringReplaceBeforeLast(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        guard let lastScalar = source.unicodeScalars.last else {
            return missingDelimiterValue
        }
        return replacement + String(lastScalar)
    }
    guard let range = source.range(of: delimiter, options: .backwards) else {
        return missingDelimiterValue
    }
    return replacement + String(source[range.lowerBound...])
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
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

private func runtimeMakeArrayRaw(_ values: [Int]) -> Int {
    let box = RuntimeArrayBox(length: values.count)
    for (index, value) in values.enumerated() {
        box.elements[index] = value
    }
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
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

private func runtimePropagateThrownOrTrap(
    _ thrown: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    context: String
) {
    guard thrown != 0 else { return }
    guard let outThrown else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(context) threw")
    }
    outThrown.pointee = thrown
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

private func runtimeFormatString(_ template: String, arguments: [Int], locale: Locale? = nil) -> String {
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
            result += runtimeRenderFormattedArgument(argument, specifier: specifier, locale: locale)
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

private func runtimeRenderFormattedArgument(
    _ argument: Int,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?
) -> String {
    switch specifier.normalizedConversion {
    case "s":
        let value = runtimeFormatStringValue(argument, specifier: specifier, locale: locale)
        return runtimeApplyStringWidth(value, specifier: specifier)
    case "b":
        let value = runtimeFormatBooleanValue(argument)
        let normalized = specifier.conversion.isUppercase
            ? runtimeFormatUppercase(value, locale: locale)
            : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    case "d", "i":
        let value = Int64(runtimeFormatIntegerValue(argument))
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
    case "x", "o":
        let value = UInt64(bitPattern: Int64(runtimeFormatIntegerValue(argument)))
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
    case "f", "e", "g":
        let value = runtimeFormatDoubleValue(argument)
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
    case "c":
        let value = runtimeFormatCharacterValue(argument)
        let normalized = specifier.conversion.isUppercase
            ? runtimeFormatUppercase(value, locale: locale)
            : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    default:
        return runtimeApplyStringWidth(
            runtimeFormatStringValue(argument, specifier: specifier, locale: locale),
            specifier: specifier
        )
    }
}

private func runtimeFormatStringValue(
    _ argument: Int,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?
) -> String {
    var value = runtimeElementToString(argument)
    if let precision = specifier.precision, value.count > precision {
        value = String(value.prefix(precision))
    }
    if specifier.conversion.isUppercase {
        value = runtimeFormatUppercase(value, locale: locale)
    }
    return value
}

private func runtimeFormatUppercase(_ value: String, locale: Locale?) -> String {
    if let locale {
        return value.uppercased(with: locale)
    }
    return value.uppercased()
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
    runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
}

// MARK: - STDLIB-319: String.toBigDecimal() / String.toBigInteger()

/// BigDecimal and BigInteger are represented as boxed strings in KSwiftK.
/// The runtime validates the format and stores the string representation.
final class RuntimeBigNumberBox {
    let value: String
    let kind: BigNumberKind

    enum BigNumberKind { case decimal, integer }

    init(value: String, kind: BigNumberKind) {
        self.value = value
        self.kind = kind
    }
}

/// Locale-independent validation for BigDecimal format matching Kotlin/Java:
/// `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?`
///
/// Note: We intentionally avoid `Decimal(string:)` or `NumberFormatter` because
/// Foundation's decimal parsing is locale-sensitive (e.g., decimal separator may
/// vary by locale). Instead, this hand-written parser validates against a fixed
/// POSIX-style grammar that matches Kotlin/JVM BigDecimal semantics.
private func isValidBigDecimalFormat(_ s: String) -> Bool {
    var i = s.startIndex
    guard i < s.endIndex else { return false }
    // Optional leading sign
    if s[i] == "+" || s[i] == "-" {
        i = s.index(after: i)
        guard i < s.endIndex else { return false }
    }
    // Must have at least one digit before or after the decimal point
    let digitStart = i
    while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
    let hasIntPart = i > digitStart
    var hasFracPart = false
    if i < s.endIndex, s[i] == "." {
        i = s.index(after: i)
        let fracStart = i
        while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
        hasFracPart = i > fracStart
    }
    guard hasIntPart || hasFracPart else { return false }
    // Optional exponent
    if i < s.endIndex, s[i] == "e" || s[i] == "E" {
        i = s.index(after: i)
        guard i < s.endIndex else { return false }
        if s[i] == "+" || s[i] == "-" {
            i = s.index(after: i)
            guard i < s.endIndex else { return false }
        }
        let expStart = i
        while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
        guard i > expStart else { return false }
    }
    return i == s.endIndex
}

@_cdecl("kk_string_toBigDecimal")
public func kk_string_toBigDecimal(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_string_toBigDecimal received invalid string handle")
    }
    // No whitespace trimming: Kotlin/JVM throws NumberFormatException on
    // leading/trailing whitespace, so we validate the raw string as-is.
    guard isValidBigDecimalFormat(str) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NumberFormatException: For input string: \"\(str)\"")
        return 0
    }
    let box = RuntimeBigNumberBox(value: str, kind: .decimal)
    return registerRuntimeObject(box)
}

@_cdecl("kk_string_toBigInteger")
public func kk_string_toBigInteger(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_string_toBigInteger received invalid string handle")
    }
    // Validate integer format: [+-]?\d+ (optional single leading sign, then digits).
    // No whitespace trimming: Kotlin/JVM throws NumberFormatException on
    // leading/trailing whitespace, so we validate the raw string as-is.
    var idx = str.startIndex
    guard idx < str.endIndex else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NumberFormatException: For input string: \"\(str)\"")
        return 0
    }
    if str[idx] == "+" || str[idx] == "-" {
        idx = str.index(after: idx)
    }
    let digitStart = idx
    while idx < str.endIndex, str[idx] >= "0", str[idx] <= "9" {
        idx = str.index(after: idx)
    }
    let isValid = idx > digitStart && idx == str.endIndex
    guard isValid else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NumberFormatException: For input string: \"\(str)\"")
        return 0
    }
    let box = RuntimeBigNumberBox(value: str, kind: .integer)
    return registerRuntimeObject(box)
}

@_cdecl("kk_bignum_toString")
public func kk_bignum_toString(_ numRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: numRaw),
          let box = tryCast(ptr, to: RuntimeBigNumberBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bignum_toString received invalid BigNumber handle")
    }
    return runtimeMakeStringRaw(box.value)
}

// MARK: - STDLIB-HOF-023: Advanced String Higher-Order Functions

@_cdecl("kk_string_mapIndexed")
public func kk_string_mapIndexed(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    var mappedElements: [Int] = []
    for (index, scalar) in scalars.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: index,
            rhs: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        mappedElements.append(result)
    }
    return runtimeMakeListRaw(mappedElements)
}

@_cdecl("kk_string_mapNotNull")
public func kk_string_mapNotNull(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    var mappedElements: [Int] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != runtimeNullSentinelInt {
            mappedElements.append(result)
        }
    }
    return runtimeMakeListRaw(mappedElements)
}

@_cdecl("kk_string_firstNotNullOf")
public func kk_string_firstNotNullOf(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        if result != 0, let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "NoSuchElementException: No element of the char sequence was transformed to a non-null value."
    )
    return 0
}

@_cdecl("kk_string_firstNotNullOfOrNull")
public func kk_string_firstNotNullOfOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
        if result != 0, let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_reduceRightIndexed")
public func kk_string_reduceRightIndexed(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: "Empty char sequence can't be reduced."),
            outThrown
        )
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: Int(scalars[index].value),
            arg3: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceRightIndexedOrNull")
public func kk_string_reduceRightIndexedOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return runtimeNullSentinelInt
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: Int(scalars[index].value),
            arg3: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceRightOrNull")
public func kk_string_reduceRightOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return runtimeNullSentinelInt
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: Int(scalars[index].value),
            rhs: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_sumBy")
public func kk_string_sumBy(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    var total = 0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_string_sumByDouble")
public func kk_string_sumByDouble(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    var total = 0.0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        total += kk_bits_to_double(result)
    }
    return kk_double_to_bits(total)
}

@_cdecl("kk_string_filterIndexed")
public func kk_string_filterIndexed(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var filtered: [UnicodeScalar] = []
    for (index, scalar) in scalars.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: index,
            rhs: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_filterNot")
public func kk_string_filterNot(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var filtered: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_takeWhile")
public func kk_string_takeWhile(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var taken: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { break }
        taken.append(scalar)
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(taken))
}

@_cdecl("kk_string_dropWhile")
public func kk_string_dropWhile(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var dropIndex = 0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { break }
        dropIndex += 1
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(Array(scalars.dropFirst(dropIndex))))
}

@_cdecl("kk_string_splitToSequence")
public func kk_string_splitToSequence(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)

    if delimiter.isEmpty {
        let singleElement = runtimeMakeStringRaw(source)
        let seq = RuntimeSequenceBox(steps: [.source(elements: [singleElement])])
        return registerRuntimeObject(seq)
    }

    let splitStrings = runtimeSplitString(source, delimiter: delimiter).map { runtimeMakeStringRaw($0) }
    let seq = RuntimeSequenceBox(steps: [.source(elements: splitStrings)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_string_joinToString")
public func kk_string_joinToString(
    _ strListRaw: Int, _ separatorRaw: Int, _ prefixRaw: Int, _ postfixRaw: Int
) -> Int {
    guard let list = runtimeListBox(from: strListRaw) else {
        return runtimeMakeStringRaw("")
    }

    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""

    let strings = list.elements.compactMap { extractString(from: UnsafeMutableRawPointer(bitPattern: $0)) }
    let result = prefix + strings.joined(separator: separator) + postfix
    return runtimeMakeStringRaw(result)
}

@_cdecl("kk_string_find")
public func kk_string_find(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeNullSentinelInt }
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if result != 0 { return kk_box_char(Int(scalar.value)) }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_findLast")
public func kk_string_findLast(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeNullSentinelInt }
    var foundChar: UnicodeScalar?
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if result != 0 { foundChar = scalar }
    }
    if let char = foundChar {
        return kk_box_char(Int(char.value))
    }
    return runtimeNullSentinelInt
}

// MARK: - STDLIB-partition: String.partition(predicate)

@_cdecl("kk_string_partition")
public func kk_string_partition(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else {
        let first = runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function))
        let second = runtimeMakeStringRaw("")
        return kk_pair_new(first, second)
    }
    var matched: [UnicodeScalar] = []
    var unmatched: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return kk_pair_new(runtimeMakeStringRaw(""), runtimeMakeStringRaw(""))
        }
        if maybeUnbox(result) != 0 {
            matched.append(scalar)
        } else {
            unmatched.append(scalar)
        }
    }
    let first = runtimeMakeStringRaw(runtimeStringFromScalars(matched))
    let second = runtimeMakeStringRaw(runtimeStringFromScalars(unmatched))
    return kk_pair_new(first, second)
}
