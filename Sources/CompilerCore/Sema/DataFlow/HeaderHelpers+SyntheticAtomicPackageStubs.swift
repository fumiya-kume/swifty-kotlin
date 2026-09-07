
/// `kotlin.concurrent.atomics` package-level scaffolding — the
/// `@ExperimentalAtomicApi` annotation, the `MemoryOrder` enum, and the
/// type aliases back to `kotlin.concurrent` — extracted from
/// the Atomic residual registration surface.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicAnnotation(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationName = interner.intern(name)
        let fqName = packageFQName + [annotationName]
        guard symbols.lookup(fqName: fqName) == nil else { return }

        _ = symbols.define(
            kind: .annotationClass,
            name: annotationName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    func ensureAtomicMemoryOrderEnum(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("MemoryOrder")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: symbol)
        }

        let entries = [
            "RELAXED",
            "ACQUIRE",
            "RELEASE",
            "ACQUIRE_RELEASE",
            "SEQUENTIALLY_CONSISTENT",
        ]
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: entrySymbol)
        }
        return symbol
    }

    func setAtomicEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    func registerAtomicTypeAlias(
        aliasName: String,
        aliasPackageFQName: [InternedString],
        targetName: String,
        targetPackageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem,
        typeParameterNames: [String] = []
    ) {
        let aliasInterned = interner.intern(aliasName)
        let aliasFQName = aliasPackageFQName + [aliasInterned]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        let targetInterned = interner.intern(targetName)
        let targetFQName = targetPackageFQName + [targetInterned]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else { return }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: aliasInterned,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let underlyingArgs: [TypeArg]
        if typeParameterNames.isEmpty {
            underlyingArgs = []
        } else {
            let typeParamSymbols = typeParameterNames.map { paramName in
                let internedParam = interner.intern(paramName)
                let typeParamFQName = aliasFQName + [internedParam]
                return symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
                    kind: .typeParameter,
                    name: internedParam,
                    fqName: typeParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            symbols.setTypeAliasTypeParameters(typeParamSymbols, for: aliasSymbol)
            underlyingArgs = typeParamSymbols.map { typeParamSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable))))
            }
        }
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: underlyingArgs,
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }
}
