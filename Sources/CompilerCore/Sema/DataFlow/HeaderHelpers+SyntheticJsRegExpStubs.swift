import Foundation

/// Synthetic Kotlin/JS `RegExp` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsRegExpStubs(
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

        let regExpSymbol = ensureClassSymbol(
            named: "RegExp",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: regExpSymbol)
        }

        let regExpType = types.make(.classType(ClassType(
            classSymbol: regExpSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(regExpType, for: regExpSymbol)

        registerJsRegExpConstructor(
            ownerSymbol: regExpSymbol,
            ownerType: regExpType,
            parameters: [
                ("pattern", types.stringType, false),
                ("flags", types.makeNullable(types.stringType), true),
            ],
            symbols: symbols,
            interner: interner
        )
        registerJsRegExpMember(
            ownerSymbol: regExpSymbol,
            ownerType: regExpType,
            named: "reset",
            returnType: types.unitType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsRegExpConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let alreadyRegistered = symbols.lookupAll(fqName: ctorFQName).contains { symbol in
            symbols.functionSignature(for: symbol)?.parameterTypes == parameterTypes
        }
        guard !alreadyRegistered else { return }

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
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerJsRegExpMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        named name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        let parameterTypes = parameters.map(\.type)
        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: memberSymbol
        )
    }
}
