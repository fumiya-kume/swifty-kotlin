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

        appendSyntheticMetadataAnnotations(
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
}
