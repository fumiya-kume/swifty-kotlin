import Foundation

// Runtime support for the basic kotlin.test assertion helpers used by STDLIB-TEST-157.

private func runtimeTestDisplayString(from rawValue: Int) -> String {
    if let message = extractString(from: UnsafeMutableRawPointer(bitPattern: rawValue)) {
        return message
    }
    if rawValue == runtimeNullSentinelInt {
        return "null"
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return String(rawValue)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return String(intBox.value)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self),
       let scalar = UnicodeScalar(charBox.value)
    {
        return String(Character(scalar))
    }
    if let throwable = tryCast(pointer, to: RuntimeThrowableBox.self) {
        return throwable.message
    }
    return "<object \(pointer)>"
}

private func runtimeTestNullableMessage(_ rawValue: Int) -> String? {
    if rawValue == runtimeNullSentinelInt || rawValue == 0 {
        return nil
    }
    return runtimeTestDisplayString(from: rawValue)
}

private func runtimeTestFailure(
    message: String,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "AssertionError: \(message)")
    return 0
}

@_cdecl("kk_test_assertEquals")
public func kk_test_assertEquals(
    _ expected: Int,
    _ actual: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeValuesEqual(expected, actual) else {
        return runtimeTestFailure(
            message: "Expected <\(runtimeTestDisplayString(from: expected))> but was <\(runtimeTestDisplayString(from: actual))>.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertEquals_message")
public func kk_test_assertEquals_message(
    _ expected: Int,
    _ actual: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeValuesEqual(expected, actual) else {
        let message = runtimeTestNullableMessage(messageRaw)
            ?? "Expected <\(runtimeTestDisplayString(from: expected))> but was <\(runtimeTestDisplayString(from: actual))>."
        return runtimeTestFailure(message: message, outThrown)
    }
    return 0
}

@_cdecl("kk_test_assertTrue")
public func kk_test_assertTrue(
    _ condition: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard condition != 0 else {
        return runtimeTestFailure(message: "Expected value to be true.", outThrown)
    }
    return 0
}

@_cdecl("kk_test_assertTrue_message")
public func kk_test_assertTrue_message(
    _ condition: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard condition != 0 else {
        return runtimeTestFailure(
            message: runtimeTestNullableMessage(messageRaw) ?? "Expected value to be true.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertNull")
public func kk_test_assertNull(
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        return runtimeTestFailure(
            message: "Expected value to be null, but was <\(runtimeTestDisplayString(from: value))>.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertNull_message")
public func kk_test_assertNull_message(
    _ value: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        let message = runtimeTestNullableMessage(messageRaw)
            ?? "Expected value to be null, but was <\(runtimeTestDisplayString(from: value))>."
        return runtimeTestFailure(message: message, outThrown)
    }
    return 0
}


