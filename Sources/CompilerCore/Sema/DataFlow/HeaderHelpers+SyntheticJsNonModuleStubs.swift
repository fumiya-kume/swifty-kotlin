import Foundation

/// Synthetic stubs for stable Kotlin/JS annotations.
extension DataFlowSemaPhase {
    func registerSyntheticJsNonModuleStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(path: ["kotlin", "js"], symbols: symbols, interner: interner)
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let symbol = ensureAnnotationClassSymbol(
            named: "JsNonModule",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: symbol)
        }

        appendJsNonModuleMetadata(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.FILE",
                    ]
                ),
            ],
            to: symbol,
            symbols: symbols
        )
    }

    private func appendJsNonModuleMetadata(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in records where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
