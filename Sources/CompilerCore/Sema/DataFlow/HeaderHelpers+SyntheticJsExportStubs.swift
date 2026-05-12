import Foundation

/// Synthetic Kotlin/JS `JsExport` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsExportStubs(
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
            named: "JsExport",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendJsExportAnnotationMetadata(to: annotationSymbol, symbols: symbols)
    }

    private func appendJsExportAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.js.ExperimentalJsExport"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.FILE",
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
