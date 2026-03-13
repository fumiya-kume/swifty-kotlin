import Foundation

extension CallTypeChecker {
    func allowsProjectedReceiverUnsafeVariance(
        _ candidate: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if let externalLinkName = sema.symbols.externalLinkName(for: candidate) {
            switch externalLinkName {
            case "kk_list_contains", "kk_list_indexOf", "kk_list_lastIndexOf",
                 "kk_list_onEach", "kk_list_onEachIndexed",
                 "kk_list_maxByOrNull", "kk_list_minByOrNull",
                 "kk_list_maxOfOrNull", "kk_list_minOfOrNull",
                 "kk_set_contains", "kk_set_intersect", "kk_set_union", "kk_set_subtract",
                 "kk_map_get", "kk_map_contains_key":
                return true
            default:
                break
            }
        }

        guard let symbol = sema.symbols.symbol(candidate) else { return false }
        let knownNames = KnownCompilerNames(interner: interner)
        let ownerFQName = Array(symbol.fqName.dropLast())
        switch (ownerFQName, symbol.name) {
        case (knownNames.kotlinCollectionsListFQName, interner.intern("contains")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("indexOf")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("lastIndexOf")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("onEach")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("onEachIndexed")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("maxByOrNull")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("minByOrNull")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("maxOfOrNull")),
             (knownNames.kotlinCollectionsListFQName, interner.intern("minOfOrNull")),
             (knownNames.kotlinCollectionsListFQName, knownNames.isEmpty),
             (knownNames.kotlinCollectionsSetFQName, interner.intern("contains")),
             (knownNames.kotlinCollectionsSetFQName, interner.intern("intersect")),
             (knownNames.kotlinCollectionsSetFQName, interner.intern("union")),
             (knownNames.kotlinCollectionsSetFQName, interner.intern("subtract")),
             (knownNames.kotlinCollectionsSetFQName, knownNames.isEmpty),
             (knownNames.kotlinCollectionsCollectionFQName, interner.intern("contains")),
             (knownNames.kotlinCollectionsCollectionFQName, knownNames.isEmpty),
             (knownNames.kotlinCollectionsMapFQName, interner.intern("get")),
             (knownNames.kotlinCollectionsMapFQName, interner.intern("containsKey")):
            return true
        default:
            return false
        }
    }

    func makeProjectionViolationDiagnostic(
        candidates: [SymbolID],
        receiverType: TypeID,
        calleeName: InternedString,
        range: SourceRange,
        sema: SemaModule,
        interner: StringInterner
    ) -> Diagnostic? {
        var firstViolatedParamType: TypeID?
        var hasProjectionCompatibleCandidate = false

        for candidate in candidates {
            if allowsProjectedReceiverUnsafeVariance(candidate, sema: sema, interner: interner) {
                hasProjectionCompatibleCandidate = true
                continue
            }
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
                      receiverType: receiverType,
                      signature: signature,
                      symbols: sema.symbols
                  )
            else {
                continue
            }

            if let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                signature: signature,
                writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
            ) {
                if firstViolatedParamType == nil {
                    firstViolatedParamType = signature.parameterTypes[violatingParamIndex]
                }
            } else {
                hasProjectionCompatibleCandidate = true
            }
        }

        guard !hasProjectionCompatibleCandidate,
              let violatingParamType = firstViolatedParamType
        else {
            return nil
        }

        let renderedParamType = sema.types.renderType(violatingParamType)
        return Diagnostic(
            severity: .error,
            code: "KSWIFTK-SEMA-VAR-OUT",
            message: "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))'"
                + " because the type parameter appears in an 'in' position (parameter type '\(renderedParamType)').",
            primaryRange: range,
            secondaryRanges: []
        )
    }
}
