import Foundation

// MARK: - Runtime Reflection (REFL-004)

private func runtimeReflectionKClassBox(from raw: Int) -> RuntimeKClassBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKClassBox.self)
}

private func runtimeReflectionStringRaw(_ value: String) -> Int {
    let utf8 = Array(value.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}

private extension RuntimeKClassBox {
    var reflectionSimpleName: String {
        if let metadata {
            return metadata.simpleName
        }
        if nameHint != 0,
           nameHint != runtimeNullSentinelInt,
           let hint = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint))
        {
            return hint
        }
        return ""
    }

    var reflectionQualifiedName: String {
        if let metadata {
            return metadata.qualifiedName
        }
        let raw = kk_type_token_qualified_name(typeToken, nameHint)
        return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? reflectionSimpleName
    }
}

@_cdecl("kk_kclass_get_simple_name")
public func kk_kclass_get_simple_name(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return runtimeReflectionStringRaw(kclass.reflectionSimpleName)
}

@_cdecl("kk_kclass_get_qualified_name")
public func kk_kclass_get_qualified_name(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return runtimeReflectionStringRaw(kclass.reflectionQualifiedName)
}

@_cdecl("kk_kclass_get_superclass_name")
public func kk_kclass_get_superclass_name(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw),
          let supertypeName = kclass.metadata?.supertypeName
    else {
        return runtimeNullSentinelInt
    }
    return runtimeReflectionStringRaw(supertypeName)
}

@_cdecl("kk_kclass_is_data_class")
public func kk_kclass_is_data_class(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return kclass.metadata?.isDataClass == true ? 1 : 0
}

@_cdecl("kk_kclass_is_sealed_class")
public func kk_kclass_is_sealed_class(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return kclass.metadata?.isSealedClass == true ? 1 : 0
}

@_cdecl("kk_kclass_is_value_class")
public func kk_kclass_is_value_class(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return kclass.metadata?.isValueClass == true ? 1 : 0
}

@_cdecl("kk_kclass_get_field_count")
public func kk_kclass_get_field_count(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    return kclass.metadata?.fieldCount ?? 0
}

@_cdecl("kk_kclass_get_instance_size_words")
public func kk_kclass_get_instance_size_words(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return 0
    }
    // The current metadata registry does not expose instance size yet.
    return 0
}

@_cdecl("kk_kclass_get_arity")
public func kk_kclass_get_arity(_ kclassRaw: Int) -> Int {
    guard runtimeReflectionKClassBox(from: kclassRaw) != nil else {
        return 0
    }
    // The current metadata registry does not expose type-parameter arity yet.
    return 0
}

// MARK: - KFunction Dynamic Call (STDLIB-REFLECT-067)

private func runtimeKFunctionBox(from raw: Int) -> RuntimeKFunctionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj else { return nil }
    return tryCast(ptr, to: RuntimeKFunctionBox.self)
}

/// Creates a KFunction runtime box with full reflection metadata.
@_cdecl("kk_kfunction_create")
public func kk_kfunction_create(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ isSuspend: Int,
    _ fnPtr: Int,
    _ closureRaw: Int
) -> Int {
    let box = RuntimeKFunctionBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        isSuspend: isSuspend != 0,
        fnPtr: fnPtr,
        closureRaw: closureRaw
    )
    return registerRuntimeObject(box)
}

/// Returns the name of the KFunction as a KKString raw pointer.
@_cdecl("kk_kfunction_get_name")
public func kk_kfunction_get_name(_ kfunctionRaw: Int) -> Int {
    runtimeKFunctionBox(from: kfunctionRaw)?.nameRaw ?? runtimeNullSentinelInt
}

/// Returns the arity (number of value parameters) of the KFunction.
@_cdecl("kk_kfunction_get_arity")
public func kk_kfunction_get_arity(_ kfunctionRaw: Int) -> Int {
    runtimeKFunctionBox(from: kfunctionRaw)?.arity ?? 0
}

/// Returns the return type descriptor as a KKString raw pointer, or null sentinel if unknown.
@_cdecl("kk_kfunction_get_return_type")
public func kk_kfunction_get_return_type(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else { return runtimeNullSentinelInt }
    return box.returnTypeRaw != 0 ? box.returnTypeRaw : runtimeNullSentinelInt
}

/// Returns 1 if the KFunction is declared suspend, 0 otherwise.
@_cdecl("kk_kfunction_is_suspend")
public func kk_kfunction_is_suspend(_ kfunctionRaw: Int) -> Int {
    runtimeKFunctionBox(from: kfunctionRaw)?.isSuspend == true ? 1 : 0
}

/// Returns the value-parameter list as a runtime List of descriptor strings.
@_cdecl("kk_kfunction_get_parameters")
public func kk_kfunction_get_parameters(_ kfunctionRaw: Int) -> Int {
    let arity = runtimeKFunctionBox(from: kfunctionRaw)?.arity ?? 0
    return registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: max(0, arity))))
}

