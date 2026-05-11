/// Returns the existing symbol for `pkg.name` if one was already registered,
/// otherwise defines a fresh synthetic `kind: .object` symbol there and
/// returns it.
///
/// Previously copy-pasted as a `private` method in
/// `HeaderHelpers+SyntheticStringStubs.swift`,
/// `HeaderHelpers+SyntheticRandomStubs.swift`,
/// `HeaderHelpers+SyntheticCoroutineStubs.swift`, and
/// `HeaderHelpers+SyntheticTODOAndIOStubs.swift` (the last two using the
/// shorter `ensureObjectSymbol` name). Centralized here so future edits land
/// in a single place.
func ensureSyntheticObjectSymbol(
    named name: String,
    in pkg: [InternedString],
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID {
    let internedName = interner.intern(name)
    let fqName = pkg + [internedName]
    if let existing = symbols.lookup(fqName: fqName) {
        return existing
    }
    return symbols.define(
        kind: .object,
        name: internedName,
        fqName: fqName,
        declSite: nil,
        visibility: .public,
        flags: [.synthetic]
    )
}
