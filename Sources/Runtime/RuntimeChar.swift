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
