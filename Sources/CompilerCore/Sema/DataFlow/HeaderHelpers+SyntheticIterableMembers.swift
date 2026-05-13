// swiftlint:disable file_length

/// Per-member synthetic Iterable<E> registrations:
/// `asSequence`, `joinTo`, `firstNotNullOf{,OrNull}`, `all`, `last`,
/// `joinToString`, `windowed(transform:)`, `plusElement`,
/// `minusElement`, `reduceRight*`, `sumBy{,Double}`.
///
/// Split out from `HeaderHelpers+SyntheticIterableStubs.swift`.
extension DataFlowSemaPhase {
    /// runtime we delegate to `kk_iterable_asSequence` which handles any
    /// collection handle (List, Set, Array) via `runtimeCollectionElements`.
    func registerIterableAsSequenceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("asSequence")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        // Retrieve the type parameter E from Iterable<E>.
        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        // Return type is Sequence<E> — ensure the Sequence interface stub exists.
        let sequenceSymbol = ensureSyntheticSequenceStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        // At runtime, use kk_iterable_asSequence which handles List, Set, and Array handles.
        // The corresponding ExternDecl is exposed via RuntimeABIExterns and
        // it is registered as non-throwing in ABILoweringPass+NonThrowingCallees.swift.
        symbols.setExternalLinkName("kk_iterable_asSequence", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.joinTo(buffer, separator, prefix, postfix)` (STDLIB-COL-FN-102).
    ///
    /// This mirrors the subset already supported by `joinToString`: separator,
    /// prefix, and postfix defaults, without limit/truncated/transform.
    func registerIterableJoinToMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("joinTo")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let kotlinTextPkg = ensurePackage(path: ["kotlin", "text"], symbols: symbols, interner: interner)
        let appendableSymbol = ensureInterfaceSymbol(
            named: "Appendable",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: appendableSymbol)
        }
        let appendableType = types.make(.classType(ClassType(
            classSymbol: appendableSymbol,
            args: [],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_joinTo", for: memberSymbol)

        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("buffer", appendableType, false),
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
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
            parameterDefaults.append(parameter.hasDefault)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: appendableType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.firstNotNullOfOrNull(transform)` (STDLIB-COL-HOF-002).
    func registerIterableFirstNotNullOfOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("firstNotNullOfOrNull")
        let memberFQName = iterableFQName + [memberName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: resultTypeParamName,
            fqName: memberFQName + [resultTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: resultType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [transformType]
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(
            StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: "firstNotNullOfOrNull",
                arity: 1,
                fallback: "kk_iterable_firstNotNullOfOrNull"
            ),
            for: memberSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [transformType],
                returnType: resultType,
                typeParameterSymbols: [iterableTypeParamSymbol, resultTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.all(predicate)` (STDLIB-COL-FN-007).
    func registerIterableAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("all")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_all", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.booleanType,
                typeParameterSymbols: [iterableTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.last()` (STDLIB-COL-FN-104).
    func registerIterableLastMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("last")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_last", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: elementType,
                canThrow: true,
                typeParameterSymbols: [iterableTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.joinToString(separator, prefix, postfix)` (STDLIB-COL-FN-103).
    func registerIterableJoinToStringMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("joinToString")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_joinToString", for: memberSymbol)

        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
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
            parameterDefaults.append(parameter.hasDefault)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: types.stringType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [iterableTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.windowed(size, step, partialWindows, transform)` HOF overload (STDLIB-COL-WIN-001).
    ///
    /// Kotlin signature:
    /// `fun <T, R> Iterable<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (List<T>) -> R): List<R>`
    ///
    /// The runtime ABI erases `R`, so the return type is modeled as `List<Any>`.
    func registerIterableWindowedTransformMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("windowed")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName ?? kotlinCollectionsPkg + [interner.intern("List")]
        let listTypeParamFQName = listFQName + [interner.intern("E")]
        guard let listTypeParamSymbol = symbols.lookup(fqName: listTypeParamFQName) else { return }
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol,
            nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let transformParameterType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [transformParameterType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listOfAnyReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(types.anyType)],
            nullability: .nonNull
        )))

        func registerWindowedTransformOverload(_ parameterTypes: [TypeID]) {
            let existingOverloads = symbols.lookupAll(fqName: memberFQName)
            let alreadyRegistered = existingOverloads.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == parameterTypes
                    && symbols.externalLinkName(for: symID) == "kk_list_windowed_transform"
            }
            guard !alreadyRegistered else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_windowed_transform", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: listOfAnyReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerWindowedTransformOverload([types.intType, transformType])
        registerWindowedTransformOverload([types.intType, types.intType, transformType])
        registerWindowedTransformOverload([types.intType, types.intType, types.booleanType, transformType])
    }

    /// Register `Iterable<E>.firstNotNullOf(transform)` (STDLIB-COL-HOF-001).
    func registerIterableFirstNotNullOfMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("firstNotNullOf")
        let memberFQName = iterableFQName + [memberName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: resultTypeParamName,
            fqName: memberFQName + [resultTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nonNull
        )))
        let nullableResultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: nullableResultType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [transformType]
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(
            StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: "firstNotNullOf",
                arity: 1,
                fallback: "kk_iterable_firstNotNullOf"
            ),
            for: memberSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [transformType],
                returnType: resultType,
                typeParameterSymbols: [iterableTypeParamSymbol, resultTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.plusElement(element): List<E>`.
    func registerIterablePlusElementMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("plusElement")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_plus_element", for: memberSymbol)
        let elementParameterName = interner.intern("element")
        let elementParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: elementParameterName,
            fqName: memberFQName + [elementParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: elementParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: returnType,
                valueParameterSymbols: [elementParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<T>.reduceRight(operation: (T, S) -> S): S`.
    func registerIterableReduceRightMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("reduceRight")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let accumulatorTypeParamName = interner.intern("S")
        let accumulatorTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: accumulatorTypeParamName,
            fqName: memberFQName + [accumulatorTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let accumulatorType = types.make(.typeParam(TypeParamType(
            symbol: accumulatorTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let operationType = types.make(.functionType(FunctionType(
            params: [elementType, accumulatorType],
            returnType: accumulatorType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduceRight", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: accumulatorType,
                typeParameterSymbols: [iterableTypeParamSymbol, accumulatorTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.minusElement(element): List<E>` (STDLIB-COL-HOF-005).
    func registerIterableReduceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("reduce")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let accumulatorTypeParamName = interner.intern("S")
        let accumulatorTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: accumulatorTypeParamName,
            fqName: memberFQName + [accumulatorTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let accumulatorType = types.make(.typeParam(TypeParamType(
            symbol: accumulatorTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let operationType = types.make(.functionType(FunctionType(
            params: [accumulatorType, elementType],
            returnType: accumulatorType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduce", for: memberSymbol)
        let operationParameterName = interner.intern("operation")
        let operationParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: operationParameterName,
            fqName: memberFQName + [operationParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: operationParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: accumulatorType,
                valueParameterSymbols: [operationParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [iterableTypeParamSymbol, accumulatorTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<T>.reduceIndexed(operation: (Int, S, T) -> S): S`.

    func registerIterableReduceIndexedMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("reduceIndexed")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let accumulatorTypeParamName = interner.intern("S")
        let accumulatorTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: accumulatorTypeParamName,
            fqName: memberFQName + [accumulatorTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let accumulatorType = types.make(.typeParam(TypeParamType(
            symbol: accumulatorTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let operationType = types.make(.functionType(FunctionType(
            params: [types.intType, accumulatorType, elementType],
            returnType: accumulatorType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduceIndexed", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: accumulatorType,
                typeParameterSymbols: [iterableTypeParamSymbol, accumulatorTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.minusElement(element): List<E>` (STDLIB-COL-HOF-005).

    func registerIterableMinusElementMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("minusElement")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_minus_element", for: memberSymbol)
        let elementParameterName = interner.intern("element")
        let elementParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: elementParameterName,
            fqName: memberFQName + [elementParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: elementParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: returnType,
                valueParameterSymbols: [elementParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.reduceRightIndexed(operation): S` (STDLIB-COL-HOF-006).
    func registerIterableReduceRightIndexedMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("reduceRightIndexed")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let operationType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType, typeParamType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduceRightIndexed", for: memberSymbol)
        let operationParameterName = interner.intern("operation")
        let operationParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: operationParameterName,
            fqName: memberFQName + [operationParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: operationParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: typeParamType,
                valueParameterSymbols: [operationParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.reduceRightIndexedOrNull(operation): S?` (STDLIB-COL-HOF-007).
    func registerIterableReduceRightIndexedOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("reduceRightIndexedOrNull")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let nullableElementType = types.makeNullable(typeParamType)
        let operationType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType, typeParamType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduceRightIndexedOrNull", for: memberSymbol)
        let operationParameterName = interner.intern("operation")
        let operationParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: operationParameterName,
            fqName: memberFQName + [operationParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: operationParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: nullableElementType,
                valueParameterSymbols: [operationParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.reduceRightOrNull(operation): S?` (STDLIB-COL-HOF-008).
    func registerIterableReduceRightOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("reduceRightOrNull")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let nullableElementType = types.makeNullable(typeParamType)
        let operationType = types.make(.functionType(FunctionType(
            params: [typeParamType, typeParamType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_reduceRightOrNull", for: memberSymbol)
        let operationParameterName = interner.intern("operation")
        let operationParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: operationParameterName,
            fqName: memberFQName + [operationParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: operationParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: nullableElementType,
                valueParameterSymbols: [operationParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.sumBy(selector): Int` (STDLIB-COL-HOF-009).
    func registerIterableSumByMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("sumBy")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.intType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(
            StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: "sumBy",
                arity: 1,
                fallback: "kk_list_sumBy"
            ),
            for: memberSymbol
        )
        symbols.setAnnotations([
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use sumOf instead.\"",
                    "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                ]
            ),
        ], for: memberSymbol)
        let selectorParameterName = interner.intern("selector")
        let selectorParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: selectorParameterName,
            fqName: memberFQName + [selectorParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: selectorParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [selectorType],
                returnType: types.intType,
                valueParameterSymbols: [selectorParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.sumByDouble(selector): Double` (STDLIB-COL-HOF-010).
    func registerIterableSumByDoubleMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("sumByDouble")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.doubleType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(
            StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: "sumByDouble",
                arity: 1,
                fallback: "kk_list_sumByDouble"
            ),
            for: memberSymbol
        )
        symbols.setAnnotations([
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use sumOf instead.\"",
                    "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                ]
            ),
        ], for: memberSymbol)
        let selectorParameterName = interner.intern("selector")
        let selectorParameterSymbol = symbols.define(
            kind: .valueParameter,
            name: selectorParameterName,
            fqName: memberFQName + [selectorParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: selectorParameterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [selectorType],
                returnType: types.doubleType,
                valueParameterSymbols: [selectorParameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }
}
