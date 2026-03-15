import Foundation

/// Synthetic stubs for Result<T>, runCatching, and related member functions (STDLIB-280/281/282/283).
extension DataFlowSemaPhase {
    func registerSyntheticResultStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]

        // --- Result<T> class symbol ---
        let resultSymbol = ensureClassSymbol(named: "Result", in: kotlinPkg, symbols: symbols, interner: interner)

        // Type parameter T
        let tName = interner.intern("T")
        let resultFQName = kotlinPkg + [interner.intern("Result")]
        let tFQName = resultFQName + [tName]
        let tSymbol: SymbolID
        if let existing = symbols.lookup(fqName: tFQName) {
            tSymbol = existing
        } else {
            tSymbol = symbols.define(
                kind: .typeParameter,
                name: tName,
                fqName: tFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(resultSymbol, for: tSymbol)
        }

        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        let nullableTType = types.makeNullable(tType)

        let resultType = types.make(.classType(ClassType(
            classSymbol: resultSymbol, args: [.out(tType)], nullability: .nonNull
        )))

        // Throwable type
        let throwableFQName = kotlinPkg + [interner.intern("Throwable")]
        let throwableSymbol: SymbolID
        if let existing = symbols.lookup(fqName: throwableFQName) {
            throwableSymbol = existing
        } else {
            throwableSymbol = symbols.define(
                kind: .class,
                name: interner.intern("Throwable"),
                fqName: throwableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nonNull
        )))
        let nullableThrowableType = types.makeNullable(throwableType)

        let boolType = types.booleanType
        let anyType = types.anyType

        // --- STDLIB-280: runCatching top-level function ---
        // fun <T> runCatching(block: () -> T): Result<T>
        let blockType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [],
            returnType: tType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerResultTopLevelFunction(
            named: "runCatching",
            packageFQName: kotlinPkg,
            parameters: [("block", blockType)],
            returnType: resultType,
            externalLinkName: "kk_runCatching",
            typeParameterSymbols: [tSymbol],
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-281: Result properties ---
        registerResultMemberProperty(
            named: "isSuccess",
            externalLinkName: "kk_result_isSuccess",
            ownerSymbol: resultSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerResultMemberProperty(
            named: "isFailure",
            externalLinkName: "kk_result_isFailure",
            ownerSymbol: resultSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-282: Result member functions ---

        // getOrNull(): T?
        registerResultMemberFunction(
            named: "getOrNull",
            externalLinkName: "kk_result_getOrNull",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [],
            returnType: nullableTType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // getOrDefault(defaultValue: T): T
        registerResultMemberFunction(
            named: "getOrDefault",
            externalLinkName: "kk_result_getOrDefault",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [("defaultValue", tType, false, false)],
            returnType: tType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // getOrElse(onFailure: (Throwable) -> T): T
        let onFailureLambdaType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [throwableType],
            returnType: tType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerResultMemberFunction(
            named: "getOrElse",
            externalLinkName: "kk_result_getOrElse",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [("onFailure", onFailureLambdaType, false, false)],
            returnType: tType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // getOrThrow(): T
        registerResultMemberFunction(
            named: "getOrThrow",
            externalLinkName: "kk_result_getOrThrow",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [],
            returnType: tType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // exceptionOrNull(): Throwable?
        registerResultMemberFunction(
            named: "exceptionOrNull",
            externalLinkName: "kk_result_exceptionOrNull",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [],
            returnType: nullableThrowableType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-283: Result HOF functions ---

        // map(transform: (T) -> R): Result<R>
        let rName = interner.intern("R")

        // Create map-scoped R type parameter
        let mapRFQName = resultFQName + [interner.intern("map"), rName]
        let mapRSymbol: SymbolID
        if let existing = symbols.lookup(fqName: mapRFQName) {
            mapRSymbol = existing
        } else {
            mapRSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let mapRType = types.make(.typeParam(TypeParamType(symbol: mapRSymbol, nullability: .nonNull)))

        let mapTransformType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [tType],
            returnType: mapRType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let resultMapRType = types.make(.classType(ClassType(
            classSymbol: resultSymbol, args: [.out(mapRType)], nullability: .nonNull
        )))
        registerResultMemberFunction(
            named: "map",
            externalLinkName: "kk_result_map",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [("transform", mapTransformType, false, false)],
            returnType: resultMapRType,
            typeParameterSymbols: [tSymbol, mapRSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R
        // Create fold-scoped R type parameter
        let foldRFQName = resultFQName + [interner.intern("fold"), rName]
        let foldRSymbol: SymbolID
        if let existing = symbols.lookup(fqName: foldRFQName) {
            foldRSymbol = existing
        } else {
            foldRSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: foldRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let foldRType = types.make(.typeParam(TypeParamType(symbol: foldRSymbol, nullability: .nonNull)))

        let foldOnSuccessType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [tType],
            returnType: foldRType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let foldOnFailureType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [throwableType],
            returnType: foldRType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerResultMemberFunction(
            named: "fold",
            externalLinkName: "kk_result_fold",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [
                ("onSuccess", foldOnSuccessType, false, false),
                ("onFailure", foldOnFailureType, false, false),
            ],
            returnType: foldRType,
            typeParameterSymbols: [tSymbol, foldRSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // onSuccess(action: (T) -> Unit): Result<T>
        let onSuccessActionType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [tType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerResultMemberFunction(
            named: "onSuccess",
            externalLinkName: "kk_result_onSuccess",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [("action", onSuccessActionType, false, false)],
            returnType: resultType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // onFailure(action: (Throwable) -> Unit): Result<T>
        let onFailureActionType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [throwableType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerResultMemberFunction(
            named: "onFailure",
            externalLinkName: "kk_result_onFailure",
            ownerSymbol: resultSymbol,
            ownerType: resultType,
            parameters: [("action", onFailureActionType, false, false)],
            returnType: resultType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Result Helpers

    private func registerResultTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        typeParameterSymbols: [SymbolID],
        symbols: SymbolTable,
        interner: StringInterner
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

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func registerResultMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []

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
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    private func registerResultMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
