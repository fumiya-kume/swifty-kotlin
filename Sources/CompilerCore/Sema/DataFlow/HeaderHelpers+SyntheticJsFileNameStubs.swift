import Foundation

/// Synthetic Kotlin/JS `JsFileName` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsFileNameStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsPkgSymbol = symbols.lookup(fqName: jsPkg)

        let annotationName = interner.intern("JsFileName")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsFileName",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: annotationSymbol)
        }

        appendJsFileNameAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerSyntheticStringAnnotationPropertyAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: jsPkg + [annotationName],
            propertyName: "name",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsFileNameAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FILE"]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlin.js.ExperimentalJsFileName"),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
