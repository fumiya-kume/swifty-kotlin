import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeExceptionSymbol = ensureClassSymbol(
            named: "RuntimeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let uninitializedSymbol = ensureClassSymbol(
            named: "UninitializedPropertyAccessException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let nullPointerSymbol = ensureClassSymbol(
            named: "NullPointerException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let numberFormatSymbol = ensureClassSymbol(
            named: "NumberFormatException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let illegalArgumentSymbol = ensureClassSymbol(
            named: "IllegalArgumentException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let illegalStateSymbol = ensureClassSymbol(
            named: "IllegalStateException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let indexOutOfBoundsSymbol = ensureClassSymbol(
            named: "IndexOutOfBoundsException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let unsupportedOperationSymbol = ensureClassSymbol(
            named: "UnsupportedOperationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let noSuchElementSymbol = ensureClassSymbol(
            named: "NoSuchElementException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let arithmeticSymbol = ensureClassSymbol(
            named: "ArithmeticException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let classCastSymbol = ensureClassSymbol(
            named: "ClassCastException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        symbols.setDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalArgumentSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalStateSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: indexOutOfBoundsSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: unsupportedOperationSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: noSuchElementSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: arithmeticSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: classCastSymbol)

        for symbol in [
            throwableSymbol,
            exceptionSymbol,
            runtimeExceptionSymbol,
            uninitializedSymbol,
            nullPointerSymbol,
            numberFormatSymbol,
            cancellationSymbol,
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
        ] {
            let type = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            symbols.setPropertyType(type, for: symbol)
        }

        registerSyntheticExceptionConstructors(
            ownerSymbol: exceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: runtimeExceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: runtimeExceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: uninitializedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: uninitializedSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: nullPointerSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: nullPointerSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: numberFormatSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: numberFormatSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: cancellationSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: cancellationSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true
        )
        for exSymbol in [
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
        ] {
            registerSyntheticExceptionConstructors(
                ownerSymbol: exSymbol,
                ownerType: types.make(.classType(ClassType(classSymbol: exSymbol, args: [], nullability: .nonNull))),
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true
            )
        }

        // MARK: - Throwable member properties (STDLIB-127)

        let throwableFQName = kotlinPkg + [interner.intern("Throwable")]

        // message: String?
        let messageName = interner.intern("message")
        let messageFQName = throwableFQName + [messageName]
        if symbols.lookup(fqName: messageFQName) == nil {
            let messagePropSymbol = symbols.define(
                kind: .property,
                name: messageName,
                fqName: messageFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: messagePropSymbol)
            symbols.setExternalLinkName("kk_throwable_message", for: messagePropSymbol)
            let nullableStringType = types.makeNullable(types.stringType)
            symbols.setPropertyType(nullableStringType, for: messagePropSymbol)
        }

        // cause: Throwable?
        let causeName = interner.intern("cause")
        let causeFQName = throwableFQName + [causeName]
        if symbols.lookup(fqName: causeFQName) == nil {
            let causePropSymbol = symbols.define(
                kind: .property,
                name: causeName,
                fqName: causeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: causePropSymbol)
            symbols.setExternalLinkName("kk_throwable_cause", for: causePropSymbol)
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol, args: [], nullability: .nullable
            )))
            symbols.setPropertyType(nullableThrowableType, for: causePropSymbol)
        }

        // stackTraceToString(): String
        let stackTraceName = interner.intern("stackTraceToString")
        let stackTraceFQName = throwableFQName + [stackTraceName]
        if symbols.lookup(fqName: stackTraceFQName) == nil {
            let stackTraceSymbol = symbols.define(
                kind: .function,
                name: stackTraceName,
                fqName: stackTraceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: stackTraceSymbol)
            symbols.setExternalLinkName("kk_throwable_stackTraceToString", for: stackTraceSymbol)
            let throwableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol, args: [], nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: throwableType,
                    parameterTypes: [],
                    returnType: types.stringType
                ),
                for: stackTraceSymbol
            )
        }
    }

    private func registerSyntheticExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        includeMessageOverload: Bool
    ) {
        registerSyntheticExceptionConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        if includeMessageOverload {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType)],
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticExceptionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName("kk_throwable_new", for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }
}
