import Foundation

/// Synthetic Kotlin/JS `Promise<out T>` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsPromiseStubs(
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

        let promiseName = interner.intern("Promise")
        let promiseFQName = kotlinJsPkg + [promiseName]
        let promiseSymbol: SymbolID
        if let existing = symbols.lookup(fqName: promiseFQName),
           symbols.symbol(existing)?.kind == .class {
            promiseSymbol = existing
        } else {
            promiseSymbol = symbols.define(
                kind: .class,
                name: promiseName,
                fqName: promiseFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: promiseSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = promiseFQName + [typeParamName]
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
                flags: []
            )
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let promiseType = types.make(.classType(ClassType(
            classSymbol: promiseSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: promiseSymbol)
        types.setNominalTypeParameterVariances([.out], for: promiseSymbol)
        symbols.setPropertyType(promiseType, for: promiseSymbol)

        registerJsPromiseThenOnFulfilled(
            ownerSymbol: promiseSymbol,
            ownerType: promiseType,
            classTypeParameterType: typeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let throwableType = ensureJsPromiseThrowableType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerJsPromiseThenOnFulfilledOnRejected(
            ownerSymbol: promiseSymbol,
            ownerType: promiseType,
            classTypeParameterType: typeParamType,
            throwableType: throwableType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJsPromiseThenOnFulfilled(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        classTypeParameterType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }

        let functionName = interner.intern("then")
        let functionFQName = ownerInfo.fqName + [functionName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamFQName = functionFQName + [resultTypeParamName]
        let resultTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: resultTypeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            resultTypeParamSymbol = existing
        } else {
            resultTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: resultTypeParamName,
                fqName: resultTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }

        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nonNull
        )))
        let onFulfilledType = types.make(.functionType(FunctionType(
            params: [classTypeParameterType],
            returnType: resultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let promiseReturnType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.out(resultType)],
            nullability: .nonNull
        )))

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == [onFulfilledType]
                && signature.returnType == promiseReturnType
                && signature.typeParameterSymbols == [resultTypeParamSymbol]
        }) {
            symbols.setParentSymbol(existing, for: resultTypeParamSymbol)
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
        symbols.setParentSymbol(functionSymbol, for: resultTypeParamSymbol)

        let parameterName = interner.intern("onFulfilled")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        symbols.setPropertyType(onFulfilledType, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [onFulfilledType],
                returnType: promiseReturnType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [resultTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func ensureJsPromiseThrowableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: throwableSymbol)
        }
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(throwableType, for: throwableSymbol)
        return throwableType
    }

    private func registerJsPromiseThenOnFulfilledOnRejected(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        classTypeParameterType: TypeID,
        throwableType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }

        let functionName = interner.intern("then")
        let functionFQName = ownerInfo.fqName + [functionName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamFQName = functionFQName + [resultTypeParamName]
        let resultTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: resultTypeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            resultTypeParamSymbol = existing
        } else {
            resultTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: resultTypeParamName,
                fqName: resultTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }

        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nonNull
        )))
        let onFulfilledType = types.make(.functionType(FunctionType(
            params: [classTypeParameterType],
            returnType: resultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let onRejectedType = types.make(.functionType(FunctionType(
            params: [throwableType],
            returnType: resultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let promiseReturnType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.out(resultType)],
            nullability: .nonNull
        )))
        let parameterTypes = [onFulfilledType, onRejectedType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == promiseReturnType
                && signature.typeParameterSymbols == [resultTypeParamSymbol]
        }) {
            symbols.setParentSymbol(existing, for: resultTypeParamSymbol)
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
        symbols.setParentSymbol(functionSymbol, for: resultTypeParamSymbol)

        let valueParameterSymbols = [
            ("onFulfilled", onFulfilledType),
            ("onRejected", onRejectedType),
        ].map { parameter -> SymbolID in
            let parameterName = interner.intern(parameter.0)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.1, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: promiseReturnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: [resultTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }
}
