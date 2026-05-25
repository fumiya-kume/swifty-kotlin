import Foundation

/// Synthetic stubs for Kotlin/JS stdlib declarations.
extension DataFlowSemaPhase {
    func registerSyntheticJsStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(path: ["kotlin", "js"], symbols: symbols, interner: interner)
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        registerSyntheticJsEagerInitializationAnnotation(
            packageFQName: kotlinJsPkg,
            packageSymbol: kotlinJsPkgSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsEagerInitializationAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let symbol = ensureAnnotationClassSymbol(
            named: "EagerInitialization",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: symbol)
        }

        appendSyntheticMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.PROPERTY"]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"This annotation is a temporal migration assistance and may be removed in the future releases, please consider filing an issue about the case where it is needed\"",
                    ]
                ),
            ],
            to: symbol,
            symbols: symbols
        )
    }
}
