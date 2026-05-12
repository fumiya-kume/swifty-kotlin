import Foundation

/// Synthetic Kotlin/JS `JsAny` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsAnyStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let jsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsPkgSymbol = symbols.lookup(fqName: jsPkg)

        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: interfaceSymbol)
        }

        appendJsAnyAnnotationMetadata(to: interfaceSymbol, symbols: symbols)
    }

    private func appendJsAnyAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalWasmJsInterop"
        )

        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
