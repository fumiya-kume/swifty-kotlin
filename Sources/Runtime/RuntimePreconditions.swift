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

@_cdecl("kk_error")
public func kk_error(_ messageRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "An operation is not supported."
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
