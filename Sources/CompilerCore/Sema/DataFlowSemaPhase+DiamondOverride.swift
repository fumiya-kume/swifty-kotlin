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

        guard symbolInfo.kind == .class || symbolInfo.kind == .object,
              !symbolInfo.flags.contains(.abstractType)
        else {
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
    ///
    /// This considers transitive interface inheritance: if a direct interface supertype inherits
    /// a default method from a parent interface, it still counts as providing that default.
    ///
    /// To avoid false positives (e.g. two direct supertypes inheriting the same default method
    /// from a common ancestor), we group by the *implementation symbol* (the function symbol ID)
    /// rather than only the direct interface ID.
    private func collectDiamondConflicts(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> [InternedString: [SymbolID]] {
        let directSupertypes = symbols.directSupertypes(for: symbol)
        let interfaceSupertypes = directSupertypes
            .filter { symbols.symbol($0)?.kind == .interface }
            .sorted(by: { $0.rawValue < $1.rawValue })

        guard interfaceSupertypes.count >= 2 else { return [:] }

        // methodName -> implFunctionSymbolID -> providingDirectInterfaceIDs
        var providersByName: [InternedString: [SymbolID: Set<SymbolID>]] = [:]

        for directInterfaceID in interfaceSupertypes {
            var visited: Set<SymbolID> = []
            var queue: [SymbolID] = [directInterfaceID]

            while !queue.isEmpty {
                let currentInterfaceID = queue.removeFirst()
                guard visited.insert(currentInterfaceID).inserted else { continue }
                guard let ifaceSym = symbols.symbol(currentInterfaceID) else { continue }

                for childID in symbols.children(ofFQName: ifaceSym.fqName) {
                    guard let childSym = symbols.symbol(childID),
                          childSym.kind == .function,
                          !childSym.flags.contains(.abstractType)
                    else { continue }

                    providersByName[childSym.name, default: [:]][childID, default: []]
                        .insert(directInterfaceID)
                }

                let parentInterfaces = symbols.directSupertypes(for: currentInterfaceID)
                    .filter { symbols.symbol($0)?.kind == .interface }
                    .sorted(by: { $0.rawValue < $1.rawValue })

                queue.append(contentsOf: parentInterfaces)
            }
        }

        var conflicts: [InternedString: Set<SymbolID>] = [:]
        for (methodName, implementations) in providersByName where implementations.keys.count >= 2 {
            let ifaceSet = implementations.values.reduce(into: Set<SymbolID>()) { acc, ids in
                acc.formUnion(ids)
            }
            guard ifaceSet.count >= 2 else { continue }
            conflicts[methodName] = ifaceSet
        }

        return conflicts
            .mapValues { $0.sorted(by: { $0.rawValue < $1.rawValue }) }
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
        for methodName in conflicts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let providerIDs = conflicts[methodName], !overriddenNames.contains(methodName) else {
                continue
            }
            let memberName = interner.resolve(methodName)
            let ifaceNames = providerIDs.compactMap { symbols.symbol($0) }
                .map { $0.fqName.map { interner.resolve($0) }.joined(separator: ".") }
                .joined(separator: ", ")
            let msg = "Class '\(className)' must override '\(memberName)' "
                + "because it is inherited from multiple interfaces: \(ifaceNames)."
            diagnostics.error("KSWIFTK-SEMA-DIAMOND", msg, range: declRange)
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
