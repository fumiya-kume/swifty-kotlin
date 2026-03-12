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

private func charRuntimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}
