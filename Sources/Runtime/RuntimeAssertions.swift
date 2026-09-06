
// MARK: - Typed Exception Box Classes (STDLIB-LOG-149)
//
// Typed RuntimeThrowableBox subclasses for AssertionError, IllegalStateException,
// IllegalArgumentException, NoWhenBranchMatchedException, and
// ConcurrentModificationException, StringIndexOutOfBoundsException, and
// ArrayIndexOutOfBoundsException. These enable proper type-discriminated catch
// blocks in compiled Kotlin code (e.g., `catch (e: IllegalArgumentException)`).
//
// The message stored in each box is the *user-visible* message (without the
// exception-type prefix). The `renderedMessage` property adds the type prefix
// for stack-trace / toString() output, matching Kotlin JVM behaviour.

final class RuntimeFreezingExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.native.concurrent.FreezingException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.native.concurrent.FreezingException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("FreezingException", message)
    }
}

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
        runtimeRenderedExceptionMessage("AssertionError", message)
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
        runtimeRenderedExceptionMessage("IllegalStateException", message)
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
        runtimeRenderedExceptionMessage("IllegalArgumentException", message)
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
        runtimeRenderedExceptionMessage("NoWhenBranchMatchedException", message)
    }
}

final class RuntimeConcurrentModificationExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ConcurrentModificationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ConcurrentModificationException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ConcurrentModificationException", message)
    }
}

final class RuntimeInvalidMutabilityExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.native.concurrent.InvalidMutabilityException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.native.concurrent.InvalidMutabilityException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("InvalidMutabilityException", message)
    }
}

final class RuntimeArrayIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ArrayIndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ArrayIndexOutOfBoundsException",
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ArrayIndexOutOfBoundsException", message)
    }
}

final class RuntimeStringIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.StringIndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.StringIndexOutOfBoundsException",
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("StringIndexOutOfBoundsException", message)
    }
}

final class RuntimeNumberFormatExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NumberFormatException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NumberFormatException",
            "kotlin.IllegalArgumentException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NumberFormatException", message)
    }
}

final class RuntimeArithmeticExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ArithmeticException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ArithmeticException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ArithmeticException", message)
    }
}

final class RuntimeNegativeArraySizeExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NegativeArraySizeException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NegativeArraySizeException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NegativeArraySizeException", message)
    }
}

// KSP-467-adjacent (catch-clause sibling-type discrimination fix): typed boxes for
// the remaining built-in exception classes that were previously constructed via the
// generic, type-erased `__kk_throwable_new`/`__kk_throwable_new_with_cause` external
// functions. Without a distinct RuntimeThrowableBox subclass + hierarchy, `kk_op_is`
// cannot tell these apart from any other built-in exception, so a `catch (e: T)`
// clause for one of these types would incorrectly match an unrelated sibling
// exception (e.g. `catch (e: NumberFormatException)` catching a thrown
// `IllegalStateException`). See Sources/Runtime/RuntimeStringArray.swift kk_op_is.
final class RuntimeExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.Exception"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("Exception", message)
    }
}

final class RuntimeCharacterCodingExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.text.CharacterCodingException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.text.CharacterCodingException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("CharacterCodingException", message)
    }
}

final class RuntimeKotlinNothingValueExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.KotlinNothingValueException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.KotlinNothingValueException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("KotlinNothingValueException", message)
    }
}

final class RuntimeErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.Error"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("Error", message)
    }
}

final class RuntimeOutOfMemoryErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.OutOfMemoryError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.OutOfMemoryError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("OutOfMemoryError", message)
    }
}

final class RuntimeNotImplementedErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NotImplementedError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NotImplementedError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NotImplementedError", message)
    }
}

final class RuntimeIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("IndexOutOfBoundsException", message)
    }
}

final class RuntimeUnsupportedOperationExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.UnsupportedOperationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.UnsupportedOperationException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("UnsupportedOperationException", message)
    }
}

final class RuntimeNoSuchElementExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NoSuchElementException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NoSuchElementException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NoSuchElementException", message)
    }
}

final class RuntimeClassCastExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ClassCastException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ClassCastException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ClassCastException", message)
    }
}

final class RuntimeTypeCastExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.TypeCastException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.TypeCastException",
            "kotlin.ClassCastException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("TypeCastException", message)
    }
}

final class RuntimeNullPointerExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NullPointerException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NullPointerException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NullPointerException", message)
    }
}

// MARK: - Typed Allocators

/// Allocates a `FreezingException` with Kotlin/Native's exact constructor message.
func runtimeAllocateFreezingException(toFreezeRaw: Int, blockerRaw: Int) -> Int {
    let message = "freezing of \(runtimeRenderAnyForPrint(toFreezeRaw)) has failed, first blocker is \(runtimeRenderAnyForPrint(blockerRaw))"
    let throwable = RuntimeFreezingExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `AssertionError` with the given message.
func runtimeAllocateAssertionError(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeAssertionErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalStateException` with the given message.
func runtimeAllocateIllegalStateException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalStateExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalArgumentException` with the given message.
func runtimeAllocateIllegalArgumentException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalArgumentExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateNoWhenBranchMatchedException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeNoWhenBranchMatchedExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateConcurrentModificationException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeConcurrentModificationExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateInvalidMutabilityException(message: String?) -> Int {
    let throwable = RuntimeInvalidMutabilityExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateArrayIndexOutOfBoundsException(message: String?) -> Int {
    let throwable = RuntimeArrayIndexOutOfBoundsExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateStringIndexOutOfBoundsException(message: String?) -> Int {
    let throwable = RuntimeStringIndexOutOfBoundsExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateNumberFormatException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeNumberFormatExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateArithmeticException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeArithmeticExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `NegativeArraySizeException` with the given message.
func runtimeAllocateNegativeArraySizeException(message: String?) -> Int {
    let throwable = RuntimeNegativeArraySizeExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `Exception` with the given message.
func runtimeAllocateException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `CharacterCodingException` with the given message.
func runtimeAllocateCharacterCodingException(message: String?) -> Int {
    let throwable = RuntimeCharacterCodingExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `KotlinNothingValueException` with the given message.
func runtimeAllocateKotlinNothingValueException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeKotlinNothingValueExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `Error` with the given message.
func runtimeAllocateError(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `OutOfMemoryError` with the given message.
func runtimeAllocateOutOfMemoryError(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeOutOfMemoryErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Message used by `NotImplementedError()` when no reason is supplied.
let runtimeNotImplementedDefaultMessage = "An operation is not implemented."

/// Allocates a `NotImplementedError` with the given message.
func runtimeAllocateNotImplementedError(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNotImplementedErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IndexOutOfBoundsException` with the given message.
func runtimeAllocateIndexOutOfBoundsException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeIndexOutOfBoundsExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `UnsupportedOperationException` with the given message.
func runtimeAllocateUnsupportedOperationException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeUnsupportedOperationExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `NoSuchElementException` with the given message.
func runtimeAllocateNoSuchElementException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeNoSuchElementExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `ClassCastException` with the given message.
func runtimeAllocateClassCastException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeClassCastExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `TypeCastException` with the given message.
func runtimeAllocateTypeCastException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeTypeCastExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `NullPointerException` with the given message.
func runtimeAllocateNullPointerException(message: String?, cause: Int = 0) -> Int {
    let throwable = RuntimeNullPointerExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeExceptionMessage(from raw: Int, defaultMessage: String?) -> String? {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return defaultMessage
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? defaultMessage
}

func runtimeJVMExceptionFQName(from kotlinFQName: String) -> String {
    switch kotlinFQName {
    case "kotlin.Exception":
        return "java.lang.Exception"
    case "kotlin.RuntimeException":
        return "java.lang.RuntimeException"
    case "kotlin.IllegalArgumentException":
        return "java.lang.IllegalArgumentException"
    case "kotlin.IllegalStateException":
        return "java.lang.IllegalStateException"
    case "kotlin.ArithmeticException":
        return "java.lang.ArithmeticException"
    case "kotlin.AssertionError":
        return "java.lang.AssertionError"
    case "kotlin.ClassCastException":
        return "java.lang.ClassCastException"
    case "kotlin.IndexOutOfBoundsException":
        return "java.lang.IndexOutOfBoundsException"
    case "kotlin.ArrayIndexOutOfBoundsException":
        return "java.lang.ArrayIndexOutOfBoundsException"
    case "kotlin.StringIndexOutOfBoundsException":
        return "java.lang.StringIndexOutOfBoundsException"
    case "kotlin.NegativeArraySizeException":
        return "java.lang.NegativeArraySizeException"
    case "kotlin.NullPointerException":
        return "java.lang.NullPointerException"
    case "kotlin.NumberFormatException":
        return "java.lang.NumberFormatException"
    case "kotlin.UnsupportedOperationException":
        return "java.lang.UnsupportedOperationException"
    case "kotlin.Error":
        return "java.lang.Error"
    case "kotlin.OutOfMemoryError":
        return "java.lang.OutOfMemoryError"
    case "kotlin.ConcurrentModificationException":
        return "java.util.ConcurrentModificationException"
    case "kotlin.NoSuchElementException":
        return "java.util.NoSuchElementException"
    case "kotlin.io.IOException":
        return "java.io.IOException"
    case "kotlin.Throwable":
        return "java.lang.Throwable"
    default:
        // Preserve unknown or user-defined FQ names instead of guessing java.lang.
        return kotlinFQName
    }
}

// Shared by typed exception bridges and the source-backed Throwable(cause)
// constructor. The JVM constructor derives its message from cause.toString().
func runtimeCauseToString(from raw: Int) -> String? {
    guard raw != 0,
          raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }

    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }

    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        let exceptionFQName = runtimeJVMExceptionFQName(from: throwable.exceptionFQName)
        guard let message = throwable.message else {
            return exceptionFQName
        }
        return "\(exceptionFQName): \(message)"
    }

    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        let exceptionFQName = runtimeJVMExceptionFQName(
            from: runtimeSourceThrowableQualifiedName(for: object.classID)
        )
        guard let message = object.throwableMessage else {
            return exceptionFQName
        }
        return "\(exceptionFQName): \(message)"
    }

    return nil
}

private func runtimeAssertionErrorMessage(from raw: Int) -> String? {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return nil
    }
    return runtimeRenderAnyForPrint(raw)
}

@_cdecl("__kk_no_when_branch_matched_exception_new")
public func kk_no_when_branch_matched_exception_new() -> Int {
    runtimeAllocateNoWhenBranchMatchedException(message: "No when branch matched")
}

@_cdecl("__kk_no_when_branch_matched_exception_new_message")
public func kk_no_when_branch_matched_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "No when branch matched")
    )
}

@_cdecl("__kk_no_when_branch_matched_exception_new_message_cause")
public func kk_no_when_branch_matched_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "No when branch matched"),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_no_when_branch_matched_exception_new_cause")
public func kk_no_when_branch_matched_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: "No when branch matched",
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_concurrent_modification_exception_new")
public func kk_concurrent_modification_exception_new() -> Int {
    runtimeAllocateConcurrentModificationException(message: nil)
}

@_cdecl("__kk_concurrent_modification_exception_new_message")
public func kk_concurrent_modification_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_invalid_mutability_exception_new_message")
public func kk_invalid_mutability_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateInvalidMutabilityException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_concurrent_modification_exception_new_message_cause")
public func kk_concurrent_modification_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_concurrent_modification_exception_new_cause")
public func kk_concurrent_modification_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_array_index_out_of_bounds_exception_new")
public func kk_array_index_out_of_bounds_exception_new() -> Int {
    runtimeAllocateArrayIndexOutOfBoundsException(message: nil)
}

@_cdecl("__kk_array_index_out_of_bounds_exception_new_message")
public func kk_array_index_out_of_bounds_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateArrayIndexOutOfBoundsException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("kk_negative_array_size_exception_new")
public func kk_negative_array_size_exception_new() -> Int {
    runtimeAllocateNegativeArraySizeException(message: nil)
}

@_cdecl("kk_negative_array_size_exception_new_message")
public func kk_negative_array_size_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNegativeArraySizeException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

// MARK: - Explicit constructor entry points (catch-clause sibling-type discrimination fix)
//
// Each of these gives a user-facing `SomeBuiltinException(...)` constructor call its
// own external symbol (instead of sharing the type-erased `__kk_throwable_new`/
// `__kk_throwable_new_with_cause`), so the allocated box carries the correct
// `exceptionHierarchyFQNames` and `kk_op_is`/catch-clause dispatch can tell sibling
// exception types apart. See the source-backed constructor declarations in
// Stdlib/kotlin/Exceptions.kt and Stdlib/kotlin/IllegalStateException/Stdlib.kt.

@_cdecl("__kk_freezing_exception_new")
public func kk_freezing_exception_new(_ toFreezeRaw: Int, _ blockerRaw: Int) -> Int {
    runtimeAllocateFreezingException(toFreezeRaw: toFreezeRaw, blockerRaw: blockerRaw)
}

@_cdecl("__kk_illegal_state_exception_new")
public func kk_illegal_state_exception_new() -> Int {
    runtimeAllocateIllegalStateException(message: nil)
}

@_cdecl("__kk_illegal_state_exception_new_message")
public func kk_illegal_state_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateIllegalStateException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_illegal_state_exception_new_message_cause")
public func kk_illegal_state_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateIllegalStateException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_illegal_state_exception_new_cause")
public func kk_illegal_state_exception_new_cause(_ causeRaw: Int) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeAllocateIllegalStateException(
        message: runtimeCauseToString(from: cause),
        cause: cause
    )
}

@_cdecl("__kk_cancellation_exception_new")
public func kk_cancellation_exception_new() -> Int {
    runtimeAllocateCancellationException(message: nil)
}

@_cdecl("__kk_cancellation_exception_new_message")
public func kk_cancellation_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateCancellationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_cancellation_exception_new_message_cause")
public func kk_cancellation_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeAllocateCancellationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: cause
    )
}

@_cdecl("__kk_cancellation_exception_new_cause")
public func kk_cancellation_exception_new_cause(_ causeRaw: Int) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeAllocateCancellationException(
        message: runtimeCauseToString(from: cause),
        cause: cause
    )
}

@_cdecl("__kk_illegal_argument_exception_new")
public func kk_illegal_argument_exception_new() -> Int {
    runtimeAllocateIllegalArgumentException(message: nil)
}

@_cdecl("__kk_illegal_argument_exception_new_message")
public func kk_illegal_argument_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateIllegalArgumentException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_illegal_argument_exception_new_message_cause")
public func kk_illegal_argument_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateIllegalArgumentException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_illegal_argument_exception_new_cause")
public func kk_illegal_argument_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateIllegalArgumentException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_arithmetic_exception_new")
public func kk_arithmetic_exception_new() -> Int {
    runtimeAllocateArithmeticException(message: nil)
}

@_cdecl("__kk_arithmetic_exception_new_message")
public func kk_arithmetic_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateArithmeticException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_assertion_error_new")
public func kk_assertion_error_new() -> Int {
    runtimeAllocateAssertionError(message: nil)
}

@_cdecl("__kk_assertion_error_new_message")
public func kk_assertion_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateAssertionError(message: runtimeAssertionErrorMessage(from: messageRaw))
}

@_cdecl("__kk_assertion_error_new_message_cause")
public func kk_assertion_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateAssertionError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_uninitialized_property_access_exception_new")
public func kk_uninitialized_property_access_exception_new() -> Int {
    runtimeAllocateUninitializedPropertyAccessException(message: nil)
}

@_cdecl("__kk_uninitialized_property_access_exception_new_message")
public func kk_uninitialized_property_access_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateUninitializedPropertyAccessException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_uninitialized_property_access_exception_new_message_cause")
public func kk_uninitialized_property_access_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateUninitializedPropertyAccessException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_uninitialized_property_access_exception_new_cause")
public func kk_uninitialized_property_access_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateUninitializedPropertyAccessException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_exception_new")
public func kk_exception_new() -> Int {
    runtimeAllocateException(message: nil)
}

@_cdecl("__kk_exception_new_message")
public func kk_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_exception_new_message_cause")
public func kk_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_exception_new_cause")
public func kk_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_character_coding_exception_new")
public func kk_character_coding_exception_new() -> Int {
    runtimeAllocateCharacterCodingException(message: nil)
}

@_cdecl("__kk_character_coding_exception_new_message")
public func kk_character_coding_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateCharacterCodingException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_kotlin_nothing_value_exception_new")
public func kk_kotlin_nothing_value_exception_new() -> Int {
    runtimeAllocateKotlinNothingValueException(message: nil)
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_message")
public func kk_kotlin_nothing_value_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateKotlinNothingValueException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_message_cause")
public func kk_kotlin_nothing_value_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateKotlinNothingValueException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_cause")
public func kk_kotlin_nothing_value_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateKotlinNothingValueException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_error_new")
public func kk_error_new() -> Int {
    runtimeAllocateError(message: nil)
}

@_cdecl("__kk_error_new_message")
public func kk_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateError(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_error_new_message_cause")
public func kk_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_error_new_cause")
public func kk_error_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateError(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_out_of_memory_error_new")
public func kk_out_of_memory_error_new() -> Int {
    runtimeAllocateOutOfMemoryError(message: nil)
}

@_cdecl("__kk_out_of_memory_error_new_message")
public func kk_out_of_memory_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateOutOfMemoryError(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_not_implemented_error_new")
public func __kk_not_implemented_error_new() -> Int {
    runtimeAllocateNotImplementedError(message: runtimeNotImplementedDefaultMessage)
}

@_cdecl("__kk_not_implemented_error_new_message")
public func __kk_not_implemented_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNotImplementedError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: runtimeNotImplementedDefaultMessage)
            ?? runtimeNotImplementedDefaultMessage
    )
}

@_cdecl("__kk_unsupported_operation_exception_new")
public func kk_unsupported_operation_exception_new() -> Int {
    runtimeAllocateUnsupportedOperationException(message: nil)
}

@_cdecl("__kk_unsupported_operation_exception_new_message")
public func kk_unsupported_operation_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateUnsupportedOperationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    )
}

@_cdecl("__kk_unsupported_operation_exception_new_message_cause")
public func kk_unsupported_operation_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateUnsupportedOperationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_unsupported_operation_exception_new_cause")
public func kk_unsupported_operation_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateUnsupportedOperationException(
        message: runtimeCauseToString(from: causeRaw),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("__kk_no_such_element_exception_new")
public func kk_no_such_element_exception_new() -> Int {
    runtimeAllocateNoSuchElementException(message: nil)
}

@_cdecl("__kk_no_such_element_exception_new_message")
public func kk_no_such_element_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNoSuchElementException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_class_cast_exception_new")
public func kk_class_cast_exception_new() -> Int {
    runtimeAllocateClassCastException(message: nil)
}

@_cdecl("__kk_class_cast_exception_new_message")
public func kk_class_cast_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateClassCastException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}

@_cdecl("__kk_type_cast_exception_new")
public func kk_type_cast_exception_new() -> Int {
    runtimeAllocateTypeCastException(message: nil)
}

@_cdecl("__kk_type_cast_exception_new_message")
public func kk_type_cast_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateTypeCastException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil))
}
