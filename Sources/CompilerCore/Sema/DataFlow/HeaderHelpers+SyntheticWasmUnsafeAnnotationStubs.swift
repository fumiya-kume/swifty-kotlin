import Foundation

/// Synthetic stubs for `kotlin.wasm.unsafe` marker annotations.
extension DataFlowSemaPhase {
    func registerSyntheticWasmUnsafeAnnotationStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let wasmUnsafePkg = ensurePackage(
            path: ["kotlin", "wasm", "unsafe"],
            symbols: symbols,
            interner: interner
        )
        let wasmUnsafePkgSymbol = symbols.lookup(fqName: wasmUnsafePkg)

        let unsafeWasmMemoryApiSymbol = ensureAnnotationClassSymbol(
            named: "UnsafeWasmMemoryApi",
            in: wasmUnsafePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic], for: unsafeWasmMemoryApiSymbol)
        if let wasmUnsafePkgSymbol {
            symbols.setParentSymbol(wasmUnsafePkgSymbol, for: unsafeWasmMemoryApiSymbol)
        }

        let requiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: [
                "message=\"Unsafe APIs to access to WebAssembly linear memory\"",
            ]
        )
        var annotations = symbols.annotations(for: unsafeWasmMemoryApiSymbol)
        guard !annotations.contains(requiresOptIn) else {
            return
        }
        annotations.append(requiresOptIn)
        symbols.setAnnotations(annotations, for: unsafeWasmMemoryApiSymbol)
    }
}
