import Foundation

/// Synthetic stubs for experimental Kotlin/JS annotations backed by `ExperimentalStdlibApi`.
extension DataFlowSemaPhase {
    func registerSyntheticJsExternalInheritorsOnlyStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(path: ["kotlin", "js"], symbols: symbols, interner: interner)
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let symbol = ensureAnnotationClassSymbol(
            named: "JsExternalInheritorsOnly",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: symbol)
        }

        appendJsExternalInheritorsOnlyMetadata(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
            ],
            to: symbol,
            symbols: symbols
        )
    }

    private func appendJsExternalInheritorsOnlyMetadata(
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
