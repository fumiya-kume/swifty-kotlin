import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: atomicLazy(initializer) top-level function.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - atomicLazy

    func registerNativeConcurrentAtomicLazy(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("atomicLazy")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
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
                flags: [.synthetic]
            )
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let initializerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))
        let lazyType = nativeConcurrentLazyType(
            elementType: typeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.parameterTypes == [initializerType]
                && signature.returnType == lazyType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }

        let initializerName = interner.intern("initializer")
        let initializerSymbol = symbols.define(
            kind: .valueParameter,
            name: initializerName,
            fqName: functionFQName + [initializerName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: initializerSymbol)
        symbols.setPropertyType(initializerType, for: initializerSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [initializerType],
                returnType: lazyType,
                isSuspend: false,
                valueParameterSymbols: [initializerSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
