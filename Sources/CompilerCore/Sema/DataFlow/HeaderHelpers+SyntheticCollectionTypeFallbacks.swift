import RuntimeABI

// Fallback declarations for collection and sequence nominal types.
// These compiler-side shells remain available for --no-stdlib and precompiled
// metadata contexts until the corresponding KSP migration removes them.

extension DataFlowSemaPhase {
    func registerSyntheticCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
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

        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        func defineCollectionFunctionMember(
            name: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            flags: SymbolFlags,
            externalLinkName: String? = nil
        ) {
            let memberName = interner.intern(name)
            let memberFQName = collectionFQName + [memberName]
            // Keep runtime-linked placeholders for Collection's native interface
            // members so bundled declarations can claim them without losing ABI
            // links. The migrated random APIs are extensions in Collections.kt;
            // leave those to source-backed resolution instead of retaining the
            // legacy synthetic bridge.
            let isMigratedExtension = name == "random" || name == "randomOrNull"
            if isMigratedExtension && bundledIndex.contains(
                ownerFQName: collectionFQName,
                name: memberName,
                arity: parameterTypes.count
            ) {
                skipStats?.recordSkip(
                    ownerFQName: collectionFQName,
                    name: memberName,
                    arity: parameterTypes.count,
                    interner: interner
                )
                return
            }
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

        // Registered inline because size is a .property, not a function.
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
            symbols.setExternalLinkName("__kk_collection_size", for: sizeSymbol)
            symbols.setPropertyType(types.intType, for: sizeSymbol)
        }

        // BUG-166: needs externalLinkName for the same reason as `contains`
        // below — without it, calling isEmpty() through a `Collection<T>`-typed
        // (rather than concrete `List<T>`/`Set<T>`-typed) receiver requires
        // virtual itable dispatch, which the built-in List/Set runtime boxes
        // never register for.
        defineCollectionFunctionMember(
            name: "isEmpty",
            parameterTypes: [],
            returnType: types.booleanType,
            flags: [.synthetic],
            externalLinkName: "__kk_collection_isEmpty"
        )

        // Variance note: Collection declares `out E`, but contains() uses E in
        // parameter (contravariant) position. This matches Kotlin's own declaration
        // where `contains` has `@UnsafeVariance E` — the mismatch is intentional.
        //
        // BUG-166: externalLinkName is required here, not optional. Without it,
        // a call through a `Collection<T>`-typed receiver (as opposed to a
        // concrete `List<T>`/`Set<T>`-typed one, which resolves `contains`
        // through the name-based collection dispatch fallback before this
        // member is ever considered) binds to this member as a real
        // `chosenCallee` and requires virtual itable dispatch — but the
        // built-in List/Set runtime boxes never register themselves into the
        // itable system (they bypass kk_object_new construction entirely), so
        // dispatch panics with KSWIFTK-RUNTIME-0001 ("method not found in
        // vtable/itable"). Setting externalLinkName makes
        // CallLowerer+MemberCallDefaultsAndResolution.tryEmitVirtualDispatch
        // skip virtual dispatch and call the (already receiver-type-agnostic)
        // kk_op_contains directly instead, exactly like the random/
        // randomOrNull/last members below.
        defineCollectionFunctionMember(
            name: "contains",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            externalLinkName: "kk_op_contains"
        )

