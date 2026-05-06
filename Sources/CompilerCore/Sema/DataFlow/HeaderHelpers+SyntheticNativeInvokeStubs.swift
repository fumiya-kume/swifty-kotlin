import Foundation

/// Synthetic Kotlin/JS `nativeInvoke` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticNativeInvokeStubs(
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
            named: "nativeInvoke",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendNativeInvokeAnnotationMetadata(to: annotationSymbol, symbols: symbols)
    }

    private func appendNativeInvokeAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FUNCTION"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use inline extension function with body using dynamic\"",
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
