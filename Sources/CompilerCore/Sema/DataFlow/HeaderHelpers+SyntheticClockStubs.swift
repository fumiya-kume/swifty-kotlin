/// Residual compiler/runtime support for kotlin.time.Clock (STDLIB-TIME-086).
///
/// `Clock` and the public `Clock.System.now()` API are source-backed. This
/// residual file retains only the interface shell and the nested object anchor
/// required by source loading. `Clock` is user-implementable, so `now()` must
/// remain an interface member for virtual dispatch to work.
///
/// `Clock.System` is created as a nested object so that the bundled Kotlin
/// source extension `Clock.System.now()` in Stdlib/kotlin/time/Clock.kt can
/// resolve. The Clock.System.now() factory itself is implemented in Kotlin
/// source and delegates to `kk_clock_system_now` via a `@KsSymbolName`
/// external declaration.
///
/// kotlin.time.Instant itself is registered by
/// HeaderHelpers+SyntheticInstantStubs.swift; this file only re-resolves the
/// existing Instant symbol to use as the return type of Clock.now().
extension DataFlowSemaPhase {
    func registerSyntheticClockStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Instant class (registered by registerSyntheticInstantStubs)

        _ = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        // MARK: - Clock interface

        let clockSymbol = ensureInterfaceSymbol(
            named: "Clock",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        // Clock.Companion is a public namespace object in the Kotlin API.
        _ = ensureClockCompanionSymbol(
            ownerSymbol: clockSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Clock.System nested object ---
        // Created so the bundled Kotlin-source extension Clock.System.now()
        // in Stdlib/kotlin/time/Clock.kt can resolve.
        _ = ensureClockNestedObject(
            named: "System",
            ownerSymbol: clockSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("Clock")],
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    /// Creates the public namespace object `Clock.Companion`.
    private func ensureClockCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        if let importedCompanion = symbols.lookupAll(fqName: companionFQName)
            .compactMap({ symbols.symbol($0) })
            .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })
        {
            symbols.setParentSymbol(ownerSymbol, for: importedCompanion.id)
            symbols.setCompanionObjectSymbol(importedCompanion.id, for: ownerSymbol)
            return companionFQName
        }
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    /// Creates a nested object (e.g. Clock.System) under an existing class symbol.
    /// Returns the FQ name of the newly created (or existing) object.
    private func ensureClockNestedObject(
        named objectName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(objectName)
        let fqName = ownerFQName + [interned]
        let objectSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName), symbols.symbol(existing) != nil {
            objectSymbol = existing
        } else {
            objectSymbol = symbols.define(
                kind: .object,
                name: interned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: objectSymbol)
        symbols.setDirectSupertypes([ownerSymbol], for: objectSymbol)
        types.setNominalDirectSupertypes([ownerSymbol], for: objectSymbol)
        return fqName
    }

}
