import Foundation

// CLASS-004: Diamond override validation — when a class implements multiple interfaces
// that both provide a default method with the same name, the class must override it.
extension DataFlowSemaPhase {
    func validateDiamondOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateDiamondOverridesForDecl(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func validateDiamondOverridesForDecl(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID),
              let symbolInfo = symbols.symbol(symbol)
        else {
            return
        }

        recurseDiamondValidation(
            decl: decl, ast: ast, symbols: symbols,
            bindings: bindings, diagnostics: diagnostics, interner: interner
        )

        guard symbolInfo.kind == .class || symbolInfo.kind == .object else {
            return
        }

        let conflicts = collectDiamondConflicts(for: symbol, symbols: symbols)
        guard !conflicts.isEmpty else { return }

        let overriddenNames = collectOverriddenMemberNames(
            for: symbol, decl: decl, ast: ast, symbols: symbols
        )

        emitDiamondDiagnostics(
            conflicts: conflicts,
            overriddenNames: overriddenNames,
            symbolInfo: symbolInfo,
            decl: decl,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func recurseDiamondValidation(
        decl: Decl,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let nestedIDs: [DeclID]
        switch decl {
        case let .classDecl(classDecl): nestedIDs = classDecl.nestedClasses
        case let .interfaceDecl(ifaceDecl): nestedIDs = ifaceDecl.nestedClasses
        case let .objectDecl(objectDecl): nestedIDs = objectDecl.nestedClasses
        default: return
        }
        for nestedDeclID in nestedIDs {
            validateDiamondOverridesForDecl(
                declID: nestedDeclID, ast: ast, symbols: symbols,
                bindings: bindings, diagnostics: diagnostics, interner: interner
            )
        }
    }

    /// Collects conflicting default method names across direct interface supertypes.
    /// Returns a map from method name to the list of interface symbols that provide a default.
    private func collectDiamondConflicts(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> [InternedString: [SymbolID]] {
        let directSupertypes = symbols.directSupertypes(for: symbol)
        let interfaceSupertypes = directSupertypes.filter {
            symbols.symbol($0)?.kind == .interface
        }
        guard interfaceSupertypes.count >= 2 else { return [:] }

        var providers: [InternedString: [SymbolID]] = [:]
        for interfaceID in interfaceSupertypes {
            guard let ifaceSym = symbols.symbol(interfaceID) else { continue }
            for childID in symbols.children(ofFQName: ifaceSym.fqName) {
                guard let childSym = symbols.symbol(childID),
                      childSym.kind == .function,
                      !childSym.flags.contains(.abstractType)
                else { continue }
                providers[childSym.name, default: []].append(interfaceID)
            }
        }
        return providers.filter { $0.value.count >= 2 }
    }

    // swiftlint:disable:next function_parameter_count
    private func emitDiamondDiagnostics(
        conflicts: [InternedString: [SymbolID]],
        overriddenNames: Set<InternedString>,
        symbolInfo: SemanticSymbol,
        decl: Decl,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let declRange = extractDeclRange(decl)
        let className = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
        for (methodName, providerIDs) in conflicts where !overriddenNames.contains(methodName) {
            let memberName = interner.resolve(methodName)
            let ifaceNames = providerIDs.compactMap { symbols.symbol($0) }
                .map { $0.fqName.map { interner.resolve($0) }.joined(separator: ".") }
                .joined(separator: ", ")
            diagnostics.error(
                "KSWIFTK-SEMA-DIAMOND",
                "Class '\(className)' must override '\(memberName)' because it is inherited from multiple interfaces: \(ifaceNames).",
                range: declRange
            )
        }
    }

    private func extractDeclRange(_ decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(classDecl): classDecl.range
        case let .objectDecl(objectDecl): objectDecl.range
        default: nil
        }
    }
}
