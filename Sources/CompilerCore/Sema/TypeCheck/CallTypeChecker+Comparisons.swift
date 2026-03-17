import Foundation

extension CallTypeChecker {
    func comparisonSpecialCallKind(
        for calleeName: InternedString,
        argCount: Int,
        resolvedParamType: TypeID?,
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
        let resolvedName = ctx.interner.resolve(calleeName)
        let types = ctx.sema.types

        if argCount == 3 {
            let paramType = resolvedParamType ?? types.intType
            switch resolvedName {
            case "maxOf":
                if paramType == types.longType { return .maxOfLong3 }
                if paramType == types.doubleType { return .maxOfDouble3 }
                if paramType == types.floatType { return .maxOfFloat3 }
                return .maxOfInt3
            case "minOf":
                if paramType == types.longType { return .minOfLong3 }
                if paramType == types.doubleType { return .minOfDouble3 }
                if paramType == types.floatType { return .minOfFloat3 }
                return .minOfInt3
            default:
                return nil
            }
        }

        // 2-arg overloads
        let paramType = resolvedParamType ?? types.intType
        switch resolvedName {
        case "maxOf":
            if paramType == types.longType { return .maxOfLong }
            if paramType == types.doubleType { return .maxOfDouble }
            if paramType == types.floatType { return .maxOfFloat }
            return .maxOfInt
        case "minOf":
            if paramType == types.longType { return .minOfLong }
            if paramType == types.doubleType { return .minOfDouble }
            if paramType == types.floatType { return .minOfFloat }
            return .minOfInt
        default:
            return nil
        }
    }
}
