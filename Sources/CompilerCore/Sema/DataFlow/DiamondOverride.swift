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
    /// This considers transitive interface inheritance and follows Kotlin's rules:
    /// 1. Only the most specific implementation (deepest override) for each method name
    /// 2. Conflicts occur only when multiple most specific implementations exist
    /// 3. Methods inherited from a common ancestor don't conflict if not overridden
    ///
    /// Returns methodName -> [conflictingInterfaceIDs] for actual conflicts only.
    private func collectDiamondConflicts(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> [InternedString: [SymbolID]] {
        let directSupertypes = symbols.directSupertypes(for: symbol)
        let interfaceSupertypes = directSupertypes
            .filter { symbols.symbol($0)?.kind == .interface }
            .sorted(by: { $0.rawValue < $1.rawValue })

        guard interfaceSupertypes.count >= 2 else { return [:] }

        // methodName -> (implementationSymbolID, providingInterfaceID, inheritanceDepth)
        var mostSpecificImpls: [InternedString: [(SymbolID, SymbolID, Int)]] = [:]

        for directInterfaceID in interfaceSupertypes {
            var visited: Set<SymbolID> = []
            var queue: [(SymbolID, Int)] = [(directInterfaceID, 0)]

            while !queue.isEmpty {
                let (currentInterfaceID, depth) = queue.removeFirst()
                guard visited.insert(currentInterfaceID).inserted else { continue }
                guard let ifaceSym = symbols.symbol(currentInterfaceID) else { continue }

                for childID in symbols.children(ofFQName: ifaceSym.fqName) {
                    guard let childSym = symbols.symbol(childID),
                          childSym.kind == .function,
                          !childSym.flags.contains(.abstractType)
                    else { continue }

                    let methodName = childSym.name
                    // Record this implementation with its inheritance depth
                    mostSpecificImpls[methodName, default: []].append((childID, directInterfaceID, depth))
                }

                let parentInterfaces = symbols.directSupertypes(for: currentInterfaceID)
                    .filter { symbols.symbol($0)?.kind == .interface }
                    .sorted(by: { $0.rawValue < $1.rawValue })

                queue.append(contentsOf: parentInterfaces.map { ($0, depth + 1) })
            }
        }

        var conflicts: [InternedString: Set<SymbolID>] = [:]
        for (methodName, implementations) in mostSpecificImpls {
            // Find the most specific implementations (maximum depth)
            let maxDepth = implementations.map { $0.2 }.max() ?? 0
            let mostSpecific = implementations.filter { $0.2 == maxDepth }
            
            // Group by implementation symbol to identify identical implementations
            var implGroups: [SymbolID: Set<SymbolID>] = [:]
            for (implSymbol, directInterface, _) in mostSpecific {
                implGroups[implSymbol, default: []].insert(directInterface)
            }
            
            // Conflict exists only if there are multiple different implementations
            // provided by different direct interfaces
            if implGroups.count > 1 {
                let conflictingInterfaces = implGroups.values.reduce(into: Set<SymbolID>()) { acc, interfaces in
                    acc.formUnion(interfaces)
                }
                if conflictingInterfaces.count >= 2 {
                    conflicts[methodName] = conflictingInterfaces
                }
            }
        }

        return conflicts
            .mapValues { $0.sorted(by: { $0.rawValue < $1.rawValue }) }
    }

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
