import Foundation

// String stdlib extension stubs (STDLIB-006) for kotlin.text.
// Split from DataFlowSemaPhase+HeaderHelpers.swift to stay within file-length limits.

extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let stringType = types.stringType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let intType = types.intType
        let doubleType = types.doubleType
        let listStringType = makeListOfStringType(symbols: symbols, types: types, interner: interner)

        registerSyntheticStringExtensionFunction(
            named: "trim",
            externalLinkName: "kk_string_trim",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "replace",
            externalLinkName: "kk_string_replace",
            receiverType: stringType,
            parameters: [
                ("oldValue", stringType, false, false),
                ("newValue", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "startsWith",
            externalLinkName: "kk_string_startsWith",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "endsWith",
            externalLinkName: "kk_string_endsWith",
            receiverType: stringType,
            parameters: [
                ("suffix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "contains",
            externalLinkName: "kk_string_contains_str",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toInt",
            externalLinkName: "kk_string_toInt",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "toDouble",
            externalLinkName: "kk_string_toDouble",
            receiverType: stringType,
            parameters: [],
            returnType: doubleType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }

    private func makeListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.stringType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticStringExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []
        parameterTypes.reserveCapacity(parameters.count)
        parameterSymbols.reserveCapacity(parameters.count)
        parameterDefaults.reserveCapacity(parameters.count)
        parameterVarargs.reserveCapacity(parameters.count)

        for parameter in parameters {
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
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }
}
