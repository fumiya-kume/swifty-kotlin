import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: waitForMultipleFutures(...) top-level and Collection extension.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - waitForMultipleFutures

    func registerNativeConcurrentWaitForMultipleFutures(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("waitForMultipleFutures")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let futureType = nativeConcurrentFutureType(
            elementType: typeParameterType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futuresCollectionType = nativeConcurrentCollectionType(
            named: "Collection",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futureSetType = nativeConcurrentCollectionType(
            named: "Set",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: futureSetType,
            parameters: [
                (name: "futures", type: futuresCollectionType),
                (name: "timeoutMillis", type: types.intType),
            ],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: futuresCollectionType,
            returnType: futureSetType,
            parameters: [(name: "millis", type: types.intType)],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use 'waitForMultipleFutures' top-level function instead\"",
                        "replaceWith = \"waitForMultipleFutures(this, millis)\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}
