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
    if value >= 0xD800, value <= 0xDFFF {
        return 18 // SURROGATE
    }
    guard let scalar = runtimeUnicodeScalar(value) else {
        return 0 // UNASSIGNED
    }
    let category = scalar.properties.generalCategory
    return charCategoryToInt(category)
}

@_cdecl("kk_char_category_code")
public func kk_char_category_code(_ ordinal: Int) -> Int {
    guard ordinal >= 0, ordinal < charCategoryCodes.count else {
        return charRuntimeMakeStringRaw(charCategoryCodes[0])
    }
    return charRuntimeMakeStringRaw(charCategoryCodes[ordinal])
}

@_cdecl("kk_char_category_contains")
public func kk_char_category_contains(_ ordinal: Int, _ value: Int) -> Int {
    kk_box_bool(kk_char_category(value) == ordinal ? 1 : 0)
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

// MARK: - STDLIB-003-ABI-001: Char.digitToInt(radix: Int)

/// fun Char.digitToInt(radix: Int): Int
/// Returns the numeric digit value of this Char in the given radix (2..36).
/// Throws IllegalArgumentException if radix is out of range or char is not a valid digit.
@_cdecl("kk_char_digitToInt_radix")
public func kk_char_digitToInt_radix(
    _ value: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard radix >= 2, radix <= 36 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: radix \(radix) is out of the valid range 2..36"
        )
        return 0
    }
    let digitVal: Int
    if value >= Int(("0" as UnicodeScalar).value), value <= Int(("9" as UnicodeScalar).value) {
        digitVal = value - Int(("0" as UnicodeScalar).value)
    } else if value >= Int(("a" as UnicodeScalar).value), value <= Int(("z" as UnicodeScalar).value) {
        digitVal = value - Int(("a" as UnicodeScalar).value) + 10
    } else if value >= Int(("A" as UnicodeScalar).value), value <= Int(("Z" as UnicodeScalar).value) {
        digitVal = value - Int(("A" as UnicodeScalar).value) + 10
    } else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: code point \(value) is not a valid digit in radix \(radix)"
        )
        return 0
    }
    guard digitVal < radix else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: code point \(value) is not a valid digit in radix \(radix)"
        )
        return 0
    }
    return digitVal
}

// MARK: - STDLIB-003-ABI-002: Char.Companion.digitToChar(digit: Int, radix: Int)

/// fun Char.Companion.digitToChar(digit: Int, radix: Int): Char
/// Returns the Char that represents the given digit value in the given radix (2..36).
/// Throws IllegalArgumentException if radix or digit is out of range.
@_cdecl("kk_char_digitToChar_radix")
public func kk_char_digitToChar_radix(
    _ digit: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard radix >= 2, radix <= 36 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: radix \(radix) is out of the valid range 2..36"
        )
        return 0
    }
    guard digit >= 0, digit < radix else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: digit \(digit) is out of the valid range 0..<\(radix)"
        )
        return 0
    }
    if digit < 10 {
        return Int(("0" as UnicodeScalar).value) + digit
    } else {
        return Int(("a" as UnicodeScalar).value) + digit - 10
    }
}

// MARK: - STDLIB-003-ABI-003: Char(code: Int) constructor

/// constructor(code: Int): Char
/// Returns the Char with the given Unicode code point.
/// Throws IllegalArgumentException if code is not in 0..0xFFFF.
@_cdecl("kk_char_fromCode")
public func kk_char_fromCode(
    _ code: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard code >= 0, code <= 0xFFFF else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: code \(code) is out of the valid Char range 0..0xFFFF"
        )
        return 0
    }
    return code
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
    switch category {
    case .unassigned: return 0
    case .uppercaseLetter: return 1
    case .lowercaseLetter: return 2
    case .titlecaseLetter: return 3
    case .modifierLetter: return 4
    case .otherLetter: return 5
    case .nonspacingMark: return 6
    case .enclosingMark: return 7
    case .spacingMark: return 8
    case .decimalNumber: return 9
    case .letterNumber: return 10
    case .otherNumber: return 11
    case .spaceSeparator: return 12
    case .lineSeparator: return 13
    case .paragraphSeparator: return 14
    case .control: return 15
    case .format: return 16
    case .privateUse: return 17
    case .surrogate: return 18
    case .dashPunctuation: return 19
    case .openPunctuation: return 20
    case .closePunctuation: return 21
    case .connectorPunctuation: return 22
    case .otherPunctuation: return 23
    case .mathSymbol: return 24
    case .currencySymbol: return 25
    case .modifierSymbol: return 26
    case .otherSymbol: return 27
    case .initialPunctuation: return 28
    case .finalPunctuation: return 29
    @unknown default: return 0
    }
}

private let charCategoryCodes = [
    "Cn",
    "Lu",
    "Ll",
    "Lt",
    "Lm",
    "Lo",
    "Mn",
    "Me",
    "Mc",
    "Nd",
    "Nl",
    "No",
    "Zs",
    "Zl",
    "Zp",
    "Cc",
    "Cf",
    "Co",
    "Cs",
    "Pd",
    "Ps",
    "Pe",
    "Pc",
    "Po",
    "Sm",
    "Sc",
    "Sk",
    "So",
    "Pi",
    "Pf",
]

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
