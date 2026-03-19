import Foundation

// MARK: - Result Runtime Types (STDLIB-280/281/282/283)

final class RuntimeResultBox {
    let isSuccess: Bool
    let value: Int      // success value or 0
    let exception: Int  // throwable or 0

    init(isSuccess: Bool, value: Int, exception: Int) {
        self.isSuccess = isSuccess
        self.value = value
        self.exception = exception
    }
}

private func resultBoxFromRaw(_ raw: Int) -> RuntimeResultBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeResultBox.self)
}

// MARK: - STDLIB-280: runCatching

/// kk_runCatching(fnPtr, closureRaw, outThrown) -> Int
/// Calls the lambda wrapping its result in a RuntimeResultBox.
/// On success: box with isSuccess=true, value=lambda result.
/// On failure: box with isSuccess=false, exception=thrown value.
@_cdecl("kk_runCatching")
public func kk_runCatching(_ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 {
        // Lambda threw — wrap as failure Result
        let box = RuntimeResultBox(isSuccess: false, value: 0, exception: thrown)
        return registerRuntimeObject(box)
    }
    let box = RuntimeResultBox(isSuccess: true, value: result, exception: 0)
    return registerRuntimeObject(box)
}

// MARK: - STDLIB-281: Result properties

@_cdecl("kk_result_isSuccess")
public func kk_result_isSuccess(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw) else { return 0 }
    return box.isSuccess ? 1 : 0
}

@_cdecl("kk_result_isFailure")
public func kk_result_isFailure(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw) else { return 1 }
    return box.isSuccess ? 0 : 1
}

// MARK: - STDLIB-282: Result member functions

@_cdecl("kk_result_getOrNull")
public func kk_result_getOrNull(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw), box.isSuccess else {
        return runtimeNullSentinelInt
    }
    return box.value
}

@_cdecl("kk_result_getOrDefault")
public func kk_result_getOrDefault(_ resultRaw: Int, _ defaultValue: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw), box.isSuccess else {
        return defaultValue
    }
    return box.value
}

@_cdecl("kk_result_getOrElse")
public func kk_result_getOrElse(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return runtimeNullSentinelInt
    }
    if box.isSuccess {
        return box.value
    }
    // Call the lambda with the exception as argument
    guard let result = invokeResultLambda(fnPtr: fnPtr, closureRaw: closureRaw, argument: box.exception, outThrown: outThrown) else {
        return 0
    }
    return result
}

@_cdecl("kk_result_getOrThrow")
public func kk_result_getOrThrow(
    _ resultRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return box.value
    }
    // Re-throw the stored exception
    outThrown?.pointee = box.exception
    return 0
}

@_cdecl("kk_result_exceptionOrNull")
public func kk_result_exceptionOrNull(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw) else {
        return runtimeNullSentinelInt
    }
    if box.isSuccess {
        return runtimeNullSentinelInt
    }
    return box.exception
}

// MARK: - Internal Helper: Invoke a (closureRaw, argument, &thrown) -> Int lambda

/// Shared helper for invoking a Result transform/action lambda with a single argument.
/// Casts `fnPtr` to the expected `@convention(c)` signature, calls it, and propagates
/// any thrown exception via `outThrown`. Returns `nil` if the lambda threw.
private func invokeResultLambda(
    fnPtr: Int,
    closureRaw: Int,
    argument: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, argument, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return nil
    }
    return result
}

// MARK: - STDLIB-283: Result HOF functions

@_cdecl("kk_result_map")
public func kk_result_map(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return registerRuntimeObject(RuntimeResultBox(isSuccess: false, value: 0, exception: runtimeAllocateThrowable(message: "Result is null")))
    }
    if !box.isSuccess {
        // Return the same failure
        return resultRaw
    }
    // Apply transform to success value
    guard let mapped = invokeResultLambda(fnPtr: fnPtr, closureRaw: closureRaw, argument: box.value, outThrown: outThrown) else {
        return 0
    }
    return registerRuntimeObject(RuntimeResultBox(isSuccess: true, value: mapped, exception: 0))
}

@_cdecl("kk_result_fold")
public func kk_result_fold(
    _ resultRaw: Int,
    _ onSuccessFnPtr: Int,
    _ onSuccessClosureRaw: Int,
    _ onFailureFnPtr: Int,
    _ onFailureClosureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return runtimeNullSentinelInt
    }
    if box.isSuccess {
        guard let result = invokeResultLambda(fnPtr: onSuccessFnPtr, closureRaw: onSuccessClosureRaw, argument: box.value, outThrown: outThrown) else {
            return 0
        }
        return result
    } else {
        guard let result = invokeResultLambda(fnPtr: onFailureFnPtr, closureRaw: onFailureClosureRaw, argument: box.exception, outThrown: outThrown) else {
            return 0
        }
        return result
    }
}

@_cdecl("kk_result_onSuccess")
public func kk_result_onSuccess(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return resultRaw
    }
    if box.isSuccess {
        guard invokeResultLambda(fnPtr: fnPtr, closureRaw: closureRaw, argument: box.value, outThrown: outThrown) != nil else {
            return 0
        }
    }
    return resultRaw
}

@_cdecl("kk_result_onFailure")
public func kk_result_onFailure(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return resultRaw
    }
    if !box.isSuccess {
        guard invokeResultLambda(fnPtr: fnPtr, closureRaw: closureRaw, argument: box.exception, outThrown: outThrown) != nil else {
            return 0
        }
    }
    return resultRaw
}

// MARK: - STDLIB-589: Result.recover

@_cdecl("kk_result_recover")
public func kk_result_recover(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        return resultRaw
    }
    if box.isSuccess {
        // Success — return as-is
        return resultRaw
    }
    // Failure — apply the transform to produce a new success value
    guard let recovered = invokeResultLambda(fnPtr: fnPtr, closureRaw: closureRaw, argument: box.exception, outThrown: outThrown) else {
        return 0
    }
    return registerRuntimeObject(RuntimeResultBox(isSuccess: true, value: recovered, exception: 0))
}