        let iteratorFQName = kotlinCollectionsPkg + [interner.intern("Iterator")]
        if let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) {
            let iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(typeParamType)],
                nullability: .nonNull
            )))
            defineCollectionFunctionMember(
                name: "iterator",
                parameterTypes: [],
                returnType: iteratorReturnType,
                flags: [.synthetic, .operatorFunction],
                externalLinkName: "kk_list_iterator"
            )
        }

        let collectionParameterType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        defineCollectionFunctionMember(
            name: "containsAll",
            parameterTypes: [collectionParameterType],
            returnType: types.booleanType,
            flags: [.synthetic],
            externalLinkName: "__kk_collection_containsAll"
        )

        defineCollectionFunctionMember(
            name: "random",
            parameterTypes: [],
            returnType: typeParamType,
            flags: [.synthetic],
            externalLinkName: "kk_list_random"
        )

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
    ///
    /// KSP-633: the nominal declaration is source-backed by
    /// `Stdlib/kotlin/collections/AbstractCollection.kt`, which reuses this shell on
    /// bundle load (the `.synthetic` flag is cleared then). The shell stays as the
    /// fallback for non-bundled contexts (`--no-stdlib`, precompiled stdlib artifacts),
    /// where library metadata carries no nominal type parameters.

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
        collectionInterfaceSymbol: SymbolID,
        mutableIterableInterfaceSymbol: SymbolID
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
        symbols.setDirectSupertypes(
            [collectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableCollectionSymbol
        )
        types.setNominalDirectSupertypes(
            [collectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableCollectionSymbol
        )
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)
        symbols.setSupertypeTypeArgs(
            [.invariant(typeParamType)],
            for: mutableCollectionSymbol,
            supertype: mutableIterableInterfaceSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(typeParamType)],
            for: mutableCollectionSymbol,
            supertype: mutableIterableInterfaceSymbol
        )

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
            valueParameterNames: [String] = [],
            externalLinkName: String? = nil
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
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            }

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
            valueParameterNames: ["element"],
            externalLinkName: "__kk_mutable_collection_add"
        )
        registerMutableCollectionFunction(
            name: "addAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"],
            externalLinkName: "__kk_mutable_collection_addAll"
        )
        registerMutableCollectionFunction(
            name: "clear",
            parameterTypes: [],
            returnType: types.unitType,
            externalLinkName: "__kk_mutable_collection_clear"
        )
        registerMutableCollectionFunction(
            name: "remove",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            valueParameterNames: ["element"],
            externalLinkName: "__kk_mutable_collection_remove"
        )
        registerMutableCollectionFunction(
            name: "removeAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"],
            externalLinkName: "__kk_mutable_collection_removeAll"
        )
        registerMutableCollectionFunction(
            name: "retainAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"],
            externalLinkName: "__kk_mutable_collection_retainAll"
        )

        return mutableCollectionSymbol
    }

    /// Register `kotlin.collections.AbstractMutableCollection<E>` surface (STDLIB-COL-TYPE-003).

    ///
    /// KSP-633: source-backed by `Stdlib/kotlin/collections/AbstractMutableCollection.kt`;
    /// this shell is reused on bundle load and kept as the non-bundled fallback.
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
            // KSP-998: Explicit Iterable.iterator() calls must preserve the
            // source iterator's thrown channel and remain lazy.
            symbols.setExternalLinkName("kk_iterable_iterator", for: iterFnSymbol)
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
                    canThrow: true,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iterFnSymbol
            )
        }

        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = iteratorFQName + [hasNextName]
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        if symbols.lookup(fqName: hasNextFQName) == nil,
           !bundledIndex.contains(owner: iteratorFQName, name: hasNextName, arity: 0)
        {
            let sym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .operatorFunction]
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

        let nextName = interner.intern("next")
        let nextFQName = iteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil,
           !bundledIndex.contains(owner: iteratorFQName, name: nextName, arity: 0)
        {
            let sym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .operatorFunction]
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

        // KSP-664: AbstractIterator<T> and the primitive iterator shells are
        // bundled Kotlin source (collections/AbstractIterator.kt, PrimitiveIterators.kt).

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
    ///
    /// KSP-633: the nominal declaration is source-backed by
    /// `Stdlib/kotlin/collections/MutableIterable.kt`, which reuses this shell on bundle
    /// load (the `.synthetic` flag is cleared then); the shell also stays as the
    /// fallback for non-bundled contexts. The covariant `iterator(): MutableIterator<T>`

    /// override stays compiler-side here — see the note in the `.kt` file.
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

}
