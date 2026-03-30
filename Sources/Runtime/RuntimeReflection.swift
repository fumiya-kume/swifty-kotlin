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
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

/// Returns the arity (number of value parameters) of the KFunction.
@_cdecl("kk_kfunction_get_arity")
public func kk_kfunction_get_arity(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return 0
    }
    return box.arity
}

/// Returns the return type descriptor as a KKString raw pointer, or null sentinel if unknown.
@_cdecl("kk_kfunction_get_return_type")
public func kk_kfunction_get_return_type(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.returnTypeRaw != 0 ? box.returnTypeRaw : runtimeNullSentinelInt
}

/// Returns 1 if the KFunction is declared suspend, 0 otherwise.
@_cdecl("kk_kfunction_is_suspend")
public func kk_kfunction_is_suspend(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return 0
    }
    return box.isSuspend ? 1 : 0
}

/// Returns the value-parameter list as a runtime List of descriptor strings.
@_cdecl("kk_kfunction_get_parameters")
public func kk_kfunction_get_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let placeholders = Array(repeating: 0, count: max(0, box.arity))
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Invokes the KFunction with zero arguments.
@_cdecl("kk_kfunction_call_0")
public func kk_kfunction_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: invalid handle")
        return 0
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction '\(extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw)) ?? "<unknown>")' is not directly callable"
        )
        return 0
    }
    guard box.arity == 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction call arity mismatch: expected \(box.arity), got 0"
        )
        return 0
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return fn(box.closureRaw, outThrown)
    }
    let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
    return fn(outThrown)
}

/// Invokes the KFunction with one argument.
@_cdecl("kk_kfunction_call_1")
public func kk_kfunction_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: invalid handle")
        return 0
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction '\(extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw)) ?? "<unknown>")' is not directly callable"
        )
        return 0
    }
    guard box.arity == 1 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction call arity mismatch: expected \(box.arity), got 1"
        )
        return 0
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return fn(box.closureRaw, arg, outThrown)
    }
    let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
    return fn(arg, outThrown)
}

/// Invokes the KFunction with two arguments.
@_cdecl("kk_kfunction_call_2")
public func kk_kfunction_call_2(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: invalid handle")
        return 0
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction '\(extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw)) ?? "<unknown>")' is not directly callable"
        )
        return 0
    }
    guard box.arity == 2 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction call arity mismatch: expected \(box.arity), got 2"
        )
        return 0
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return fn(box.closureRaw, arg1, arg2, outThrown)
    }
    let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
    return fn(arg1, arg2, outThrown)
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
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: invalid handle")
        return 0
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction '\(extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw)) ?? "<unknown>")' is not directly callable"
        )
        return 0
    }
    guard box.arity == 3 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction call arity mismatch: expected \(box.arity), got 3"
        )
        return 0
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return fn(box.closureRaw, arg1, arg2, arg3, outThrown)
    }
    let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
    return fn(arg1, arg2, arg3, outThrown)
}

/// Invokes the KFunction with a vararg list (STDLIB-REFLECT-067).
/// Unpacks the runtime List into individual arguments and dispatches based on arity.
@_cdecl("kk_kfunction_call_vararg")
public func kk_kfunction_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: invalid handle")
        return 0
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction '\(extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw)) ?? "<unknown>")' is not directly callable"
        )
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
    let actualArity = args.count
    guard box.arity == actualArity else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction call arity mismatch: expected \(box.arity), got \(actualArity)"
        )
        return 0
    }
    switch actualArity {
    case 0:
        if box.closureRaw != 0 {
            let fn = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
            return fn(box.closureRaw, outThrown)
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
        return fn(outThrown)
    case 1:
        if box.closureRaw != 0 {
            let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
            return fn(box.closureRaw, args[0], outThrown)
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
        return fn(args[0], outThrown)
    case 2:
        if box.closureRaw != 0 {
            let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
            return fn(box.closureRaw, args[0], args[1], outThrown)
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
        return fn(args[0], args[1], outThrown)
    case 3:
        if box.closureRaw != 0 {
            let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
            return fn(box.closureRaw, args[0], args[1], args[2], outThrown)
        }
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
        return fn(args[0], args[1], args[2], outThrown)
    default:
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "KFunction.call(): arity \(actualArity) is not supported for dynamic dispatch"
        )
        return 0
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
