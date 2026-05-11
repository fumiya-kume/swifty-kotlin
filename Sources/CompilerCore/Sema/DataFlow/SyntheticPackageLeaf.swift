import Foundation

/// Look up the package symbol for `fqName`, defining a synthetic leaf
/// entry if it doesn't yet exist. Unlike `ensureSyntheticPackageHierarchy`,
/// this does not walk the path — it expects every ancestor segment to
/// already be registered (e.g. via a prior call for the parent package).
///
/// Returns `.invalid` if `fqName` is empty.
func ensureSyntheticPackage(
    fqName: [InternedString],
    symbols: SymbolTable
) -> SymbolID {
    if let existing = symbols.lookup(fqName: fqName) {
        return existing
    }
    guard let name = fqName.last else {
        return .invalid
    }
    return symbols.define(
        kind: .package,
        name: name,
        fqName: fqName,
        declSite: nil,
        visibility: .public,
        flags: [.synthetic]
    )
}
