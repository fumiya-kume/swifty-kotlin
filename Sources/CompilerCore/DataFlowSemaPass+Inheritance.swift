import Foundation

extension DataFlowSemaPassPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID) else {
                    continue
                }
                let superTypeRefs: [TypeRefID]
                switch decl {
                case .classDecl(let classDecl):
                    superTypeRefs = classDecl.superTypes
                case .interfaceDecl(let interfaceDecl):
                    superTypeRefs = interfaceDecl.superTypes
                case .objectDecl(let objectDecl):
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
        case .named(let refPath, let refs, _):
            path = refPath
            argRefs = refs
        case .functionType:
            return nil
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1 && !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
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
            case .invariant(let innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return []
                }
                result.append(.invariant(resolved))
            case .out(let innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types) else {
                    return []
                }
                result.append(.out(resolved))
            case .in(let innerRef):
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
        case .named(let path, let argRefs, let nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            guard !path.isEmpty else {
                return nil
            }
            // Try both raw path and package-qualified path (same as resolveNominalSymbolAndTypeArgs)
            var candidatePaths: [[InternedString]] = [path]
            if path.count == 1 && !currentPackage.isEmpty {
                candidatePaths.append(currentPackage + path)
            }
            for candidatePath in candidatePaths {
                if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) }) {
                    let resolvedArgs = resolveTypeArgRefsForInheritance(argRefs, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types)
                    return types.make(.classType(ClassType(classSymbol: nominalSymbol.id, args: resolvedArgs, nullability: nullability)))
                }
            }
            // Note: Primitive/built-in types (e.g., Int, String, Boolean) cannot be resolved here
            // because DataFlowSemaPass does not have access to StringInterner. When a type arg
            // references a primitive, resolution fails and the all-or-nothing fallback in
            // resolveTypeArgRefsForInheritance drops all type args for that supertype edge.
            // This is a known limitation; the full TypeCheckSemaPass resolves these correctly later.
            return nil
        case .functionType(let paramRefIDs, let returnRefID, let isSuspend, let nullable):
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
        }
    }

    func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return true
        default:
            return false
        }
    }
}
