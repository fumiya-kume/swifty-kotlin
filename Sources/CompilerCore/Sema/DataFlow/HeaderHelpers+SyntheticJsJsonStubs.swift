import Foundation

/// Synthetic Kotlin/JS `Json` interface and `json` factory function surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsJsonStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )

        let jsonSymbol = ensureInterfaceSymbol(
            named: "Json",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: jsonSymbol)
        }
        let jsonType = types.make(.classType(ClassType(
            classSymbol: jsonSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsonType, for: jsonSymbol)

        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairStringNullableAnyType = symbols.lookup(fqName: pairFQName).map { pairSymbol in
            types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [
                    .out(types.stringType),
                    .out(types.nullableAnyType),
                ],
                nullability: .nonNull
            )))
        } ?? types.anyType

        registerSyntheticJsJsonFunction(
            packageFQName: kotlinJsPkg,
            pairType: pairStringNullableAnyType,
            returnType: jsonType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsJsonFunction(
        packageFQName: [InternedString],
        pairType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("json")
        let functionFQName = packageFQName + [functionName]
        let alreadyRegistered = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [pairType]
                && signature.returnType == returnType
                && signature.valueParameterIsVararg == [true]
        }
        guard !alreadyRegistered else { return }

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

        let parameterName = interner.intern("pairs")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        symbols.setPropertyType(pairType, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [pairType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true]
            ),
            for: functionSymbol
        )
    }
}
