import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Future<T> class with result, consume, getState members.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Future<T>

    func registerNativeConcurrentFuture(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        futureStateType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let futureName = interner.intern("Future")
        let futureFQName = packageFQName + [futureName]

        let futureSymbol: SymbolID
        if let existing = symbols.lookup(fqName: futureFQName), symbols.symbol(existing)?.kind == .class {
            futureSymbol = existing
        } else {
            futureSymbol = symbols.define(
                kind: .class,
                name: futureName,
                fqName: futureFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: futureSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = futureFQName + [typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let futureType = types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: futureSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: futureSymbol)
        symbols.setPropertyType(futureType, for: futureSymbol)

        // Future.result: T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: futureSymbol,
            name: "result",
            propertyType: typeParamType,
            getterLinkName: "kk_future_result",
            symbols: symbols,
            interner: interner
        )

        // Future.consume(): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "consume",
            externalLinkName: "kk_future_consume",
            returnType: typeParamType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // Future.getState(): FutureState
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "getState",
            externalLinkName: "kk_future_getState",
            returnType: futureStateType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }
}
