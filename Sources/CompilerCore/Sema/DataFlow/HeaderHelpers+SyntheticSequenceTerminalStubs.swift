// swiftlint:disable file_length
import RuntimeABI

/// Synthetic stubs for `Sequence` terminal operators (`toSet`, `toMap`,
/// `groupBy`, `maxOrNull`, `minOrNull`, `flatten`, `take`, `drop`,
/// `windowed`, etc.) backed by STDLIB-470.
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift` to keep
/// each header-helpers file scoped to a single responsibility.
extension DataFlowSemaPhase {
    func registerSyntheticSequenceTerminalMembers(
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
        let actionType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let foldIndexedOperationType = types.make(.functionType(FunctionType(
            params: [types.intType, types.anyType, typeParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let reduceIndexedOperationType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType, typeParamType],
            returnType: typeParamType,
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
        func registerSequenceOverloadedMemberStub(
            named name: String,
            externalLinkName: String,
            receiverType: TypeID,
            parameters: [(name: String, type: TypeID)],
            returnType: TypeID,
            additionalTypeParameterSymbols: [SymbolID] = [],
            additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
            canThrow: Bool = false
        ) {
            let memberName = interner.intern(name)
            let memberFQName = sequenceFQName + [memberName]
            let parameterTypes = parameters.map { $0.type }
            let hasMatchingSignature = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return sig.receiverType == receiverType
                    && sig.parameterTypes == parameterTypes
                    && sig.returnType == returnType
            }
            guard !hasMatchingSignature else { return }

            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
            let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: name,
                arity: parameterTypes.count,
                fallback: externalLinkName
            )
            symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)

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
                parameterSymbols.append(parameterSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    canThrow: canThrow,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                    valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                    typeParameterSymbols: [typeParamSymbol] + additionalTypeParameterSymbols,
                    typeParameterUpperBoundsList: [[]] + additionalTypeParameterUpperBoundsList,
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
        let listReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ], elementType: typeParamType)
        let mutableListReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ], elementType: typeParamType, invariant: true)
        let collectionReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ], elementType: typeParamType)
        let iterableReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ], elementType: typeParamType)
        let setReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ], elementType: typeParamType)
        let mutableSetReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ], elementType: typeParamType, invariant: true)

        // sorted(): Sequence<T>
        registerSequenceOverloadedMemberStub(
            named: "sorted",
            externalLinkName: "kk_sequence_sorted",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType
        )

        // sortedBy(selector: (T) -> R): Sequence<T>, where R : Comparable<R>
        do {
            let memberName = interner.intern("sortedBy")
            let memberFQName = sequenceFQName + [memberName]
            let selectorReturnType: TypeID
            let extraTypeParamSymbols: [SymbolID]
            let extraUpperBoundsList: [[TypeID]]
            if let rParam = makeComparableTypeParam(
                symbols: symbols,
                types: types,
                interner: interner,
                memberFQName: memberFQName
            ) {
                selectorReturnType = rParam.type
                extraTypeParamSymbols = [rParam.symbol]
                extraUpperBoundsList = [rParam.upperBounds]
            } else {
                selectorReturnType = types.anyType
                extraTypeParamSymbols = []
                extraUpperBoundsList = []
            }
            let selectorType = types.make(.functionType(FunctionType(
                params: [typeParamType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceOverloadedMemberStub(
                named: "sortedBy",
                externalLinkName: "kk_sequence_sortedBy",
                receiverType: receiverType,
                parameters: [("selector", selectorType)],
                returnType: receiverType,
                additionalTypeParameterSymbols: extraTypeParamSymbols,
                additionalTypeParameterUpperBoundsList: extraUpperBoundsList,
                canThrow: true
            )
        }

        // first(): T
        registerSequenceMemberStub(
            named: "first",
            externalLinkName: "kk_sequence_first",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // firstOrNull(): T?
        registerSequenceMemberStub(
            named: "firstOrNull",
            externalLinkName: "kk_sequence_firstOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
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
            interner: interner,
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

        // last(): T
        registerSequenceMemberStub(
            named: "last",
            externalLinkName: "kk_sequence_last",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // lastOrNull(): T?
        registerSequenceMemberStub(
            named: "lastOrNull",
            externalLinkName: "kk_sequence_lastOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // singleOrNull(): T?
        registerSequenceMemberStub(
            named: "singleOrNull",
            externalLinkName: "kk_sequence_singleOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // count(): Int
        registerSequenceMemberStub(
            named: "count",
            externalLinkName: "kk_sequence_count",
            receiverType: receiverType,
            parameters: [],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // fold(initial: R, operation: (R, T) -> R): R
        let foldName = interner.intern("fold")
        let foldFQName = sequenceFQName + [foldName]
        if symbols.lookup(fqName: foldFQName) == nil {
            let foldRName = interner.intern("R")
            let foldRSymbol = symbols.define(
                kind: .typeParameter,
                name: foldRName,
                fqName: foldFQName + [foldRName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let foldRType = types.make(.typeParam(TypeParamType(
                symbol: foldRSymbol,
                nullability: .nonNull
            )))
            let foldOperationType = types.make(.functionType(FunctionType(
                params: [foldRType, typeParamType],
                returnType: foldRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "fold",
                externalLinkName: "kk_sequence_fold",
                receiverType: receiverType,
                parameters: [
                    ("initial", foldRType),
                    ("operation", foldOperationType),
                ],
                returnType: foldRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [foldRSymbol]
            )
        }

        // contains(element: T): Boolean
        registerSequenceMemberStub(
            named: "contains",
            externalLinkName: "kk_sequence_contains",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // any(): Boolean
        registerSequenceMemberStub(
            named: "any",
            externalLinkName: "kk_sequence_any",
            receiverType: receiverType,
            parameters: [],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // indexOf(element: T): Int
        registerSequenceMemberStub(
            named: "indexOf",
            externalLinkName: "kk_sequence_indexOf",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // elementAtOrNull(index: Int): T?
        registerSequenceMemberStub(
            named: "elementAtOrNull",
            externalLinkName: "kk_sequence_elementAtOrNull",
            receiverType: receiverType,
            parameters: [("index", types.intType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // none(): Boolean
        registerSequenceMemberStub(
            named: "none",
            externalLinkName: "kk_sequence_none",
            receiverType: receiverType,
            parameters: [],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // elementAt(index: Int): T
        registerSequenceMemberStub(
            named: "elementAt",
            externalLinkName: "kk_sequence_elementAt",
            receiverType: receiverType,
            parameters: [("index", types.intType)],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // findLast(predicate: (T) -> Boolean): T?
        registerSequenceMemberStub(
            named: "findLast",
            externalLinkName: "kk_sequence_findLast",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // sum()/average()
        registerSequenceMemberStub(
            named: "sum",
            externalLinkName: "kk_sequence_sum",
            receiverType: receiverType,
            parameters: [],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSequenceMemberStub(
            named: "average",
            externalLinkName: "kk_sequence_average",
            receiverType: receiverType,
            parameters: [],
            returnType: types.doubleType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        do {
            let distinctByName = interner.intern("distinctBy")
            let distinctByFQName = sequenceFQName + [distinctByName]
            if symbols.lookup(fqName: distinctByFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: distinctByFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let selectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "distinctBy",
                    externalLinkName: "kk_sequence_distinctBy",
                    receiverType: receiverType,
                    parameters: [("selector", selectorType)],
                    returnType: receiverType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }
        }
        let sequenceElementToIntType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "sumOf",
            externalLinkName: "kk_sequence_sumOf",
            receiverType: receiverType,
            parameters: [("selector", sequenceElementToIntType)],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )
        registerSequenceMemberStub(
            named: "sumBy",
            externalLinkName: "kk_sequence_sumBy",
            receiverType: receiverType,
            parameters: [("selector", sequenceElementToIntType)],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            canThrow: true
        )
        let sequenceElementToDoubleType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.doubleType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "sumByDouble",
            externalLinkName: "kk_sequence_sumByDouble",
            receiverType: receiverType,
            parameters: [("selector", sequenceElementToDoubleType)],
            returnType: types.doubleType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            canThrow: true
        )

        // toList(): List<T>
        registerSequenceMemberStub(
            named: "toList",
            externalLinkName: "kk_sequence_to_list",
            receiverType: receiverType,
            parameters: [],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // STDLIB-SEQ-006: constrainOnce(): Sequence<T>
        registerSequenceMemberStub(
            named: "constrainOnce",
            externalLinkName: "kk_sequence_constrainOnce",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMutableList(): MutableList<T>
        registerSequenceMemberStub(
            named: "toMutableList",
            externalLinkName: "kk_sequence_toMutableList",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableListReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // asIterable(): Iterable<T>
        registerSequenceMemberStub(
            named: "asIterable",
            externalLinkName: "kk_sequence_asIterable",
            receiverType: receiverType,
            parameters: [],
            returnType: iterableReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMutableSet(): MutableSet<T>
        registerSequenceMemberStub(
            named: "toMutableSet",
            externalLinkName: "kk_sequence_toMutableSet",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableSetReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toHashSet(): MutableSet<T>
        registerSequenceMemberStub(
            named: "toHashSet",
            externalLinkName: "kk_sequence_toHashSet",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableSetReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toSortedSet(): MutableSet<T>
        registerSequenceMemberStub(
            named: "toSortedSet",
            externalLinkName: "kk_sequence_toSortedSet",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableSetReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toCollection(destination): Collection<T>
        registerSequenceMemberStub(
            named: "toCollection",
            externalLinkName: "kk_sequence_toCollection",
            receiverType: receiverType,
            parameters: [("destination", collectionReturnType)],
            returnType: collectionReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // filterNot(predicate): Sequence<T>
        registerSequenceMemberStub(
            named: "filterNot",
            externalLinkName: "kk_sequence_filterNot",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // takeWhile(predicate): Sequence<T>
        registerSequenceMemberStub(
            named: "takeWhile",
            externalLinkName: "kk_sequence_takeWhile",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSequenceMemberStub(
            named: "filterNotTo",
            externalLinkName: "kk_sequence_filterNotTo",
            receiverType: receiverType,
            parameters: [("destination", collectionReturnType), ("predicate", predicateType)],
            returnType: collectionReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatMap(transform): Sequence<R> for Iterable<R> and Sequence<R> transform results.
        do {
            let memberName = interner.intern("flatMap")
            let memberFQName = sequenceFQName + [memberName]
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: memberFQName + [rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: memberFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            func registerFlatMapOverload(transformReturnType: TypeID) {
                let transformType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: transformReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID),
                          signature.receiverType == receiverType,
                          signature.parameterTypes == [transformType],
                          signature.returnType == sequenceRType
                    else { return false }
                    return true
                }
                guard !alreadyRegistered else { return }

                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_sequence_flatMap", for: memberSymbol)

                let transformName = interner.intern("transform")
                let transformSymbol = symbols.define(
                    kind: .valueParameter,
                    name: transformName,
                    fqName: memberFQName + [transformName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: transformSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [transformType],
                        returnType: sequenceRType,
                        canThrow: true,
                        valueParameterSymbols: [transformSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: [typeParamSymbol, rSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            let iterableRType = makeSyntheticIterableType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: rType
            )
            registerFlatMapOverload(transformReturnType: iterableRType)
            registerFlatMapOverload(transformReturnType: sequenceRType)
        }

        // flatMapTo(destination, transform): Collection<R>
        do {
            let memberName = interner.intern("flatMapTo")
            let memberFQName = sequenceFQName + [memberName]
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: memberFQName + [rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: memberFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let destinationType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Collection"),
            ], elementType: rType)
            let transformReturnType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ], elementType: rType)
            let transformType = types.make(.functionType(FunctionType(
                params: [typeParamType],
                returnType: transformReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceOverloadedMemberStub(
                named: "flatMapTo",
                externalLinkName: "kk_sequence_flatMapTo",
                receiverType: receiverType,
                parameters: [
                    ("destination", destinationType),
                    ("transform", transformType),
                ],
                returnType: destinationType,
                additionalTypeParameterSymbols: [rSymbol],
                canThrow: true
            )
        }

        // flatMapIndexed(transform): Sequence<R> for Iterable<R> and Sequence<R> transform results.
        do {
            let memberName = interner.intern("flatMapIndexed")
            let memberFQName = sequenceFQName + [memberName]
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: memberFQName + [rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: memberFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            func registerFlatMapIndexedOverload(transformReturnType: TypeID) {
                let transformType = types.make(.functionType(FunctionType(
                    params: [types.intType, typeParamType],
                    returnType: transformReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == 1,
                          let parameterType = signature.parameterTypes.first
                    else { return false }
                    return parameterType == transformType
                }
                guard !alreadyRegistered else { return }

                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_sequence_flatMapIndexed", for: memberSymbol)

                let transformName = interner.intern("transform")
                let transformSymbol = symbols.define(
                    kind: .valueParameter,
                    name: transformName,
                    fqName: memberFQName + [transformName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: transformSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [transformType],
                        returnType: sequenceRType,
                        canThrow: true,
                        valueParameterSymbols: [transformSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: [typeParamSymbol, rSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            if let iterableSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]) {
                let iterableRType = types.make(.classType(ClassType(
                    classSymbol: iterableSymbol,
                    args: [.out(rType)],
                    nullability: .nonNull
                )))
                registerFlatMapIndexedOverload(transformReturnType: iterableRType)
            }
            registerFlatMapIndexedOverload(transformReturnType: sequenceRType)
        }

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

        // requireNoNulls(): Sequence<T> (STDLIB-SEQ-014)
        let nullableElementSequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(types.makeNullable(typeParamType))],
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "requireNoNulls",
            externalLinkName: "kk_sequence_requireNoNulls",
            receiverType: nullableElementSequenceType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // filterIsInstance<R>(): Sequence<R> (STDLIB-SEQ-FN-026)
        do {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [interner.intern("filterIsInstance"), rName],
                declSite: nil,
                visibility: .private,
                flags: [.reifiedTypeParameter]
            )
            let rType = types.make(.typeParam(TypeParamType(
                symbol: rSymbol,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "filterIsInstance",
                externalLinkName: "kk_sequence_filterIsInstance",
                receiverType: receiverType,
                parameters: [],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> (STDLIB-SEQ-012)
        registerSequenceMemberStub(
            named: "partition",
            externalLinkName: "kk_sequence_partition",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        // plusElement(element: T): Sequence<T> (STDLIB-SEQ-013)
        registerSequenceMemberStub(
            named: "plusElement",
            externalLinkName: "kk_sequence_plus_element",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // minusElement(element: T): Sequence<T> (STDLIB-SEQ-028)
        registerSequenceMemberStub(
            named: "minusElement",
            externalLinkName: "kk_sequence_minus",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // union<T>(other: Iterable<T>): Set<T>
        do {
            let memberName = interner.intern("union")
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
            let methodIterableType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ], elementType: methodTType)
            let methodSetType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Set"),
            ], elementType: methodTType)
            registerSequenceMemberStub(
                named: "union",
                externalLinkName: "kk_sequence_union",
                receiverType: methodReceiverType,
                parameters: [("other", methodIterableType)],
                returnType: methodSetType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // minus(element: T): Sequence<T>
        registerSequenceMemberStub(
            named: "minus",
            externalLinkName: "kk_sequence_minus",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // foldIndexed(initial, operation): R
        registerSequenceMemberStub(
            named: "foldIndexed",
            externalLinkName: "kk_sequence_foldIndexed",
            receiverType: receiverType,
            parameters: [("initial", types.anyType), ("operation", foldIndexedOperationType)],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // reduceIndexed(operation): T
        registerSequenceMemberStub(
            named: "reduceIndexed",
            externalLinkName: "kk_sequence_reduceIndexed",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // reduceIndexedOrNull(operation): T?
        registerSequenceMemberStub(
            named: "reduceIndexedOrNull",
            externalLinkName: "kk_sequence_reduceIndexedOrNull",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // runningFoldIndexed(initial, operation): Sequence<R>
        let runningFoldIndexedName = interner.intern("runningFoldIndexed")
        let runningFoldIndexedFQName = sequenceFQName + [runningFoldIndexedName]
        if symbols.lookup(fqName: runningFoldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: runningFoldIndexedFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(
                params: [types.intType, rType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "runningFoldIndexed",
                externalLinkName: "kk_sequence_runningFoldIndexed",
                receiverType: receiverType,
                parameters: [("initial", rType), ("operation", operationType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // scanIndexed(initial, operation): Sequence<R>
        let scanIndexedName = interner.intern("scanIndexed")
        let scanIndexedFQName = sequenceFQName + [scanIndexedName]
        if symbols.lookup(fqName: scanIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: scanIndexedFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(
                params: [types.intType, rType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "scanIndexed",
                externalLinkName: "kk_sequence_scanIndexed",
                receiverType: receiverType,
                parameters: [("initial", rType), ("operation", operationType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // runningReduceIndexed(operation): List<T>
        registerSequenceMemberStub(
            named: "runningReduceIndexed",
            externalLinkName: "kk_sequence_runningReduceIndexed",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // partition(predicate): Pair<List<T>, List<T>>
        if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]) {
            let partitionReturnType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(listReturnType), .out(listReturnType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "partition",
                externalLinkName: "kk_sequence_partition",
                receiverType: receiverType,
                parameters: [("predicate", predicateType)],
                returnType: partitionReturnType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true
            )
        }

        // associate(transform): Map<K, V>
        if let mapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]), let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]) {
            let associateName = interner.intern("associate")
            let associateFQName = sequenceFQName + [associateName]
            if symbols.lookup(fqName: associateFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let valueTypeParamName = interner.intern("V")
                let valueTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: valueTypeParamName,
                    fqName: associateFQName + [valueTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
                let transformType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(keyType), .out(valueType)],
                        nullability: .nonNull
                    ))),
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.out(keyType), .out(valueType)],
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associate",
                    externalLinkName: "kk_sequence_associate",
                    receiverType: receiverType,
                    parameters: [("transform", transformType)],
                    returnType: returnType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
                )
            }
        }

        // associateBy(keySelector): Map<K, T>
        if let mapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]) {
            let associateByName = interner.intern("associateBy")
            let associateByFQName = sequenceFQName + [associateByName]
            if symbols.lookup(fqName: associateByFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateByFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.out(keyType), .out(typeParamType)],
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateBy",
                    externalLinkName: "kk_sequence_associateBy",
                    receiverType: receiverType,
                    parameters: [("keySelector", keySelectorType)],
                    returnType: returnType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }
        }

        // associateWith(valueSelector): Map<T, R>
        if let mapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]) {
            let associateWithFQName = sequenceFQName + [interner.intern("associateWith")]
            if symbols.lookup(fqName: associateWithFQName) == nil {
                let rName = interner.intern("R")
                let rFQName = associateWithFQName + [rName]
                let rSymbol = symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
                let valueSelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.out(typeParamType), .out(rType)],
                    nullability: .nonNull
                )))
                let associateWithSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("associateWith"),
                    fqName: associateWithFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: associateWithSymbol)
                symbols.setExternalLinkName("kk_sequence_associateWith", for: associateWithSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [valueSelectorType],
                        returnType: returnType,
                        canThrow: true,
                        typeParameterSymbols: [typeParamSymbol, rSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: associateWithSymbol
                )
            }
        }

        if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]),
           let mutableMapSymbol = symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("MutableMap"),
           ])
        {
            let associateToName = interner.intern("associateTo")
            let associateToFQName = sequenceFQName + [associateToName]
            if symbols.lookup(fqName: associateToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let valueTypeParamName = interner.intern("V")
                let valueTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: valueTypeParamName,
                    fqName: associateToFQName + [valueTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(valueType)],
                    nullability: .nonNull
                )))
                let transformType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(keyType), .out(valueType)],
                        nullability: .nonNull
                    ))),
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateTo",
                    externalLinkName: "kk_sequence_associateTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("transform", transformType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
                )
            }

            let associateByToName = interner.intern("associateByTo")
            let associateByToFQName = sequenceFQName + [associateByToName]
            if symbols.lookup(fqName: associateByToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateByToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(typeParamType)],
                    nullability: .nonNull
                )))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateByTo",
                    externalLinkName: "kk_sequence_associateByTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("keySelector", keySelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }

            let associateWithToName = interner.intern("associateWithTo")
            let associateWithToFQName = sequenceFQName + [associateWithToName]
            if symbols.lookup(fqName: associateWithToFQName) == nil {
                let valueTypeParamName = interner.intern("V")
                let valueTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: valueTypeParamName,
                    fqName: associateWithToFQName + [valueTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(typeParamType), .out(valueType)],
                    nullability: .nonNull
                )))
                let valueSelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: valueType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateWithTo",
                    externalLinkName: "kk_sequence_associateWithTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("valueSelector", valueSelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [valueTypeParamSymbol]
                )
            }
        }

        if let mutableMapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]) {
            let groupByToName = interner.intern("groupByTo")
            let groupByToFQName = sequenceFQName + [groupByToName]
            if symbols.lookup(fqName: groupByToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: groupByToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(mutableListReturnType)],
                    nullability: .nonNull
                )))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "groupByTo",
                    externalLinkName: "kk_sequence_groupByTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("keySelector", keySelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }
        }

        // maxByOrNull / minByOrNull / maxOf / minOf (STDLIB-301)
        do {
            func registerComparableSelectorMember(
                name: String,
                externalLinkName: String,
                returnTypeBuilder: (TypeID) -> TypeID
            ) {
                let memberName = interner.intern(name)
                let memberFQName = sequenceFQName + [memberName]
                guard symbols.lookup(fqName: memberFQName) == nil else { return }
                let selectorReturnType: TypeID
                let extraTypeParamSymbols: [SymbolID]
                let extraUpperBoundsList: [[TypeID]]
                if let rParam = makeComparableTypeParam(
                    symbols: symbols, types: types, interner: interner,
                    memberFQName: memberFQName
                ) {
                    selectorReturnType = rParam.type
                    extraTypeParamSymbols = [rParam.symbol]
                    extraUpperBoundsList = [rParam.upperBounds]
                } else {
                    selectorReturnType = types.anyType
                    extraTypeParamSymbols = []
                    extraUpperBoundsList = []
                }
                let selectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: selectorReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: name,
                    externalLinkName: externalLinkName,
                    receiverType: receiverType,
                    parameters: [("selector", selectorType)],
                    returnType: returnTypeBuilder(selectorReturnType),
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: extraTypeParamSymbols,
                    additionalTypeParameterUpperBoundsList: extraUpperBoundsList
                )
            }

            registerComparableSelectorMember(
                name: "maxBy",
                externalLinkName: "kk_sequence_maxBy",
                returnTypeBuilder: { _ in typeParamType }
            )
            registerComparableSelectorMember(
                name: "maxByOrNull",
                externalLinkName: "kk_sequence_maxByOrNull",
                returnTypeBuilder: { _ in types.makeNullable(typeParamType) }
            )
            registerComparableSelectorMember(
                name: "minByOrNull",
                externalLinkName: "kk_sequence_minByOrNull",
                returnTypeBuilder: { _ in types.makeNullable(typeParamType) }
            )
            registerComparableSelectorMember(
                name: "maxOfOrNull",
                externalLinkName: "kk_sequence_maxOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
            )
            registerComparableSelectorMember(
                name: "maxOf",
                externalLinkName: "kk_sequence_maxOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
            registerComparableSelectorMember(
                name: "minOf",
                externalLinkName: "kk_sequence_minOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
            registerComparableSelectorMember(
                name: "minOfOrNull",
                externalLinkName: "kk_sequence_minOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
            )
        }

        // maxWithOrNull(comparator): T?
        do {
            let comparatorType = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
                types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(typeParamType)],
                    nullability: .nonNull
                )))
            } else {
                types.make(.functionType(FunctionType(
                    params: [typeParamType, typeParamType],
                    returnType: types.intType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }
            registerSequenceMemberStub(
                named: "maxWithOrNull",
                externalLinkName: "kk_sequence_maxWithOrNull",
                receiverType: receiverType,
                parameters: [("comparator", comparatorType)],
                returnType: types.makeNullable(typeParamType),
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                flags: [.synthetic, .inlineFunction]
            )
        }

        // unzip(): Pair<List<A>, List<B>> for Sequence<Pair<A, B>>
        let unzipName = interner.intern("unzip")
        let unzipFQName = sequenceFQName + [unzipName]
        if symbols.lookup(fqName: unzipFQName) == nil {
            let aName = interner.intern("A")
            let aSymbol = symbols.define(
                kind: .typeParameter,
                name: aName,
                fqName: unzipFQName + [aName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let bName = interner.intern("B")
            let bSymbol = symbols.define(
                kind: .typeParameter,
                name: bName,
                fqName: unzipFQName + [bName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let aType = types.make(.typeParam(TypeParamType(symbol: aSymbol, nullability: .nonNull)))
            let bType = types.make(.typeParam(TypeParamType(symbol: bSymbol, nullability: .nonNull)))
            let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
                ?? symbols.lookupByShortName(interner.intern("Pair")).first
            let specializedReceiverType: TypeID
            let returnType: TypeID
            if let pairSymbol {
                let pairElementType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(aType), .out(bType)],
                    nullability: .nonNull
                )))
                specializedReceiverType = types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(pairElementType)],
                    nullability: .nonNull
                )))
                let firstListType = nominalCollectionType([
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ], elementType: aType)
                let secondListType = nominalCollectionType([
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ], elementType: bType)
                returnType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(firstListType), .out(secondListType)],
                    nullability: .nonNull
                )))
            } else {
                specializedReceiverType = receiverType
                returnType = types.anyType
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: unzipName,
                fqName: unzipFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_sequence_unzip", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: specializedReceiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [aSymbol, bSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        // toSet(): Set<T>
        registerSequenceMemberStub(
            named: "toSet",
            externalLinkName: "kk_sequence_toSet",
            receiverType: receiverType,
            parameters: [],
            returnType: setReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMap(): Map<K,V>
        registerSequenceMemberStub(
            named: "toMap",
            externalLinkName: "kk_sequence_toMap",
            receiverType: receiverType,
            parameters: [],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // groupBy(keySelector: (T) -> K): Map<K, List<T>>
        if let mapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]) {
            let groupByFQName = sequenceFQName + [interner.intern("groupBy")]
            if symbols.lookup(fqName: groupByFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamFQName = groupByFQName + [keyTypeParamName]
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: keyTypeParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(
                    symbol: keyTypeParamSymbol,
                    nullability: .nonNull
                )))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.out(keyType), .out(listReturnType)],
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "groupBy",
                    externalLinkName: "kk_sequence_groupBy",
                    receiverType: receiverType,
                    parameters: [("keySelector", keySelectorType)],
                    returnType: returnType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }
        }

        // maxOrNull(): T?
        registerSequenceMemberStub(
            named: "maxOrNull",
            externalLinkName: "kk_sequence_maxOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(types.anyType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // minOrNull(): T?
        registerSequenceMemberStub(
            named: "minOrNull",
            externalLinkName: "kk_sequence_minOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(types.anyType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatten(): Sequence<T>
        registerSequenceMemberStub(
            named: "flatten",
            externalLinkName: "kk_sequence_flatten",
            receiverType: receiverType,
            parameters: [],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-SEQ-008: chunked(size, transform): Sequence<R>
        do {
            let chunkedName = interner.intern("chunked")
            let chunkedFQName = sequenceFQName + [chunkedName]
            let rName = interner.intern("R")
            let rFQName = chunkedFQName + [rName]
            let rSymbol: SymbolID = if let existing = symbols.lookup(fqName: rFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let rType = types.make(.typeParam(TypeParamType(
                symbol: rSymbol,
                nullability: .nonNull
            )))
            let invariantChunkListType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ], elementType: typeParamType, invariant: true)
            let transformType = types.make(.functionType(FunctionType(
                params: [invariantChunkListType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "chunked",
                externalLinkName: "kk_sequence_chunked_transform",
                receiverType: receiverType,
                parameters: [("size", types.intType), ("transform", transformType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol]
            )
        }

        // STDLIB-SEQ-FN-012: chunked(size): Sequence<List<T>>
        let chunkedReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(listReturnType)],
            nullability: .nonNull
        )))
        registerSequenceOverloadedMemberStub(
            named: "chunked",
            externalLinkName: "kk_sequence_chunked",
            receiverType: receiverType,
            parameters: [("size", types.intType)],
            returnType: chunkedReturnType,
            canThrow: true
        )

        // windowed(size, step, partialWindows, transform): Sequence<R>
        do {
            let windowedName = interner.intern("windowed")
            let windowedFQName = sequenceFQName + [windowedName]
            let rName = interner.intern("R")
            let rFQName = windowedFQName + [interner.intern("transform"), rName]
            let rSymbol: SymbolID = if let existing = symbols.lookup(fqName: rFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let rType = types.make(.typeParam(TypeParamType(
                symbol: rSymbol,
                nullability: .nonNull
            )))
            let invariantWindowListType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ], elementType: typeParamType, invariant: true)
            let transformType = types.make(.functionType(FunctionType(
                params: [invariantWindowListType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "windowed",
                externalLinkName: "kk_sequence_windowed_transform",
                receiverType: receiverType,
                parameters: [
                    ("size", types.intType),
                    ("step", types.intType),
                    ("partialWindows", types.booleanType),
                    ("transform", transformType),
                ],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol]
            )
        }

        // STDLIB-SEQ-FN-131: windowed(size, step, partialWindows): Sequence<List<T>>
        let windowedReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(listReturnType)],
            nullability: .nonNull
        )))
        registerSequenceOverloadedMemberStub(
            named: "windowed",
            externalLinkName: "kk_sequence_windowed",
            receiverType: receiverType,
            parameters: [
                ("size", types.intType),
                ("step", types.intType),
                ("partialWindows", types.booleanType),
            ],
            returnType: windowedReturnType,
            canThrow: false
        )

        // forEachIndexed(action: (Int, T) -> Unit): Unit
        let forEachIndexedActionType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "forEachIndexed",
            externalLinkName: "kk_sequence_forEachIndexed",
            receiverType: receiverType,
            parameters: [("action", forEachIndexedActionType)],
            returnType: types.unitType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // onEach(action: (T) -> Unit): Sequence<T>
        registerSequenceMemberStub(
            named: "onEach",
            externalLinkName: "kk_sequence_onEach",
            receiverType: receiverType,
            parameters: [("action", actionType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // onEachIndexed(action: (Int, T) -> Unit): Sequence<T>
        registerSequenceMemberStub(
            named: "onEachIndexed",
            externalLinkName: "kk_sequence_onEachIndexed",
            receiverType: receiverType,
            parameters: [("action", forEachIndexedActionType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatMapIndexed(transform: (Int, T) -> Iterable<R>): Sequence<R>
        // flatMapIndexed(transform: (Int, T) -> Sequence<R>): Sequence<R>
        let flatMapIndexedName = interner.intern("flatMapIndexed")
        let flatMapIndexedFQName = sequenceFQName + [flatMapIndexedName]
        let flatMapIndexedTypeParamName = interner.intern("R")
        let flatMapIndexedTypeParamSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: flatMapIndexedFQName + [flatMapIndexedTypeParamName]
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: flatMapIndexedTypeParamName,
                fqName: flatMapIndexedFQName + [flatMapIndexedTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let flatMapIndexedTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapIndexedTypeParamSymbol,
            nullability: .nonNull
        )))
        let iterableFlatMapIndexedReturnType = makeSyntheticIterableType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: flatMapIndexedTypeParamType
        )
        let sequenceFlatMapIndexedReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(flatMapIndexedTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapIndexedIterableTransformType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: iterableFlatMapIndexedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let flatMapIndexedSequenceTransformType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: sequenceFlatMapIndexedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceOverloadedMemberStub(
            named: "flatMapIndexed",
            externalLinkName: "kk_sequence_flatMapIndexed",
            receiverType: receiverType,
            parameters: [("transform", flatMapIndexedIterableTransformType)],
            returnType: sequenceFlatMapIndexedReturnType,
            additionalTypeParameterSymbols: [flatMapIndexedTypeParamSymbol]
        )
        registerSequenceOverloadedMemberStub(
            named: "flatMapIndexed",
            externalLinkName: "kk_sequence_flatMapIndexed",
            receiverType: receiverType,
            parameters: [("transform", flatMapIndexedSequenceTransformType)],
            returnType: sequenceFlatMapIndexedReturnType,
            additionalTypeParameterSymbols: [flatMapIndexedTypeParamSymbol]
        )

        // any(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "any",
            externalLinkName: "kk_sequence_any",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // all(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "all",
            externalLinkName: "kk_sequence_all",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // none(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "none",
            externalLinkName: "kk_sequence_none",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // find(predicate: (T) -> Boolean): T?  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "find",
            externalLinkName: "kk_sequence_find",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // zip(other: Sequence<R>): Sequence<Pair<T, R>>
        do {
            let zipName = interner.intern("zip")
            let zipFQName = sequenceFQName + [zipName]
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: zipFQName + [rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: zipFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let otherSequenceType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            let pairType: TypeID = if let pairSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("Pair"),
            ]) {
                types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(typeParamType), .out(rType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            let zippedSequenceType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(pairType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "zip",
                externalLinkName: "kk_sequence_zip",
                receiverType: receiverType,
                parameters: [("other", otherSequenceType)],
                returnType: zippedSequenceType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // zipWithNext(): Sequence<Pair<T, T>>
        let zipWithNextName = interner.intern("zipWithNext")
        let zipWithNextFQName = sequenceFQName + [zipWithNextName]
        if symbols.lookup(fqName: zipWithNextFQName) == nil {
            let pairSymbol: SymbolID? = symbols.lookup(fqName: [
                interner.intern("kotlin"), interner.intern("Pair"),
            ])
            let zipWithNextResultType: TypeID = if let pairSymbol {
                types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(typeParamType), .out(typeParamType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            let zipWithNextSequenceResultType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(zipWithNextResultType)],
                nullability: .nonNull
            )))
            let zipWithNextSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: zipWithNextSymbol)
            symbols.setExternalLinkName("kk_sequence_zipWithNext", for: zipWithNextSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: zipWithNextSequenceResultType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: zipWithNextSymbol
            )
        }

        // zipWithNext(transform: (T, T) -> R): Sequence<R>
        let zipWithNextTransformFQName = zipWithNextFQName + [interner.intern("transform")]
        if symbols.lookup(fqName: zipWithNextTransformFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = zipWithNextTransformFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [typeParamType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: transformSymbol)
            symbols.setExternalLinkName("kk_sequence_zipWithNextTransform", for: transformSymbol)
            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: zipWithNextTransformFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(transformSymbol, for: transformParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: sequenceRType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol, rSymbol],
                    classTypeParameterCount: 1
                ),
                for: transformSymbol
            )
        }
    }

}
