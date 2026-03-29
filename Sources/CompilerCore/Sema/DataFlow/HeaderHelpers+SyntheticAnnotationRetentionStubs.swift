/// Synthetic stdlib stubs for kotlin.annotation.AnnotationRetention and @Retention.
///
/// Covers:
/// - STDLIB-ANNO-114: `AnnotationRetention` enum (SOURCE, BINARY, RUNTIME)
/// - STDLIB-ANNO-114: `@Retention(AnnotationRetention)` annotation class
///
/// These stubs register the kotlin.annotation package, the AnnotationRetention enum
/// with its three entries, and the Retention annotation class so that
/// `@Retention(AnnotationRetention.RUNTIME)` (and similar) compiles without errors.
extension DataFlowSemaPhase {
    func registerSyntheticAnnotationRetentionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure kotlin.annotation package hierarchy
        let kotlinAnnotationPkg = ensurePackage(
            path: ["kotlin", "annotation"],
            symbols: symbols,
            interner: interner
        )

        // --- AnnotationRetention enum class ---
        let retentionEnumSymbol = ensureAnnotationRetentionEnumClass(
            in: kotlinAnnotationPkg,
            symbols: symbols,
            interner: interner
        )

        let retentionEnumType = types.make(.classType(ClassType(
            classSymbol: retentionEnumSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Set propertyType on each entry so member access resolves correctly.
        setAnnotationRetentionEntryTypes(
            enumSymbol: retentionEnumSymbol,
            enumType: retentionEnumType,
            symbols: symbols
        )

        // --- @Retention annotation class ---
        ensureRetentionAnnotationClass(
            in: kotlinAnnotationPkg,
            retentionEnumType: retentionEnumType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - AnnotationRetention enum

    private func ensureAnnotationRetentionEnumClass(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("AnnotationRetention")
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

        // Register enum entries: SOURCE, BINARY, RUNTIME
        for entry in ["SOURCE", "BINARY", "RUNTIME"] {
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

    private func setAnnotationRetentionEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else { continue }
            symbols.setPropertyType(enumType, for: child)
        }
    }

    // MARK: - @Retention annotation class

    private func ensureRetentionAnnotationClass(
        in pkg: [InternedString],
        retentionEnumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let name = interner.intern("Retention")
        let fqName = pkg + [name]
        if symbols.lookup(fqName: fqName) != nil {
            return
        }
        let retentionSymbol = symbols.define(
            kind: .annotationClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: retentionSymbol)
        }

        // Register the primary constructor parameter `value: AnnotationRetention`
        let ctorFQName = fqName + [interner.intern("<init>")]
        if symbols.lookup(fqName: ctorFQName) == nil {
            let ctorSymbol = symbols.define(
                kind: .constructor,
                name: interner.intern("<init>"),
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(retentionSymbol, for: ctorSymbol)

            let paramName = interner.intern("value")
            let paramFQName = ctorFQName + [paramName]
            if symbols.lookup(fqName: paramFQName) == nil {
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: paramFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
                symbols.setPropertyType(retentionEnumType, for: paramSymbol)
            }
        }

        // Register `value` property on the annotation class
        let valuePropName = interner.intern("value")
        let valuePropFQName = fqName + [valuePropName]
        if symbols.lookup(fqName: valuePropFQName) == nil {
            let propSymbol = symbols.define(
                kind: .property,
                name: valuePropName,
                fqName: valuePropFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(retentionSymbol, for: propSymbol)
            symbols.setPropertyType(retentionEnumType, for: propSymbol)
        }
    }
}
