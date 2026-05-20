import Foundation

// MARK: - kotlin.js JsReference (STDLIB-JS-FN-004)

final class RuntimeJsReferenceBox {
    let valueRaw: Int

    init(valueRaw: Int) {
        self.valueRaw = valueRaw
    }
}

private func runtimeJsReferenceBox(from rawValue: Int) -> RuntimeJsReferenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeJsReferenceBox.self)
}

@_cdecl("kk_js_reference_get")
public func kk_js_reference_get(_ jsRefRaw: Int) -> Int {
    guard let reference = runtimeJsReferenceBox(from: jsRefRaw) else {
        fatalError(
            "KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_js_reference_get received invalid JsReference handle"
        )
    }
    return reference.valueRaw
}
