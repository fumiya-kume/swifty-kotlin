import Foundation

// Runtime support for kotlin.require, kotlin.check, kotlin.error (STDLIB-062).
// These functions throw IllegalArgumentException or IllegalStateException when conditions fail.

@_cdecl("kk_require")
public func kk_require(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Failed requirement.")
        return 0
    }
    return 0
}

@_cdecl("kk_check")
public func kk_check(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Check failed.")
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
        defaultMessage: "Failed requirement.",
        allocate: runtimeAllocateIllegalArgumentException
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
        defaultMessage: "Check failed.",
        allocate: runtimeAllocateIllegalStateException
    )
}

// MARK: - checkNotNull / requireNotNull (STDLIB-ASSERT-ABI-001)

/// Runtime entry for kotlin.checkNotNull(value).
/// On null input: throws IllegalStateException("Required value was null.").
/// On non-null input: returns the value unchanged.
@_cdecl("kk_check_not_null")
public func kk_check_not_null(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if value == runtimeNullSentinelInt || value == 0 {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Required value was null.")
        return 0
    }
    return value
}

/// Runtime entry for kotlin.requireNotNull(value).
/// On null input: throws IllegalArgumentException("Required value was null.").
/// On non-null input: returns the value unchanged.
@_cdecl("kk_require_not_null")
public func kk_require_not_null(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if value == runtimeNullSentinelInt || value == 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Required value was null.")
        return 0
    }
    return value
}

/// Lazy-message variant of kk_check_not_null.
/// The message closure is evaluated only when the value is null.
@_cdecl("kk_check_not_null_lazy")
public func kk_check_not_null_lazy(
    _ value: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        return value
    }
    notNullWithLazyMessage(fnPtr, closureRaw, outThrown, allocate: runtimeAllocateIllegalStateException)
    return 0
}

/// Lazy-message variant of kk_require_not_null.
/// The message closure is evaluated only when the value is null.
@_cdecl("kk_require_not_null_lazy")
public func kk_require_not_null_lazy(
    _ value: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        return value
    }
    notNullWithLazyMessage(fnPtr, closureRaw, outThrown, allocate: runtimeAllocateIllegalArgumentException)
    return 0
}

private func notNullWithLazyMessage(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    allocate: (String, Int) -> Int
) {
    let defaultMessage = "Required value was null."
    guard fnPtr != 0 else {
        outThrown?.pointee = allocate(defaultMessage, 0)
        return
    }
    var lazyThrown = 0
    let rawMessage = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &lazyThrown)
    if lazyThrown != 0 {
        outThrown?.pointee = allocate(defaultMessage, lazyThrown)
        return
    }
    let message = runtimePreconditionMessage(from: rawMessage)
    outThrown?.pointee = allocate(message, 0)
}

// MARK: - assert (STDLIB-258)

@_cdecl("kk_precondition_assert")
public func kk_precondition_assert(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeAreAssertionsEnabled() else {
        return 0
    }
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateAssertionError(message: "Assertion failed.")
        return 0
    }
    return 0
}

@_cdecl("kk_precondition_assert_lazy")
public func kk_precondition_assert_lazy(
    _ condition: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeAreAssertionsEnabled() else {
        return 0
    }
    guard condition == 0 else {
        return 0
    }
    guard fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateAssertionError(message: "Assertion failed.")
        return 0
    }

    var lazyThrown = 0
    let rawMessage = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &lazyThrown)
    if lazyThrown != 0 {
        outThrown?.pointee = runtimeAllocateAssertionError(
            message: "Assertion failed.",
            cause: lazyThrown
        )
        return 0
    }

    let message = runtimePreconditionMessage(from: rawMessage)
    outThrown?.pointee = runtimeAllocateAssertionError(message: message)
    return 0
}

@_cdecl("kk_error")
public func kk_error(_ messageRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let message = runtimePreconditionMessage(from: messageRaw)
    outThrown?.pointee = runtimeAllocateIllegalStateException(message: message)
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
    defaultMessage: String,
    allocate: (String, Int) -> Int
) -> Int {
    outThrown?.pointee = 0
    guard condition == 0 else {
        return 0
    }

    // No lazy message lambda provided — use the default message directly
    guard fnPtr != 0 else {
        outThrown?.pointee = allocate(defaultMessage, 0)
        return 0
    }

    // Evaluate the lazy message lambda
    var lazyThrown = 0
    let rawMessage = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &lazyThrown)

    if lazyThrown != 0 {
        // Lazy message evaluation itself threw — wrap as precondition failure with cause.
        // STDLIB-257: The precondition failure (IllegalArgumentException / IllegalStateException)
        // is the primary exception; the lambda's exception is attached as the cause so callers
        // can distinguish "precondition failed" from "lazy message evaluation failed".
        outThrown?.pointee = allocate(defaultMessage, lazyThrown)
        return 0
    }

    // Lazy message evaluated successfully — use it for the precondition failure.
    // Kotlin's e.message returns only the user-provided message, not the exception type prefix.
    let message = runtimePreconditionMessage(from: rawMessage)
    outThrown?.pointee = allocate(message, 0)
    return 0
}

func runtimePreconditionMessage(from rawValue: Int) -> String {
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

// MARK: - synchronized (STDLIB-325)

/// Runtime support for kotlin.synchronized(lock, block).
/// Uses NSRecursiveLock-based per-object locking. The lock argument is used as a key
/// to obtain a reentrant lock, and the block lambda is executed under that lock.
@_cdecl("kk_synchronized")
public func kk_synchronized(_ lock: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

@_cdecl("kk_reentrant_read_write_lock_read")
public func kk_reentrant_read_write_lock_read(
    _ lock: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

private let runtimeLockStorage = NSLock()
private nonisolated(unsafe) var runtimeLocks: [Int: NSRecursiveLock] = [:]

private func runtimeGetOrCreateLock(for key: Int) -> NSRecursiveLock {
    runtimeLockStorage.lock()
    defer { runtimeLockStorage.unlock() }
    if let existing = runtimeLocks[key] {
        return existing
    }
    let newLock = NSRecursiveLock()
    runtimeLocks[key] = newLock
    return newLock
}
