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
    guard runtimeReflectionKClassBox(from: kclassRaw) != nil else {
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
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKFunctionBox.self)
}

// MARK: - KParameter (STDLIB-REFLECT-063)

/// Creates and registers a KParameter box.
/// - Parameters:
///   - index: 0-based parameter index.
///   - nameRaw: KKString for the parameter name (0 if unnamed).
///   - typeRaw: KKString for the parameter type name.
///   - isOptional: 1 if the parameter has a default value.
///   - kind: 0 = INSTANCE, 1 = EXTENSION_RECEIVER, 2 = VALUE.
@_cdecl("kk_kparameter_create")
public func kk_kparameter_create(
    _ index: Int,
    _ nameRaw: Int,
    _ typeRaw: Int,
    _ isOptional: Int,
    _ kind: Int
) -> Int {
    let box = RuntimeKParameterBox(
        index: index,
        nameRaw: nameRaw,
        typeRaw: typeRaw,
        isOptional: isOptional != 0,
        kind: kind
    )
    return registerRuntimeObject(box)
}

private func runtimeKParameterBox(from raw: Int) -> RuntimeKParameterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKParameterBox.self)
}

@_cdecl("kk_kparameter_get_index")
public func kk_kparameter_get_index(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.index
}

@_cdecl("kk_kparameter_get_name")
public func kk_kparameter_get_name(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("kk_kparameter_get_type")
public func kk_kparameter_get_type(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.typeRaw
}

@_cdecl("kk_kparameter_is_optional")
public func kk_kparameter_is_optional(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return 0
    }
    return box.isOptional ? 1 : 0
}

@_cdecl("kk_kparameter_get_kind")
public func kk_kparameter_get_kind(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return 2 // VALUE by default
    }
    return box.kind
}

// MARK: - KFunction Factory (STDLIB-REFLECT-063)

/// Creates and registers a KFunction box.
/// - Parameters:
///   - nameRaw: Opaque pointer to the KKString for the function name.
///   - arity: Number of parameters (excluding receiver for member functions).
///   - returnTypeRaw: Opaque pointer to the KKString for the return type (0 if unknown).
///   - isSuspend: 1 if the function is a suspend function, 0 otherwise.
///   - fnPtr: C function pointer integer for direct dispatch (0 if unavailable).
///   - closureRaw: Closure environment pointer (0 for top-level functions).
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

/// Extended factory that also attaches parameter metadata and type string.
/// - Parameters:
///   - nameRaw: KKString for the function name.
///   - arity: Number of value parameters.
///   - returnTypeRaw: KKString for the return type.
///   - isSuspend: 1 if suspend function.
///   - fnPtr: C function pointer.
///   - closureRaw: Closure environment pointer.
///   - paramListRaw: Runtime list of KParameter handles (0 for empty).
///   - typeStringRaw: KKString for the function type signature (0 if unknown).
@_cdecl("kk_kfunction_create_full")
public func kk_kfunction_create_full(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ isSuspend: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ paramListRaw: Int,
    _ typeStringRaw: Int
) -> Int {
    var paramRaws: [Int] = []
    if paramListRaw != 0, paramListRaw != runtimeNullSentinelInt {
        let isValidPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: paramListRaw))
        }
        if isValidPtr,
           let ptr = UnsafeMutableRawPointer(bitPattern: paramListRaw),
           let listBox = tryCast(ptr, to: RuntimeListBox.self)
        {
            paramRaws = listBox.elements
        }
    }
    let box = RuntimeKFunctionBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        isSuspend: isSuspend != 0,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        parameterRaws: paramRaws,
        typeStringRaw: typeStringRaw
    )
    return registerRuntimeObject(box)
}

@_cdecl("kk_kfunction_get_name")
public func kk_kfunction_get_name(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("kk_kfunction_get_arity")
public func kk_kfunction_get_arity(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.arity
}

@_cdecl("kk_kfunction_get_return_type")
public func kk_kfunction_get_return_type(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.returnTypeRaw
}

@_cdecl("kk_kfunction_is_suspend")
public func kk_kfunction_is_suspend(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return 0
    }
    return box.isSuspend ? 1 : 0
}

/// Returns the list of all KParameter handles for this function.
@_cdecl("kk_kfunction_get_parameters")
public func kk_kfunction_get_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.parameterRaws))
}

/// Returns only the VALUE parameters (kind == 2), excluding INSTANCE and EXTENSION_RECEIVER.
@_cdecl("kk_kfunction_get_value_parameters")
public func kk_kfunction_get_value_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    let valueParams = box.parameterRaws.filter { raw in
        guard let paramBox = runtimeKParameterBox(from: raw) else { return true }
        return paramBox.kind == 2 // VALUE
    }
    return registerRuntimeObject(RuntimeListBox(elements: valueParams))
}

