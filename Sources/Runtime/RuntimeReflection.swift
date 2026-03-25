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
