import Foundation

/// Synthetic Kotlin/JS `Console` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsConsoleStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let consoleSymbol = ensureInterfaceSymbol(
            named: "Console",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: consoleSymbol)
        }

        let consoleType = types.make(.classType(ClassType(
            classSymbol: consoleSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(consoleType, for: consoleSymbol)

        registerJsConsoleMember(
            named: "dir",
            ownerSymbol: consoleSymbol,
            ownerType: consoleType,
            parameter: (name: "o", type: types.anyType, isVararg: false),
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        let nullableAny = types.makeNullable(types.anyType)
        for name in ["error", "info", "log", "warn"] {
            registerJsConsoleMember(
                named: name,
                ownerSymbol: consoleSymbol,
                ownerType: consoleType,
                parameter: (name: "o", type: nullableAny, isVararg: true),
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerJsConsoleMember(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameter: (name: String, type: TypeID, isVararg: Bool),
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard symbols.symbol(symbol)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.parameterTypes == [parameter.type]
                && signature.valueParameterIsVararg == [parameter.isVararg]
        }) {
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [parameter.type],
                    returnType: returnType,
                    valueParameterSymbols: symbols.functionSignature(for: existing)?.valueParameterSymbols ?? [],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [parameter.isVararg]
                ),
                for: existing
            )
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)

        let parameterName = interner.intern(parameter.name)
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [parameter.type],
                returnType: returnType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [parameter.isVararg]
            ),
            for: functionSymbol
        )
    }
}
