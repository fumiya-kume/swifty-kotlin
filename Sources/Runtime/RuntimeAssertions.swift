import Foundation

// MARK: - Typed Exception Box Classes (STDLIB-LOG-149)
//
// Typed RuntimeThrowableBox subclasses for AssertionError, IllegalStateException,
// IllegalArgumentException, and NoWhenBranchMatchedException. These enable proper
// type-discriminated catch blocks in compiled Kotlin code (e.g.,
// `catch (e: IllegalArgumentException)`).
//
// The message stored in each box is the *user-visible* message (without the
// exception-type prefix). The `renderedMessage` property adds the type prefix
// for stack-trace / toString() output, matching Kotlin JVM behaviour.

final class RuntimeAssertionErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.AssertionError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.AssertionError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "AssertionError: \(message)"
    }
}

final class RuntimeIllegalStateExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IllegalStateException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IllegalStateException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "IllegalStateException: \(message)"
    }
}

final class RuntimeIllegalArgumentExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IllegalArgumentException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IllegalArgumentException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "IllegalArgumentException: \(message)"
    }
}

final class RuntimeNoWhenBranchMatchedExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NoWhenBranchMatchedException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NoWhenBranchMatchedException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "NoWhenBranchMatchedException: \(message)"
    }
}

// MARK: - Typed Allocators

/// Allocates an `AssertionError` with the given message.
func runtimeAllocateAssertionError(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeAssertionErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalStateException` with the given message.
func runtimeAllocateIllegalStateException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalStateExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalArgumentException` with the given message.
func runtimeAllocateIllegalArgumentException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalArgumentExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateNoWhenBranchMatchedException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNoWhenBranchMatchedExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeNoWhenBranchMatchedMessage(from raw: Int) -> String {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return "No when branch matched"
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? "No when branch matched"
}

@_cdecl("kk_no_when_branch_matched_exception_new")
public func kk_no_when_branch_matched_exception_new() -> Int {
    runtimeAllocateNoWhenBranchMatchedException(message: "No when branch matched")
}

@_cdecl("kk_no_when_branch_matched_exception_new_message")
public func kk_no_when_branch_matched_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(message: runtimeNoWhenBranchMatchedMessage(from: messageRaw))
}

@_cdecl("kk_no_when_branch_matched_exception_new_message_cause")
public func kk_no_when_branch_matched_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: runtimeNoWhenBranchMatchedMessage(from: messageRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_no_when_branch_matched_exception_new_cause")
public func kk_no_when_branch_matched_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: "No when branch matched",
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}
