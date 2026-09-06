import Foundation

// MARK: - Runtime Reflection (REFL-004)

private let runtimeHiddenAnnotationFQNames: Set<String> = [
    "kotlin.Metadata",
]

private func runtimeShouldExposeAnnotation(fqName: String) -> Bool {
    !runtimeHiddenAnnotationFQNames.contains(fqName)
}

private func runtimeReflectionKClassBox(from raw: Int) -> RuntimeKClassBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKClassBox.self)
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
        let raw = __kk_type_token_qualified_name(typeToken, nameHint)
        let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
        if let qualifiedName, qualifiedName.contains(".") {
            return qualifiedName
        }
        let simpleName = reflectionSimpleName
        if let qualifiedName, !qualifiedName.isEmpty, qualifiedName != simpleName {
            return qualifiedName
        }
        if let stdlibQualifiedName = runtimeReflectionStdlibQualifiedName(for: simpleName) {
            return stdlibQualifiedName
        }
        return simpleName
    }
}

private func runtimeReflectionStdlibQualifiedName(for simpleName: String) -> String? {
    switch simpleName {
    case "Array":
        return "kotlin.Array"
    case "Iterable", "Collection", "MutableCollection", "List", "MutableList", "Set", "MutableSet", "Map", "MutableMap":
        return "kotlin.collections.\(simpleName)"
    case "Iterator", "MutableIterator":
        return "kotlin.collections.\(simpleName)"
    default:
        return nil
    }
}


// (a) RF-DEAD-002: 配線予定 → STDLIB-REFLECT-067 (KClass.typeParameters.size)
@_cdecl("__kk_kclass_get_arity")
public func __kk_kclass_get_arity(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw) else {
        return 0
    }
    return kclass.metadata?.typeParameterCount ?? 0
}

// MARK: - Annotation Reflection (STDLIB-REFLECT-065)

/// Returns the annotations list for a KClass as a RuntimeListBox.
/// Each element is a RuntimeAnnotationBox raw handle.
/// - Parameter kclassRaw: Opaque pointer to a RuntimeKClassBox.
/// - Returns: Opaque pointer to a RuntimeListBox of annotation handles.
@_cdecl("__kk_kclass_get_annotations")
public func __kk_kclass_get_annotations(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw),
          let metadata = kclass.metadata
    else {
        // Return empty list.
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    var annotationHandles: [Int] = []
    for record in metadata.annotations where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        let box = RuntimeAnnotationBox(
            annotationFQName: record.annotationFQName,
            arguments: record.arguments,
            annotationClassRaw: 0
        )
        annotationHandles.append(registerRuntimeObject(box))
    }
    return registerRuntimeObject(RuntimeListBox(elements: annotationHandles))
}

/// Searches for an annotation by its simple or qualified name on a KClass.
/// Implements `KClass.findAnnotation<T>()` — returns the first matching annotation or null.
/// - Parameters:
///   - kclassRaw: Opaque pointer to a RuntimeKClassBox.
///   - nameRaw: Opaque pointer to the annotation class name string to search for.
/// - Returns: Opaque pointer to a RuntimeAnnotationBox, or null sentinel if not found.
@_cdecl("__kk_kclass_find_annotation")
public func __kk_kclass_find_annotation(_ kclassRaw: Int, _ nameRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw),
          let metadata = kclass.metadata,
          let searchName = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
    else {
        return runtimeNullSentinelInt
    }

    for record in metadata.annotations where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        // Match by FQ name or simple name.
        let simpleName = record.annotationFQName.split(separator: ".").last.map(String.init) ?? record.annotationFQName
        if record.annotationFQName == searchName || simpleName == searchName {
            let box = RuntimeAnnotationBox(
                annotationFQName: record.annotationFQName,
                arguments: record.arguments,
                annotationClassRaw: 0
            )
            return registerRuntimeObject(box)
        }
    }
    return runtimeNullSentinelInt
}

/// Looks up the associated object bound by an annotation key on a KClass.
/// The current metadata pipeline records annotation arguments as strings, so
/// this returns null unless a future emitter stores a runtime object handle.
@_cdecl("__kk_kclass_find_associated_object")
public func __kk_kclass_find_associated_object(_ kclassRaw: Int, _ keyNameRaw: Int) -> Int {
    guard let kclass = runtimeReflectionKClassBox(from: kclassRaw),
          let metadata = kclass.metadata,
          let keyName = extractString(from: UnsafeMutableRawPointer(bitPattern: keyNameRaw))
    else {
        return runtimeNullSentinelInt
    }

    for record in metadata.annotations where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        let simpleName = record.annotationFQName.split(separator: ".").last.map(String.init) ?? record.annotationFQName
        guard record.annotationFQName == keyName || simpleName == keyName else {
            continue
        }
        return runtimeAssociatedObjectHandle(from: record.arguments)
    }
    return runtimeNullSentinelInt
}

