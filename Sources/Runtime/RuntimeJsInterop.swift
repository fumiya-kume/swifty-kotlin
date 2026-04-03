import Foundation

// MARK: - Kotlin/JS Interop Runtime

@_cdecl("kk_js_readonly_array_view")
public func kk_js_readonly_array_view(_ raw: Int) -> Int {
    raw
}

@_cdecl("kk_js_readonly_map_view")
public func kk_js_readonly_map_view(_ raw: Int) -> Int {
    raw
}

@_cdecl("kk_js_map_view")
public func kk_js_map_view(_ raw: Int) -> Int {
    raw
}

@_cdecl("kk_js_readonly_set_view")
public func kk_js_readonly_set_view(_ raw: Int) -> Int {
    raw
}

@_cdecl("kk_js_set_view")
public func kk_js_set_view(_ raw: Int) -> Int {
    raw
}

@_cdecl("kk_kclass_create_instance")
public func kk_kclass_create_instance(_ kclassRaw: Int) -> Int {
    guard kclassRaw != 0,
          kclassRaw != runtimeNullSentinelInt,
          runtimeKClassBox(from: kclassRaw) != nil
    else {
        return runtimeNullSentinelInt
    }
    let constructorRaw = runtimeKConstructorRegistry.primaryConstructor(for: kclassRaw)
        ?? runtimeKConstructorRegistry.constructors(for: kclassRaw).first(where: { raw in
            guard let box = runtimeKConstructorBox(from: raw) else {
                return false
            }
            return box.arity == 0
        })
    guard let constructorRaw,
          let constructorBox = runtimeKConstructorBox(from: constructorRaw),
          constructorBox.arity == 0
    else {
        return runtimeNullSentinelInt
    }

    var thrown: Int = 0
    let result = kk_kconstructor_call_0(constructorRaw, &thrown)
    return thrown == 0 ? result : runtimeNullSentinelInt
}
