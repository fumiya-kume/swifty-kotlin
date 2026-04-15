import Foundation

/// Synthetic stdlib stubs for kotlin.DeepRecursiveFunction / kotlin.DeepRecursiveScope.
///
/// This implementation follows the compiler's existing synthetic-stdlib model.
/// The full Kotlin stdlib API uses suspend member extensions inside DeepRecursiveScope,
/// but this compiler currently models only a single explicit receiver in
/// FunctionSignature. To preserve source compatibility for common usage patterns,
/// we expose:
/// - DeepRecursiveScope<T, R>.callRecursive(value: T): R
/// - DeepRecursiveFunction<T, R>.callRecursive(value: T): R
/// - DeepRecursiveFunction<T, R>.invoke(value: T): R
///
/// The runtime provides the corresponding entry points.
extension DataFlowSemaPhase {
    func registerSyntheticDeepRecursiveStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg)

        let scopeSymbol = ensureClassSymbol(
            named: "DeepRecursiveScope",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: scopeSymbol)
        }

        let functionSymbol = ensureClassSymbol(
            named: "DeepRecursiveFunction",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: functionSymbol)
        }

        let scopeTypeParams = ensureNominalTypeParameters(
            ownerSymbol: scopeSymbol,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveScope")],
            names: ["T", "R"],
            symbols: symbols,
            interner: interner
        )
        let functionTypeParams = ensureNominalTypeParameters(
            ownerSymbol: functionSymbol,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveFunction")],
            names: ["T", "R"],
            symbols: symbols,
            interner: interner
        )

        types.setNominalTypeParameterSymbols(scopeTypeParams, for: scopeSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: scopeSymbol)
        types.setNominalTypeParameterSymbols(functionTypeParams, for: functionSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: functionSymbol)

        let scopeTType = types.make(.typeParam(TypeParamType(symbol: scopeTypeParams[0], nullability: .nonNull)))
        let scopeRType = types.make(.typeParam(TypeParamType(symbol: scopeTypeParams[1], nullability: .nonNull)))
        let functionTType = types.make(.typeParam(TypeParamType(symbol: functionTypeParams[0], nullability: .nonNull)))
        let functionRType = types.make(.typeParam(TypeParamType(symbol: functionTypeParams[1], nullability: .nonNull)))

        let scopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(scopeTType), .invariant(scopeRType)],
            nullability: .nonNull
        )))
        let scopeTypeInFunctionContext = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(functionTType), .invariant(functionRType)],
            nullability: .nonNull
        )))
        let functionType = types.make(.classType(ClassType(
            classSymbol: functionSymbol,
            args: [.invariant(functionTType), .invariant(functionRType)],
            nullability: .nonNull
        )))
        let functionTypeInScopeContext = types.make(.classType(ClassType(
            classSymbol: functionSymbol,
            args: [.invariant(scopeTType), .invariant(scopeRType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(scopeType, for: scopeSymbol)
        symbols.setPropertyType(functionType, for: functionSymbol)

        let blockType = types.make(.functionType(FunctionType(
            receiver: scopeTypeInFunctionContext,
            params: [functionTType],
            returnType: functionRType,
            nullability: .nonNull
        )))

        registerDeepRecursiveConstructor(
            ownerSymbol: functionSymbol,
            ownerType: functionType,
            parameterType: blockType,
            classTypeParameterSymbols: functionTypeParams,
            symbols: symbols,
            interner: interner
        )

        registerDeepRecursiveMember(
            ownerSymbol: functionSymbol,
            ownerType: functionType,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveFunction")],
            typeParameterSymbols: functionTypeParams,
            name: "invoke",
            parameters: [(name: "value", type: functionTType)],
            returnType: functionRType,
            externalLinkName: "kk_deep_recursive_function_invoke",
            isSuspend: false,
            extraFlags: [.operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerDeepRecursiveMember(
            ownerSymbol: functionSymbol,
            ownerType: functionType,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveFunction")],
            typeParameterSymbols: functionTypeParams,
            name: "callRecursive",
            parameters: [(name: "value", type: functionTType)],
            returnType: functionRType,
            externalLinkName: "kk_deep_recursive_function_callRecursive",
            isSuspend: true,
            extraFlags: [],
            symbols: symbols,
            interner: interner
        )

        registerDeepRecursiveMember(
            ownerSymbol: scopeSymbol,
            ownerType: scopeType,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveScope")],
            typeParameterSymbols: scopeTypeParams,
            name: "callRecursive",
            parameters: [(name: "value", type: scopeTType)],
            returnType: scopeRType,
            externalLinkName: "kk_deep_recursive_scope_callRecursive",
            isSuspend: true,
            extraFlags: [],
            symbols: symbols,
            interner: interner
        )

        registerDeepRecursiveMember(
            ownerSymbol: scopeSymbol,
            ownerType: functionTypeInScopeContext,
            ownerFQName: kotlinPkg + [interner.intern("DeepRecursiveScope")],
            typeParameterSymbols: scopeTypeParams,
            name: "callRecursive",
            parameters: [(name: "value", type: scopeTType)],
            returnType: scopeRType,
            externalLinkName: "kk_deep_recursive_function_callRecursive",
            isSuspend: true,
            extraFlags: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureNominalTypeParameters(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        names: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SymbolID] {
        names.map { name in
            let internedName = interner.intern(name)
            let fqName = ownerFQName + [internedName]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(ownerSymbol, for: symbol)
            return symbol
        }
    }

    private func registerDeepRecursiveConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameterType: TypeID,
        classTypeParameterSymbols: [SymbolID],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let initFQName = ownerInfo.fqName + [initName]
        guard symbols.lookupAll(fqName: initFQName).isEmpty else {
            return
        }

        let initSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: initSymbol)
        symbols.setExternalLinkName("kk_deep_recursive_function_new", for: initSymbol)

        let blockName = interner.intern("block")
        let blockSymbol = symbols.define(
            kind: .valueParameter,
            name: blockName,
            fqName: initFQName + [blockName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(initSymbol, for: blockSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [parameterType],
                returnType: ownerType,
                valueParameterSymbols: [blockSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: initSymbol
        )
    }

    private func registerDeepRecursiveMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        ownerFQName: [InternedString],
        typeParameterSymbols: [SymbolID],
        name: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        isSuspend: Bool,
        extraFlags: SymbolFlags,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = ownerFQName + [memberName]
        let hasMatchingOverload = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
                && signature.isSuspend == isSuspend
        }
        guard !hasMatchingOverload else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: SymbolFlags.synthetic.union(extraFlags)
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
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
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: typeParameterSymbols.count
            ),
            for: memberSymbol
        )
    }

}
