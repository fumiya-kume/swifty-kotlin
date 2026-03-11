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
        guard case let .classType(classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        switch interner.resolve(symbol.name) {
        case "IntArray":
            return sema.types.intType
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
        switch interner.resolve(calleeName) {
        case "runBlocking":
            guard argumentCount >= 1 else { return nil }
            return sema.types.anyType
        case "launch":
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Job",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case "async":
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Deferred",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case "delay":
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case "kk_array_new", "IntArray", "LongArray", "DoubleArray", "BooleanArray", "CharArray":
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case "kk_array_get", "kk_list_get":
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case "kk_array_set":
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        // Flow (CORO-003): type-erase Flow<T> as nullableAnyType
        case "flow":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "emit":
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case "collect":
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case "map", "filter", "take":
            guard argumentCount == 1 || argumentCount == 2 else { return nil }
            return sema.types.nullableAnyType
        default:
            return nil
        }
    }

    func resolveBuiltinTypeName(_ name: String, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case "Byte": types.withNullability(nullability, for: types.intType)
        case "Short": types.withNullability(nullability, for: types.intType)
        case "Int": types.withNullability(nullability, for: types.intType)
        case "Long": types.withNullability(nullability, for: types.longType)
        case "Float": types.withNullability(nullability, for: types.floatType)
        case "Double": types.withNullability(nullability, for: types.doubleType)
        case "Boolean": types.withNullability(nullability, for: types.booleanType)
        case "Char": types.withNullability(nullability, for: types.charType)
        case "String": types.withNullability(nullability, for: types.stringType)
        case "UInt": types.withNullability(nullability, for: types.uintType)
        case "ULong": types.withNullability(nullability, for: types.ulongType)
        case "UByte": types.withNullability(nullability, for: types.ubyteType)
        case "UShort": types.withNullability(nullability, for: types.ushortType)
        case "Any": types.withNullability(nullability, for: types.anyType)
        case "Unit": types.unitType
        case "Nothing": types.withNullability(nullability, for: types.nothingType)
        default: nil
        }
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
            let name = interner.resolve(shortName)
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(name, nullability: nullability, types: sema.types) {
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
                    "Unresolved type '\(name)'.",
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
