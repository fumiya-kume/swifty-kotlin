import Foundation

private func runtimeUnicodeScalar(_ value: Int) -> UnicodeScalar? {
    UnicodeScalar(value)
}

@_cdecl("kk_char_isDigit")
public func kk_char_isDigit(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(CharacterSet.decimalDigits.contains(scalar) ? 1 : 0)
}

@_cdecl("kk_char_isLetter")
public func kk_char_isLetter(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(CharacterSet.letters.contains(scalar) ? 1 : 0)
}

@_cdecl("kk_char_isLetterOrDigit")
public func kk_char_isLetterOrDigit(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    let isLetterOrDigit = CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
    return kk_box_bool(isLetterOrDigit ? 1 : 0)
}

@_cdecl("kk_char_isUpperCase")
public func kk_char_isUpperCase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(CharacterSet.uppercaseLetters.contains(scalar) ? 1 : 0)
}

@_cdecl("kk_char_isLowerCase")
public func kk_char_isLowerCase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(CharacterSet.lowercaseLetters.contains(scalar) ? 1 : 0)
}

@_cdecl("kk_char_isWhitespace")
public func kk_char_isWhitespace(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(scalar.properties.isWhitespace ? 1 : 0)
}

@_cdecl("kk_char_uppercase")
public func kk_char_uppercase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return charRuntimeMakeStringRaw("\u{FFFD}")
    }
    return charRuntimeMakeStringRaw(String(scalar).uppercased())
}

@_cdecl("kk_char_lowercase")
public func kk_char_lowercase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return charRuntimeMakeStringRaw("\u{FFFD}")
    }
    return charRuntimeMakeStringRaw(String(scalar).lowercased())
}

@_cdecl("kk_char_titlecase")
public func kk_char_titlecase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return charRuntimeMakeStringRaw("\u{FFFD}")
    }
    let titlecased = scalar.properties.titlecaseMapping
    return charRuntimeMakeStringRaw(titlecased)
}

@_cdecl("kk_char_digitToInt")
public func kk_char_digitToInt(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let scalar = runtimeUnicodeScalar(value) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Char is not a digit")
        return 0
    }
    if let digitValue = charBase10DigitValue(scalar) {
        return digitValue
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Char \(scalar) is not a digit")
    return 0
}

@_cdecl("kk_char_digitToIntOrNull")
public func kk_char_digitToIntOrNull(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value),
          let digitValue = charBase10DigitValue(scalar)
    else {
        return runtimeNullSentinelInt
    }
    return digitValue
}

// Char arithmetic operators

/// operator fun Char.minus(other: Char): Int
/// Returns the difference of the Unicode code points of two Char values.
@_cdecl("kk_char_minus")
public func kk_char_minus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    let lhs = kk_unbox_char(lhsRaw)
    let rhs = kk_unbox_char(rhsRaw)
    return lhs - rhs
}

// New numeric conversion functions
@_cdecl("kk_char_toInt")
public func kk_char_toInt(_ value: Int) -> Int {
    // Return Unicode code point (deprecated but for compatibility)
    return value
}

@_cdecl("kk_char_toDouble")
public func kk_char_toDouble(_ value: Int) -> Int {
    // Encode the Double payload using the runtime's bit-level ABI.
    kk_double_to_bits(Double(value))
}

@_cdecl("kk_char_toIntOrNull")
public func kk_char_toIntOrNull(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value),
          let digitValue = charBase10DigitValue(scalar)
    else {
        return runtimeNullSentinelInt
    }
    return digitValue
}

@_cdecl("kk_char_toDoubleOrNull")
public func kk_char_toDoubleOrNull(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value),
          let digitValue = charBase10DigitValue(scalar)
    else {
        return runtimeNullSentinelInt
    }
    return kk_double_to_bits(Double(digitValue))
}

// Code point and Unicode properties
@_cdecl("kk_char_code")
public func kk_char_code(_ value: Int) -> Int {
    // Return Unicode code point
    return value
}

@_cdecl("kk_char_category")
public func kk_char_category(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return -1 // Invalid character
    }
    // Map Unicode general category to enum values
    let category = scalar.properties.generalCategory
    return charCategoryToInt(category)
}

@_cdecl("kk_char_directionality")
public func kk_char_directionality(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else {
        return -1 // Invalid character
    }
    return charDirectionalityToInt(scalar)
}