/// Invokes the KFunction with zero arguments.
@_cdecl("kk_kfunction_call_0")
public func kk_kfunction_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw), box.fnPtr != 0, box.arity == 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(0): invalid handle or arity mismatch"
        )
        return 0
    }
    if box.closureRaw != 0 {
        return unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)(box.closureRaw, outThrown)
    }
    return unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)(outThrown)
}

/// Invokes the KFunction with one argument.
@_cdecl("kk_kfunction_call_1")
public func kk_kfunction_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw), box.fnPtr != 0, box.arity == 1 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(1): invalid handle or arity mismatch"
        )
        return 0
    }
    if box.closureRaw != 0 {
        return unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)(box.closureRaw, arg, outThrown)
    }
    return unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)(arg, outThrown)
}

/// Invokes the KFunction with two arguments.
@_cdecl("kk_kfunction_call_2")
public func kk_kfunction_call_2(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw), box.fnPtr != 0, box.arity == 2 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(2): invalid handle or arity mismatch"
        )
        return 0
    }
    if box.closureRaw != 0 {
        return unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)(box.closureRaw, arg1, arg2, outThrown)
    }
    return unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)(arg1, arg2, outThrown)
}

/// Invokes the KFunction with three arguments (STDLIB-REFLECT-067).
@_cdecl("kk_kfunction_call_3")
public func kk_kfunction_call_3(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw), box.fnPtr != 0, box.arity == 3 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(3): invalid handle or arity mismatch"
        )
        return 0
    }
    if box.closureRaw != 0 {
        return unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)(box.closureRaw, arg1, arg2, arg3, outThrown)
    }
    return unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)(arg1, arg2, arg3, outThrown)
}

/// Invokes the KFunction with a runtime List of arguments (STDLIB-REFLECT-067).
/// Unpacks the list and dispatches based on arity.
@_cdecl("kk_kfunction_call_vararg")
public func kk_kfunction_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw), box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction.call(vararg): invalid handle")
        return 0
    }
    var args: [Int] = []
    if argsListRaw != 0 && argsListRaw != runtimeNullSentinelInt,
       let ptr = UnsafeMutableRawPointer(bitPattern: argsListRaw) {
        let isObj = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObj, let listBox = tryCast(ptr, to: RuntimeListBox.self) {
            args = listBox.elements
        }
    }
    guard box.arity == args.count else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(vararg) arity mismatch: expected \(box.arity), got \(args.count)"
        )
        return 0
    }
    switch args.count {
    case 0:
        return kk_kfunction_call_0(kfunctionRaw, outThrown)
    case 1:
        return kk_kfunction_call_1(kfunctionRaw, args[0], outThrown)
    case 2:
        return kk_kfunction_call_2(kfunctionRaw, args[0], args[1], outThrown)
    case 3:
        return kk_kfunction_call_3(kfunctionRaw, args[0], args[1], args[2], outThrown)
    default:
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(vararg): arity \(args.count) not supported"
        )
        return 0
    }
}

// MARK: - KProperty Dynamic Access (STDLIB-REFLECT-067)

private func runtimeKPropertyStubBox(from raw: Int) -> RuntimeKPropertyStub? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj else { return nil }
    return tryCast(ptr, to: RuntimeKPropertyStub.self)
}

/// Reads a property value dynamically via the registered getter (STDLIB-REFLECT-067).
@_cdecl("kk_kproperty_get")
public func kk_kproperty_get(
    _ handle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let stub = runtimeKPropertyStubBox(from: handle), stub.getterFnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KProperty.get(): no getter or invalid handle"
        )
        return 0
    }
    typealias GetterFn = @convention(c) (Int) -> Int
    return unsafeBitCast(stub.getterFnPtr, to: GetterFn.self)(stub.receiverPtr)
}

/// Writes a property value dynamically via the registered setter (STDLIB-REFLECT-067).
@_cdecl("kk_kproperty_set")
public func kk_kproperty_set(
    _ handle: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let stub = runtimeKPropertyStubBox(from: handle), stub.setterFnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KProperty.set(): no setter or invalid handle (read-only?)"
        )
        return 0
    }
    typealias SetterFn = @convention(c) (Int, Int) -> Int
    return unsafeBitCast(stub.setterFnPtr, to: SetterFn.self)(stub.receiverPtr, value)
}

// MARK: - KConstructor Dynamic Call (STDLIB-REFLECT-067)

/// Invokes a KConstructor with zero arguments (delegates to kk_kfunction_call_0).
@_cdecl("kk_kconstructor_call_0")
public func kk_kconstructor_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_kfunction_call_0(kfunctionRaw, outThrown)
}

/// Invokes a KConstructor with one argument (delegates to kk_kfunction_call_1).
@_cdecl("kk_kconstructor_call_1")
public func kk_kconstructor_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_kfunction_call_1(kfunctionRaw, arg, outThrown)
}

/// Invokes a KConstructor with a vararg list (delegates to kk_kfunction_call_vararg).
@_cdecl("kk_kconstructor_call_vararg")
public func kk_kconstructor_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_kfunction_call_vararg(kfunctionRaw, argsListRaw, outThrown)
}