/// Returns a human-readable function type string, e.g. "(Int, Int) -> Int".
@_cdecl("kk_kfunction_get_type")
public func kk_kfunction_get_type(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    if box.typeStringRaw != 0, box.typeStringRaw != runtimeNullSentinelInt {
        return box.typeStringRaw
    }
    // Fallback: synthesize from return type if available.
    if box.returnTypeRaw != 0, box.returnTypeRaw != runtimeNullSentinelInt {
        return box.returnTypeRaw
    }
    return runtimeNullSentinelInt
}

// MARK: KFunction.call() — arity 0

@_cdecl("kk_kfunction_call_0")
public func kk_kfunction_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: KFunction expects \(box.arity) argument(s) but call() was invoked with 0.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "UnsupportedOperationException: KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return fn(box.closureRaw, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
        return fn(outThrown)
    }
}

// MARK: KFunction.call() — arity 1

@_cdecl("kk_kfunction_call_1")
public func kk_kfunction_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 1 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: KFunction expects \(box.arity) argument(s) but call() was invoked with 1.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "UnsupportedOperationException: KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return fn(box.closureRaw, arg, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
        return fn(arg, outThrown)
    }
}

// MARK: KFunction.call() — arity 2

@_cdecl("kk_kfunction_call_2")
public func kk_kfunction_call_2(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 2 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: KFunction expects \(box.arity) argument(s) but call() was invoked with 2.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "UnsupportedOperationException: KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return fn(box.closureRaw, arg1, arg2, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
        return fn(arg1, arg2, outThrown)
    }
}

// MARK: KFunction.call() — arity 3

@_cdecl("kk_kfunction_call_3")
public func kk_kfunction_call_3(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 3 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: KFunction expects \(box.arity) argument(s) but call() was invoked with 3.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "UnsupportedOperationException: KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return fn(box.closureRaw, arg1, arg2, arg3, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
        return fn(arg1, arg2, arg3, outThrown)
    }
}

// MARK: KFunction.call() — vararg (list-based)

/// Dispatches to the appropriate arity overload by unpacking a runtime List.
@_cdecl("kk_kfunction_call_vararg")
public func kk_kfunction_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    // Unpack the argument list.
    var args: [Int] = []
    if argsListRaw != 0, argsListRaw != runtimeNullSentinelInt {
        let isValidPtr = runtimeStorage.withLock { state in
            state.objectPointers.contains(UInt(bitPattern: argsListRaw))
        }
        guard isValidPtr,
              let listPtr = UnsafeMutableRawPointer(bitPattern: argsListRaw),
              let listBox = tryCast(listPtr, to: RuntimeListBox.self)
        else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: Invalid argument list handle in KFunction.call().")
            return runtimeNullSentinelInt
        }
        args = listBox.elements
    }
    guard args.count == box.arity else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: KFunction expects \(box.arity) argument(s) but call() was invoked with \(args.count).")
        return runtimeNullSentinelInt
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
            message: "UnsupportedOperationException: KFunction.call() supports at most 3 arguments via vararg dispatch; got \(args.count).")
        return runtimeNullSentinelInt
    }
}

// MARK: - STDLIB-REFLECT-066: KType toString

/// Internal helper to render a KTypeBox as a human-readable string.
func runtimeKTypeToString(_ box: RuntimeKTypeBox) -> String {
    var baseName = "kotlin.Any"
    if box.classifierRaw != 0,
       box.classifierRaw != runtimeNullSentinelInt,
       let classifierPtr = UnsafeMutableRawPointer(bitPattern: box.classifierRaw),
       runtimeStorage.withLock({ $0.objectPointers.contains(UInt(bitPattern: classifierPtr)) }),
       let kclassBox = tryCast(classifierPtr, to: RuntimeKClassBox.self)
    {
        let qualName = kclassBox.reflectionQualifiedName
        if !qualName.isEmpty {
            baseName = qualName
        } else {
            let simpleName = kclassBox.reflectionSimpleName
            if !simpleName.isEmpty {
                baseName = simpleName
            }
        }
    }
    return box.isMarkedNullable ? baseName + "?" : baseName
}

