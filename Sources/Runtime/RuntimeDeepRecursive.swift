import Foundation

final class RuntimeDeepRecursiveFunctionBox {
    let fnPtr: Int
    let closureRaw: Int

    init(fnPtr: Int, closureRaw: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
    }
}

final class RuntimeDeepRecursiveScopeBox {
    let function: RuntimeDeepRecursiveFunctionBox

    init(function: RuntimeDeepRecursiveFunctionBox) {
        self.function = function
    }
}

private func runtimeDeepRecursiveFunctionBox(from rawValue: Int) -> RuntimeDeepRecursiveFunctionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeDeepRecursiveFunctionBox.self)
}

private func runtimeDeepRecursiveScopeBox(from rawValue: Int) -> RuntimeDeepRecursiveScopeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeDeepRecursiveScopeBox.self)
}

private func runtimeInvokeDeepRecursive(
    _ function: RuntimeDeepRecursiveFunctionBox,
    _ value: Int
) -> Int {
    let scopeRaw = registerRuntimeObject(RuntimeDeepRecursiveScopeBox(function: function))
    var thrown = 0
    if function.closureRaw != 0 {
        let fn = unsafeBitCast(function.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        let result = fn(function.closureRaw, scopeRaw, value, &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: DeepRecursiveFunction block threw")
        }
        return result
    }

    let fn = unsafeBitCast(function.fnPtr, to: KKFunctionEntryPoint2.self)
    let result = fn(scopeRaw, value, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: DeepRecursiveFunction block threw")
    }
    return result
}

@_cdecl("kk_deep_recursive_function_new")
public func kk_deep_recursive_function_new(_ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: DeepRecursiveFunction requires a valid block")
    }
    return registerRuntimeObject(RuntimeDeepRecursiveFunctionBox(fnPtr: fnPtr, closureRaw: closureRaw))
}

@_cdecl("kk_deep_recursive_function_invoke")
public func kk_deep_recursive_function_invoke(_ functionRaw: Int, _ value: Int) -> Int {
    guard let function = runtimeDeepRecursiveFunctionBox(from: functionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveFunction handle")
    }
    return runtimeInvokeDeepRecursive(function, value)
}

@_cdecl("kk_deep_recursive_scope_callRecursive")
public func kk_deep_recursive_scope_callRecursive(_ scopeRaw: Int, _ value: Int) -> Int {
    guard let scope = runtimeDeepRecursiveScopeBox(from: scopeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveScope handle")
    }
    return runtimeInvokeDeepRecursive(scope.function, value)
}

@_cdecl("kk_deep_recursive_function_callRecursive")
public func kk_deep_recursive_function_callRecursive(_ functionRaw: Int, _ value: Int) -> Int {
    guard let function = runtimeDeepRecursiveFunctionBox(from: functionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveFunction handle")
    }
    return runtimeInvokeDeepRecursive(function, value)
}
