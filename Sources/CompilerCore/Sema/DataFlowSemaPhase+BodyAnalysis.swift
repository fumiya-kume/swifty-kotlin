import Foundation

// swiftlint:disable file_length
extension DataFlowSemaPhase {
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
        case let .funDecl(funDecl):
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

            // swiftlint:disable opening_brace
            if let symbol = bindings.declSymbols[declID],
               let signature = symbols.functionSignature(for: symbol),
               case .expr = funDecl.body
            {
                // Bind a synthetic expression type for expression-body functions.
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindExprType(expr, type: signature.returnType)
            }
            // swiftlint:enable opening_brace

            // Validate tailrec: the terminal expression must be a self-recursive call.
            if funDecl.isTailrec {
                let isTailCall = checkTailRecursiveBody(
                    funDecl.body, functionName: funDecl.name, ast: ast
                )
                if !isTailCall {
                    diagnostics.warning(
                        "KSWIFTK-SEMA-TAILREC",
                        "Function marked 'tailrec' but last expression is not a self-recursive call.",
                        range: funDecl.range
                    )
                }
            }

        case let .propertyDecl(propertyDecl):
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
        localTypeParameters: [InternedString: SymbolID] = [:],
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID? {
        guard let typeRefID, let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }

        switch typeRef {
        case let .named(path, argRefs, nullable):
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
            case "Long":
                return types.make(.primitive(.long, nullability))
            case "Float":
                return types.make(.primitive(.float, nullability))
            case "Double":
                return types.make(.primitive(.double, nullability))
            case "Char":
                return types.make(.primitive(.char, nullability))
            case "Boolean":
                return types.make(.primitive(.boolean, nullability))
            case "String":
                return types.make(.primitive(.string, nullability))
            case "Any":
                return nullability == .nullable ? types.nullableAnyType : types.anyType
            case "Unit":
                return nullability == .nullable ? types.nullableAnyType : types.unitType
            case "Nothing":
                return nullability == .nullable ? types.nullableNothingType : types.nothingType
            default:
                break
            }

