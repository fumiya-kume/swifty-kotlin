import Foundation

/// Synthetic stubs for kotlin.io enum types.
///
/// Covers:
/// - STDLIB-IO-TYPE-007: `kotlin.io.OnErrorAction` enum
///
/// `OnErrorAction` is used as the return type of the error-handler lambda
/// passed to `File.copyRecursively`. The enum has two entries:
/// - `SKIP`      — skip the problematic file and continue the copy
/// - `TERMINATE` — stop the copy and return `false`
///
/// The enum is registered as a synthetic `enumClass` in the `kotlin.io` package
/// so that source such as `OnErrorAction.SKIP` resolves through the standard
/// `resolveClassNameMemberValue` path.
///
/// This stub must run after `registerSyntheticFileIOStubs` (which defines the
/// `kotlin.io` package and `java.io.File`).
extension DataFlowSemaPhase {
    func registerSyntheticKotlinIOEnumStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-TYPE-007: OnErrorAction enum
        let onErrorActionSymbol = ensureOnErrorActionEnumClass(
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        let onErrorActionType = types.make(.classType(ClassType(
            classSymbol: onErrorActionSymbol, args: [], nullability: .nonNull
        )))
        setOnErrorActionEntryTypes(
            enumSymbol: onErrorActionSymbol,
            enumType: onErrorActionType,
            symbols: symbols
        )
    }

    // MARK: - STDLIB-IO-TYPE-007: OnErrorAction enum

    private func ensureOnErrorActionEnumClass(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("OnErrorAction")
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

        // Register enum entries: SKIP and TERMINATE
        let entries = ["SKIP", "TERMINATE"]
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

    /// Set propertyType on each enum entry so that resolveClassNameMemberValue
    /// (which checks `.field` + propertyType) can resolve `OnErrorAction.SKIP` etc.
    private func setOnErrorActionEntryTypes(
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
}
