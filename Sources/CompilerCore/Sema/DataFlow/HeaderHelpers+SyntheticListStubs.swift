import Foundation
import RuntimeABI

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// List<E> interface and read-only member registrations (iterators, transform, aggregate, conversion).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let listName = interner.intern("List")
        let listFQName = kotlinCollectionsPkg + [listName]
        let listInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: listFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: listName,
                fqName: listFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Define type parameter E for List<E>
        let listTypeParamName = interner.intern("E")
        let listTypeParamFQName = listFQName + [listTypeParamName]
        let listTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: listTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([listTypeParamSymbol], for: listInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: listInterfaceSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(listTypeParamType)], for: listInterfaceSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(listTypeParamType)], for: listInterfaceSymbol, supertype: collectionInterfaceSymbol)

        registerListLastIndexExtensionProperty(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol
        )
        registerListGetOperator(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListContainsAndIsEmptyMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )
        registerListIndicesExtensionProperty(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol
        )
        registerListJoinToStringMember(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListContentEqualsMember(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListTransformMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )
        registerListAggregateMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListIteratorMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        return listInterfaceSymbol
    }

    /// Register `kotlin.collections.AbstractList<E>` surface (STDLIB-COL-ABSTRACT-003).
    func registerSyntheticAbstractListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        abstractCollectionSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractListName = interner.intern("AbstractList")
        let abstractListFQName = kotlinCollectionsPkg + [abstractListName]
        let abstractListSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractListFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractListName,
                fqName: abstractListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractListFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractListSymbol)
        types.setNominalTypeParameterVariances([.out], for: abstractListSymbol)

        let abstractListType = types.make(.classType(ClassType(
            classSymbol: abstractListSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractListType, for: abstractListSymbol)

        let directSupertypes = [abstractCollectionSymbol, listInterfaceSymbol]
        symbols.setDirectSupertypes(directSupertypes, for: abstractListSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: abstractListSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: abstractCollectionSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: abstractCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: listInterfaceSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractListFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractListSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractListType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractListSymbol
    }

    /// Register `operator fun get(index: Int): E` on the List interface.
    private func registerListGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listGetName = interner.intern("get")
        let listGetFQName = listFQName + [listGetName]
        guard symbols.lookup(fqName: listGetFQName) == nil else { return }
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listGetSymbol = symbols.define(
            kind: .function,
            name: listGetName,
            fqName: listGetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: listGetSymbol)
        symbols.setExternalLinkName("kk_list_get", for: listGetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [types.intType],
                returnType: listTypeParamType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: listGetSymbol
        )
    }

    /// Register `val <T> List<T>.lastIndex: Int`.
    private func registerListLastIndexExtensionProperty(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID
    ) {
        let propertyName = interner.intern("lastIndex")
        let propertyFQName = kotlinCollectionsPkg + [propertyName]
        let existing = symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            guard symbols.symbol(symbolID)?.kind == .property,
                  let receiverType = symbols.extensionPropertyReceiverType(for: symbolID),
                  case let .classType(receiverClass) = types.kind(of: types.makeNonNullable(receiverType))
            else {
                return false
            }
            return receiverClass.classSymbol == listInterfaceSymbol
        }

        let propertySymbol: SymbolID
        let receiverType: TypeID
        let typeParameterSymbol: SymbolID
        if let existing {
            propertySymbol = existing
            guard let existingReceiver = symbols.extensionPropertyReceiverType(for: existing),
                  case let .classType(existingReceiverClass) = types.kind(of: types.makeNonNullable(existingReceiver)),
                  case let .out(existingElementType)? = existingReceiverClass.args.first,
                  case let .typeParam(existingElementParam) = types.kind(of: existingElementType)
            else {
                symbols.setPropertyType(types.intType, for: existing)
                symbols.setExternalLinkName("kk_list_lastIndex", for: existing)
                return
            }
            receiverType = existingReceiver
            typeParameterSymbol = existingElementParam.symbol
        } else {
            let typeParameterName = interner.intern("T")
            let typeParameterFQName = propertyFQName + [typeParameterName]
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let typeParameterType = types.make(.typeParam(TypeParamType(
                symbol: typeParameterSymbol,
                nullability: .nonNull
            )))
            receiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(typeParameterType)],
                nullability: .nonNull
            )))
            propertySymbol = symbols.define(
                kind: .property,
                name: propertyName,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) {
                symbols.setParentSymbol(packageSymbol, for: propertySymbol)
            }
            symbols.setParentSymbol(propertySymbol, for: typeParameterSymbol)
            symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        }

        symbols.setPropertyType(types.intType, for: propertySymbol)
        symbols.setExternalLinkName("kk_list_lastIndex", for: propertySymbol)

        let getterFQName = propertyFQName + [interner.intern("$get")]
        let getterSymbol: SymbolID
        if let existingGetter = symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
            getterSymbol = existingGetter
        } else {
            getterSymbol = symbols.define(
                kind: .function,
                name: interner.intern("get"),
                fqName: getterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(propertySymbol, for: getterSymbol)
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
            symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.intType,
                typeParameterSymbols: [typeParameterSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: getterSymbol
        )
        symbols.setExternalLinkName("kk_list_lastIndex", for: getterSymbol)
    }

    /// Register `val <T> List<T>.indices: IntRange`.
    private func registerListIndicesExtensionProperty(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID
    ) {
        let propertyName = interner.intern("indices")
        let propertyFQName = kotlinCollectionsPkg + [propertyName]
        let existing = symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            guard symbols.symbol(symbolID)?.kind == .property,
                  let receiverType = symbols.extensionPropertyReceiverType(for: symbolID),
                  case let .classType(receiverClass) = types.kind(of: types.makeNonNullable(receiverType))
            else {
                return false
            }
            return receiverClass.classSymbol == listInterfaceSymbol
        }

        let returnType = ensureIntRangeTypeForListIndices(symbols: symbols, types: types, interner: interner)
        let propertySymbol: SymbolID
        let receiverType: TypeID
        let typeParameterSymbol: SymbolID
        if let existing {
            propertySymbol = existing
            guard let existingReceiver = symbols.extensionPropertyReceiverType(for: existing),
                  case let .classType(existingReceiverClass) = types.kind(of: types.makeNonNullable(existingReceiver)),
                  case let .out(existingElementType)? = existingReceiverClass.args.first,
                  case let .typeParam(existingElementParam) = types.kind(of: existingElementType)
            else {
                symbols.setPropertyType(returnType, for: existing)
                symbols.setExternalLinkName("kk_list_indices", for: existing)
                return
            }
            receiverType = existingReceiver
            typeParameterSymbol = existingElementParam.symbol
        } else {
            let typeParameterName = interner.intern("T")
            let typeParameterFQName = propertyFQName + [typeParameterName]
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let typeParameterType = types.make(.typeParam(TypeParamType(
                symbol: typeParameterSymbol,
                nullability: .nonNull
            )))
            receiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(typeParameterType)],
                nullability: .nonNull
            )))
            propertySymbol = symbols.define(
                kind: .property,
                name: propertyName,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) {
                symbols.setParentSymbol(packageSymbol, for: propertySymbol)
            }
            symbols.setParentSymbol(propertySymbol, for: typeParameterSymbol)
            symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        }

        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExternalLinkName("kk_list_indices", for: propertySymbol)

        let getterFQName = propertyFQName + [interner.intern("$get")]
        let getterSymbol: SymbolID
        if let existingGetter = symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
            getterSymbol = existingGetter
        } else {
            getterSymbol = symbols.define(
                kind: .function,
                name: interner.intern("get"),
                fqName: getterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(propertySymbol, for: getterSymbol)
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
            symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParameterSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: getterSymbol
        )
        symbols.setExternalLinkName("kk_list_indices", for: getterSymbol)
    }

    private func ensureIntRangeTypeForListIndices(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinName = interner.intern("kotlin")
        let rangesName = interner.intern("ranges")
        let rangesFQName = [kotlinName, rangesName]
        let rangesPackageSymbol: SymbolID = if let existing = symbols.lookup(fqName: rangesFQName) {
            existing
        } else {
            symbols.define(
                kind: .package,
                name: rangesName,
                fqName: rangesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let intRangeName = interner.intern("IntRange")
        let intRangeFQName = rangesFQName + [intRangeName]
        let intRangeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: intRangeFQName) {
            intRangeSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: intRangeName,
                fqName: intRangeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            intRangeSymbol = created
        }
        return types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    /// STDLIB-538: Register `ListIterator<T>` interface extending `Iterator<T>`,
    /// with `hasPrevious(): Boolean` and `previous(): T` members.
    private func ensureSyntheticListIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let listIteratorName = interner.intern("ListIterator")
        let listIteratorFQName = kotlinCollectionsPkg + [listIteratorName]
        if let existing = symbols.lookup(fqName: listIteratorFQName) {
            return existing
        }

        // Look up the parent Iterator<T> symbol.
        let iteratorName = interner.intern("Iterator")
        let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
        let iteratorSymbol = symbols.lookup(fqName: iteratorFQName)

        let listIteratorSymbol = symbols.define(
            kind: .interface,
            name: listIteratorName,
            fqName: listIteratorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Type parameter T
        let tpName = interner.intern("T")
        let tpFQName = listIteratorFQName + [tpName]
        let tpSymbol = symbols.define(
            kind: .typeParameter,
            name: tpName,
            fqName: tpFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tpSymbol], for: listIteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: listIteratorSymbol)

        // Supertype: Iterator<T>
        if let iteratorSymbol {
            symbols.setDirectSupertypes([iteratorSymbol], for: listIteratorSymbol)
            types.setNominalDirectSupertypes([iteratorSymbol], for: listIteratorSymbol)
            symbols.setSupertypeTypeArgs([.out(tpType)], for: listIteratorSymbol, supertype: iteratorSymbol)
            types.setNominalSupertypeTypeArgs([.out(tpType)], for: listIteratorSymbol, supertype: iteratorSymbol)
        }

        let listIteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: listIteratorSymbol,
            args: [.out(tpType)],
            nullability: .nonNull
        )))

        // hasNext(): Boolean (inherited from Iterator, registered for member resolution)
        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = listIteratorFQName + [hasNextName]
        if symbols.lookup(fqName: hasNextFQName) == nil {
            let hasNextSym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: hasNextSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
            ))), for: hasNextSym)
            symbols.setExternalLinkName("kk_list_iterator_hasNext", for: hasNextSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: hasNextSym
            )
        }

        // next(): T (inherited from Iterator, registered for member resolution)
        let nextName = interner.intern("next")
        let nextFQName = listIteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil {
            let nextSym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: nextSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: tpType, isSuspend: false, nullability: .nonNull
            ))), for: nextSym)
            symbols.setExternalLinkName("kk_list_iterator_next", for: nextSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: tpType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: nextSym
            )
        }

        // hasPrevious(): Boolean
        let hasPreviousName = interner.intern("hasPrevious")
        let hasPreviousFQName = listIteratorFQName + [hasPreviousName]
        let hasPreviousSym = symbols.define(
            kind: .function, name: hasPreviousName, fqName: hasPreviousFQName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(listIteratorSymbol, for: hasPreviousSym)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
        ))), for: hasPreviousSym)
        symbols.setExternalLinkName("kk_list_iterator_hasPrevious", for: hasPreviousSym)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listIteratorReceiverType,
                parameterTypes: [],
                returnType: types.booleanType,
                typeParameterSymbols: [tpSymbol],
                classTypeParameterCount: 1
            ),
            for: hasPreviousSym
        )

        // previous(): T
        let previousName = interner.intern("previous")
        let previousFQName = listIteratorFQName + [previousName]
        let previousSym = symbols.define(
            kind: .function, name: previousName, fqName: previousFQName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(listIteratorSymbol, for: previousSym)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: tpType, isSuspend: false, nullability: .nonNull
        ))), for: previousSym)
        symbols.setExternalLinkName("kk_list_iterator_previous", for: previousSym)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listIteratorReceiverType,
                parameterTypes: [],
                returnType: tpType,
                typeParameterSymbols: [tpSymbol],
                classTypeParameterCount: 1
            ),
            for: previousSym
        )

        return listIteratorSymbol
    }

    /// Register `MutableListIterator<T>` extending `ListIterator<T>` and `MutableIterator<T>` (STDLIB-COL-TYPE-006).
    private func ensureSyntheticMutableListIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let mutableListIteratorName = interner.intern("MutableListIterator")
        let mutableListIteratorFQName = kotlinCollectionsPkg + [mutableListIteratorName]
        if let existing = symbols.lookup(fqName: mutableListIteratorFQName) {
            return existing
        }

        let listIteratorSymbol = ensureSyntheticListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let mutableIteratorSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableIterator")]
        )

        let mutableListIteratorSymbol = symbols.define(
            kind: .interface,
            name: mutableListIteratorName,
            fqName: mutableListIteratorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        let typeParamName = interner.intern("T")
        let typeParamFQName = mutableListIteratorFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableListIteratorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableListIteratorSymbol)

        var directSupertypes = [listIteratorSymbol]
        if let mutableIteratorSymbol {
            directSupertypes.append(mutableIteratorSymbol)
        }
        symbols.setDirectSupertypes(directSupertypes, for: mutableListIteratorSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: mutableListIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: listIteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: listIteratorSymbol)
        if let mutableIteratorSymbol {
            symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol)
            types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol)
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListIteratorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        func registerMutationMember(name: String) {
            let memberName = interner.intern(name)
            let memberFQName = mutableListIteratorFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableListIteratorSymbol, for: memberSymbol)
            let valueName = interner.intern("element")
            let valueSymbol = symbols.define(
                kind: .valueParameter,
                name: valueName,
                fqName: memberFQName + [valueName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: valueSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [typeParamType],
                    returnType: types.unitType,
                    valueParameterSymbols: [valueSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        func registerRemoveMember() {
            let memberName = interner.intern("remove")
            let memberFQName = mutableListIteratorFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableListIteratorSymbol, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.unitType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMutationMember(name: "add")
        registerMutationMember(name: "set")
        registerRemoveMember()

        return mutableListIteratorSymbol
    }

    /// STDLIB-538: Register `List<E>.listIterator(): ListIterator<E>`.
    private func registerListIteratorMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listIteratorInterfaceSymbol = ensureSyntheticListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let memberName = interner.intern("listIterator")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listIteratorInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_iterator", for: memberSymbol)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: returnType, isSuspend: false, nullability: .nonNull
        ))), for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `MutableList<E>.listIterator(): MutableListIterator<E>`.
    func registerMutableListIteratorMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let mutableListIteratorSymbol = ensureSyntheticMutableListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let memberName = interner.intern("listIterator")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableListIteratorSymbol,
            args: [.invariant(mlTypeParamType)],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_iterator", for: memberSymbol)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: returnType, isSuspend: false, nullability: .nonNull
        ))), for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-183: List<T>.component1() ~ component5() for destructuring.
    func registerListComponentNMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let componentNames = ["component1", "component2", "component3", "component4", "component5"]
        let externalLinkNames = [
            "kk_list_component1", "kk_list_component2", "kk_list_component3",
            "kk_list_component4", "kk_list_component5",
        ]
        for (componentName, externalLinkName) in zip(componentNames, externalLinkNames) {
            let name = interner.intern(componentName)
            let fqName = listFQName + [name]
            guard symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == listReceiverType && sig.parameterTypes.isEmpty
            }) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: listTypeParamType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerListContainsAndIsEmptyMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        let containsName = interner.intern("contains")
        let containsFQName = listFQName + [containsName]
        if symbols.lookup(fqName: containsFQName) == nil {
            let containsSymbol = symbols.define(
                kind: .function,
                name: containsName,
                fqName: containsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: containsSymbol)
            symbols.setExternalLinkName("kk_list_contains", for: containsSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [listTypeParamType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: containsSymbol
            )
        }

        let containsAllName = interner.intern("containsAll")
        let containsAllFQName = listFQName + [containsAllName]
        if symbols.lookup(fqName: containsAllFQName) == nil {
            let containsAllSymbol = symbols.define(
                kind: .function,
                name: containsAllName,
                fqName: containsAllFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: containsAllSymbol)
            symbols.setExternalLinkName("kk_list_containsAll", for: containsAllSymbol)
            let collectionParamType = types.make(.classType(ClassType(
                classSymbol: collectionInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [collectionParamType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: containsAllSymbol
            )
        }

        let isEmptyName = interner.intern("isEmpty")
        let isEmptyFQName = listFQName + [isEmptyName]
        if symbols.lookup(fqName: isEmptyFQName) == nil {
            let isEmptySymbol = symbols.define(
                kind: .function,
                name: isEmptyName,
                fqName: isEmptyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: isEmptySymbol)
            symbols.setExternalLinkName("kk_list_is_empty", for: isEmptySymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: isEmptySymbol
            )
        }

        let isNotEmptyName = interner.intern("isNotEmpty")
        let isNotEmptyFQName = listFQName + [isNotEmptyName]
        if symbols.lookup(fqName: isNotEmptyFQName) == nil {
            let isNotEmptySymbol = symbols.define(
                kind: .function,
                name: isNotEmptyName,
                fqName: isNotEmptyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: isNotEmptySymbol)
            symbols.setExternalLinkName("kk_list_is_not_empty", for: isNotEmptySymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: isNotEmptySymbol
            )
        }

    }

    func registerListToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableListSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableList")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableListType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_mutable_list", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableListType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListJoinToStringMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let memberName = interner.intern("joinToString")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_joinToString", for: memberSymbol)

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
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListContentEqualsMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let memberName = interner.intern("contentEquals")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_structural_eq", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.anyType],
                returnType: types.booleanType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func registerListToSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        setInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let setType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: setType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-651: Register `List<T>.toMutableSet()` returning `MutableSet<T>`.
    func registerListToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.invariant(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_mutable_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-651: Register `Set<E>.toSet()` returning `Set<E>`.
    func registerSetToSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("toSet")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
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
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_to_set", for: memberSymbol)
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

    /// STDLIB-651: Register `Set<E>.toMutableSet()` returning `MutableSet<E>`.
    func registerSetToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        let memberName = interner.intern("toMutableSet")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.invariant(typeParamType)],
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
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_to_mutable_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-510: Register `List<T>.intersect(other)`, `.union(other)`, `.subtract(other)` returning `Set<T>`.
    /// Kotlin stdlib declares the parameter as `Iterable<T>`.
    func registerListSetOperationMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        setInterfaceSymbol: SymbolID,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        for (memberName, externName) in [
            ("intersect", "kk_list_intersect"),
            ("union", "kk_list_union"),
            ("subtract", "kk_list_subtract"),
        ] {
            let internedName = interner.intern(memberName)
            let memberFQName = listFQName + [internedName]
            guard symbols.lookup(fqName: memberFQName) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: internedName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [paramType],
                    returnType: returnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    /// STDLIB-510: Register `List<T>.toHashSet()` returning `MutableSet<T>`.
    func registerListToHashSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toHashSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.invariant(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_toHashSet", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func registerListToMapMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        mapInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let pairSymbol = symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("Pair")]
        ) ?? symbols.lookupByShortName(interner.intern("Pair")).first
        guard let pairSymbol,
              let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName
        else {
            return
        }
        let memberName = interner.intern("toMap")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyTypeSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: memberFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueTypeSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: memberFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeSymbol, nullability: .nonNull)))
        let pairType = types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(pairType)],
            nullability: .nonNull
        )))
        let mapType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setParentSymbol(memberSymbol, for: keyTypeSymbol)
        symbols.setParentSymbol(memberSymbol, for: valueTypeSymbol)
        symbols.setExternalLinkName("kk_list_toMap", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mapType,
                typeParameterSymbols: [keyTypeSymbol, valueTypeSymbol],
                classTypeParameterCount: 0
            ),
            for: memberSymbol
        )

        let associateToMemberName = interner.intern("associateTo")
        let associateToMemberFQName = listFQName + [associateToMemberName]
        guard symbols.lookup(fqName: associateToMemberFQName) == nil else { return }

        let associateToKeyTypeParamName = interner.intern("K")
        let associateToValueTypeParamName = interner.intern("V")
        let associateToKeyTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: associateToKeyTypeParamName,
            fqName: associateToMemberFQName + [associateToKeyTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let associateToValueTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: associateToValueTypeParamName,
            fqName: associateToMemberFQName + [associateToValueTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let associateToKeyType = types.make(.typeParam(TypeParamType(
            symbol: associateToKeyTypeParamSymbol, nullability: .nonNull
        )))
        let associateToValueType = types.make(.typeParam(TypeParamType(
            symbol: associateToValueTypeParamSymbol, nullability: .nonNull
        )))
        let associateToReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let associateToDestinationType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(associateToKeyType), .out(associateToValueType)],
            nullability: .nonNull
        )))
        let associateToTransformType = types.make(.functionType(FunctionType(
            params: [listTypeParamType],
            returnType: types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(associateToKeyType), .out(associateToValueType)],
                nullability: .nonNull
            ))),
            isSuspend: false,
            nullability: .nonNull
        )))
        let associateToMemberSymbol = symbols.define(
            kind: .function,
            name: associateToMemberName,
            fqName: associateToMemberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: associateToMemberSymbol)
        symbols.setParentSymbol(associateToMemberSymbol, for: associateToKeyTypeParamSymbol)
        symbols.setParentSymbol(associateToMemberSymbol, for: associateToValueTypeParamSymbol)
        symbols.setExternalLinkName(
            StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: "associateTo",
                arity: 2,
                fallback: "kk_list_associateTo"
            ),
            for: associateToMemberSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: associateToReceiverType,
                parameterTypes: [associateToDestinationType, associateToTransformType],
                returnType: associateToDestinationType,
                typeParameterSymbols: [listTypeParamSymbol, associateToKeyTypeParamSymbol, associateToValueTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: associateToMemberSymbol
        )

        // STDLIB-COL-DEST-004: associateByTo(destination, keySelector) -> M
        let associateByToMemberName = interner.intern("associateByTo")
        let associateByToMemberFQName = listFQName + [associateByToMemberName]
        if symbols.lookup(fqName: associateByToMemberFQName) == nil {
            let associateByToKeyTypeParamName = interner.intern("K")
            let associateByToKeyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: associateByToKeyTypeParamName,
                fqName: associateByToMemberFQName + [associateByToKeyTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let associateByToKeyType = types.make(.typeParam(TypeParamType(
                symbol: associateByToKeyTypeParamSymbol, nullability: .nonNull
            )))
            let associateByToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateByToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(associateByToKeyType), .out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateByToKeySelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: associateByToKeyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let associateByToMemberSymbol = symbols.define(
                kind: .function,
                name: associateByToMemberName,
                fqName: associateByToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: associateByToMemberSymbol)
            symbols.setParentSymbol(associateByToMemberSymbol, for: associateByToKeyTypeParamSymbol)
            symbols.setExternalLinkName(
                StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                    ownerKind: .list,
                    memberName: "associateByTo",
                    arity: 2,
                    fallback: "kk_list_associateByTo"
                ),
                for: associateByToMemberSymbol
            )
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: associateByToReceiverType,
                    parameterTypes: [associateByToDestinationType, associateByToKeySelectorType],
                    returnType: associateByToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, associateByToKeyTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: associateByToMemberSymbol
            )
        }

        // STDLIB-COL-DEST-004: associateWithTo(destination, valueSelector) -> M
        let associateWithToMemberName = interner.intern("associateWithTo")
        let associateWithToMemberFQName = listFQName + [associateWithToMemberName]
        if symbols.lookup(fqName: associateWithToMemberFQName) == nil {
            let associateWithToValueTypeParamName = interner.intern("V")
            let associateWithToValueTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: associateWithToValueTypeParamName,
                fqName: associateWithToMemberFQName + [associateWithToValueTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let associateWithToValueType = types.make(.typeParam(TypeParamType(
                symbol: associateWithToValueTypeParamSymbol, nullability: .nonNull
            )))
            let associateWithToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateWithToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(listTypeParamType), .out(associateWithToValueType)],
                nullability: .nonNull
            )))
            let associateWithToValueSelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: associateWithToValueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let associateWithToMemberSymbol = symbols.define(
                kind: .function,
                name: associateWithToMemberName,
                fqName: associateWithToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: associateWithToMemberSymbol)
            symbols.setParentSymbol(associateWithToMemberSymbol, for: associateWithToValueTypeParamSymbol)
            symbols.setExternalLinkName(
                StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                    ownerKind: .list,
                    memberName: "associateWithTo",
                    arity: 2,
                    fallback: "kk_list_associateWithTo"
                ),
                for: associateWithToMemberSymbol
            )
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: associateWithToReceiverType,
                    parameterTypes: [associateWithToDestinationType, associateWithToValueSelectorType],
                    returnType: associateWithToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, associateWithToValueTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: associateWithToMemberSymbol
            )
        }

        // STDLIB-COL-DEST-004: groupByTo(destination, keySelector) -> M
        let groupByToMemberName = interner.intern("groupByTo")
        let groupByToMemberFQName = listFQName + [groupByToMemberName]
        if symbols.lookup(fqName: groupByToMemberFQName) == nil {
            let groupByToKeyTypeParamName = interner.intern("K")
            let groupByToKeyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: groupByToKeyTypeParamName,
                fqName: groupByToMemberFQName + [groupByToKeyTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let groupByToKeyType = types.make(.typeParam(TypeParamType(
                symbol: groupByToKeyTypeParamSymbol, nullability: .nonNull
            )))
            let groupByToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let groupByToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(groupByToKeyType), .out(listTypeParamType)],
                nullability: .nonNull
            )))
            let groupByToKeySelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: groupByToKeyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let groupByToMemberSymbol = symbols.define(
                kind: .function,
                name: groupByToMemberName,
                fqName: groupByToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: groupByToMemberSymbol)
            symbols.setParentSymbol(groupByToMemberSymbol, for: groupByToKeyTypeParamSymbol)
            symbols.setExternalLinkName(
                StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                    ownerKind: .list,
                    memberName: "groupByTo",
                    arity: 2,
                    fallback: "kk_list_groupByTo"
                ),
                for: groupByToMemberSymbol
            )
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: groupByToReceiverType,
                    parameterTypes: [groupByToDestinationType, groupByToKeySelectorType],
                    returnType: groupByToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, groupByToKeyTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: groupByToMemberSymbol
            )
        }
    }

    /// Register `List<E>.asSequence(): Sequence<E>` member stub (STDLIB-471).
    ///
    /// Note: `Array<E>.asSequence()` does not need a separate Sema stub because
    /// array member calls are resolved through the collection member-call
    /// fallback path (`CallTypeChecker+MemberCallFallbacks`), and the lowering
    /// pass routes to `kk_array_asSequence` via `arrayExprIDs` tracking.
    func registerListAsSequenceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("asSequence")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        // Return type is Sequence<E> — ensure the Sequence interface stub exists.
        let kotlinSequencesPkg: [InternedString] = [
            interner.intern("kotlin"), interner.intern("sequences")
        ]
        if symbols.lookup(fqName: kotlinSequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: kotlinSequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
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
        // Register a type parameter T on Sequence so generic substitution works.
        let seqTypeParamName = interner.intern("T")
        let seqTypeParamFQName = sequenceFQName + [seqTypeParamName]
        if symbols.lookup(fqName: seqTypeParamFQName) == nil {
            let seqTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: seqTypeParamName,
                fqName: seqTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            types.setNominalTypeParameterSymbols([seqTypeParamSymbol], for: sequenceSymbol)
            types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)
        }
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_asSequence", for: memberSymbol)
        // typeParameterSymbols lists all type params (class + function-level).
        // classTypeParameterCount: 1 marks the first entry (E) as belonging to
        // List<E>, not to asSequence itself.  This is the standard pattern used
        // by every other List member stub in this file.
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

}
