import Foundation

/// Synthetic Kotlin/JS `JsSymbol` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsSymbolStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let annotationName = interner.intern("JsSymbol")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsSymbol",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendJsSymbolAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerSyntheticStringAnnotationPropertyAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: kotlinJsPkg + [annotationName],
            propertyName: "name",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsSymbolAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
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
