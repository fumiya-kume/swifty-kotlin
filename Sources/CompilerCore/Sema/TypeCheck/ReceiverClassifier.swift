struct ReceiverClassification {
    let isArrayReceiver: Bool
    let isIterableReceiver: Bool
    let isCollectionReceiver: Bool
    let isSequenceReceiver: Bool
    let isMapReceiver: Bool
    let isSetReceiver: Bool
    let isListReceiver: Bool
    let isMutableCollectionReceiver: Bool
    let isMutableListReceiver: Bool
    let isMutableSetReceiver: Bool
    let isMutableMapReceiver: Bool
    let isListFactoryReceiver: Bool
    let isSyntheticSequenceReceiver: Bool
}

struct ReceiverClassifier {
    let sema: SemaModule
    let interner: StringInterner

    func classify(
        receiverID: ExprID,
        receiverType explicitReceiverType: TypeID? = nil,
        ast: ASTModule? = nil
    ) -> ReceiverClassification {
        let receiverType = explicitReceiverType ?? sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let isCollectionExpr = sema.bindings.isCollectionExpr(receiverID)
        let isListFactoryReceiver = ast.map {
            isListCollectionFactoryReceiver(receiverID: receiverID, ast: $0)
        } ?? false
        let isCollectionType = isCollectionLikeType(receiverType)
        let isMapReceiver = isMapLikeCollectionType(receiverType)
        // KSP-435: a receiver whose *static* type is `Iterable<T>` (e.g. a
        // `val x: Iterable<Int> = setOf(...)` widening) is a collection
        // receiver, not a synthetic object-expression Sequence, even though
        // `isCollectionExpr` can be true here (propagated from the
        // initializer). Without this exclusion such a receiver was
        // misclassified as a synthetic Sequence, which made
        // `isSequenceReceiver` true and routed both aggregate HOFs
        // (`reduce`/`fold` resolving against the bundled `Sequence<T>`
        // source instead of the real element type's own implementation) and
        // plain `Iterable` members (`requireNoNulls`, `last`, ...) to the
        // Sequence bridges instead of the bundled Kotlin `kotlin.collections`
        // source.
        let isSyntheticSequenceReceiver = isCollectionExpr
            && !isCollectionType
            && !isMapReceiver
            && !isListFactoryReceiver
            && !isIterableLikeType(receiverType)
        return ReceiverClassification(
            isArrayReceiver: isArrayLikeType(receiverType),
            // Keep concrete Kotlin collections on their collection-owned paths.
            // Only exact Iterable and user-defined nominal Iterable implementations
            // should activate the generic Iterable source extensions.
            isIterableReceiver: isIterableLikeType(receiverType) && !isCollectionType,
            isCollectionReceiver: isCollectionExpr || isCollectionType,
            isSequenceReceiver: isSequenceLikeType(receiverType) || isSyntheticSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetLikeCollectionType(receiverType),
            isListReceiver: isConcreteListLikeCollectionType(receiverType),
            isMutableCollectionReceiver: isMutableCollectionType(receiverType),
            isMutableListReceiver: isMutableListCollectionType(receiverType),
            isMutableSetReceiver: isMutableSetType(receiverType),
            isMutableMapReceiver: isMutableMapType(receiverType),
            isListFactoryReceiver: isListFactoryReceiver,
            isSyntheticSequenceReceiver: isSyntheticSequenceReceiver
        )
    }

    func isArrayLikeReceiver(receiverID: ExprID) -> Bool {
        isArrayLikeType(receiverType(for: receiverID))
    }

    func isArrayLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    func isIterableLikeReceiver(receiverID: ExprID) -> Bool {
        isIterableLikeType(receiverType(for: receiverID))
    }

