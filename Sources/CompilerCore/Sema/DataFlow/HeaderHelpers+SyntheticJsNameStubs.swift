import Foundation

/// Synthetic Kotlin/JS `JsName` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsNameStubs(
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

        let annotationName = interner.intern("JsName")
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsName",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: annotationSymbol)
        }

        appendJsNameAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerSyntheticStringAnnotationPropertyAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: jsPkg + [annotationName],
            propertyName: "name",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendJsNameAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
            ]
        )

        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
