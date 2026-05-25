import Foundation

/// Synthetic Kotlin/Wasm `WasmExport` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticWasmExportStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let wasmPkg = ensurePackage(
            path: ["kotlin", "wasm"],
            symbols: symbols,
            interner: interner
        )
        let wasmPkgSymbol = symbols.lookup(fqName: wasmPkg)

        let annotationName = interner.intern("WasmExport")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "WasmExport",
            in: wasmPkg,
            symbols: symbols,
            interner: interner
        )
        if let wasmPkgSymbol {
            symbols.setParentSymbol(wasmPkgSymbol, for: annotationSymbol)
        }

        appendWasmExportAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerSyntheticStringAnnotationPropertyAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: wasmPkg + [annotationName],
            propertyName: "name",
            parameterHasDefaultValue: true,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendWasmExportAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.wasm.ExperimentalWasmInterop"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FUNCTION"]
            ),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
