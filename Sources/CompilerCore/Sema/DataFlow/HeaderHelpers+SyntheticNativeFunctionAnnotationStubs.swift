import Foundation

/// Synthetic Kotlin/JS native function annotation surfaces.
extension DataFlowSemaPhase {
    func registerSyntheticNativeGetterStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticNativeFunctionAnnotationStub(
            named: "nativeGetter",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeSetterStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticNativeFunctionAnnotationStub(
            named: "nativeSetter",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeInvokeStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticNativeFunctionAnnotationStub(
            named: "nativeInvoke",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeFunctionAnnotationStub(
        named name: String,
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
            named: name,
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: annotationSymbol)
        }

        appendSyntheticNativeFunctionAnnotationMetadata(to: annotationSymbol, symbols: symbols)
    }

    private func appendSyntheticNativeFunctionAnnotationMetadata(
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
