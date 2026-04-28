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
        let cancellationName = interner.intern("CancellationException")
        let canonicalCancellationFQName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("cancellation"),
            cancellationName,
        ]
        let rootCancellationFQName = kotlinPkg + [cancellationName]
        if let canonicalCancellationSymbol = symbols.lookup(fqName: canonicalCancellationFQName) {
            if symbols.lookup(fqName: rootCancellationFQName) == nil {
                let rootCancellationSymbol = symbols.define(
                    kind: .typeAlias,
                    name: cancellationName,
                    fqName: rootCancellationFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                let canonicalCancellationType = types.make(.classType(ClassType(
                    classSymbol: canonicalCancellationSymbol, args: [], nullability: .nonNull
                )))
                symbols.setTypeAliasUnderlyingType(canonicalCancellationType, for: rootCancellationSymbol)
            }
        } else {
            let cancellationSymbol = ensureClassSymbol(
                named: "CancellationException",
                in: kotlinPkg,
                symbols: symbols,
                interner: interner
            )
            symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
            types.setNominalDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
            let cancellationType = types.make(.classType(ClassType(
                classSymbol: cancellationSymbol, args: [], nullability: .nonNull
            )))
            symbols.setPropertyType(cancellationType, for: cancellationSymbol)
            registerSyntheticExceptionConstructors(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol
            )
        }
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
        let noWhenBranchMatchedSymbol = ensureClassSymbol(
            named: "NoWhenBranchMatchedException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let concurrentModificationSymbol = ensureClassSymbol(
            named: "ConcurrentModificationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let errorSymbol = ensureClassSymbol(
            named: "Error",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let assertionErrorSymbol = ensureClassSymbol(
            named: "AssertionError",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        symbols.setDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        symbols.setDirectSupertypes([throwableSymbol], for: errorSymbol)
        symbols.setDirectSupertypes([errorSymbol], for: assertionErrorSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalArgumentSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalStateSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: indexOutOfBoundsSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: unsupportedOperationSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: noSuchElementSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: arithmeticSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: classCastSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: noWhenBranchMatchedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: concurrentModificationSymbol)

        // Register nominal supertypes in TypeSystem for subtype checking
        types.setNominalDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: illegalArgumentSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: illegalStateSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: indexOutOfBoundsSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: unsupportedOperationSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: noSuchElementSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: arithmeticSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: classCastSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: noWhenBranchMatchedSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: concurrentModificationSymbol)
        types.setNominalDirectSupertypes([throwableSymbol], for: errorSymbol)
        types.setNominalDirectSupertypes([errorSymbol], for: assertionErrorSymbol)

        for symbol in [
            throwableSymbol,
            exceptionSymbol,
            runtimeExceptionSymbol,
            uninitializedSymbol,
            nullPointerSymbol,
            numberFormatSymbol,
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
            noWhenBranchMatchedSymbol,
            concurrentModificationSymbol,
            errorSymbol,
            assertionErrorSymbol,
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
            includeMessageOverload: false,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: runtimeExceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: runtimeExceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: uninitializedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: uninitializedSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: nullPointerSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: nullPointerSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: numberFormatSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: numberFormatSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        for exSymbol in [
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
            errorSymbol,
            assertionErrorSymbol,
        ] {
            registerSyntheticExceptionConstructors(
                ownerSymbol: exSymbol,
                ownerType: types.make(.classType(ClassType(classSymbol: exSymbol, args: [], nullability: .nonNull))),
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol
            )
        }
        registerSyntheticNullableExceptionConstructors(
            ownerSymbol: noWhenBranchMatchedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: noWhenBranchMatchedSymbol, args: [], nullability: .nonNull))),
            throwableSymbol: throwableSymbol,
            externalLinkPrefix: "kk_no_when_branch_matched_exception",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNullableExceptionConstructors(
            ownerSymbol: concurrentModificationSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: concurrentModificationSymbol, args: [], nullability: .nonNull))),
            throwableSymbol: throwableSymbol,
            externalLinkPrefix: "kk_concurrent_modification_exception",
            symbols: symbols,
            types: types,
            interner: interner
        )

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

        // MARK: - Advanced exception features (STDLIB-EXCEPT-105)

        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nonNull
        )))
        let nullableThrowableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nullable
        )))

        // initCause(cause: Throwable?): Throwable
        let initCauseName = interner.intern("initCause")
        let initCauseFQName = throwableFQName + [initCauseName]
        if symbols.lookup(fqName: initCauseFQName) == nil {
            let initCauseSymbol = symbols.define(
                kind: .function,
                name: initCauseName,
                fqName: initCauseFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: initCauseSymbol)
            symbols.setExternalLinkName("kk_throwable_initCause", for: initCauseSymbol)

            let causeParamName = interner.intern("cause")
            let causeParamSymbol = symbols.define(
                kind: .valueParameter,
                name: causeParamName,
                fqName: initCauseFQName + [causeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initCauseSymbol, for: causeParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: throwableType,
                    parameterTypes: [nullableThrowableType],
                    returnType: throwableType,
                    valueParameterSymbols: [causeParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: initCauseSymbol
            )
        }

        // addSuppressed(exception: Throwable): Unit
        let addSuppressedName = interner.intern("addSuppressed")
        let addSuppressedFQName = throwableFQName + [addSuppressedName]
        if symbols.lookup(fqName: addSuppressedFQName) == nil {
            let addSuppressedSymbol = symbols.define(
                kind: .function,
                name: addSuppressedName,
                fqName: addSuppressedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: addSuppressedSymbol)
            symbols.setExternalLinkName("kk_throwable_addSuppressed", for: addSuppressedSymbol)

            let exceptionParamName = interner.intern("exception")
            let exceptionParamSymbol = symbols.define(
                kind: .valueParameter,
                name: exceptionParamName,
                fqName: addSuppressedFQName + [exceptionParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(addSuppressedSymbol, for: exceptionParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: throwableType,
                    parameterTypes: [throwableType],
                    returnType: types.unitType,
                    valueParameterSymbols: [exceptionParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: addSuppressedSymbol
            )
        }

        // getSuppressed(): Array<Throwable>
        let getSuppressedName = interner.intern("getSuppressed")
        let getSuppressedFQName = throwableFQName + [getSuppressedName]
        if symbols.lookup(fqName: getSuppressedFQName) == nil {
            let getSuppressedSymbol = symbols.define(
                kind: .function,
                name: getSuppressedName,
                fqName: getSuppressedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(throwableSymbol, for: getSuppressedSymbol)
            symbols.setExternalLinkName("kk_throwable_getSuppressed", for: getSuppressedSymbol)
            let returnType = makeSyntheticArrayType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: throwableType
            )
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: throwableType,
                    parameterTypes: [],
                    returnType: returnType
                ),
                for: getSuppressedSymbol
            )
        }
    }

    private func makeSyntheticArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func registerSyntheticExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        includeMessageOverload: Bool,
        throwableSymbol: SymbolID? = nil
    ) {
        registerSyntheticExceptionConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        if includeMessageOverload {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType)],
                externalLinkName: "kk_throwable_new",
                symbols: symbols,
                interner: interner
            )
        }
        // (message: String, cause: Throwable?) overload
        if includeMessageOverload, let throwableSymbol {
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol, args: [], nullability: .nullable
            )))
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType), ("cause", nullableThrowableType)],
                externalLinkName: "kk_throwable_new_with_cause",
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerSyntheticExceptionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
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
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

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

    private func registerSyntheticNullableExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        throwableSymbol: SymbolID,
        externalLinkPrefix: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableStringType = types.makeNullable(types.stringType)
        let nullableThrowableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let overloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            ([], "\(externalLinkPrefix)_new"),
            ([("message", nullableStringType)], "\(externalLinkPrefix)_new_message"),
            (
                [("message", nullableStringType), ("cause", nullableThrowableType)],
                "\(externalLinkPrefix)_new_message_cause"
            ),
            ([("cause", nullableThrowableType)], "\(externalLinkPrefix)_new_cause"),
        ]
        for overload in overloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }
    }
}