private func runtimeAssociatedObjectHandle(from arguments: [String]) -> Int {
    for argument in arguments {
        if argument.hasPrefix("runtimeObjectRaw="),
           let raw = Int(argument.dropFirst("runtimeObjectRaw=".count))
        {
            return raw
        }
    }
    return runtimeNullSentinelInt
}

/// Registers a single annotation for a KClass identified by typeToken.
/// Called during module initialization (once per annotation) to attach compile-time
/// annotation data to the already-registered metadata entry.
/// - Parameters:
///   - typeToken: The type token identifying the type.
///   - fqNameRaw: Runtime string pointer for the annotation FQ name.
///   - argsEncodedRaw: Runtime string pointer for pipe-delimited argument values (empty string if none).
///   - argCount: Number of arguments encoded in the argsEncoded string.
@_cdecl("__kk_kclass_register_single_annotation")
public func __kk_kclass_register_single_annotation(
    _ typeToken: Int,
    _ fqNameRaw: Int,
    _ argsEncodedRaw: Int,
    _ argCount: Int
) -> Int {
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    guard runtimeShouldExposeAnnotation(fqName: fqName) else {
        return 0
    }

    var arguments: [String] = []
    if argCount > 0,
       let argsEncoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)),
       !argsEncoded.isEmpty
    {
        arguments = argsEncoded.components(separatedBy: "|")
    }

    let record = RuntimeAnnotationRecord(annotationFQName: fqName, arguments: arguments)
    runtimeKClassMetadataRegistry.appendAnnotations(typeToken: typeToken, annotations: [record])
    return 0
}

// MARK: - KFunction Dynamic Call (STDLIB-REFLECT-067)

private func runtimeKFunctionBox(from raw: Int) -> RuntimeKFunctionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
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
@_cdecl("__kk_kparameter_create")
public func __kk_kparameter_create(
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
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kParameterRuntimeTypeID)
}

private func runtimeKParameterBox(from raw: Int) -> RuntimeKParameterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKParameterBox.self)
}

@_cdecl("__kk_kparameter_get_index")
public func __kk_kparameter_get_index(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.index
}

@_cdecl("__kk_kparameter_get_name")
public func __kk_kparameter_get_name(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("__kk_kparameter_get_type")
public func __kk_kparameter_get_type(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.typeRaw
}

@_cdecl("__kk_kparameter_is_optional")
public func __kk_kparameter_is_optional(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return 0
    }
    return box.isOptional ? 1 : 0
}

@_cdecl("__kk_kparameter_get_kind")
public func __kk_kparameter_get_kind(_ raw: Int) -> Int {
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
@_cdecl("__kk_kfunction_create")
public func __kk_kfunction_create(
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
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
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
@_cdecl("__kk_kfunction_create_full")
public func __kk_kfunction_create_full(
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
        let isValidPtr = runtimeStorage.withGCLock { state in
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
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
}

@_cdecl("__kk_kfunction_get_name")
public func __kk_kfunction_get_name(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("__kk_kfunction_get_arity")
public func __kk_kfunction_get_arity(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return box.arity
}

@_cdecl("__kk_kfunction_get_return_type")
public func __kk_kfunction_get_return_type(_ kfunctionRaw: Int) -> Int {
    __kk_kcallable_get_return_type(kfunctionRaw)
}

@_cdecl("__kk_kfunction_is_suspend")
public func __kk_kfunction_is_suspend(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return 0
    }
    return box.isSuspend ? 1 : 0
}

/// Returns the list of all KParameter handles for this function.
@_cdecl("__kk_kfunction_get_parameters")
public func __kk_kfunction_get_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.parameterRaws))
}

/// Returns only the VALUE parameters (kind == 2), excluding INSTANCE and EXTENSION_RECEIVER.
@_cdecl("__kk_kfunction_get_value_parameters")
public func __kk_kfunction_get_value_parameters(_ kfunctionRaw: Int) -> Int {
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
@_cdecl("__kk_kfunction_get_type")
public func __kk_kfunction_get_type(_ kfunctionRaw: Int) -> Int {
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

@_cdecl("__kk_kfunction_call_0")
public func __kk_kfunction_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 0.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
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

@_cdecl("__kk_kfunction_call_1")
public func __kk_kfunction_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 1 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 1.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
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

@_cdecl("__kk_kfunction_call_2")
public func __kk_kfunction_call_2(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 2 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 2.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
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

@_cdecl("__kk_kfunction_call_3")
public func __kk_kfunction_call_3(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 3 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 3.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
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
@_cdecl("__kk_kfunction_call_vararg")
public func __kk_kfunction_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    // Unpack the argument list.
    var args: [Int] = []
    if argsListRaw != 0, argsListRaw != runtimeNullSentinelInt {
        let isValidPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: argsListRaw))
        }
        guard isValidPtr,
              let listPtr = UnsafeMutableRawPointer(bitPattern: argsListRaw),
              let listBox = tryCast(listPtr, to: RuntimeListBox.self)
        else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Invalid argument list handle in KFunction.call().")
            return runtimeNullSentinelInt
        }
        args = listBox.elements
    }
    guard args.count == box.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with \(args.count).")
        return runtimeNullSentinelInt
    }
    switch args.count {
    case 0:
        return __kk_kfunction_call_0(kfunctionRaw, outThrown)
    case 1:
        return __kk_kfunction_call_1(kfunctionRaw, args[0], outThrown)
    case 2:
        return __kk_kfunction_call_2(kfunctionRaw, args[0], args[1], outThrown)
    case 3:
        return __kk_kfunction_call_3(kfunctionRaw, args[0], args[1], args[2], outThrown)
    default:
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction.call() supports at most 3 arguments via vararg dispatch; got \(args.count).")
        return runtimeNullSentinelInt
    }
}