/// Returns a human-readable string for a KType, e.g. "kotlin.String" or "kotlin.String?".
@_cdecl("kk_ktype_to_string")
public func kk_ktype_to_string(_ ktypeRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: ktypeRaw),
          runtimeStorage.withLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let box = tryCast(ptr, to: RuntimeKTypeBox.self)
    else {
        return runtimeReflectionStringRaw("kotlin.Any")
    }
    return runtimeReflectionStringRaw(runtimeKTypeToString(box))
}

// MARK: - KProperty Dynamic Access (STDLIB-REFLECT-067)

private func runtimeKPropertyStubBox(from raw: Int) -> RuntimeKPropertyStub? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKPropertyStub.self)
}

/// Invokes the getter function pointer stored in a KProperty stub.
/// The stub is created by `kk_kproperty_stub_create`; this function is
/// called when Kotlin code invokes `prop.get()` via dynamic dispatch.
///
/// - Parameter handle: Opaque pointer to a `RuntimeKPropertyStub`.
/// - Parameter outThrown: Optional out-pointer for thrown exception.
/// - Returns: The property value, or `runtimeNullSentinelInt` on failure.
@_cdecl("kk_kproperty_get")
public func kk_kproperty_get(
    _ handle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeKPropertyStubBox(from: handle) != nil else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KProperty handle.")
        return runtimeNullSentinelInt
    }
    // RuntimeKPropertyStub carries only name/type metadata; actual value access
    // is delegated through the callable-ref mechanism at the call site.
    // Return the sentinel to indicate "no direct value" — the compiler lowers
    // KProperty.get() to the appropriate accessor call before reaching here.
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "UnsupportedOperationException: KProperty.get() requires a bound receiver; use a property reference with receiver.")
    return runtimeNullSentinelInt
}

/// Invokes the setter function pointer stored in a KProperty stub.
@_cdecl("kk_kproperty_set")
public func kk_kproperty_set(
    _ handle: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard runtimeKPropertyStubBox(from: handle) != nil else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid KProperty handle.")
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "UnsupportedOperationException: KProperty.set() requires a bound receiver; use a mutable property reference with receiver.")
    return runtimeNullSentinelInt
}

// MARK: - KConstructor (STDLIB-REFLECT-064)

private func runtimeKConstructorBox(from raw: Int) -> RuntimeKConstructorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKConstructorBox.self)
}

/// Creates and registers a KConstructor box.
/// - Parameters:
///   - nameRaw: Opaque pointer to the KKString for the constructor name (typically "<init>").
///   - arity: Number of parameters.
///   - returnTypeRaw: Opaque pointer to the KKString for the return type (0 if unknown).
///   - fnPtr: C function pointer integer for direct dispatch (0 if unavailable).
///   - isPrimary: 1 if this is the primary constructor, 0 otherwise.
///   - visibilityRaw: Opaque pointer to the KKString for visibility (0 for default/PUBLIC).
///   - declaringClassRaw: Opaque pointer to the declaring KClass box (0 if unknown).
@_cdecl("kk_kconstructor_create")
public func kk_kconstructor_create(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ fnPtr: Int,
    _ isPrimary: Int,
    _ visibilityRaw: Int,
    _ declaringClassRaw: Int
) -> Int {
    let box = RuntimeKConstructorBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        fnPtr: fnPtr,
        isPrimary: isPrimary != 0,
        visibilityRaw: visibilityRaw,
        declaringClassRaw: declaringClassRaw
    )
    return registerRuntimeObject(box)
}

@_cdecl("kk_kconstructor_get_name")
public func kk_kconstructor_get_name(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("kk_kconstructor_get_arity")
public func kk_kconstructor_get_arity(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return runtimeNullSentinelInt
    }
    return box.arity
}

@_cdecl("kk_kconstructor_get_return_type")
public func kk_kconstructor_get_return_type(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return runtimeNullSentinelInt
    }
    return box.returnTypeRaw
}

@_cdecl("kk_kconstructor_is_primary")
public func kk_kconstructor_is_primary(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return 0
    }
    return box.isPrimary ? 1 : 0
}

@_cdecl("kk_kconstructor_get_visibility")
public func kk_kconstructor_get_visibility(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return runtimeNullSentinelInt
    }
    if box.visibilityRaw == 0 {
        // Default to "PUBLIC" string.
        return runtimeReflectionStringRaw("PUBLIC")
    }
    return box.visibilityRaw
}

/// Returns the parameters of a KConstructor as a runtime list of KKString name handles.
@_cdecl("kk_kconstructor_get_parameters")
public func kk_kconstructor_get_parameters(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.parameterNameRaws))
}