    func isExactIterableType(_ type: TypeID) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        return symbol.name == interner.intern("Iterable") || symbol.fqName == iterableFQName
    }

    func isIterableLikeType(_ type: TypeID) -> Bool {
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let iterableFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
        if symbol.name == interner.intern("Iterable") || symbol.fqName == iterableFQName {
            return true
        }
        let kotlinRangesFQName = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
        ]
        let rangeTypeNames: Set = Set([
            "OpenEndRange", "IntRange", "IntProgression", "LongRange", "LongProgression",
            "UIntRange", "UIntProgression", "ULongRange", "ULongProgression",
            "CharRange", "CharProgression",
        ].map(interner.intern))
        if rangeTypeNames.contains(symbol.name),
           symbol.fqName.isEmpty || (
               symbol.fqName.count == 3
                   && Array(symbol.fqName.prefix(2)) == kotlinRangesFQName
           )
        {
            // Range/progression types have dedicated source-backed owners for
            // collection HOFs. Do not let their Iterable supertypes reroute
            // those calls to kotlin.collections.Iterable.
            return false
        }
        // User-defined classes implementing Iterable must use the generic
        // Iterable source extensions rather than unresolved member fallbacks.
        guard let iterableSymbol = sema.symbols.lookup(fqName: iterableFQName) else {
            return false
        }
        return sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: iterableSymbol)
    }

    /// KSP-979: Recognize a statically Iterable value and user-defined nominal
    /// subtypes for the source-backed Iterable index family. Keep the existing
    /// exact-name classifier unchanged so other collection fast paths do not
    /// gain new receivers as a side effect.
    func isNominalIterableType(_ type: TypeID) -> Bool {
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        if symbol.name == interner.intern("Iterable") || symbol.fqName == iterableFQName {
            return true
        }
        guard let iterableSymbol = sema.symbols.lookup(fqName: iterableFQName) else {
            return false
        }
        return sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: iterableSymbol)
    }

    /// BUG-167: True for the `kotlin.collections` iterable *interfaces*, whose
    /// `iterator()` exists only as a synthetic stub (so Sema binds no loop
    /// iteration operators) and whose concrete iterator is only known at
    /// runtime. Concrete types such as `List<T>` are deliberately excluded.
    func isIterableInterfaceType(_ type: TypeID) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let interfaceNames = [
            interner.intern("Iterable"),
            interner.intern("MutableIterable"),
            interner.intern("Collection"),
            interner.intern("MutableCollection"),
        ]
        let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
        if symbol.fqName.count == 3, Array(symbol.fqName.prefix(2)) == kotlinCollections {
            return interfaceNames.contains(symbol.fqName[2])
        }
        // Fall back to simple name match only for synthetic symbols (no FQN)
        return symbol.fqName.isEmpty && interfaceNames.contains(symbol.name)
    }

    func isSequenceLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isSequenceSymbol(symbol)
    }

    func isCollectionLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        for (_, symbol) in classTypes(of: type) {
            if knownNames.isCollectionLikeSymbol(symbol) {
                return true
            }
        }
        return false
    }

    func isListLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    func isConcreteListLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && classType.args.count == 1
    }

    func isMapLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    func isMutableCollectionType(_ type: TypeID) -> Bool {
        for (classType, symbol) in classTypes(of: type) {
            if (
                symbol.name == interner.intern("MutableCollection")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("MutableCollection"),
                    ]
            ) && classType.args.count == 1 {
                return true
            }
        }
        return false
    }

    func isMutableListCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return (
            symbol.name == knownNames.mutableList
                || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
                || symbol.fqName == knownNames.kotlinCollectionsArrayListFQName
        ) && classType.args.count == 1
    }

    func isMutableSetType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol) && classType.args.count == 1
    }

    func isMutableMapType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMutableMapSymbol(symbol) && classType.args.count == 2
    }

    func isConcreteListLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && !knownNames.isMapLikeSymbol(symbol)
    }

    func isSetLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.collectionKind(of: symbol) == .set && classType.args.count == 1
    }

    func isListCollectionFactoryReceiver(receiverID: ExprID, ast: ASTModule) -> Bool {
        guard sema.bindings.isCollectionExpr(receiverID),
              let expr = ast.arena.expr(receiverID),
              case .call(let calleeID, _, _, _) = expr,
              let calleeExpr = ast.arena.expr(calleeID),
              case .nameRef(let name, _) = calleeExpr
        else {
            return false
        }
        return name == interner.intern("listOf")
            || name == interner.intern("listOfNotNull")
            || name == interner.intern("emptyList")
            || name == interner.intern("mutableListOf")
            || name == interner.intern("arrayListOf")
    }

    private func receiverType(for receiverID: ExprID) -> TypeID {
        sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
    }

    private func classTypes(of type: TypeID) -> [(classType: ClassType, symbol: SemanticSymbol)] {
        var visitedTypeParams: Set<SymbolID> = []
        return classTypes(of: type, visitedTypeParams: &visitedTypeParams)
    }

    private func classTypes(
        of type: TypeID,
        visitedTypeParams: inout Set<SymbolID>
    ) -> [(classType: ClassType, symbol: SemanticSymbol)] {
        let nonNullType = sema.types.makeNonNullable(type)
        switch sema.types.kind(of: nonNullType) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                return []
            }
            return [(classType, symbol)]
        case let .intersection(parts):
            return parts.flatMap {
                classTypes(of: $0, visitedTypeParams: &visitedTypeParams)
            }
        case let .typeParam(typeParam):
            guard visitedTypeParams.insert(typeParam.symbol).inserted else {
                return []
            }
            return sema.symbols.typeParameterUpperBounds(for: typeParam.symbol).flatMap {
                classTypes(of: $0, visitedTypeParams: &visitedTypeParams)
            }
        default:
            return []
        }
    }
}

extension CallTypeChecker {
    func receiverClassifier(sema: SemaModule, interner: StringInterner) -> ReceiverClassifier {
        ReceiverClassifier(sema: sema, interner: interner)
    }

    func isArrayLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isArrayLikeReceiver(receiverID: receiverID)
    }

    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isSequenceLikeType(receiverType)
    }

    func isCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isCollectionLikeType(receiverType)
    }

    func isListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isListLikeType(receiverType)
    }
}
