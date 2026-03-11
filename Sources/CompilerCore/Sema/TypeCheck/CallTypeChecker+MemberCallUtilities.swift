import Foundation

extension CallTypeChecker {
    func allowsProjectedReceiverUnsafeVariance(
        _ candidate: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if let externalLinkName = sema.symbols.externalLinkName(for: candidate) {
            switch externalLinkName {
            case "kk_set_contains", "kk_map_get", "kk_map_containsKey":
                return true
            default:
                break
            }
        }

        guard let symbol = sema.symbols.symbol(candidate) else { return false }
        let ownerName = symbol.fqName.dropLast().last.map(interner.resolve) ?? ""
        let memberName = interner.resolve(symbol.name)
        return (ownerName == "Set" && memberName == "contains")
            || (ownerName == "Map" && (memberName == "get" || memberName == "containsKey"))
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
