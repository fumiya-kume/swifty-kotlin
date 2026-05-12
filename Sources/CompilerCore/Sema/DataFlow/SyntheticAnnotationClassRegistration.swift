/// Registers a synthetic `kind: .annotationClass` symbol under `packageFQName`
/// if one is not already present. Either way the resulting symbol's parent is
/// set to `packageSymbol` when valid, so the caller can use the same helper to
/// re-anchor an existing annotation class that was registered without a parent
/// (this matters when a stub registration runs after a partial load).
///
/// Previously copy-pasted as a `private` method in
/// `HeaderHelpers+SyntheticMetaprogStubs.swift` and
/// `HeaderHelpers+SyntheticTestStubs.swift`. Centralized here so future edits
/// land in a single place.
func registerSyntheticAnnotationClass(
    named name: String,
    packageFQName: [InternedString],
    packageSymbol: SymbolID,
    symbols: SymbolTable,
    interner: StringInterner
) {
    let className = interner.intern(name)
    let classFQName = packageFQName + [className]
    let classSymbol: SymbolID
    if let existing = symbols.lookup(fqName: classFQName) {
        classSymbol = existing
    } else {
        classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }
    if packageSymbol != .invalid {
        symbols.setParentSymbol(packageSymbol, for: classSymbol)
    }
}
