import Foundation

extension CallTypeChecker {
    func comparisonSpecialCallKind(
        for calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> StdlibSpecialCallKind? {
        if locals[calleeName] != nil {
            return nil
        }
        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard !visibleCandidates.isEmpty else {
            return nil
        }
        let expectedPrefix = [ctx.interner.intern("kotlin"), ctx.interner.intern("comparisons")]
        let onlySyntheticComparisonCandidates = visibleCandidates.allSatisfy { symbolID in
            guard let symbol = ctx.sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.flags.contains(.synthetic)
                && symbol.fqName.count >= expectedPrefix.count
                && Array(symbol.fqName.prefix(expectedPrefix.count)) == expectedPrefix
        }
        guard onlySyntheticComparisonCandidates else {
            return nil
        }
        return switch ctx.interner.resolve(calleeName) {
        case "maxOf": .maxOfInt
        case "minOf": .minOfInt
        default: nil
        }
    }
}
