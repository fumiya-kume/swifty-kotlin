/// Walks the given fully-qualified package path and registers a synthetic
/// `kind: .package` symbol for every prefix that does not already exist.
/// Returns the input path unchanged for callers that chain into further
/// definitions.
///
/// Previously copy-pasted as a `private` method in
/// `HeaderHelpers+SyntheticFunctionTypeStubs.swift`,
/// `HeaderHelpers+SyntheticTestStubs.swift`, and
/// `HeaderHelpers+SyntheticTODOAndIOStubs.swift`. Centralized here so future
/// edits land in a single place.
func ensureSyntheticPackageHierarchy(
    fqName path: [InternedString],
    symbols: SymbolTable
) -> [InternedString] {
    guard !path.isEmpty else { return path }
    var fqName: [InternedString] = []
    for part in path {
        fqName.append(part)
        if symbols.lookup(fqName: fqName) == nil {
            _ = symbols.define(
                kind: .package,
                name: part,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
    }
    return fqName
}
