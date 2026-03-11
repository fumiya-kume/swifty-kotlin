import Foundation

/// Synthetic stdlib top-level functions for kotlin.require, kotlin.check, kotlin.error (STDLIB-062).
/// These stubs enable name resolution and type checking; runtime behavior is implemented in Runtime.
extension DataFlowSemaPhase {
    func registerSyntheticPreconditionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let packageSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        registerSyntheticPreconditionFunction(
            named: "require",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameterName: "condition",
            parameterType: types.booleanType,
            returnType: types.unitType,
            externalLinkName: "kk_require",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticPreconditionFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameterName: "condition",
            parameterType: types.booleanType,
            returnType: types.unitType,
            externalLinkName: "kk_check",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticPreconditionFunction(
            named: "error",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameterName: "message",
            parameterType: types.stringType,
            returnType: types.nothingType,
            externalLinkName: "kk_error",
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerSyntheticPreconditionFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == [parameterType]
                && existingSignature.returnType == returnType
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
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        let paramNameID = interner.intern(parameterName)
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramNameID,
            fqName: functionFQName + [paramNameID],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: paramSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [parameterType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
        )
    }
}
