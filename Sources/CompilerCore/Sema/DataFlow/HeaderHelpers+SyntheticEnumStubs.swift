
extension DataFlowSemaPhase {
    /// Registers synthetic enum type/container stubs: kotlin.Enum<T> and
    /// EnumEntries<T>. The top-level enum functions are bundled source
    /// declarations; their concrete calls are expanded by the enum-specific
    /// type checker/lowerer.
    func registerSyntheticEnumStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        if symbols.lookup(fqName: kotlinCollectionsPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("collections"), fqName: kotlinCollectionsPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinEnumsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("enums")]
        if symbols.lookup(fqName: kotlinEnumsPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("enums"), fqName: kotlinEnumsPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }

        // Bootstrap kotlin.Enum<T> with name: String, ordinal: Int. KSP-732
        // and KSP-837 declare the nominal class and its six public members in
        // `Stdlib/kotlin/Enum.kt`; bundle loading reuses this shell and its
        // source-backed members replace the fallback properties below. Keep
        // the shell's type parameter in the TypeSystem so header collection
        // does not define a fresh, orphaned `kotlin.Enum.$<id>.T`.
        let enumName = interner.intern("Enum")
        let enumFQName = kotlinPkg + [enumName]
        let enumSymbol = ensureEnumClassSymbol(symbols: symbols, interner: interner, kotlinPkg: kotlinPkg)
        let enumTypeParamSymbol = ensureEnumTypeParameter(symbols: symbols, interner: interner, enumFQName: enumFQName)
        types.setNominalTypeParameterSymbols([enumTypeParamSymbol], for: enumSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: enumSymbol)
        registerEnumNameOrdinalProperties(
            symbols: symbols,
            types: types,
            interner: interner,
            enumSymbol: enumSymbol,
            enumFQName: kotlinPkg + [interner.intern("Enum")]
        )

