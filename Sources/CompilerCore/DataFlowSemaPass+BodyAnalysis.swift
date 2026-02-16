import Foundation

extension DataFlowSemaPassPhase {
    func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case .funDecl(let funDecl):
            var seenNames: Set<InternedString> = []
            for valueParam in funDecl.valueParams {
                if seenNames.contains(valueParam.name) {
                    diagnostics.error(
                        "KSWIFTK-TYPE-0002",
                        "Duplicate function parameter name.",
                        range: funDecl.range
                    )
                }
                seenNames.insert(valueParam.name)
            }

            if let symbol = bindings.declSymbols[declID],
               let signature = symbols.functionSignature(for: symbol),
               case .expr = funDecl.body {
                // Bind a synthetic expression type for expression-body functions.
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindExprType(expr, type: signature.returnType)
            }

        case .propertyDecl(let propertyDecl):
            if let symbol = bindings.declSymbols[declID] {
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindIdentifier(expr, symbol: symbol)
                let boundType = resolveTypeRef(
                    propertyDecl.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) ?? types.anyType
                bindings.bindExprType(expr, type: boundType)
            }

        case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) -> TypeID? {
        guard let typeRefID, let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }

        let nullability: Nullability
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, let nullable):
            path = refPath
            nullability = nullable ? .nullable : .nonNull
        }

        guard let shortName = path.last else {
            return nil
        }

        if path.count == 1, let typeParamSymbol = localTypeParameters[shortName] {
            return types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: nullability)))
        }

        switch interner.resolve(shortName) {
        case "Int":
            return types.make(.primitive(.int, nullability))
        case "Boolean":
            return types.make(.primitive(.boolean, nullability))
        case "String":
            return types.make(.primitive(.string, nullability))
        case "Any":
            return nullability == .nullable ? types.nullableAnyType : types.anyType
        case "Unit":
            return nullability == .nullable ? types.nullableAnyType : types.unitType
        case "Nothing":
            return types.nothingType
        default:
            break
        }

        if let resolved = symbols.lookupAll(fqName: path)
            .compactMap({ symbols.symbol($0) })
            .first(where: { isNominalTypeSymbol($0.kind) }) {
            if resolved.kind == .typeAlias {
                if let underlying = resolveTypeAliasUnderlying(
                    resolved.id,
                    symbols: symbols,
                    types: types,
                    visited: []
                ) {
                    if nullability == .nullable {
                        return applyNullability(underlying, types: types)
                    }
                    return underlying
                }
            }
            return types.make(.classType(ClassType(classSymbol: resolved.id, args: [], nullability: nullability)))
        }
        return nullability == .nullable ? types.nullableAnyType : types.anyType
    }

    private func applyNullability(_ typeID: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: typeID) {
        case .primitive(let p, _):
            return types.make(.primitive(p, .nullable))
        case .classType(let ct):
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: .nullable)))
        case .typeParam(let tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable)))
        case .functionType(let ft):
            return types.make(.functionType(FunctionType(receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: .nullable)))
        case .any, .unit, .nothing:
            return types.nullableAnyType
        default:
            return typeID
        }
    }

    private func resolveTypeAliasUnderlying(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        visited: Set<SymbolID>
    ) -> TypeID? {
        guard !visited.contains(symbolID) else {
            return nil
        }
        guard let underlying = symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        if case .classType(let classType) = types.kind(of: underlying),
           let targetSymbol = symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias {
            var newVisited = visited
            newVisited.insert(symbolID)
            return resolveTypeAliasUnderlying(
                classType.classSymbol,
                symbols: symbols,
                types: types,
                visited: newVisited
            )
        }
        return underlying
    }
}
