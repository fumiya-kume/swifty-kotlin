import Foundation

/// Synthetic Kotlin/JS `JsStatic` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsStaticStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsStatic",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendJsStaticAnnotationMetadata(to: annotationSymbol, symbols: symbols)
    }

    private func appendJsStaticAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.js.ExperimentalJsStatic"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                ]
            ),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
