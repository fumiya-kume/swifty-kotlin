import Foundation

extension DataFlowSemaPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID)
                else {
                    continue
                }
                let superTypeRefs: [TypeRefID]
                switch decl {
                case let .classDecl(classDecl):
                    superTypeRefs = classDecl.superTypes
                case let .interfaceDecl(interfaceDecl):
                    superTypeRefs = interfaceDecl.superTypes
                case let .objectDecl(objectDecl):
                    superTypeRefs = objectDecl.superTypes
                default:
                    continue
                }

                var superSymbols: [SymbolID] = []
                for superTypeRef in superTypeRefs {
                    if let resolved = resolveNominalSymbolAndTypeArgs(
                        superTypeRef,
                        currentPackage: file.packageFQName,
                        ast: ast,
                        symbols: symbols,
                        types: types
                    ) {
                        superSymbols.append(resolved.symbol)
                        if !resolved.typeArgs.isEmpty {
                            symbols.setSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                            types.setNominalSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                        }
                    }
                }
                let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
                types.setNominalDirectSupertypes(uniqueSuperSymbols, for: symbol)
            }
        }
    }

    private struct ResolvedSupertype {
        let symbol: SymbolID
        let typeArgs: [TypeArg]
    }

    private func resolveNominalSymbolAndTypeArgs(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> ResolvedSupertype? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        let argRefs: [TypeArgRef]
        switch typeRef {
        case let .named(refPath, refs, _):
            path = refPath
            argRefs = refs
        case .functionType, .intersection:
            return nil
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1, !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id
            {
                let resolvedArgs = resolveTypeArgRefsForInheritance(
                    argRefs,
                    currentPackage: currentPackage,
                    ast: ast,
                    symbols: symbols,
                    types: types
                )
                return ResolvedSupertype(symbol: symbol, typeArgs: resolvedArgs)
            }
        }
        return nil
    }

    private func resolveTypeArgRefsForInheritance(
        _ argRefs: [TypeArgRef],
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [TypeArg] {
        // Use all-or-nothing semantics: if any type arg fails to resolve,
        // return an empty array to preserve positional integrity.
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return []
                }
                result.append(.invariant(resolved))
            case let .out(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return []
                }
                result.append(.out(resolved))
            case let .in(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return []
                }
                result.append(.in(resolved))
            case .star:
                result.append(.star)
            }
        }
        return result
    }

    private func resolveTypeRefForInheritance(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> TypeID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            guard !path.isEmpty else {
                return nil
            }
            // Try both raw path and package-qualified path (same as resolveNominalSymbolAndTypeArgs)
            var candidatePaths: [[InternedString]] = [path]
            if path.count == 1, !currentPackage.isEmpty {
                candidatePaths.append(currentPackage + path)
            }
            for candidatePath in candidatePaths {
                if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })
                {
                    let resolvedArgs = resolveTypeArgRefsForInheritance(argRefs, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types)
                    return types.make(.classType(ClassType(classSymbol: nominalSymbol.id, args: resolvedArgs, nullability: nullability)))
                }
            }
            // Note: Primitive/built-in types (e.g., Int, String, Boolean) cannot be resolved here
            // because DataFlowSemaPhase does not have access to StringInterner. When a type arg
            // references a primitive, resolution fails and the all-or-nothing fallback in
            // resolveTypeArgRefsForInheritance drops all type args for that supertype edge.
            // This is a known limitation; the full TypeCheckSemaPhase resolves these correctly later.
            return nil
        case let .functionType(paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            var paramTypes: [TypeID] = []
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRefForInheritance(paramRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return nil
                }
                paramTypes.append(paramType)
            }
            guard let returnType = resolveTypeRefForInheritance(returnRefID, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                return nil
            }
            return types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))
        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap { resolveTypeRefForInheritance($0, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))
        }
    }

    func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            true
        default:
            false
        }
    }

    // P5-112: Validate that concrete subclasses of abstract classes override all abstract members.
    func validateAbstractOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateAbstractOverridesForDecl(
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

    private func validateAbstractOverridesForDecl(
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

        // Recursively validate nested classes
        switch decl {
        case let .classDecl(classDecl):
            for nestedDeclID in classDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        case let .interfaceDecl(interfaceDecl):
            for nestedDeclID in interfaceDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        case let .objectDecl(objectDecl):
            for nestedDeclID in objectDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        default:
            return
        }

        // Only check concrete class/object declarations (not abstract, not interface)
        guard symbolInfo.kind == .class || symbolInfo.kind == .object,
              !symbolInfo.flags.contains(.abstractType)
        else {
            return
        }

        // Collect all abstract members from the entire supertype chain
        let abstractMembers = collectInheritedAbstractMembers(
            for: symbol,
            symbols: symbols
        )
        guard !abstractMembers.isEmpty else { return }

        // Collect the names of members that this class provides overrides for
        let overriddenNames = collectOverriddenMemberNames(
            for: symbol,
            decl: decl,
            ast: ast,
            symbols: symbols
        )

        // Check that every abstract member name is overridden
        for abstractMember in abstractMembers {
            guard let abstractSym = symbols.symbol(abstractMember) else { continue }
            let memberName = interner.resolve(abstractSym.name)
            if !overriddenNames.contains(abstractSym.name) {
                let className = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                let declRange: SourceRange? = switch decl {
                case let .classDecl(cd): cd.range
                case let .objectDecl(od): od.range
                default: nil
                }
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class '\(className)' must override abstract member '\(memberName)' or be declared abstract.",
                    range: declRange
                )
            }
        }
    }

    /// Collects all abstract member symbol IDs from the entire supertype chain of a class,
    /// filtering out those that have been concretely overridden by intermediate classes.
    private func collectInheritedAbstractMembers(
        for classSymbol: SymbolID,
        symbols: SymbolTable
    ) -> [SymbolID] {
        var abstractMembersByName: [InternedString: SymbolID] = [:]
        var concreteOverrideNames: Set<InternedString> = []
        var visited: Set<SymbolID> = [classSymbol]
        var queue = symbols.directSupertypes(for: classSymbol)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let currentSym = symbols.symbol(current) else { continue }

            let children = symbols.children(ofFQName: currentSym.fqName)
            for childID in children {
                guard let childSym = symbols.symbol(childID) else { continue }
                if childSym.kind == .function || childSym.kind == .property {
                    if childSym.flags.contains(.abstractType) {
                        // Only record the abstract member if we haven't seen
                        // a concrete override for this name yet.
                        if !concreteOverrideNames.contains(childSym.name) {
                            abstractMembersByName[childSym.name] = childID
                        }
                    } else {
                        // This is a concrete member. Only treat it as satisfying
                        // abstract requirements from higher supertypes if no closer
                        // supertype has already (re-)abstracted this name.
                        if abstractMembersByName[childSym.name] == nil {
                            concreteOverrideNames.insert(childSym.name)
                        }
                    }
                }
            }

            // Continue walking supertypes
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }

        return Array(abstractMembersByName.values)
    }

    /// Collects the set of member names that this class provides via `override`.
    func collectOverriddenMemberNames(
        for _: SymbolID,
        decl: Decl,
        ast: ASTModule,
        symbols _: SymbolTable
    ) -> Set<InternedString> {
        var overriddenNames: Set<InternedString> = []

        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
            memberProperties = classDecl.memberProperties
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
            memberProperties = objectDecl.memberProperties
        default:
            return overriddenNames
        }

        for memberDeclID in memberFunctions {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .funDecl(funDecl) = memberDecl else { continue }
            if funDecl.modifiers.contains(.override) {
                overriddenNames.insert(funDecl.name)
            }
        }

        for memberDeclID in memberProperties {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .propertyDecl(propertyDecl) = memberDecl else { continue }
            if propertyDecl.modifiers.contains(.override) {
                overriddenNames.insert(propertyDecl.name)
            }
        }

        return overriddenNames
    }

    // P5-78: Validate that direct subclasses of sealed types are in the same package.
    func validateSealedHierarchy(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID),
                      let symbolInfo = symbols.symbol(symbol)
                else {
                    continue
                }
                // Only check class and interface declarations that have supertypes
                let hasSuperTypes: Bool
                switch decl {
                case let .classDecl(classDecl):
                    hasSuperTypes = !classDecl.superTypes.isEmpty
                case let .interfaceDecl(interfaceDecl):
                    hasSuperTypes = !interfaceDecl.superTypes.isEmpty
                case let .objectDecl(objectDecl):
                    hasSuperTypes = !objectDecl.superTypes.isEmpty
                default:
                    continue
                }
                guard hasSuperTypes else { continue }

                let supertypes = symbols.directSupertypes(for: symbol)
                for supertypeID in supertypes {
                    guard let supertypeSymbol = symbols.symbol(supertypeID),
                          supertypeSymbol.flags.contains(.sealedType)
                    else {
                        continue
                    }
                    // Check same-package: compare package prefixes
                    let subtypePackage = Array(symbolInfo.fqName.dropLast())
                    let supertypePackage = Array(supertypeSymbol.fqName.dropLast())
                    if subtypePackage != supertypePackage {
                        let subtypeName = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let supertypeName = supertypeSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            "KSWIFTK-SEMA-0070",
                            "'\(subtypeName)' cannot inherit from sealed type '\(supertypeName)': sealed subclasses must be in the same package.",
                            range: ast.arena.decl(declID).flatMap { d -> SourceRange? in
                                switch d {
                                case let .classDecl(cd): return cd.range
                                case let .interfaceDecl(id): return id.range
                                case let .objectDecl(od): return od.range
                                default: return nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
