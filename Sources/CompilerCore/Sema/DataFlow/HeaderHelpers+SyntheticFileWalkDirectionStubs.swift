import Foundation

/// Synthetic stub for kotlin.io.FileWalkDirection (STDLIB-IO-TYPE-005).
///
/// `FileWalkDirection` is a Kotlin stdlib enum in the `kotlin.io` package
/// with two entries:
/// - `TOP_DOWN` – directories are visited before their contents (default)
/// - `BOTTOM_UP` – directories are visited after their contents
///
/// This stub registers the enum class and its entries in the symbol table so
/// that name resolution and type checking succeed for code that references
/// `FileWalkDirection.TOP_DOWN` / `FileWalkDirection.BOTTOM_UP` or declares
/// a parameter of type `FileWalkDirection`.
///
/// Registration runs after `registerSyntheticFileIOStubs` (which ensures the
/// `kotlin.io` package exists) so the parent link can always be resolved.
extension DataFlowSemaPhase {
    func registerSyntheticFileWalkDirectionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )

        let enumSymbol = ensureFileWalkDirectionEnumClass(
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(enumType, for: enumSymbol)

        setFileWalkDirectionEntryTypes(
            enumSymbol: enumSymbol,
            enumType: enumType,
            symbols: symbols
        )
    }

    // MARK: - Private helpers

    private func ensureFileWalkDirectionEnumClass(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("FileWalkDirection")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: enumSymbol)
        }

        // Register enum entries: TOP_DOWN and BOTTOM_UP
        for entry in ["TOP_DOWN", "BOTTOM_UP"] {
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
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    /// Set propertyType on each enum entry so that resolveClassNameMemberValue
    /// (which checks `.field` + propertyType) can resolve
    /// `FileWalkDirection.TOP_DOWN` / `FileWalkDirection.BOTTOM_UP`.
    private func setFileWalkDirectionEntryTypes(
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
