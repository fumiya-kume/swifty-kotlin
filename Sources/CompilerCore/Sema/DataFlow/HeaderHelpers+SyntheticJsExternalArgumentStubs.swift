import Foundation

/// Synthetic Kotlin/JS `JsExternalArgument` annotation surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsExternalArgumentStubs(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let jsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsPkgSymbol = symbols.lookup(fqName: jsPkg)

        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "JsExternalArgument",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: annotationSymbol)
        }

        var annotations = symbols.annotations(for: annotationSymbol)
        let records = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.ExperimentalStdlibApi"
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.VALUE_PARAMETER"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.BINARY"]
            ),
        ]
        var didAppend = false
        for record in records where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: annotationSymbol)
        }
    }
}