@_cdecl("kk_char_isSurrogate")
public func kk_char_isSurrogate(_ value: Int) -> Int {
    return kk_box_bool((value >= 0xD800 && value <= 0xDFFF) ? 1 : 0)
}

@_cdecl("kk_char_isHighSurrogate")
public func kk_char_isHighSurrogate(_ value: Int) -> Int {
    return kk_box_bool((value >= 0xD800 && value <= 0xDBFF) ? 1 : 0)
}

@_cdecl("kk_char_isLowSurrogate")
public func kk_char_isLowSurrogate(_ value: Int) -> Int {
    return kk_box_bool((value >= 0xDC00 && value <= 0xDFFF) ? 1 : 0)
}

@_cdecl("kk_char_isISOControl")
public func kk_char_isISOControl(_ value: Int) -> Int {
    return kk_box_bool((value <= 0x1F || (value >= 0x7F && value <= 0x9F)) ? 1 : 0)
}

@_cdecl("kk_char_isTitleCase")
public func kk_char_isTitleCase(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value) else { return kk_box_bool(0) }
    return kk_box_bool(scalar.properties.generalCategory == .titlecaseLetter ? 1 : 0)
}

private func charBase10DigitValue(_ scalar: UnicodeScalar) -> Int? {
    if scalar.value >= 0x30, scalar.value <= 0x39 {
        return Int(scalar.value - 0x30)
    }
    if CharacterSet.decimalDigits.contains(scalar) {
        let numericValue = scalar.properties.numericValue
        if let value = numericValue, value >= 0, value <= 9, value == value.rounded() {
            return Int(value)
        }
    }
    return nil
}

private func charCategoryToInt(_ category: Unicode.GeneralCategory) -> Int {
    // Map Unicode.GeneralCategory to Kotlin CharCategory enum values
    switch category {
    case .uppercaseLetter: return 0  // UPPERCASE_LETTER
    case .lowercaseLetter: return 1  // LOWERCASE_LETTER
    case .titlecaseLetter: return 2  // TITLECASE_LETTER
    case .modifierLetter: return 3   // MODIFIER_LETTER
    case .otherLetter: return 4      // OTHER_LETTER
    case .nonspacingMark: return 5   // NON_SPACING_MARK
    case .spacingMark: return 6  // COMBINING_SPACING_MARK
    case .enclosingMark: return 7    // ENCLOSING_MARK
    case .decimalNumber: return 8    // DECIMAL_DIGIT_NUMBER
    case .letterNumber: return 9     // LETTER_NUMBER
    case .otherNumber: return 10     // OTHER_NUMBER
    case .connectorPunctuation: return 11  // CONNECTOR_PUNCTUATION
    case .dashPunctuation: return 12  // DASH_PUNCTUATION
    case .openPunctuation: return 13 // OPEN_PUNCTUATION
    case .closePunctuation: return 14 // CLOSE_PUNCTUATION
    case .initialPunctuation: return 15  // INITIAL_PUNCTUATION
    case .finalPunctuation: return 16    // FINAL_PUNCTUATION
    case .otherPunctuation: return 17    // OTHER_PUNCTUATION
    case .mathSymbol: return 18      // MATH_SYMBOL
    case .currencySymbol: return 19  // CURRENCY_SYMBOL
    case .modifierSymbol: return 20  // MODIFIER_SYMBOL
    case .otherSymbol: return 21     // OTHER_SYMBOL
    case .spaceSeparator: return 22  // SPACE_SEPARATOR
    case .lineSeparator: return 23   // LINE_SEPARATOR
    case .paragraphSeparator: return 24  // PARAGRAPH_SEPARATOR
    case .control: return 25         // CONTROL
    case .format: return 26          // FORMAT
    case .surrogate: return 27       // SURROGATE
    case .privateUse: return 28      // PRIVATE_USE
    case .unassigned: return 29      // UNASSIGNED
    @unknown default: return 29      // UNASSIGNED
    }
}

private func charDirectionalityToInt(_ scalar: UnicodeScalar) -> Int {
    // Swift's Unicode scalar properties do not currently expose bidi classes
    // on all supported toolchains, so keep a conservative fallback mapping.
    if scalar.properties.isWhitespace {
        return 13 // WHITESPACE
    }
    let value = scalar.value
    switch value {
    case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF:
        return 1 // RIGHT_TO_LEFT
    default:
        return 0 // LEFT_TO_RIGHT
    }
}

private func charRuntimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}
