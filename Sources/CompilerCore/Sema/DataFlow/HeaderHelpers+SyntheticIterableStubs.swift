import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Iterable, MutableIterable, Sequence, and Collection<T> interfaces plus member helpers (incl. primitive iterator stubs).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let collectionName = interner.intern("Collection")
        let collectionFQName = kotlinCollectionsPkg + [collectionName]
        let collectionInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: collectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: collectionName,
                fqName: collectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = collectionFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: collectionInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: collectionInterfaceSymbol)
        symbols.setDirectSupertypes([iterableInterfaceSymbol], for: collectionInterfaceSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol], for: collectionInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: collectionInterfaceSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: collectionInterfaceSymbol, supertype: iterableInterfaceSymbol)

        // Register Collection<T> members: size, isEmpty, contains (STDLIB-295)
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        // Helper to define a synthetic Collection function member and register
        // its parent + function signature in one place.
        func defineCollectionFunctionMember(
            name: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            flags: SymbolFlags,
            externalLinkName: String? = nil
        ) {
            let memberName = interner.intern(name)
            let memberFQName = collectionFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: collectionReceiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // size: Int — Kotlin val property, registered as .property kind.
        // NOTE: size is registered inline (not via defineCollectionFunctionMember)
        // because it is a property (.property kind), not a function.
        let sizeName = interner.intern("size")
        let sizeFQName = collectionFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSymbol = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: sizeSymbol)
            symbols.setPropertyType(types.intType, for: sizeSymbol)
        }

        // isEmpty(): Boolean
        defineCollectionFunctionMember(
            name: "isEmpty",
            parameterTypes: [],
            returnType: types.booleanType,
            flags: [.synthetic]
        )

        // contains(element: E): Boolean — operator for Kotlin `in`.
        // Variance note: Collection declares `out E`, but contains() uses E in
        // parameter (contravariant) position. This matches Kotlin's own declaration
        // where `contains` has `@UnsafeVariance E` — the mismatch is intentional.
        defineCollectionFunctionMember(
            name: "contains",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction]
        )

        // last(): E — modeled directly here because Collection member lookup does
        // not currently inherit synthetic Iterable extension members.
        let lastName = interner.intern("last")
        let lastFQName = collectionFQName + [lastName]
        if symbols.lookup(fqName: lastFQName) == nil {
            let lastSymbol = symbols.define(
                kind: .function,
                name: lastName,
                fqName: lastFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: lastSymbol)
            symbols.setExternalLinkName("kk_iterable_last", for: lastSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: collectionReceiverType,
                    parameterTypes: [],
                    returnType: typeParamType,
                    canThrow: true,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: lastSymbol
            )
        }

        // random(): E
        defineCollectionFunctionMember(
            name: "random",
            parameterTypes: [],
            returnType: typeParamType,
            flags: [.synthetic],
            externalLinkName: "kk_list_random"
        )

        // randomOrNull(): E?
        defineCollectionFunctionMember(
            name: "randomOrNull",
            parameterTypes: [],
            returnType: types.makeNullable(typeParamType),
            flags: [.synthetic],
            externalLinkName: "kk_list_randomOrNull"
        )

        return collectionInterfaceSymbol
    }

    /// Register `kotlin.collections.AbstractCollection<E>` surface (STDLIB-COL-TYPE-001).
    func registerSyntheticAbstractCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractCollectionName = interner.intern("AbstractCollection")
        let abstractCollectionFQName = kotlinCollectionsPkg + [abstractCollectionName]
        let abstractCollectionSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractCollectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractCollectionName,
                fqName: abstractCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractCollectionFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractCollectionSymbol)
        types.setNominalTypeParameterVariances([.out], for: abstractCollectionSymbol)

        let abstractCollectionType = types.make(.classType(ClassType(
            classSymbol: abstractCollectionSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractCollectionType, for: abstractCollectionSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: abstractCollectionSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: abstractCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractCollectionSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractCollectionSymbol, supertype: collectionInterfaceSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractCollectionFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractCollectionSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractCollectionType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractCollectionSymbol
    }

    /// Register a minimal `kotlin.collections.MutableCollection<E>` interface surface.
    func registerSyntheticMutableCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let mutableCollectionName = interner.intern("MutableCollection")
        let mutableCollectionFQName = kotlinCollectionsPkg + [mutableCollectionName]
        let mutableCollectionSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableCollectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableCollectionName,
                fqName: mutableCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = mutableCollectionFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableCollectionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableCollectionSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: mutableCollectionSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: mutableCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)

        let mutableCollectionType = types.make(.classType(ClassType(
            classSymbol: mutableCollectionSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        func registerMutableCollectionFunction(
            name: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            valueParameterNames: [String] = []
        ) {
            let memberName = interner.intern(name)
            let memberFQName = mutableCollectionFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableCollectionSymbol, for: memberSymbol)

            var valueParameterSymbols: [SymbolID] = []
            for parameterName in valueParameterNames {
                let interned = interner.intern(parameterName)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: interned,
                    fqName: memberFQName + [interned],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
                valueParameterSymbols.append(parameterSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableCollectionType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    valueParameterSymbols: valueParameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                    valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMutableCollectionFunction(
            name: "add",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            valueParameterNames: ["element"]
        )
        registerMutableCollectionFunction(
            name: "addAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )
        registerMutableCollectionFunction(
            name: "clear",
            parameterTypes: [],
            returnType: types.unitType
        )
        registerMutableCollectionFunction(
            name: "remove",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            valueParameterNames: ["element"]
        )
        registerMutableCollectionFunction(
            name: "removeAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )
        registerMutableCollectionFunction(
            name: "retainAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )

        return mutableCollectionSymbol
    }

    /// Register `kotlin.collections.AbstractMutableCollection<E>` surface (STDLIB-COL-TYPE-003).
    func registerSyntheticAbstractMutableCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        mutableCollectionInterfaceSymbol: SymbolID
    ) {
        let abstractMutableCollectionName = interner.intern("AbstractMutableCollection")
        let abstractMutableCollectionFQName = kotlinCollectionsPkg + [abstractMutableCollectionName]
        let abstractMutableCollectionSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableCollectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableCollectionName,
                fqName: abstractMutableCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractMutableCollectionFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractMutableCollectionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractMutableCollectionSymbol)

        let abstractMutableCollectionType = types.make(.classType(ClassType(
            classSymbol: abstractMutableCollectionSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableCollectionType, for: abstractMutableCollectionSymbol)

        let abstractCollectionFQName = kotlinCollectionsPkg + [interner.intern("AbstractCollection")]
        let readonlyCollectionSupertype = symbols.lookup(fqName: abstractCollectionFQName) ?? collectionInterfaceSymbol
        symbols.setDirectSupertypes([readonlyCollectionSupertype, mutableCollectionInterfaceSymbol], for: abstractMutableCollectionSymbol)
        types.setNominalDirectSupertypes([readonlyCollectionSupertype, mutableCollectionInterfaceSymbol], for: abstractMutableCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableCollectionSymbol, supertype: readonlyCollectionSupertype)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableCollectionSymbol, supertype: readonlyCollectionSupertype)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableCollectionSymbol, supertype: mutableCollectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableCollectionSymbol, supertype: mutableCollectionInterfaceSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableCollectionFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableCollectionSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableCollectionType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }
    }

    /// Register `Collection<E>.toList(): List<E>` so that `keys.toList()` / `values.toList()` resolve.
    /// Also registers `Collection<E>.toCollection(destination)` for destination appends.
    /// Must be called after both Collection and List stubs are registered.
    func registerCollectionToListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        let collectionFQName = kotlinCollectionsPkg + [interner.intern("Collection")]
        guard let typeParamSymbol = symbols.lookup(
            fqName: collectionFQName + [interner.intern("E")]
        ) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let listReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toList")
        let memberFQName = collectionFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_collection_toList", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: collectionReceiverType,
                parameterTypes: [],
                returnType: listReturnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )

        let toCollectionName = interner.intern("toCollection")
        let toCollectionFQName = collectionFQName + [toCollectionName]
        if symbols.lookup(fqName: toCollectionFQName) == nil {
            let toCollectionSym = symbols.define(
                kind: .function,
                name: toCollectionName,
                fqName: toCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: toCollectionSym)
            symbols.setExternalLinkName("kk_collection_toCollection", for: toCollectionSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: collectionReceiverType,
                    parameterTypes: [collectionReceiverType],
                    returnType: collectionReceiverType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: toCollectionSym
            )
        }
    }

    func registerCollectionToTypedArrayMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) {
        let collectionFQName = kotlinCollectionsPkg + [interner.intern("Collection")]
        guard let typeParamSymbol = symbols.lookup(
            fqName: collectionFQName + [interner.intern("E")]
        ),
        let arraySymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")])
        else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let arrayReturnType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toTypedArray")
        let memberFQName = collectionFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_collection_toTypedArray", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: collectionReceiverType,
                parameterTypes: [],
                returnType: arrayReturnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Collection<E>.toMutableList(): MutableList<E>` (STDLIB-021).
    func registerCollectionToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        let collectionFQName = kotlinCollectionsPkg + [interner.intern("Collection")]
        guard let typeParamSymbol = symbols.lookup(
            fqName: collectionFQName + [interner.intern("E")]
        ) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let mutableListReturnType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toMutableList")
        let memberFQName = collectionFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_collection_toMutableList", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: collectionReceiverType,
                parameterTypes: [],
                returnType: mutableListReturnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.toMutableList(): MutableList<E>` (STDLIB-021).
    func registerIterableToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableList")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

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
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(typeParamType)],
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
        symbols.setExternalLinkName("kk_iterable_toMutableList", for: memberSymbol)
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

    /// Register `Iterable<E>.toMutableSet(): MutableSet<E>` (STDLIB-021).
    func registerIterableToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableSetSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableSet")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

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
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(typeParamType)],
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
        symbols.setExternalLinkName("kk_iterable_toMutableSet", for: memberSymbol)
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

    /// Register `Iterable<E>.toHashSet(): HashSet<E>` (STDLIB-021).
    /// At runtime HashSet is backed by the same RuntimeSetBox as MutableSet.
    func registerIterableToHashSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableSetSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toHashSet")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

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
        // Return MutableSet<E> (HashSet is a type alias for MutableSet at the runtime level)
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(typeParamType)],
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
        symbols.setExternalLinkName("kk_iterable_toHashSet", for: memberSymbol)
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

    func registerSyntheticIterableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let iterableName = interner.intern("Iterable")
        let iterableFQName = kotlinCollectionsPkg + [iterableName]
        let iterableInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: iterableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: iterableName,
                fqName: iterableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: iterableInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: iterableInterfaceSymbol)

        // Register Iterator<T> interface (STDLIB-221)
        let iteratorName = interner.intern("Iterator")
        let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
        let iteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: iteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: iteratorName,
                fqName: iteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let itTypeParamName = interner.intern("T")
        let itTypeParamFQName = iteratorFQName + [itTypeParamName]
        let itTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: itTypeParamName,
            fqName: itTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([itTypeParamSymbol], for: iteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: iteratorSymbol)
        let iteratorTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: itTypeParamSymbol,
            nullability: .nonNull
        )))
        let iteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(iteratorTypeParamType)],
            nullability: .nonNull
        )))

        // Iterable.iterator(): Iterator<E>
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = iterableFQName + [iterFnName]
        if symbols.lookup(fqName: iterFnFQName) == nil {
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let iterableReceiverType = types.make(.classType(ClassType(
                classSymbol: iterableInterfaceSymbol,
                args: [.out(typeParamType)],
                nullability: .nonNull
            )))
            let iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(typeParamType)],
                nullability: .nonNull
            )))
            let iterFnSymbol = symbols.define(
                kind: .function,
                name: iterFnName,
                fqName: iterFnFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(iterableInterfaceSymbol, for: iterFnSymbol)
            symbols.setExternalLinkName("kk_range_iterator", for: iterFnSymbol)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [],
                returnType: iteratorReturnType,
                isSuspend: false,
                nullability: .nonNull
            ))), for: iterFnSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iterableReceiverType,
                    parameterTypes: [],
                    returnType: iteratorReturnType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iterFnSymbol
            )
        }

        // Iterator.hasNext(): Boolean
        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = iteratorFQName + [hasNextName]
        if symbols.lookup(fqName: hasNextFQName) == nil {
            let sym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(iteratorSymbol, for: sym)
            symbols.setExternalLinkName("kk_iterator_hasNext", for: sym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [itTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: sym
            )
        }

        // Iterator.next(): T
        let nextName = interner.intern("next")
        let nextFQName = iteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil {
            let sym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(iteratorSymbol, for: sym)
            symbols.setExternalLinkName("kk_iterator_next", for: sym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: iteratorTypeParamType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iteratorReceiverType,
                    parameterTypes: [],
                    returnType: iteratorTypeParamType,
                    typeParameterSymbols: [itTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: sym
            )
        }

        registerSyntheticAbstractIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iteratorSymbol: iteratorSymbol
        )

        registerSyntheticPrimitiveIteratorStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iteratorSymbol: iteratorSymbol
        )

        // MutableIterator<T> : Iterator<T> (STDLIB-221)
        let mutableIteratorName = interner.intern("MutableIterator")
        let mutableIteratorFQName = kotlinCollectionsPkg + [mutableIteratorName]
        let mutableIteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface, name: mutableIteratorName, fqName: mutableIteratorFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let mutableIteratorTypeParamName = interner.intern("T")
        let mutableIteratorTypeParamFQName = mutableIteratorFQName + [mutableIteratorTypeParamName]
        let mutableIteratorTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIteratorTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: mutableIteratorTypeParamName,
                fqName: mutableIteratorTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let mutableIteratorTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mutableIteratorTypeParamSymbol,
            nullability: .nonNull
        )))
        let mutableIteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: mutableIteratorSymbol,
            args: [.out(mutableIteratorTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([mutableIteratorTypeParamSymbol], for: mutableIteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: mutableIteratorSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: mutableIteratorSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: mutableIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(mutableIteratorTypeParamType)], for: mutableIteratorSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(mutableIteratorTypeParamType)], for: mutableIteratorSymbol, supertype: iteratorSymbol)

        // MutableIterator.remove(): Unit
        let removeName = interner.intern("remove")
        let removeFQName = mutableIteratorFQName + [removeName]
        if symbols.lookup(fqName: removeFQName) == nil {
            let removeSymbol = symbols.define(
                kind: .function, name: removeName, fqName: removeFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableIteratorSymbol, for: removeSymbol)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.unitType, isSuspend: false, nullability: .nonNull
            ))), for: removeSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.unitType,
                    typeParameterSymbols: [mutableIteratorTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: removeSymbol
            )
        }

        return iterableInterfaceSymbol
    }

    /// Register `kotlin.collections.MutableIterable<T>` surface (STDLIB-COL-TYPE-005).
    func registerSyntheticMutableIterableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let mutableIterableName = interner.intern("MutableIterable")
        let mutableIterableFQName = kotlinCollectionsPkg + [mutableIterableName]
        let mutableIterableSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIterableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableIterableName,
                fqName: mutableIterableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = mutableIterableFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableIterableSymbol)
        types.setNominalTypeParameterVariances([.out], for: mutableIterableSymbol)
        symbols.setDirectSupertypes([iterableInterfaceSymbol], for: mutableIterableSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol], for: mutableIterableSymbol)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: mutableIterableSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: mutableIterableSymbol, supertype: iterableInterfaceSymbol)

        let mutableIterableType = types.make(.classType(ClassType(
            classSymbol: mutableIterableSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let mutableIteratorFQName = kotlinCollectionsPkg + [interner.intern("MutableIterator")]
        guard let mutableIteratorSymbol = symbols.lookup(fqName: mutableIteratorFQName) else {
            assertionFailure("MutableIterator must be registered before MutableIterable")
            return mutableIterableSymbol
        }
        let mutableIteratorType = types.make(.classType(ClassType(
            classSymbol: mutableIteratorSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let iteratorName = interner.intern("iterator")
        let iteratorFQName = mutableIterableFQName + [iteratorName]
        if symbols.lookup(fqName: iteratorFQName) == nil {
            let iteratorSymbol = symbols.define(
                kind: .function,
                name: iteratorName,
                fqName: iteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(mutableIterableSymbol, for: iteratorSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableIterableType,
                    parameterTypes: [],
                    returnType: mutableIteratorType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iteratorSymbol
            )
        }

        return mutableIterableSymbol
    }

    /// Ensure the synthetic `kotlin.sequences.Sequence<T>` interface stub exists,
    /// including its `operator fun iterator(): Iterator<T>` member.
    ///
    /// This helper is idempotent: it creates the package, interface, type parameter,
    /// and `iterator()` member only if they are not already present.  Callers that
    /// need a `Sequence` return type (e.g., `asSequence()` on various collection
    /// types) should call this first and use the returned `SymbolID`.
    func ensureSyntheticSequenceStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        // Step 1: Ensure the kotlin.sequences package exists.
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

        // Step 2: Ensure the Sequence interface exists.
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

        // Step 3: Ensure the type parameter T on Sequence exists.
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

        // Step 4: Ensure `operator fun iterator(): Iterator<T>` exists on Sequence,
        // independently of whether the type parameter was newly created above.
        // This prevents the case where Sequence<T> already exists (e.g., created
        // elsewhere) but iterator() is missing.
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = sequenceFQName + [iterFnName]
        if symbols.lookup(fqName: iterFnFQName) == nil {
            if let seqTypeParamSymbol = symbols.lookup(fqName: seqTypeParamFQName) {
                let seqTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: seqTypeParamSymbol, nullability: .nonNull
                )))
                let iteratorName = interner.intern("Iterator")
                let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
                if let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) {
                    let iteratorReturnType = types.make(.classType(ClassType(
                        classSymbol: iteratorSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    let iterFnSymbol = symbols.define(
                        kind: .function,
                        name: iterFnName,
                        fqName: iterFnFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic, .operatorFunction]
                    )
                    symbols.setParentSymbol(sequenceSymbol, for: iterFnSymbol)
                    let seqReceiverType = types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: seqReceiverType,
                            parameterTypes: [],
                            returnType: iteratorReturnType,
                            typeParameterSymbols: [seqTypeParamSymbol],
                            classTypeParameterCount: 1
                        ),
                        for: iterFnSymbol
                    )
                }
            }
        }

        // STDLIB-SEQ-008: Sequence<T>.chunked(size, transform): Sequence<R>
        let chunkedName = interner.intern("chunked")
        let chunkedFQName = sequenceFQName + [chunkedName]
        if let seqTypeParamSymbol = symbols.lookup(fqName: seqTypeParamFQName),
           let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")])
        {
            let seqTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: seqTypeParamSymbol,
                nullability: .nonNull
            )))
            let chunkParameterType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(seqTypeParamType)],
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [chunkParameterType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceReturnType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(types.anyType)],
                nullability: .nonNull
            )))
            let alreadyRegistered = symbols.lookupAll(fqName: chunkedFQName).contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes.count == 2
                    && symbols.externalLinkName(for: symID) == "kk_sequence_chunked_transform"
            }
            if !alreadyRegistered {
                let chunkedSymbol = symbols.define(
                    kind: .function,
                    name: chunkedName,
                    fqName: chunkedFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: chunkedSymbol)
                symbols.setExternalLinkName("kk_sequence_chunked_transform", for: chunkedSymbol)
                let receiverType = types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(seqTypeParamType)],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, transformType],
                        returnType: sequenceReturnType,
                        typeParameterSymbols: [seqTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: chunkedSymbol
                )
            }
        }

        return sequenceSymbol
    }
}
