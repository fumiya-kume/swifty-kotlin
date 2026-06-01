import Foundation

// MARK: - ランタイム関数型操作

@_silgen_name("kk_function_andThen")
public func kk_function_andThen<T, R, NewR>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (R) -> NewR
) -> (T) -> NewR {
    return { g(f($0)) }
}

@_silgen_name("kk_function_compose")
public func kk_function_compose<NewT, T, R>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (NewT) -> T
) -> (NewT) -> R {
    return { f(g($0)) }
}

@_silgen_name("kk_function_curried")
public func kk_function_curried<P1, P2, R>(
    _ f: @escaping (P1, P2) -> R
) -> (P1) -> (P2) -> R {
    return { p1 in
        return { p2 in
            f(p1, p2)
        }
    }
}

func runtimeFunctionValueBox(from rawValue: Int) -> RuntimeFunctionValueBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeFunctionValueBox.self)
}

private func runtimeFunctionInvokeInvalidArity(expected: Int, actual: Int) -> Int {
    runtimeAllocateThrowable(message: "Function invoke arity mismatch: expected \(expected), got \(actual)")
}

@_cdecl("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 1 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 1, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return function(box.closureRaw, arg, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint1.self)
    return function(arg, outThrown)
}

@_cdecl("kk_function_invoke_0")
public func kk_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 0 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 0, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return function(box.closureRaw, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKThunkEntryPoint.self)
    return function(outThrown)
}

@_cdecl("kk_function_invoke_2")
public func kk_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 2 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 2, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return function(box.closureRaw, arg1, arg2, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint2.self)
    return function(arg1, arg2, outThrown)
}

@_cdecl("kk_function_invoke_3")
public func kk_function_invoke_3(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 3 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 3, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return function(box.closureRaw, arg1, arg2, arg3, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint3.self)
    return function(arg1, arg2, arg3, outThrown)
}

@_cdecl("kk_function_create_0")
public func kk_function_create_0(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 0))
}

@_cdecl("kk_function_create_1")
public func kk_function_create_1(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 1))
}

@_cdecl("kk_function_create_2")
public func kk_function_create_2(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 2))
}
