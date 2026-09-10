import RuntimeABI

/// Synthetic stubs for residual `Sequence` member operations (`random`, `randomOrNull`,
/// `firstNotNullOf`, `firstNotNullOfOrNull`, `takeLast`,
/// `takeLastWhile`, `shuffled`, and `reversed`) that are not yet migrated
/// to bundled Kotlin source.
///
/// KSP-694: Consolidated residual Sequence stubs after KSP-441..446 and KSP-308
/// migrations of terminal/HOF Sequence APIs to bundled Kotlin source.
extension DataFlowSemaPhase {
    func registerSyntheticSequenceResidualMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinSequencesPkg: [InternedString]
    ) {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))

        func nominalCollectionType(_ fqName: [InternedString], elementType: TypeID, invariant: Bool = false) -> TypeID {
            guard let symbol = symbols.lookup(fqName: fqName) else {
                return types.anyType
            }
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [invariant ? .invariant(elementType) : .out(elementType)],
                nullability: .nonNull
            )))
        }

        let listReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ], elementType: typeParamType)

        // random(): T
        registerSequenceMemberStub(
            named: "random",
            externalLinkName: "kk_sequence_random",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // randomOrNull(): T?
        registerSequenceMemberStub(
            named: "randomOrNull",
            externalLinkName: "kk_sequence_randomOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // firstNotNullOf<T, R>(transform: (T) -> R?): R
        // Use a method-local T parameter (independent of Sequence's `out T`)
        // so the projection on the receiver does not block referencing T in
        // the transform's `in` position.
        do {
            let memberName = interner.intern("firstNotNullOf")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOf",
                externalLinkName: "kk_sequence_firstNotNullOf",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: rType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // firstNotNullOfOrNull<T, R>(transform: (T) -> R?): R?
        do {
            let memberName = interner.intern("firstNotNullOfOrNull")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOfOrNull",
                externalLinkName: "kk_sequence_firstNotNullOfOrNull",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: types.makeNullable(rType),
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // takeLast(n: Int): List<T> (STDLIB-SEQ-FN-120)
        registerSequenceMemberStub(
            named: "takeLast",
            externalLinkName: "kk_sequence_takeLast",
            receiverType: receiverType,
            parameters: [("n", types.intType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // takeLastWhile(predicate: (T) -> Boolean): List<T> (STDLIB-SEQ-FN-121)
        registerSequenceMemberStub(
            named: "takeLastWhile",
            externalLinkName: "kk_sequence_takeLastWhile",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // shuffled() / shuffled(random): Sequence<T> (STDLIB-SEQ-019)
        do {
            let shuffledName = interner.intern("shuffled")
            let shuffledFQName = sequenceFQName + [shuffledName]

            func registerShuffledOverload(
                parameters: [(name: String, type: TypeID)],
                externalLinkName: String
            ) {
                let alreadyRegistered = symbols.lookupAll(fqName: shuffledFQName).contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.parameterTypes.count == parameters.count
                        && symbols.externalLinkName(for: symbolID) == externalLinkName
                }
                guard !alreadyRegistered else { return }

                let memberSymbol = symbols.define(
                    kind: .function,
                    name: shuffledName,
                    fqName: shuffledFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

                var parameterTypes: [TypeID] = []
                var parameterSymbols: [SymbolID] = []
                for parameter in parameters {
                    let parameterName = interner.intern(parameter.name)
                    let parameterSymbol = symbols.define(
                        kind: .valueParameter,
                        name: parameterName,
                        fqName: shuffledFQName + [parameterName],
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
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: receiverType,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                        valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[]],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            registerShuffledOverload(parameters: [], externalLinkName: "kk_sequence_shuffled")

            if let randomSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("random"),
                interner.intern("Random"),
            ]) {
                let randomType = types.make(.classType(ClassType(
                    classSymbol: randomSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                registerShuffledOverload(
                    parameters: [("random", randomType)],
                    externalLinkName: "kk_sequence_shuffled_random"
                )
            }
        }

        // reversed(): Sequence<T> (STDLIB-SEQ-FN-099)
        registerSequenceMemberStub(
            named: "reversed",
            externalLinkName: "kk_sequence_reversed",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

    }
}
