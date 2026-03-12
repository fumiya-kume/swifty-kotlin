import Foundation

extension DataFlowSemaPhase {
    /// Registers synthetic enum stdlib stubs: kotlin.Enum<T>, EnumEntries<T>,
    /// enumValues<T>(), enumValueOf<T>(String).
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

        // kotlin.Enum<T> with name: String, ordinal: Int
        let enumName = interner.intern("Enum")
        let enumFQName = kotlinPkg + [enumName]
        let enumSymbol = ensureEnumClassSymbol(symbols: symbols, interner: interner, kotlinPkg: kotlinPkg)
        let tParamSymbol = ensureEnumTypeParameter(symbols: symbols, types: types, interner: interner, enumFQName: enumFQName)
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        registerEnumNameOrdinalProperties(
            symbols: symbols,
            types: types,
            interner: interner,
            enumSymbol: enumSymbol,
            enumFQName: kotlinPkg + [interner.intern("Enum")],
            receiverType: enumType
        )

        // kotlin.collections.EnumEntries<T> — List-like read-only container for enum entries
        _ = ensureEnumEntriesInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // enumValues<T>(): Array<T> — top-level inline reified (returns List<T> for minimal impl)
        registerEnumValuesFunction(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // enumValueOf<T>(name: String): T — top-level inline reified
        registerEnumValueOfFunction(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
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
        types: TypeSystem,
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
        enumFQName: [InternedString],
        receiverType: TypeID
    ) {
        let stringType = types.make(.primitive(.string, .nonNull))
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
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let enumEntriesName = interner.intern("EnumEntries")
        let enumEntriesFQName = kotlinCollectionsPkg + [enumEntriesName]
        if let existing = symbols.lookup(fqName: enumEntriesFQName) {
            return existing
        }
        let tParamName = interner.intern("T")
        let tParamFQName = enumEntriesFQName + [tParamName]
        _ = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let enumEntriesSymbol = symbols.define(
            kind: .interface,
            name: enumEntriesName,
            fqName: enumEntriesFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkg = symbols.lookup(fqName: kotlinCollectionsPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: enumEntriesSymbol)
        }
        return enumEntriesSymbol
    }

    private func registerEnumValuesFunction(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString],
        kotlinCollectionsPkg: [InternedString]
    ) {
        let enumValuesName = interner.intern("enumValues")
        let enumValuesFQName = kotlinPkg + [enumValuesName]
        guard symbols.lookupAll(fqName: enumValuesFQName).isEmpty else { return }

        let listName = interner.intern("List")
        let listFQName = kotlinCollectionsPkg + [listName]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else { return }

        let tParamName = interner.intern("T")
        let tParamFQName = enumValuesFQName + [tParamName]
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let arrayType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(tParamType)],
            nullability: .nonNull
        )))

        let funcSymbol = symbols.define(
            kind: .function,
            name: enumValuesName,
            fqName: enumValuesFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let pkg = symbols.lookup(fqName: kotlinPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: funcSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: arrayType,
                isSuspend: false,
                typeParameterSymbols: [tParamSymbol],
                reifiedTypeParameterIndices: [0],
                typeParameterUpperBoundsList: [[]],
                classTypeParameterCount: 0
            ),
            for: funcSymbol
        )
    }

    private func registerEnumValueOfFunction(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let enumValueOfName = interner.intern("enumValueOf")
        let enumValueOfFQName = kotlinPkg + [enumValueOfName]
        guard symbols.lookupAll(fqName: enumValueOfFQName).isEmpty else { return }

        let tParamName = interner.intern("T")
        let tParamFQName = enumValueOfFQName + [tParamName]
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let stringType = types.make(.primitive(.string, .nonNull))

        let paramName = interner.intern("name")
        let paramFQName = enumValueOfFQName + [paramName]
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: paramFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let funcSymbol = symbols.define(
            kind: .function,
            name: enumValueOfName,
            fqName: enumValueOfFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let pkg = symbols.lookup(fqName: kotlinPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: funcSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [stringType],
                returnType: tParamType,
                isSuspend: false,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol],
                reifiedTypeParameterIndices: [0],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }

    /// Registers synthetic enum entry properties (name, ordinal) on an enum class.
    /// Called from HeaderCollection when processing enum classes.
    func collectSyntheticEnumEntryProperties(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        enumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let stringType = types.make(.primitive(.string, .nonNull))
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
        let stringType = types.make(.primitive(.string, .nonNull))

        // valueOf(name: String): T
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
                    receiverType: nil,
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
        let enumEntriesFQName = [interner.intern("kotlin"), interner.intern("collections"), enumEntriesName]
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
