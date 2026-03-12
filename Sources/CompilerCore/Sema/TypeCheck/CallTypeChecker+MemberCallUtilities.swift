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
                 "kk_set_contains", "kk_map_get", "kk_map_contains_key":
                return true
            default:
                break
            }
        }

        guard let symbol = sema.symbols.symbol(candidate) else { return false }
        let memberName = interner.resolve(symbol.name)
        let ownerFQName = symbol.fqName.dropLast().map(interner.resolve)
        switch (ownerFQName, memberName) {
        case (["kotlin", "collections", "List"], "contains"),
             (["kotlin", "collections", "List"], "indexOf"),
             (["kotlin", "collections", "List"], "lastIndexOf"),
             (["kotlin", "collections", "List"], "isEmpty"),
             (["kotlin", "collections", "Set"], "contains"),
             (["kotlin", "collections", "Set"], "isEmpty"),
             (["kotlin", "collections", "Collection"], "contains"),
             (["kotlin", "collections", "Collection"], "isEmpty"),
             (["kotlin", "collections", "Map"], "get"),
             (["kotlin", "collections", "Map"], "containsKey"):
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
