import Foundation

// MPP-001: Validate expect/actual declarations.
// In Kotlin MPP, an `expect` declaration in common code must be implemented by a
// corresponding `actual` declaration for the current compilation target.

extension DataFlowSemaPhase {
    func validateExpectActualMatching(
        ast _: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        // Only validate source declarations; imported library symbols may contain
        // expect/actual markers without requiring local counterparts.
        let expects = symbols.allSymbols().filter { sym in
            sym.flags.contains(.expectDeclaration) && sym.declSite != nil
        }

        for expectSym in expects {
            let candidates = symbols.lookupAll(fqName: expectSym.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == expectSym.kind && $0.flags.contains(.actualDeclaration) }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })

            let compatibleCandidates = candidates.filter { actual in
                areExpectActualCompatible(expect: expectSym, actual: actual, symbols: symbols, types: types)
            }

            let rendered = expectSym.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")

            guard let actualSym = compatibleCandidates.first else {
                diagnostics.error(
                    "KSWIFTK-MPP-UNRESOLVED",
                    "Missing matching 'actual' declaration for expect symbol '\(rendered)'.",
                    range: expectSym.declSite
                )
                continue
            }

            if compatibleCandidates.count > 1 {
                diagnostics.error(
                    "KSWIFTK-MPP-AMBIGUOUS",
                    "Multiple matching 'actual' declarations found for expect symbol '\(rendered)'.",
                    range: expectSym.declSite
                )
                continue
            }

            symbols.setExpectActualLink(expect: expectSym.id, actual: actualSym.id)
        }
    }

    private func areExpectActualCompatible(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch expect.kind {
        case .function, .constructor:
            guard let expectSig = symbols.functionSignature(for: expect.id),
                  let actualSig = symbols.functionSignature(for: actual.id)
            else {
                return false
            }
            return expectSig.receiverType == actualSig.receiverType
                && expectSig.parameterTypes == actualSig.parameterTypes
                && expectSig.returnType == actualSig.returnType
                && expectSig.isSuspend == actualSig.isSuspend

        case .property, .field:
            guard let expectType = symbols.propertyType(for: expect.id),
                  let actualType = symbols.propertyType(for: actual.id)
            else {
                return false
            }
            return expectType == actualType

        case .class, .interface, .object, .enumClass, .annotationClass:
            // Check type parameter count matches
            let expectTPs = types.nominalTypeParameterSymbols(for: expect.id)
            let actualTPs = types.nominalTypeParameterSymbols(for: actual.id)
            guard expectTPs.count == actualTPs.count else { return false }
            // Check each type parameter's variance and upper bounds match
            let expectVariances = types.nominalTypeParameterVariances(for: expect.id)
            let actualVariances = types.nominalTypeParameterVariances(for: actual.id)
            for (index, (eTP, aTP)) in zip(expectTPs, actualTPs).enumerated() {
                let eVar = index < expectVariances.count ? expectVariances[index] : TypeVariance.invariant
                let aVar = index < actualVariances.count ? actualVariances[index] : TypeVariance.invariant
                guard eVar == aVar else { return false }
                guard symbols.typeParameterUpperBounds(for: eTP) == symbols.typeParameterUpperBounds(for: aTP) else {
                    return false
                }
            }
            return true

        case .typeAlias:
            // Check underlying types match
            return symbols.typeAliasUnderlyingType(for: expect.id) == symbols.typeAliasUnderlyingType(for: actual.id)

        case .package:
            return true

        case .typeParameter:
            return false

        case .backingField, .valueParameter, .local, .label:
            // These symbol kinds are not meaningful as expect/actual declarations.
            return false
        }
    }
}
