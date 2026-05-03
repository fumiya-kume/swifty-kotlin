import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: WorkerBoundReference<T> class.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - WorkerBoundReference<T>

    func registerNativeConcurrentWorkerBoundReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let referenceName = interner.intern("WorkerBoundReference")
        let referenceFQName = packageFQName + [referenceName]
        let referenceSymbol: SymbolID
        if let existing = symbols.lookup(fqName: referenceFQName), symbols.symbol(existing)?.kind == .class {
            referenceSymbol = existing
        } else {
            referenceSymbol = symbols.define(
                kind: .class,
                name: referenceName,
                fqName: referenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: referenceSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = referenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let referenceType = types.make(.classType(ClassType(
            classSymbol: referenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: referenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: referenceSymbol)
        symbols.setPropertyType(referenceType, for: referenceSymbol)

        registerNativeConcurrentConstructor(
            ownerSymbol: referenceSymbol,
            ownerType: referenceType,
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "value",
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "valueOrNull",
            propertyType: types.makeNullable(typeParamType),
            symbols: symbols,
            interner: interner
        )

        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "worker",
            propertyType: workerType,
            symbols: symbols,
            interner: interner
        )
    }
}