            let candidates: [SemanticSymbol]
            let fqCandidates = symbols.lookupAll(fqName: path).compactMap { symbols.symbol($0) }
            if !fqCandidates.isEmpty {
                candidates = fqCandidates
            } else if path.count == 1 {
                candidates = symbols.lookupByShortName(shortName).compactMap { symbols.symbol($0) }
            } else {
                candidates = []
            }
            if let resolved = candidates.first(where: { isNominalTypeSymbol($0.kind) }) {
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                )
                if resolved.kind == .typeAlias {
                    if let underlying = resolveTypeAliasUnderlying(
                        resolved.id,
                        symbols: symbols,
                        types: types,
                        typeArgs: resolvedArgs,
                        visited: [],
                        diagnostics: diagnostics
                    ) {
                        if nullability == .nullable {
                            return applyNullability(underlying, types: types)
                        }
                        return underlying
                    }
                    // Fall through to class-type path for error recovery when
                    // underlying type is not yet available (e.g. unresolved RHS,
                    // imported alias without signature metadata).
                }
                return types.make(.classType(ClassType(classSymbol: resolved.id, args: resolvedArgs, nullability: nullability)))
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0025",
                "Unresolved type '\(interner.resolve(shortName))'.",
                range: nil
            )
            return types.errorType

        case let .functionType(paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            var paramTypes: [TypeID] = []
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRef(
                    paramRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) else {
                    return nil
                }
                paramTypes.append(paramType)
            }
            let returnType = resolveTypeRef(
                returnRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) ?? types.unitType
            return types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap {
                resolveTypeRef(
                    $0,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                )
            }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))
        }
    }

    func resolveTypeArgRefs(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:],
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeArg] {
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) ?? types.errorType
                result.append(.invariant(resolved))
            case let .out(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) ?? types.errorType
                result.append(.out(resolved))
            case let .in(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) ?? types.errorType
                result.append(.in(resolved))
            case .star:
                result.append(.star)
            }
        }
        return result
    }

    private func applyNullability(_ typeID: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: typeID) {
        case let .primitive(p, _):
            return types.make(.primitive(p, .nullable))
        case let .classType(ct):
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: .nullable)))
        case let .typeParam(tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable)))
        case let .functionType(ft):
            return types.make(.functionType(FunctionType(receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: .nullable)))
        case .any, .unit, .nothing:
            let nullable = types.makeNullable(typeID)
            // If makeNullable is a no-op: either the type is already nullable (keep it)
            // or makeNullable genuinely can't apply (e.g. Unit) — fall back to Any?
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
        }
    }

    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    private static let maxAliasExpansionDepth = 32

    private func resolveTypeAliasUnderlying(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        typeArgs: [TypeArg] = [],
        visited: Set<SymbolID>,
        depth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID? {
        // Cycle detection
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        // Depth limit
        guard depth < DataFlowSemaPhase.maxAliasExpansionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-DEPTH",
                "Typealias expansion exceeded maximum depth of \(DataFlowSemaPhase.maxAliasExpansionDepth).",
                range: symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard let underlying = symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        let expanded = substituteTypeAliasParams(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        )
        if case let .classType(classType) = types.kind(of: expanded),
           let targetSymbol = symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        {
            var newVisited = visited
            newVisited.insert(symbolID)
            let chainArgs = classType.args
            if let resolved = resolveTypeAliasUnderlying(
                classType.classSymbol,
                symbols: symbols,
                types: types,
                typeArgs: chainArgs,
                visited: newVisited,
                depth: depth + 1,
                diagnostics: diagnostics
            ) {
                if classType.nullability == .nullable {
                    return applyNullability(resolved, types: types)
                }
                return resolved
            }
            return nil
        }
        return expanded
    }

    private func substituteTypeAliasParams(
        _ typeID: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = symbols.typeAliasTypeParameters(for: aliasSymbol)
        // If the alias is not generic, report any provided type arguments as a mismatch and return.
        if typeParamSymbols.isEmpty {
            if !typeArgs.isEmpty {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0062",
                    "Type argument count mismatch: expected 0 but got \(typeArgs.count).",
                    range: nil
                )
            }
            return typeID
        }
        // Alias is generic. Emit a diagnostic whenever the argument count does not match,
        // even if we end up not performing any substitution.
        if typeArgs.count != typeParamSymbols.count {
            diagnostics?.error(
                "KSWIFTK-SEMA-0062",
                "Type argument count mismatch: expected \(typeParamSymbols.count) but got \(typeArgs.count).",
                range: nil
            )
        }
        var argSubstitution: [SymbolID: TypeArg] = [:]
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            argSubstitution[paramSymbol] = typeArgs[index]
        }
        guard !argSubstitution.isEmpty else {
            return typeID
        }
        return applySubstitution(typeID, argSubstitution: argSubstitution, types: types, symbols: symbols)
    }

    private func applySubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem,
        symbols: SymbolTable
    ) -> TypeID {
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if let replacement = argSubstitution[tp.symbol] {
                // In non-arg positions, extract the TypeID from the TypeArg.
                // For .star, expand to the wildcard upper bound (Any?) since
                // leaving the type parameter unsubstituted would create dangling references.
                let replacementType: TypeID = switch replacement {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    inner
                case .star:
                    types.nullableAnyType
                }
                if tp.nullability == .nullable {
                    return applyNullability(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case let .classType(ct):
            let newArgs = ct.args.map { arg -> TypeArg in
                substituteArg(arg, argSubstitution: argSubstitution, types: types, symbols: symbols)
            }
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: newArgs, nullability: ct.nullability)))
        case let .functionType(ft):
            let newReceiver = ft.receiver.map { applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols) }
            let newParams = ft.params.map { applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols) }
            let newReturn = applySubstitution(ft.returnType, argSubstitution: argSubstitution, types: types, symbols: symbols)
            return types.make(.functionType(FunctionType(receiver: newReceiver, params: newParams, returnType: newReturn, isSuspend: ft.isSuspend, nullability: ft.nullability)))
        case .primitive, .any, .unit, .nothing, .error:
            return typeID
        case let .intersection(parts):
            let newParts = parts.map { applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols) }
            return types.make(.intersection(newParts))
        }
    }

    /// Substitute a type argument, preserving use-site projections through expansion.
    /// - `.invariant(T)` in the RHS: replace with the full `TypeArg` from the use-site
    ///   (e.g., `Foo<out String>` expands `Box<T>` to `Box<out String>`)
    /// - `.out(T)` / `.in(T)` in the RHS: keep the declaration-site projection,
    ///   substitute inner type; `.star` substitution yields `.star`
    /// - `.star`: preserved as-is
    private func substituteArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem,
        symbols: SymbolTable
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            // If the inner type is a bare type parameter with a substitution,
            // replace the entire arg with the use-site TypeArg (preserving projection).
            // swiftlint:disable opening_brace
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if tp.nullability == .nullable {
                    return applyNullabilityToArg(replacement, types: types)
                }
                return replacement
            }
            // swiftlint:enable opening_brace
            return .invariant(applySubstitution(inner, argSubstitution: argSubstitution, types: types, symbols: symbols))
        case let .out(inner):
            // swiftlint:disable opening_brace
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                // Declaration-site has `.out`; if use-site is `.star`, star wins.
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .out(resolved)
            }
            // swiftlint:enable opening_brace
            return .out(applySubstitution(inner, argSubstitution: argSubstitution, types: types, symbols: symbols))
        case let .in(inner):
            // swiftlint:disable opening_brace
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .in(resolved)
            }
            // swiftlint:enable opening_brace
            return .in(applySubstitution(inner, argSubstitution: argSubstitution, types: types, symbols: symbols))
        case .star:
            return .star
        }
    }

    private func applyNullabilityToArg(_ arg: TypeArg, types: TypeSystem) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(applyNullability(inner, types: types))
        case let .out(inner):
            .out(applyNullability(inner, types: types))
        case let .in(inner):
            .in(applyNullability(inner, types: types))
        case .star:
            .star
        }
    }

    private func typeArgInnerType(_ arg: TypeArg) -> TypeID {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            fatalError("typeArgInnerType called on .star")
        }
    }

    // MARK: - Tailrec validation helpers

    /// Check whether the function body ends with a self-recursive call (tail position).
    func checkTailRecursiveBody(
        _ body: FunctionBody, functionName: InternedString, ast: ASTModule
    ) -> Bool {
        switch body {
        case .unit:
            return false
        case let .expr(exprID, _):
            return isSelfRecursiveCall(exprID, functionName: functionName, ast: ast)
        case let .block(exprIDs, _):
            guard let lastExprID = exprIDs.last else { return false }
            // If the last statement is a return expression, check its value.
            // swiftlint:disable opening_brace
            if let expr = ast.arena.expr(lastExprID),
               case let .returnExpr(value, _, _) = expr
            {
                guard let value else { return false }
                return isSelfRecursiveCall(value, functionName: functionName, ast: ast)
            }
            // swiftlint:enable opening_brace
            return isSelfRecursiveCall(lastExprID, functionName: functionName, ast: ast)
        }
    }

    /// Check if the given expression is a call to a function with the given name.
    /// Handles direct calls (`f(...)`) and qualified self-calls (`this.f(...)`).
    private func isSelfRecursiveCall(
        _ exprID: ExprID, functionName: InternedString, ast: ASTModule
    ) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }

        switch expr {
        case let .call(callee, _, _, _):
            // Direct self call: `f(...)`.
            guard let calleeExpr = ast.arena.expr(callee),
                  case let .nameRef(name, _) = calleeExpr
            else { return false }
            return name == functionName

        case let .memberCall(receiver, callee, _, _, _),
             let .safeMemberCall(receiver, callee, _, _, _):
            // Qualified self call: `this.f(...)` / `this?.f(...)`.
            guard let receiverExpr = ast.arena.expr(receiver),
                  case .thisRef = receiverExpr
            else { return false }
            return callee == functionName

        default:
            return false
        }
    }
}
