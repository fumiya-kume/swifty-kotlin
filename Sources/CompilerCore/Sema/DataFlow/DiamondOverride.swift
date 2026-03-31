import Foundation

// CLASS-004: Diamond override validation — when a class implements multiple interfaces
// that both provide a default method with the same name, the class must override it.
extension DataFlowSemaPhase {
    private struct DiamondDispatchKey: Hashable {
        let name: InternedString
        let parameterTypes: [TypeID]
        let isSuspend: Bool
    }

    private struct DiamondImplementation {
        let implementationID: SymbolID
        let directInterfaceID: SymbolID
        let inheritanceDepth: Int
    }

    private struct DiamondConflict {
        let key: DiamondDispatchKey
        let providerIDs: [SymbolID]
    }

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

        let overriddenKeys = collectDiamondOverrideKeys(
            for: decl,
            ast: ast,
            symbols: symbols,
            bindings: bindings
        )

        emitDiamondDiagnostics(
            conflicts: conflicts,
            overriddenKeys: overriddenKeys,
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
    ) -> [DiamondConflict] {
        let directSupertypes = symbols.directSupertypes(for: symbol)
        let interfaceSupertypes = directSupertypes
            .filter { symbols.symbol($0)?.kind == .interface }
            .sorted(by: { $0.rawValue < $1.rawValue })

        guard interfaceSupertypes.count >= 2 else { return [] }

        let concreteSuperclassKeys = collectConcreteSuperclassDispatchKeys(
            for: symbol,
            symbols: symbols
        )

        var mostSpecificImpls: [DiamondDispatchKey: [DiamondImplementation]] = [:]

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

                    let key = makeDiamondDispatchKey(for: childID, symbols: symbols)
                    mostSpecificImpls[key, default: []].append(DiamondImplementation(
                        implementationID: childID,
                        directInterfaceID: directInterfaceID,
                        inheritanceDepth: depth
                    ))
                }

                let parentInterfaces = symbols.directSupertypes(for: currentInterfaceID)
                    .filter { symbols.symbol($0)?.kind == .interface }
                    .sorted(by: { $0.rawValue < $1.rawValue })

                queue.append(contentsOf: parentInterfaces.map { ($0, depth + 1) })
            }
        }

        var conflicts: [DiamondConflict] = []
        for (key, implementations) in mostSpecificImpls {
            guard !concreteSuperclassKeys.contains(key) else {
                continue
            }

            // Find the most specific implementations (minimum inheritance depth).
            // Depth 0 means the direct interface provides the implementation,
            // which is more specific than defaults inherited from ancestors.
            let minDepth = implementations.map(\.inheritanceDepth).min() ?? 0
            let mostSpecific = implementations.filter { $0.inheritanceDepth == minDepth }

            // Group by implementation symbol to identify identical implementations
            var implGroups: [SymbolID: Set<SymbolID>] = [:]
            for implementation in mostSpecific {
                implGroups[implementation.implementationID, default: []].insert(implementation.directInterfaceID)
            }

            // Conflict exists only if there are multiple different implementations
            // provided by different direct interfaces
            if implGroups.count > 1 {
                let conflictingInterfaces = implGroups.values.reduce(into: Set<SymbolID>()) { acc, interfaces in
                    acc.formUnion(interfaces)
                }
                if conflictingInterfaces.count >= 2 {
                    conflicts.append(DiamondConflict(
                        key: key,
                        providerIDs: conflictingInterfaces.sorted(by: { $0.rawValue < $1.rawValue })
                    ))
                }
            }
        }

        return conflicts.sorted {
            if $0.key.name != $1.key.name {
                return $0.key.name.rawValue < $1.key.name.rawValue
            }
            if $0.key.parameterTypes.count != $1.key.parameterTypes.count {
                return $0.key.parameterTypes.count < $1.key.parameterTypes.count
            }
            return $0.providerIDs.lexicographicallyPrecedes($1.providerIDs, by: { $0.rawValue < $1.rawValue })
        }
    }

    private func emitDiamondDiagnostics(
        conflicts: [DiamondConflict],
        overriddenKeys: Set<DiamondDispatchKey>,
        symbolInfo: SemanticSymbol,
        decl: Decl,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let declRange = extractDeclRange(decl)
        let className = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
        for conflict in conflicts {
            guard !overriddenKeys.contains(conflict.key) else {
                continue
            }
            let memberName = interner.resolve(conflict.key.name)
            let ifaceNames = conflict.providerIDs.compactMap { symbols.symbol($0) }
                .map { $0.fqName.map { interner.resolve($0) }.joined(separator: ".") }
                .joined(separator: ", ")
            let msg = "Class '\(className)' must override '\(memberName)' "
                + "because it is inherited from multiple interfaces: \(ifaceNames)."
            diagnostics.error("KSWIFTK-SEMA-0171", msg, range: declRange)
        }
    }

    private func collectDiamondOverrideKeys(
        for decl: Decl,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable
    ) -> Set<DiamondDispatchKey> {
        var overriddenKeys: Set<DiamondDispatchKey> = []

        let memberFunctions: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
        default:
            return overriddenKeys
        }

        for memberDeclID in memberFunctions {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .funDecl(funDecl) = memberDecl,
                  funDecl.modifiers.contains(.override),
                  let memberSymbol = bindings.declSymbols[memberDeclID]
            else {
                continue
            }
            overriddenKeys.insert(makeDiamondDispatchKey(for: memberSymbol, symbols: symbols))
        }

        return overriddenKeys
    }

    private func collectConcreteSuperclassDispatchKeys(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> Set<DiamondDispatchKey> {
        var keys: Set<DiamondDispatchKey> = []
        var visited: Set<SymbolID> = [symbol]
        var queue = symbols.directSupertypes(for: symbol)
            .filter {
                guard let superSym = symbols.symbol($0) else { return false }
                return superSym.kind == .class || superSym.kind == .enumClass || superSym.kind == .object
            }

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted,
                  let currentSym = symbols.symbol(current)
            else {
                continue
            }

            for childID in symbols.children(ofFQName: currentSym.fqName) {
                guard let childSym = symbols.symbol(childID),
                      childSym.kind == .function,
                      !childSym.flags.contains(.abstractType)
                else {
                    continue
                }
                keys.insert(makeDiamondDispatchKey(for: childID, symbols: symbols))
            }

            let nextSuperclasses = symbols.directSupertypes(for: current).filter {
                guard let superSym = symbols.symbol($0) else { return false }
                return superSym.kind == .class || superSym.kind == .enumClass || superSym.kind == .object
            }
            queue.append(contentsOf: nextSuperclasses)
        }

        return keys
    }

    private func makeDiamondDispatchKey(
        for methodSymbol: SymbolID,
        symbols: SymbolTable
    ) -> DiamondDispatchKey {
        let methodName = symbols.symbol(methodSymbol)?.name ?? InternedString(rawValue: -1)
        let signature = symbols.functionSignature(for: methodSymbol)
        return DiamondDispatchKey(
            name: methodName,
            parameterTypes: signature?.parameterTypes ?? [],
            isSuspend: signature?.isSuspend ?? false
        )
    }

    private func extractDeclRange(_ decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(classDecl): classDecl.range
        case let .objectDecl(objectDecl): objectDecl.range
        default: nil
        }
    }
}
