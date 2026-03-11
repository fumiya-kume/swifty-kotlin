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
    if let digitValue = charUnicodeDigitValue(scalar) {
        return digitValue
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Char \(scalar) is not a digit")
    return 0
}

@_cdecl("kk_char_digitToIntOrNull")
public func kk_char_digitToIntOrNull(_ value: Int) -> Int {
    guard let scalar = runtimeUnicodeScalar(value),
          let digitValue = charUnicodeDigitValue(scalar)
    else {
        return runtimeNullSentinelInt
    }
    return digitValue
}

private func charUnicodeDigitValue(_ scalar: UnicodeScalar) -> Int? {
    // ASCII digits 0-9
    if scalar.value >= 0x30 && scalar.value <= 0x39 {
        return Int(scalar.value - 0x30)
    }
    // Unicode Nd category decimal digits
    if CharacterSet.decimalDigits.contains(scalar) {
        let numericValue = scalar.properties.numericValue
        if let value = numericValue, value >= 0 && value <= 9 && value == value.rounded() {
            return Int(value)
        }
    }
    // Latin letters for radix > 10
    let v = scalar.value
    if v >= 0x41 && v <= 0x5A { return Int(v - 0x41) + 10 }  // A-Z
    if v >= 0x61 && v <= 0x7A { return Int(v - 0x61) + 10 }  // a-z
    // Fullwidth Latin letters
    if v >= 0xFF21 && v <= 0xFF3A { return Int(v - 0xFF21) + 10 }  // Ａ-Ｚ
    if v >= 0xFF41 && v <= 0xFF5A { return Int(v - 0xFF41) + 10 }  // ａ-ｚ
    return nil
}

private func charRuntimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}
