import Foundation

struct TypeCheckHelpers {
    private func syntheticCoroutineNominalType(
        packageName: [InternedString],
        shortName: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let shortNameID = interner.intern(shortName)
        let candidates = sema.symbols.lookupAll(fqName: packageName + [shortNameID])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .object:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
        guard let symbolID = candidates.first else {
            return nil
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbolID, args: [], nullability: .nonNull)))
    }

    func emitVisibilityError(
        for symbol: SemanticSymbol,
        name: String,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let visLabel = symbol.visibility == .protected ? "protected" : "private"
        let code = symbol.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
        diagnostics.error(code, "Cannot access '\(name)': it is \(visLabel).", range: range)
    }

    func bindAndReturnErrorType(_ id: ExprID, sema: SemaModule) -> TypeID {
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    /// Returns the element type for iterating over the given type in a for-loop.
    /// Handles both array types and range/progression types (Int representing IntRange).
    /// - Parameter isRangeExpr: true when the iterable expression is a range operator
    ///   (rangeTo, rangeUntil, downTo, step), allowing Int to be treated as iterable.
    func iterableElementType(
        for iterableType: TypeID,
        isRangeExpr: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        // Range/progression types (Int) are iterable over Int elements,
        // but only when the expression is actually a range operator.
        if isRangeExpr, iterableType == sema.types.intType {
            return sema.types.intType
        }
        return arrayElementType(for: iterableType, sema: sema, interner: interner)
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let builtinNames = BuiltinTypeNames(interner: interner)
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        switch symbol.name {
        case builtinNames.intArray, knownNames.longArray:
            return sema.types.intType
        case knownNames.doubleArray:
            return sema.types.doubleType
        case knownNames.booleanArray:
            return sema.types.booleanType
        case knownNames.charArray:
            return sema.types.charType
        default:
            // For generic collection types (e.g. List<String?>, MutableList<Int>),
            // extract the first type argument as the element type.
            if !classType.args.isEmpty {
                switch classType.args[0] {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return inner
                case .star:
                    return sema.types.nullableAnyType
                }
            }
            return nil
        }
    }

    func kxMiniCoroutineBuiltinReturnType(
        calleeName: InternedString?,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let calleeName else {
            return nil
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch calleeName {
        case knownNames.runBlocking:
            guard argumentCount >= 1 else { return nil }
            return sema.types.anyType
        case knownNames.launch:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Job",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.async:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Deferred",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case interner.intern("delay"):
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("kk_array_new"),
             knownNames.intArray,
             knownNames.longArray,
             knownNames.doubleArray,
             knownNames.booleanArray,
             knownNames.charArray:
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_get"), interner.intern("kk_list_get"):
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_set"):
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        // Flow (CORO-003): preserve Flow-ness in fallback paths as Flow<Any>
        case knownNames.flow:
            guard argumentCount == 1 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.emit:
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("collect"):
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case interner.intern("map"), interner.intern("filter"), interner.intern("take"):
            guard argumentCount == 1 || argumentCount == 2 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        default:
            return nil
        }
    }

    /// Construct a `Flow<elementType>` ClassType by looking up the synthetic
    /// `kotlinx.coroutines.flow.Flow` interface symbol.  Returns `nil` when
    /// the symbol has not been registered (caller should fall back to `anyType`).
    func makeFlowType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let flowFQName: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
            interner.intern("flow"),
            interner.intern("Flow"),
        ]
        guard let symbolID = sema.symbols.lookup(fqName: flowFQName) else { return nil }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbolID,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func resolveBuiltinTypeName(
        _ name: InternedString,
        nullability: Nullability = .nonNull,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        if let builtin = BuiltinTypeNames(interner: interner).resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtin
        }
        if name == interner.intern("Byte") || name == interner.intern("Short") {
            return types.make(.primitive(.int, nullability))
        }
        return nil
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return sema.types.errorType
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            guard let shortName = path.last else {
                return sema.types.errorType
            }
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(shortName, nullability: nullability, types: sema.types, interner: interner) {
                return builtin
            }
            if path.count == 1,
               let scope,
               let typeParameterSymbol = resolveTypeParameterSymbol(shortName, scope: scope, sema: sema)
            {
                return sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: nullability)))
            }
            do {
                let fqCandidates = sema.symbols.lookupAll(fqName: path).filter { symbolID in
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    switch sym.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }.sorted(by: { $0.rawValue < $1.rawValue })
                // Fall back to short-name lookup so that packaged types
                // (e.g. `package test; class Foo`) resolve when referenced
                // by simple name (`Foo`) during type checking.
                let candidates: [SymbolID] = if !fqCandidates.isEmpty {
                    fqCandidates
                } else {
                    sema.symbols.lookupByShortName(shortName).filter { symbolID in
                        guard let sym = sema.symbols.symbol(symbolID) else { return false }
                        switch sym.kind {
                        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                            return true
                        default:
                            return false
                        }
                    }.sorted(by: { $0.rawValue < $1.rawValue })
                }
                if let symbolID = candidates.first {
                    let resolvedArgs = resolveTypeArgRefsForTypeCheck(
                        argRefs, ast: ast, sema: sema, interner: interner,
                        scope: scope, diagnostics: diagnostics
                    )
                    // Expand typealias at call-site
                    if let sym = sema.symbols.symbol(symbolID), sym.kind == .typeAlias {
                        if let expanded = expandTypeAlias(
                            symbolID,
                            typeArgs: resolvedArgs,
                            sema: sema,
                            visited: [],
                            depth: 0,
                            diagnostics: diagnostics
                        ) {
                            if nullability == .nullable {
                                return applyNullabilityForTypeCheck(expanded, types: sema.types)
                            }
                            return expanded
                        }
                        // Fall through to classType for error recovery
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: symbolID,
                        args: resolvedArgs,
                        nullability: nullability
                    )))
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(interner.resolve(shortName))'.",
                    range: nil
                )
                return sema.types.errorType
            }

        case let .functionType(paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let paramTypes = paramRefIDs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics) }
            let returnType = resolveTypeRef(returnRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
            return sema.types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case let .intersection(partRefs):
            let partTypes = partRefs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics) }
            return sema.types.make(.intersection(partTypes))
        }
    }

    func resolveTypeArgRefsForTypeCheck(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case let .invariant(innerRef):
                .invariant(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case let .out(innerRef):
                .out(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case let .in(innerRef):
                .in(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics))
            case .star:
                .star
            }
        }
    }

    private func resolveTypeParameterSymbol(
        _ name: InternedString,
        scope: Scope,
        sema: SemaModule
    ) -> SymbolID? {
        scope.lookup(name).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .typeParameter
        }
    }
}
