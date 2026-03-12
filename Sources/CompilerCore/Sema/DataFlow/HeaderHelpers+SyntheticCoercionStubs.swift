import Foundation

// Coercion extension stubs (STDLIB-150) for kotlin.ranges.

extension DataFlowSemaPhase {
    func registerSyntheticCoercionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinRangesPkg = kotlinPkg + [interner.intern("ranges")]

        // Ensure packages exist
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg, declSite: nil, visibility: .public, flags: [.synthetic])
        }
        let rangesPackageSymbol: SymbolID
        if let existing = symbols.lookup(fqName: kotlinRangesPkg) {
            rangesPackageSymbol = existing
        } else {
            rangesPackageSymbol = symbols.define(kind: .package, name: interner.intern("ranges"), fqName: kotlinRangesPkg, declSite: nil, visibility: .public, flags: [.synthetic])
            if let kotlinSym = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinSym, for: rangesPackageSymbol)
            }
        }

        // coerceIn(minimumValue: Int, maximumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_int_coerceIn",
            receiverType: types.intType,
            parameters: [
                (name: "minimumValue", type: types.intType),
                (name: "maximumValue", type: types.intType),
            ],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // coerceAtLeast(minimumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceAtLeast",
            externalLinkName: "kk_int_coerceAtLeast",
            receiverType: types.intType,
            parameters: [(name: "minimumValue", type: types.intType)],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // coerceAtMost(maximumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceAtMost",
            externalLinkName: "kk_int_coerceAtMost",
            receiverType: types.intType,
            parameters: [(name: "maximumValue", type: types.intType)],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoercionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        // Check if already registered with same signature
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
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
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for param in parameters {
            let paramName = interner.intern(param.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: functionSymbol
        )
    }
}