// MARK: - STDLIB-REFLECT-066: KType toString

func runtimeKTypeProjectionToString(_ box: RuntimeKTypeProjectionBox) -> String {
    if box.variance == nil {
        return "*"
    }
    let typeString: String
    if box.typeRaw == 0 || box.typeRaw == runtimeNullSentinelInt {
        typeString = "kotlin.Any"
    } else {
        typeString = runtimeKTypeToString(raw: box.typeRaw)
    }
    switch box.variance {
    case .in:
        return "in \(typeString)"
    case .out:
        return "out \(typeString)"
    case .invariant:
        return typeString
    case nil:
        return "*"
    }
}

private func runtimeKTypeArgumentsToString(_ argumentRaws: [Int]) -> String {
    guard !argumentRaws.isEmpty else {
        return ""
    }
    let renderedArguments = argumentRaws.map { raw -> String in
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
              let box = tryCast(ptr, to: RuntimeKTypeProjectionBox.self)
        else {
            return "*"
        }
        return runtimeKTypeProjectionToString(box)
    }
    return "<\(renderedArguments.joined(separator: ", "))>"
}

private func runtimeKTypeToString(raw ktypeRaw: Int) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: ktypeRaw),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let box = tryCast(ptr, to: RuntimeKTypeBox.self)
    else {
        return "kotlin.Any"
    }
    return runtimeKTypeToString(box)
}

private func runtimeQualifiedTypeName(_ name: String) -> String {
    switch name {
    case "Unit", "Nothing", "Any", "String", "Boolean", "Byte", "Short", "Int", "Long", "Float", "Double", "Char",
         "UByte", "UShort", "UInt", "ULong":
        return "kotlin.\(name)"
    default:
        return name
    }
}

/// Internal helper to render a KTypeBox as a human-readable string.
func runtimeKTypeToString(_ box: RuntimeKTypeBox) -> String {
    if box.typeNameRaw != 0,
       box.typeNameRaw != runtimeNullSentinelInt,
       let typeName = extractString(from: UnsafeMutableRawPointer(bitPattern: box.typeNameRaw)),
       !typeName.isEmpty
    {
        let descriptorIsNullable = typeName.hasSuffix("?")
        let baseTypeName = descriptorIsNullable ? String(typeName.dropLast()) : typeName
        let arguments = runtimeKTypeArgumentsToString(box.argumentRaws)
        let nullableSuffix = box.isMarkedNullable || descriptorIsNullable ? "?" : ""
        return runtimeQualifiedTypeName(baseTypeName) + arguments + nullableSuffix
    }

    var baseName = "kotlin.Any"
    if box.classifierRaw != 0,
       box.classifierRaw != runtimeNullSentinelInt,
       let classifierPtr = UnsafeMutableRawPointer(bitPattern: box.classifierRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: classifierPtr)) }),
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
    let arguments = runtimeKTypeArgumentsToString(box.argumentRaws)
    let nullableSuffix = box.isMarkedNullable ? "?" : ""
    return baseName + arguments + nullableSuffix
}

// MARK: - KConstructor (STDLIB-REFLECT-064)

/// Creates and registers a KConstructor box.
/// - Parameters:
///   - nameRaw: Opaque pointer to the KKString for the constructor name (typically "<init>").
///   - arity: Number of parameters.
///   - returnTypeRaw: Opaque pointer to the KKString for the return type (0 if unknown).
///   - fnPtr: C function pointer integer for direct dispatch (0 if unavailable).
///   - isPrimary: 1 if this is the primary constructor, 0 otherwise.
///   - visibilityRaw: Opaque pointer to the KKString for visibility (0 for default/PUBLIC).
///   - declaringClassRaw: Opaque pointer to the declaring KClass box (0 if unknown).
@_cdecl("__kk_kconstructor_create")
public func __kk_kconstructor_create(
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
    registerReflectionRuntimeTypeMetadata()
    let raw = registerRuntimeObject(box, typeID: kConstructorRuntimeTypeID)
    runtimeKConstructorRegistry.register(classRaw: declaringClassRaw, constructorRaw: raw)
    return raw
}
