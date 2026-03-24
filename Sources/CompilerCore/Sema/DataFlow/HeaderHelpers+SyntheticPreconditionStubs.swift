import Foundation

/// Synthetic stdlib top-level functions for kotlin.require, kotlin.check, and kotlin.error (STDLIB-062).
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

        registerSyntheticPreconditionTopLevelFunction(
            named: "require",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "condition", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_require",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "require",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "condition", type: types.booleanType),
                (name: "lazyMessage", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_require_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "condition", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_check",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "check",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "condition", type: types.booleanType),
                (name: "lazyMessage", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_check_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        // STDLIB-258: assert(condition) and assert(condition, lazyMessage)
        registerSyntheticPreconditionTopLevelFunction(
            named: "assert",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "value", type: types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_precondition_assert",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "assert",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [
                (name: "value", type: types.booleanType),
                (name: "lazyMessage", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_precondition_assert_lazy",
            symbols: symbols,
            interner: interner,
            contractNonNullParameterIndex: 0
        )
        registerSyntheticPreconditionTopLevelFunction(
            named: "error",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "message", type: types.anyType)],
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

    private func registerSyntheticPreconditionTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner,
        contractNonNullParameterIndex: Int? = nil
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let contractNonNullParameterIndex,
               let signature = symbols.functionSignature(for: existing),
               contractNonNullParameterIndex < signature.valueParameterSymbols.count
            {
                let parameterSymbol = signature.valueParameterSymbols[contractNonNullParameterIndex]
                symbols.setContractNonNullEffect(
                    ContractNonNullEffect(
                        parameterSymbol: parameterSymbol,
                        appliesOnAnyReturn: true
                    ),
                    for: existing
                )
            }
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

        let valueParameterSymbols = parameters.map { parameter in
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
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
        if let contractNonNullParameterIndex,
           contractNonNullParameterIndex < valueParameterSymbols.count
        {
            let parameterSymbol = valueParameterSymbols[contractNonNullParameterIndex]
            symbols.setContractNonNullEffect(
                ContractNonNullEffect(
                    parameterSymbol: parameterSymbol,
                    appliesOnAnyReturn: true
                ),
                for: functionSymbol
            )
        }
    }
}
