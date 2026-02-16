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

        case .classDecl, .objectDecl, .typeAliasDecl, .enumEntryDecl:
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

        switch typeRef {
        case .named(let path, let argRefs, let nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull

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

            if let symbol = symbols.lookupAll(fqName: path)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                )
                return types.make(.classType(ClassType(classSymbol: symbol, args: resolvedArgs, nullability: nullability)))
            }
            return nullability == .nullable ? types.nullableAnyType : types.anyType

        case .functionType(let paramRefIDs, let returnRefID, let isSuspend, let nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let paramTypes = paramRefIDs.compactMap { paramRef in
                resolveTypeRef(
                    paramRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                )
            }
            let returnType = resolveTypeRef(
                returnRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters
            ) ?? types.unitType
            return types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))
        }
    }

    func resolveTypeArgRefs(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) -> [TypeArg] {
        argRefs.compactMap { argRef in
            switch argRef {
            case .invariant(let innerRef):
                guard let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                ) else { return nil }
                return .invariant(resolved)
            case .out(let innerRef):
                guard let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                ) else { return nil }
                return .out(resolved)
            case .in(let innerRef):
                guard let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                ) else { return nil }
                return .in(resolved)
            case .star:
                return .star
            }
        }
    }
}