        // kotlin.enums.EnumEntries<T> — List-like read-only container for enum entries
        let enumEntriesInterfaceSymbol = ensureEnumEntriesInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinEnumsPkg: kotlinEnumsPkg,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        registerEnumEntriesGetOperator(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinEnumsPkg: kotlinEnumsPkg,
            enumEntriesSymbol: enumEntriesInterfaceSymbol
        )

    }

    private func ensureEnumClassSymbol(
        symbols: SymbolTable,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) -> SymbolID {
        let enumName = interner.intern("Enum")
        let enumFQName = kotlinPkg + [enumName]
        if let existing = symbols.lookup(fqName: enumFQName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .class,
            name: enumName,
            fqName: enumFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkg = symbols.lookup(fqName: kotlinPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: symbol)
        }
        return symbol
    }

    private func ensureEnumTypeParameter(
        symbols: SymbolTable,
        interner: StringInterner,
        enumFQName: [InternedString]
    ) -> SymbolID {
        let tName = interner.intern("T")
        let tFQName = enumFQName + [tName]
        if let existing = symbols.lookup(fqName: tFQName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: tFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
    }

    private func registerEnumNameOrdinalProperties(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        enumSymbol: SymbolID,
        enumFQName: [InternedString]
    ) {
        let stringType = types.stringType
        let intType = types.make(.primitive(.int, .nonNull))

        func ensureProperty(name: String, returnType: TypeID) {
            let nameInterned = interner.intern(name)
            let fqName = enumFQName + [nameInterned]
            guard symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .property }) else {
                return
            }
            let propSymbol = symbols.define(
                kind: .property,
                name: nameInterned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: propSymbol)
            symbols.setPropertyType(returnType, for: propSymbol)
        }

        ensureProperty(name: "name", returnType: stringType)
        ensureProperty(name: "ordinal", returnType: intType)
    }

    private func ensureEnumEntriesInterface(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinEnumsPkg: [InternedString],
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let enumEntriesName = interner.intern("EnumEntries")
        let enumEntriesFQName = kotlinEnumsPkg + [enumEntriesName]
        let tParamName = interner.intern("T")
        let tParamFQName = enumEntriesFQName + [tParamName]

        let enumEntriesSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumEntriesFQName) {
            enumEntriesSymbol = existing
        } else {
            _ = symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            enumEntriesSymbol = symbols.define(
                kind: .interface,
                name: enumEntriesName,
                fqName: enumEntriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkg = symbols.lookup(fqName: kotlinEnumsPkg), pkg != .invalid {
                symbols.setParentSymbol(pkg, for: enumEntriesSymbol)
            }
        }

        // kotlin.enums.EnumEntries<T> : kotlin.collections.List<T> (Kotlin 1.9+:
        // `EnumClass.entries` is a read-only List<T>). Registering the
        // supertype relationship in both the SymbolTable and TypeSystem
        // nominal-supertype graphs (mirroring how List/Collection/Iterable
        // register their own supertypes, e.g. registerSyntheticListStub) lets
        // ordinary member-call resolution and the collection member-call
        // fallback find List's real members (.size, .forEach, etc.) on an
        // EnumEntries<T>-typed receiver instead of reporting "Unresolved
        // member function".
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName),
              let listInterfaceSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")])
        else {
            return enumEntriesSymbol
        }
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tParamSymbol], for: enumEntriesSymbol)
        types.setNominalTypeParameterVariances([.out], for: enumEntriesSymbol)
        symbols.setDirectSupertypes([listInterfaceSymbol], for: enumEntriesSymbol)
        types.setNominalDirectSupertypes([listInterfaceSymbol], for: enumEntriesSymbol)
        symbols.setSupertypeTypeArgs([.out(tParamType)], for: enumEntriesSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(tParamType)], for: enumEntriesSymbol, supertype: listInterfaceSymbol)

        return enumEntriesSymbol
    }

    /// Registers `operator fun get(index: Int): T` on `EnumEntries<T>`.
    ///
    /// `EnumEntries<T>` has no declared members or supertypes (see
    /// `ensureEnumEntriesInterface`), so without an owned `get`, indexed access
    /// (`entries[0]`) finds no `operator fun get` candidate in Sema and the KIR
    /// indexed-access lowering falls back to the generic built-in path, which
    /// always emits `kk_array_get` regardless of the receiver's actual runtime
    /// representation. `entries`'s runtime representation is a `RuntimeListBox`
    /// (`kk_enum_make_entries_list_cached`), not a `RuntimeArrayBox`, so that
    /// fallback panics at runtime (BUG-178). EnumEntries uses a dedicated
    /// checked bridge because its get contract throws on an invalid index.
    private func registerEnumEntriesGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinEnumsPkg: [InternedString],
        enumEntriesSymbol: SymbolID
    ) {
        let enumEntriesFQName = kotlinEnumsPkg + [interner.intern("EnumEntries")]
        let tParamFQName = enumEntriesFQName + [interner.intern("T")]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }

        let getName = interner.intern("get")
        let getFQName = enumEntriesFQName + [getName]
        guard symbols.lookup(fqName: getFQName) == nil else { return }

        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: enumEntriesSymbol,
            args: [.out(tParamType)],
            nullability: .nonNull
        )))
        let getSymbol = symbols.define(
            kind: .function,
            name: getName,
            fqName: getFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction, .throwingFunction]
        )
        symbols.setParentSymbol(enumEntriesSymbol, for: getSymbol)
        symbols.setExternalLinkName("__kk_enum_entries_get", for: getSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType],
                returnType: tParamType,
                canThrow: true,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: getSymbol
        )
    }

    /// Registers synthetic enum entry properties (name, ordinal) on an enum class.
    /// Called from HeaderCollection when processing enum classes.
    func collectSyntheticEnumEntryProperties(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let intType = types.make(.primitive(.int, .nonNull))

        for (name, returnType) in [("name", stringType), ("ordinal", intType)] {
            let nameInterned = interner.intern(name)
            let fqName = ownerFQName + [nameInterned]
            guard symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .property }) else {
                continue
            }
            let propSymbol = symbols.define(
                kind: .property,
                name: nameInterned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: propSymbol)
            symbols.setPropertyType(returnType, for: propSymbol)
            scope.insert(propSymbol)
        }
    }

    /// Registers the synthetic `values(): Array<T>` static factory on an enum
    /// class itself (e.g. `Direction.values()`), mirroring how real Kotlin
    /// exposes `values()` as a pseudo-static member of the enum class rather
    /// than its companion. Unlike `valueOf`/`entries` (registered on the
    /// companion by `collectSyntheticEnumCompanionMembers`), `values()` is
    /// looked up directly under the enum class's own FQ name by the
    /// class-name-receiver static-call resolution path (see
    /// `inferRegularMemberCall`'s `staticMethodFQName` lookup), so its owner
    /// here must be `ownerSymbol` (the enum class), not the companion.
    ///
    /// The corresponding KIR function body is synthesized later by
    /// `DataEnumSealedSynthesisPass.appendSyntheticEnumValuesIfNeeded`, which
    /// reuses this exact symbol (by FQ name + owner) so the call resolved
    /// here at Sema time links to the KIR body generated during Lowering.
    /// Called from HeaderCollection when processing enum classes.
    func collectSyntheticEnumValuesMember(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        enumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let valuesName = interner.intern("values")
        // Source-backed enum extensions such as
        // `RequiresOptIn.Level.values()` own the class-name API. Do not add
        // the generated enum member as a duplicate in that case.
        guard !BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: ownerFQName,
            name: valuesName,
            arity: 0
        ) else {
            return
        }
        let valuesFQName = ownerFQName + [valuesName]
        guard symbols.lookupAll(fqName: valuesFQName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .function }) else {
            return
        }
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return
        }
        let arrayType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(enumType)],
            nullability: .nonNull
        )))
        let funcSymbol = symbols.define(
            kind: .function,
            name: valuesName,
            fqName: valuesFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: arrayType,
                isSuspend: false
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic companion members (valueOf, entries) for enum classes.
    /// Call with companionSymbol and companionScope when the companion exists (or was synthesized).
    func collectSyntheticEnumCompanionMembers(
        companionSymbol: SymbolID,
        companionFQName: [InternedString],
        enumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        // valueOf(name: String): T — companion receiver so Color.valueOf resolves
        let valueOfName = interner.intern("valueOf")
        let valueOfFQName = companionFQName + [valueOfName]
        if symbols.lookupAll(fqName: valueOfFQName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .function }) {
            let paramName = interner.intern("name")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: valueOfFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let funcSymbol = symbols.define(
                kind: .function,
                name: valueOfName,
                fqName: valueOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(companionSymbol, for: funcSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: companionType,
                    parameterTypes: [stringType],
                    returnType: enumType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: funcSymbol
            )
            scope.insert(funcSymbol)
        }

        // entries: EnumEntries<T>
        let enumEntriesName = interner.intern("EnumEntries")
        let enumEntriesFQName = [interner.intern("kotlin"), interner.intern("enums"), enumEntriesName]
        guard let enumEntriesSymbol = symbols.lookup(fqName: enumEntriesFQName) else { return }

        let entriesName = interner.intern("entries")
        let entriesFQName = companionFQName + [entriesName]
        if symbols.lookupAll(fqName: entriesFQName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .property }) {
            let entriesType = types.make(.classType(ClassType(
                classSymbol: enumEntriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let propSymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(companionSymbol, for: propSymbol)
            symbols.setPropertyType(entriesType, for: propSymbol)
            scope.insert(propSymbol)
        }
    }
}