/// Returns the value parameters (same as parameters for constructors) as a runtime list.
@_cdecl("kk_kconstructor_get_value_parameters")
public func kk_kconstructor_get_value_parameters(_ handle: Int) -> Int {
    guard let box = runtimeKConstructorBox(from: handle) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.parameterNameRaws))
}

// MARK: - KConstructor Dynamic Call (STDLIB-REFLECT-064 / STDLIB-REFLECT-067)

/// KConstructor.call() with 0 arguments.
@_cdecl("kk_kconstructor_call_0")
public func kk_kconstructor_call_0(
    _ handle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // Try as a KConstructorBox first.
    if let box = runtimeKConstructorBox(from: handle) {
        guard box.arity == 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: KConstructor expects \(box.arity) argument(s) but call() was invoked with 0.")
            return runtimeNullSentinelInt
        }
        guard box.fnPtr != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor has no callable function pointer.")
            return runtimeNullSentinelInt
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
        return fn(outThrown)
    }
    // Fallback: delegate to KFunction-based dispatch for backward compatibility.
    return kk_kfunction_call_0(handle, outThrown)
}

/// KConstructor.call() with 1 argument.
@_cdecl("kk_kconstructor_call_1")
public func kk_kconstructor_call_1(
    _ handle: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeKConstructorBox(from: handle) {
        guard box.arity == 1 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: KConstructor expects \(box.arity) argument(s) but call() was invoked with 1.")
            return runtimeNullSentinelInt
        }
        guard box.fnPtr != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor has no callable function pointer.")
            return runtimeNullSentinelInt
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
        return fn(arg, outThrown)
    }
    return kk_kfunction_call_1(handle, arg, outThrown)
}

/// KConstructor.call() with 2 arguments.
@_cdecl("kk_kconstructor_call_2")
public func kk_kconstructor_call_2(
    _ handle: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeKConstructorBox(from: handle) {
        guard box.arity == 2 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: KConstructor expects \(box.arity) argument(s) but call() was invoked with 2.")
            return runtimeNullSentinelInt
        }
        guard box.fnPtr != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor has no callable function pointer.")
            return runtimeNullSentinelInt
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
        return fn(arg1, arg2, outThrown)
    }
    return kk_kfunction_call_2(handle, arg1, arg2, outThrown)
}

/// KConstructor.call() with 3 arguments.
@_cdecl("kk_kconstructor_call_3")
public func kk_kconstructor_call_3(
    _ handle: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeKConstructorBox(from: handle) {
        guard box.arity == 3 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: KConstructor expects \(box.arity) argument(s) but call() was invoked with 3.")
            return runtimeNullSentinelInt
        }
        guard box.fnPtr != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor has no callable function pointer.")
            return runtimeNullSentinelInt
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
        return fn(arg1, arg2, arg3, outThrown)
    }
    return kk_kfunction_call_3(handle, arg1, arg2, arg3, outThrown)
}

/// KConstructor.call() with a vararg list.
@_cdecl("kk_kconstructor_call_vararg")
public func kk_kconstructor_call_vararg(
    _ handle: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeKConstructorBox(from: handle) {
        // Unpack the argument list.
        var args: [Int] = []
        if argsListRaw != 0, argsListRaw != runtimeNullSentinelInt {
            let isValidPtr = runtimeStorage.withLock { state in
                state.objectPointers.contains(UInt(bitPattern: argsListRaw))
            }
            guard isValidPtr,
                  let listPtr = UnsafeMutableRawPointer(bitPattern: argsListRaw),
                  let listBox = tryCast(listPtr, to: RuntimeListBox.self)
            else {
                outThrown?.pointee = runtimeAllocateThrowable(
                    message: "IllegalArgumentException: Invalid argument list handle in KConstructor.call().")
                return runtimeNullSentinelInt
            }
            args = listBox.elements
        }
        guard args.count == box.arity else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: KConstructor expects \(box.arity) argument(s) but call() was invoked with \(args.count).")
            return runtimeNullSentinelInt
        }
        guard box.fnPtr != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor has no callable function pointer.")
            return runtimeNullSentinelInt
        }
        switch args.count {
        case 0:
            let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
            return fn(outThrown)
        case 1:
            let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
            return fn(args[0], outThrown)
        case 2:
            let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
            return fn(args[0], args[1], outThrown)
        case 3:
            let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
            return fn(args[0], args[1], args[2], outThrown)
        default:
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "UnsupportedOperationException: KConstructor.call() supports at most 3 arguments via vararg dispatch; got \(args.count).")
            return runtimeNullSentinelInt
        }
    }
    // Fallback to KFunction dispatch.
    return kk_kfunction_call_vararg(handle, argsListRaw, outThrown)
}
