import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeExceptionSymbol = ensureClassSymbol(
            named: "RuntimeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let uninitializedSymbol = ensureClassSymbol(
            named: "UninitializedPropertyAccessException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let nullPointerSymbol = ensureClassSymbol(
            named: "NullPointerException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let numberFormatSymbol = ensureClassSymbol(
            named: "NumberFormatException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        symbols.setDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)

        for symbol in [
            throwableSymbol,
            exceptionSymbol,
            runtimeExceptionSymbol,
            uninitializedSymbol,
            nullPointerSymbol,
            numberFormatSymbol,
            cancellationSymbol,
        ] {
            let type = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            symbols.setPropertyType(type, for: symbol)
        }

        registerSyntheticExceptionConstructors(
            ownerSymbol: exceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: runtimeExceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: runtimeExceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: uninitializedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: uninitializedSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: nullPointerSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: nullPointerSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: numberFormatSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: numberFormatSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: cancellationSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: cancellationSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
    }

    private func registerSyntheticExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        includeMessageOverload: Bool
    ) {
        registerSyntheticExceptionConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        if includeMessageOverload {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType)],
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticExceptionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }
}
