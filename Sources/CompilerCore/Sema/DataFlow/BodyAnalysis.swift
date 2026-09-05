
extension DataFlowSemaPhase {
    func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols _: SymbolTable,
        types _: TypeSystem,
        bindings _: BindingTable,
        diagnostics: DiagnosticEngine,
        interner _: StringInterner
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

        case .propertyDecl:
            break

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
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        diagnostics: DiagnosticEngine? = nil,
        recursionDepth: Int = 0,
        usageRange: SourceRange? = nil
    ) -> TypeID? {
        guard recursionDepth <= DataFlowSemaPhase.maxStructuralRecursionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-TYPE-DEPTH",
                "Type nesting is too deep (exceeded maximum depth of \(DataFlowSemaPhase.maxStructuralRecursionDepth)).",
                range: nil
            )
            return types.errorType
        }
        let builtinNames = BuiltinTypeNames(interner: interner)
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

            if let builtinType = resolveBuiltinTypeName(
                shortName,
                nullability: nullability,
                types: types,
                interner: interner,
                builtinNames: builtinNames
            ) {
                return builtinType
            }

            let candidates: [SemanticSymbol]
            if path.count == 1,
               let relativeOwnerFQName
            {
                let relativeCandidates = resolveRelativeNominalCandidates(
                    named: shortName,
                    relativeTo: relativeOwnerFQName,
                    symbols: symbols
                )
                if !relativeCandidates.isEmpty {
                    candidates = relativeCandidates
                } else {
                    let fqCandidates = resolveNominalCandidates(
                        for: path,
                        currentPackageFQName: currentPackageFQName,
                        imports: imports,
                        symbols: symbols
                    )
                    if !fqCandidates.isEmpty {
                        candidates = fqCandidates
                    } else {
                        candidates = symbols.lookupByShortName(shortName).compactMap { symbols.symbol($0) }
                    }
                }
            } else {
                let fqCandidates = resolveNominalCandidates(
                    for: path,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    symbols: symbols
                )
                if !fqCandidates.isEmpty {
                    candidates = fqCandidates
                } else if path.count == 1 {
                    candidates = symbols.lookupByShortName(shortName).compactMap { symbols.symbol($0) }
                } else {
                    candidates = []
                }
            }
            if let resolved = candidates.first(where: { isNominalTypeSymbol($0.kind) }) {
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth,
                    usageRange: usageRange
                )
                if resolved.kind == .typeAlias {
                    if let underlying = resolveTypeAliasUnderlying(
                        resolved.id,
                        symbols: symbols,
                        types: types,
                        typeArgs: resolvedArgs,
                        visited: [],
                        recursionDepth: recursionDepth,
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
                if resolved.id == types.kClassInterfaceSymbol
                    || resolved.fqName == [interner.intern("kotlin"), interner.intern("reflect"), interner.intern("KClass")]
                {
                    // Preserve star and contravariant KClass projections in the
                    // nominal representation. A covariant projection is
                    // equivalent to the dedicated KClass<T> representation.
                    if let firstArg = resolvedArgs.first {
                        switch firstArg {
                        case .star, .in:
                            return types.make(.classType(ClassType(
                                classSymbol: resolved.id,
                                args: resolvedArgs,
                                nullability: nullability
                            )))
                        case .invariant, .out:
                            break
                        }
                    }
                    let argumentType: TypeID = if let firstArg = resolvedArgs.first {
                        switch firstArg {
                        case let .invariant(t):
                            t
                        case .star:
                            types.anyType
                        case let .out(t), let .in(t):
                            t
                        }
                    } else {
                        types.anyType
                    }
                    return types.makeKClassType(argument: argumentType, nullability: nullability)
                }
                return types.make(.classType(ClassType(classSymbol: resolved.id, args: resolvedArgs, nullability: nullability)))
            }
            if candidates.isEmpty,
               let builtinNestedSymbol = resolveBuiltinClassNestedType(
                   path: path,
                   types: types,
                   symbols: symbols,
                   interner: interner
               ),
               isNominalTypeSymbol(builtinNestedSymbol.kind)
            {
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth
                )
                return types.make(.classType(ClassType(classSymbol: builtinNestedSymbol.id, args: resolvedArgs, nullability: nullability)))
            }
            let stringBuilderName = interner.intern("StringBuilder")
            let kotlinTextStringBuilderFQName = [
                interner.intern("kotlin"),
                interner.intern("text"),
                stringBuilderName,
            ]
            if (path.count == 1 && shortName == stringBuilderName) || path == kotlinTextStringBuilderFQName {
                let stringBuilderSymbol = ensureKotlinTextStringBuilderSymbol(symbols: symbols, interner: interner)
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    usageRange: usageRange
                )
                return types.make(.classType(ClassType(
                    classSymbol: stringBuilderSymbol,
                    args: resolvedArgs,
                    nullability: nullability
                )))
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0025",
                "Unresolved type '\(interner.resolve(shortName))'.",
                range: usageRange
            )
            return types.errorType

        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            var contextReceiverTypes: [TypeID] = []
            for contextReceiverRef in contextReceiverRefIDs {
                guard let contextReceiverType = resolveTypeRef(
                    contextReceiverRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) else {
                    return nil
                }
                contextReceiverTypes.append(contextReceiverType)
            }
            var receiverType: TypeID?
            if let receiverRefID {
                receiverType = resolveTypeRef(
                    receiverRefID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                )
            }
            var paramTypes: [TypeID] = []
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRef(
                    paramRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
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
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                recursionDepth: recursionDepth + 1,
                usageRange: usageRange
            ) ?? types.unitType
            return types.make(.functionType(FunctionType(
                contextReceivers: contextReceiverTypes,
                receiver: receiverType,
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
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                )
            }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))

        case let .annotated(base, annotations):
            guard let baseType = resolveTypeRef(
                base,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                recursionDepth: recursionDepth + 1,
                usageRange: usageRange
            ) else {
                return nil
            }
            return ExtensionFunctionTypeSupport.normalizeAnnotatedType(
                baseType: baseType,
                annotations: annotations,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics,
                range: usageRange
            )
        }
    }

    private func resolveBuiltinTypeName(
        _ name: InternedString,
        nullability: Nullability,
        types: TypeSystem,
        interner: StringInterner,
        builtinNames: BuiltinTypeNames
    ) -> TypeID? {
        if let builtin = builtinNames.resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtin
        }
        if name == interner.intern("Byte") || name == interner.intern("Short") {
            return types.make(.primitive(.int, nullability))
        }
        return nil
    }

    private func resolveRelativeNominalCandidates(
        named shortName: InternedString,
        relativeTo ownerFQName: [InternedString],
        symbols: SymbolTable
    ) -> [SemanticSymbol] {
        guard !ownerFQName.isEmpty else {
            return []
        }

        var candidates: [SemanticSymbol] = []
        var seen: Set<SymbolID> = []
        var current = ownerFQName
        while !current.isEmpty {
            if current.last == shortName {
                for symbolID in symbols.lookupAll(fqName: current) where seen.insert(symbolID).inserted {
                    if let symbol = symbols.symbol(symbolID) {
                        candidates.append(symbol)
                    }
                }
            }

            let nestedFQName = current + [shortName]
            for symbolID in symbols.lookupAll(fqName: nestedFQName) where seen.insert(symbolID).inserted {
                if let symbol = symbols.symbol(symbolID) {
                    candidates.append(symbol)
                }
            }

            current.removeLast()
        }
        return candidates
    }

    private func resolveNominalCandidates(
        for path: [InternedString],
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl],
        symbols: SymbolTable
    ) -> [SemanticSymbol] {
        guard !path.isEmpty else {
            return []
        }

        var candidatePaths: [[InternedString]] = {
            var paths: [[InternedString]] = []
            if path.count == 1 {
                if let currentPackageFQName,
                   !currentPackageFQName.isEmpty
                {
                    paths.append(currentPackageFQName + path)
                }
                if let shortName = path.first {
                    for importDecl in imports {
                        if let alias = importDecl.alias, alias == shortName {
                            paths.append(importDecl.path)
                        } else if importDecl.alias == nil,
                                  importDecl.path.last == shortName
                        {
                            paths.append(importDecl.path)
                        }
                    }
                }
                // An unqualified root symbol is the final fallback. This ordering
                // keeps an explicit import from being shadowed by a compatibility
                // alias with the same short name (KSP-1150).
                paths.append(path)
            } else {
                paths = [path]
            }
            return paths
        }()

        // For qualified nested-type references within the current package (e.g. a
        // Companion-scoped extension "Duration.Companion.ZERO" written in the same
        // file/package as "class Duration"), try the path prefixed by the current
        // package FQName before falling back to import expansion.
        if path.count > 1,
           let currentPackageFQName,
           !currentPackageFQName.isEmpty
        {
            candidatePaths.append(currentPackageFQName + path)
        }

        // For qualified nested-type references (e.g. "KMutableProperty.Setter"), expand
        // the first component via imports and append the remaining tail.
        if path.count > 1, let firstComponent = path.first {
            let tail = Array(path.dropFirst())
            for importDecl in imports {
                if let alias = importDecl.alias, alias == firstComponent {
                    candidatePaths.append(importDecl.path + tail)
                } else if importDecl.alias == nil,
                          importDecl.path.last == firstComponent
                {
                    candidatePaths.append(importDecl.path + tail)
                }
            }
        }

        var seenPaths: Set<[InternedString]> = []
        var result: [SemanticSymbol] = []
        for candidatePath in candidatePaths where seenPaths.insert(candidatePath).inserted {
            result.append(contentsOf: symbols.lookupAll(fqName: candidatePath).compactMap { symbols.symbol($0) })
        }
        return result
    }

    func resolveTypeArgRefs(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:],
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        diagnostics: DiagnosticEngine? = nil,
        recursionDepth: Int = 0,
        usageRange: SourceRange? = nil
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
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
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
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
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
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
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
            return types.make(.functionType(FunctionType(contextReceivers: ft.contextReceivers, receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: .nullable)))
        case let .kClassType(kc):
            return types.make(.kClassType(KClassType(argument: kc.argument, nullability: .nullable)))
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

    /// Maximum structural recursion depth for type resolution and substitution.
    /// Keep one parser level available so source at the semantic boundary can
    /// still be parsed and rejected by Sema with the semantic depth diagnostic.
    static let maxStructuralRecursionDepth = TypeRefParserCore.maxRecursionDepth - 1

    private func resolveTypeAliasUnderlying(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        typeArgs: [TypeArg] = [],
        visited: Set<SymbolID>,
        depth: Int = 0,
        recursionDepth: Int = 0,
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
            recursionDepth: recursionDepth,
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
                recursionDepth: recursionDepth,
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
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = symbols.typeAliasTypeParameters(for: aliasSymbol)
        // Non-generic aliases may still carry fully-substituted underlying type arguments
        // through expected-type propagation, so there is nothing left to substitute here.
        if typeParamSymbols.isEmpty {
            return typeID
        }
        // Alias is generic. Emit a diagnostic whenever the argument count does not match,
        // even if we end up not performing any substitution.
        if !typeArgs.isEmpty && typeArgs.count != typeParamSymbols.count {
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
        return applySubstitution(
            typeID,
            argSubstitution: argSubstitution,
            types: types,
            symbols: symbols,
            recursionDepth: recursionDepth,
            diagnostics: diagnostics
        )
    }

    private func applySubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem,
        symbols: SymbolTable,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        guard recursionDepth <= DataFlowSemaPhase.maxStructuralRecursionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-TYPE-DEPTH",
                "Type substitution nesting is too deep (exceeded maximum depth of \(DataFlowSemaPhase.maxStructuralRecursionDepth)).",
                range: nil
            )
            return types.errorType
        }
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
                substituteArg(
                    arg,
                    argSubstitution: argSubstitution,
                    types: types,
                    symbols: symbols,
                    recursionDepth: recursionDepth + 1,
                    diagnostics: diagnostics
                )
            }
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: newArgs, nullability: ct.nullability)))
        case let .functionType(ft):
            let newContextReceivers = ft.contextReceivers.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newReceiver = ft.receiver.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newParams = ft.params.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newReturn = applySubstitution(
                ft.returnType,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            )
            return types.make(.functionType(FunctionType(contextReceivers: newContextReceivers, receiver: newReceiver, params: newParams, returnType: newReturn, isSuspend: ft.isSuspend, nullability: ft.nullability)))
        case let .kClassType(kc):
            let newArg = applySubstitution(
                kc.argument,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            )
            if newArg == kc.argument { return typeID }
            return types.make(.kClassType(KClassType(argument: newArg, nullability: kc.nullability)))
        case .stringStruct, .primitive, .any, .unit, .nothing, .error:
            return typeID
        case let .intersection(parts):
            let newParts = parts.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
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
        symbols: SymbolTable,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            // If the inner type is a bare type parameter with a substitution,
            // replace the entire arg with the use-site TypeArg (preserving projection).
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if tp.nullability == .nullable {
                    return applyNullabilityToArg(replacement, types: types)
                }
                return replacement
            }
            return .invariant(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
        case let .out(inner):
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                // Declaration-site has `.out`; if use-site is `.star`, star wins.
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement, types: types, diagnostics: diagnostics)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .out(resolved)
            }
            return .out(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
        case let .in(inner):
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement, types: types, diagnostics: diagnostics)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .in(resolved)
            }
            return .in(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
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

    private func typeArgInnerType(
        _ arg: TypeArg,
        types: TypeSystem,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            return inner
        case .star:
            diagnostics?.error(
                "KSWIFTK-SEMA-0063",
                "Cannot extract inner type from star projection '<*>'.",
                range: nil
            )
            return types.errorType
        }
    }

    /// Check whether the function body contains a self-recursive call in tail position.
    /// For block bodies, checks ALL return expressions (not just the last statement)
    /// to handle patterns like `if (cond) return f(x); return base`.
    func checkTailRecursiveBody(
        _ body: FunctionBody, functionName: InternedString, ast: ASTModule
    ) -> Bool {
        switch body {
        case .unit:
            return false
        case let .expr(exprID, _):
            return isSelfRecursiveCall(exprID, functionName: functionName, ast: ast)
        case let .block(exprIDs, _):
            // Check any explicit return expression in the block whose value
            // is a self-recursive call — the tail call may appear in an
            // early-return branch, not necessarily the last statement.
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID),
                   case let .returnExpr(value, _, _) = expr,
                   let value
                {
                    if isSelfRecursiveCall(value, functionName: functionName, ast: ast) {
                        return true
                    }
                }
            }
            // Also check the last expression for implicit return (expression-body style).
            guard let lastExprID = exprIDs.last else { return false }
            return isSelfRecursiveCall(lastExprID, functionName: functionName, ast: ast)
        }
    }

    /// Resolve a nested type reference (e.g. `Char.Companion`) inside a builtin
    /// type's synthetic class symbol when normal nominal lookup fails.
    private func resolveBuiltinClassNestedType(
        path: [InternedString],
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SemanticSymbol? {
        guard path.count > 1, let first = path.first else { return nil }

        let rootClassSymbol: SymbolID?
        if first == interner.intern("Char") {
            rootClassSymbol = types.charClassSymbol
        } else if first == interner.intern("String") {
            rootClassSymbol = types.stringClassSymbol
        } else if first == interner.intern("Any") {
            rootClassSymbol = types.anyClassSymbol
        } else if first == interner.intern("Long") || first == interner.intern("Short") {
            let kotlinFQName = [interner.intern("kotlin"), first]
            rootClassSymbol = symbols.lookupAll(fqName: kotlinFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID) else { return false }
                return symbol.kind == .class
            })
        } else {
            rootClassSymbol = nil
        }

        guard let root = rootClassSymbol, let rootInfo = symbols.symbol(root) else {
            return nil
        }
        let nestedFQName = rootInfo.fqName + Array(path.dropFirst())
        guard let symbolID = symbols.lookupAll(fqName: nestedFQName).first else { return nil }
        return symbols.symbol(symbolID)
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
