import Foundation

// MPP-001: Validate expect/actual declarations.
// In Kotlin MPP, an `expect` declaration in common code must be implemented by a
// corresponding `actual` declaration for the current compilation target.

extension DataFlowSemaPhase {
    func validateExpectActualMatching(
        ast: ASTModule,
        symbols: SymbolTable,
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

            guard let actualSym = candidates.first,
                  areExpectActualCompatible(expect: expectSym, actual: actualSym, symbols: symbols)
            else {
                let rendered = expectSym.fqName
                    .map { interner.resolve($0) }
                    .joined(separator: ".")
                diagnostics.error(
                    "KSWIFTK-MPP-UNRESOLVED",
                    "Missing matching 'actual' declaration for expect symbol '\(rendered)'.",
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
        symbols: SymbolTable
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

        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias, .package, .typeParameter:
            // For now, treat same-kind/same-fqName as compatible for nominal/typealias.
            return true

        case .backingField, .valueParameter, .local, .label:
            // These symbol kinds are not meaningful as expect/actual declarations.
            return false
        }
    }
}
