import RuntimeABI

/// List transform members that are not yet source-backed (e.g. `sum`, `distinctBy`)
/// extracted from the KSP-697 list residual registry.
/// KSP-421 source-backed transforms (`map`, `mapIndexed`, `mapNotNull`,
/// `flatMap`, `flatMapIndexed`, `flatten`, and `*To` variants) are no longer
/// registered here.
/// KSP-427 source-backed transforms (`take`, `takeLast`, `drop`, `dropLast`,
/// `slice`, `subList`) are no longer registered here.
extension DataFlowSemaPhase {
    func registerListTransformMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        let comparableElementBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
            [types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(listTypeParamType)],
                nullability: .nonNull
            )))]
        } else {
            []
        }

        // Register a synthetic member on List. Skips only when a symbol with the
        // same fully-qualified name and matching parameter list already exists
        // (overloads with distinct signatures are all registered).
        func registerMember(
            name: String,
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil,
            canThrow: Bool = false
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            if let types = BundledSyntheticStubRegistration.types,
               BundledSyntheticStubRegistration.shouldSkipRegistration(
                   declaredOwnerFQName: listFQName,
                   receiverType: receiverType,
                   name: memberName,
                   arity: parameterTypes.count,
                   symbols: symbols,
                   types: types,
                   interner: interner
               )
            {
                return
            }
            let alreadySameSignature = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadySameSignature else { return }
            registerMemberOverload(
                memberName: memberName,
                memberFQName: memberFQName,
                parameterTypes: parameterTypes,
                externalLinkName: externalLinkName,
                returnTypeOverride: returnTypeOverride,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                canThrow: canThrow
            )
        }

        // Register a synthetic member overload on List, checking for
        // duplicate registrations by comparing parameter signatures.
        func registerMemberOverload(
            memberName: InternedString,
            memberFQName: [InternedString],
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterSymbols: [SymbolID]? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil,
            flags: SymbolFlags = [.synthetic],
            reifiedTypeParameterIndices: Set<Int> = [],
            canThrow: Bool = false
        ) {
            if let types = BundledSyntheticStubRegistration.types,
               BundledSyntheticStubRegistration.shouldSkipRegistration(
                   declaredOwnerFQName: listFQName,
                   receiverType: receiverType,
                   name: memberName,
                   arity: parameterTypes.count,
                   symbols: symbols,
                   types: types,
                   interner: interner
               )
            {
                return
            }
            let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadyRegistered else { return }
            let sourceBackedFilterNames: Set<InternedString> = [
                interner.intern("filter"),
                interner.intern("filterNot"),
                interner.intern("filterNotNull"),
                interner.intern("filterIndexed"),
                interner.intern("filterIsInstance"),
            ]
            if sourceBackedFilterNames.contains(memberName),
               shouldSkipSyntheticStub(
                   bundledIndex: bundledIndex,
                   ownerFQName: listFQName,
                   name: memberName,
                   arity: parameterTypes.count
               )
            {
                skipStats?.recordSkip(
                    ownerFQName: listFQName,
                    name: memberName,
                    arity: parameterTypes.count,
                    interner: interner
                )
                return
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: interner.resolve(memberName),
                arity: parameterTypes.count,
                fallback: externalLinkName
            )
            symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnTypeOverride ?? receiverType,
                    canThrow: canThrow,
                    typeParameterSymbols: typeParameterSymbols ?? [listTypeParamSymbol],
                    reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: typeParameterUpperBoundsList ?? [],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMember(
            name: "sorted",
            parameterTypes: [],
            externalLinkName: "kk_list_sorted",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
        registerMember(name: "shuffled", parameterTypes: [], externalLinkName: "kk_list_shuffled")

        // The bundled ListSortingHOF.kt source owns this overload when the
        // bundled stdlib is present. Keep the synthetic fallback for
        // precompiled/no-source contexts where Random is already available.
        do {
            let shuffledRandomName = interner.intern("shuffled")
            let shuffledRandomFQName = listFQName + [shuffledRandomName]
            let kotlinRandomPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("random")]
            let randomClassName = interner.intern("Random")
            let randomFQName = kotlinRandomPkg + [randomClassName]
            if let randomSymbol = symbols.lookup(fqName: randomFQName) {
                let randomParamType = types.make(.classType(ClassType(
                    classSymbol: randomSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                registerMemberOverload(
                    memberName: shuffledRandomName,
                    memberFQName: shuffledRandomFQName,
                    parameterTypes: [randomParamType],
                    externalLinkName: "kk_list_shuffled_random"
                )
            }
        }

        registerMember(
            name: "sortedDescending",
            parameterTypes: [],
            externalLinkName: "kk_list_sortedDescending",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
    }
}
