import Foundation

// Runtime support for kotlin.require, kotlin.check, kotlin.error (STDLIB-062).
// These functions throw IllegalArgumentException or IllegalStateException when conditions fail.

@_cdecl("kk_require")
public func kk_require(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Failed requirement.")
        return 0
    }
    return 0
}

@_cdecl("kk_check")
public func kk_check(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalStateException: Check failed.")
        return 0
    }
    return 0
}

@_cdecl("kk_require_lazy")
public func kk_require_lazy(
    _ condition: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    preconditionWithLazyMessage(
        condition,
        fnPtr,
        closureRaw,
        outThrown,
        defaultMessage: "IllegalArgumentException: Failed requirement."
    )
}

@_cdecl("kk_check_lazy")
public func kk_check_lazy(
    _ condition: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    preconditionWithLazyMessage(
        condition,
        fnPtr,
        closureRaw,
        outThrown,
        defaultMessage: "IllegalStateException: Check failed."
    )
}

@_cdecl("kk_error")
public func kk_error(_ messageRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let message = runtimePreconditionMessage(from: messageRaw) ?? "An operation is not supported."
    outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalStateException: \(message)")
    return 0
}

/// Runtime support for kotlin's not-yet-implemented helper (STDLIB-063).
/// Throws NotImplementedError with the given reason.
@_cdecl("kk_todo")
public func kk_todo(_ reasonRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let reason = extractString(from: UnsafeMutableRawPointer(bitPattern: reasonRaw)) ?? "An operation is not implemented."
    outThrown?.pointee = runtimeAllocateThrowable(message: "NotImplementedError: \(reason)")
    return 0
}

@_cdecl("kk_todo_noarg")
public func kk_todo_noarg(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_todo(runtimeNullSentinelInt, outThrown)
}

private func preconditionWithLazyMessage(
    _ condition: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    defaultMessage: String
) -> Int {
    outThrown?.pointee = 0
    guard condition == 0 else {
        return 0
    }

    let message = runtimeEvaluateLazyMessage(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        ?? defaultMessage
    if outThrown?.pointee != 0 {
        return 0
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: message)
    return 0
}

private func runtimeEvaluateLazyMessage(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> String? {
    guard fnPtr != 0 else {
        return nil
    }
    var lazyThrown = 0
    let rawMessage = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &lazyThrown)
    if lazyThrown != 0 {
        outThrown?.pointee = lazyThrown
        return nil
    }
    return runtimePreconditionMessage(from: rawMessage)
}

private func runtimePreconditionMessage(from rawValue: Int) -> String? {
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
