import Foundation

/// Stateless utility functions for type checking. No back-reference to the driver needed.
/// Derived from TypeCheckSemaPass+InferHelpers.swift.
struct TypeCheckHelpers {
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
            return sema.types.nullableAnyType
        case "launch":
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case "async":
            guard argumentCount >= 1 else { return nil }
            return sema.types.nullableAnyType
        case "delay":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "kk_array_new", "IntArray":
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case "kk_array_get":
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case "kk_array_set":
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        default:
            return nil
        }
    }

    func resolveBuiltinTypeName(_ name: String, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case "Int": types.withNullability(nullability, for: types.intType)
        case "Long": types.withNullability(nullability, for: types.longType)
        case "Float": types.withNullability(nullability, for: types.floatType)
        case "Double": types.withNullability(nullability, for: types.doubleType)
        case "Boolean": types.withNullability(nullability, for: types.booleanType)
        case "Char": types.withNullability(nullability, for: types.charType)
        case "String": types.withNullability(nullability, for: types.stringType)
        case "Any": nullability == .nullable ? types.nullableAnyType : types.anyType
        case "Unit": types.unitType
        case "Nothing": nullability == .nullable ? types.nullableNothingType : types.nothingType
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
            guard let firstName = path.first else {
                return sema.types.errorType
            }
            let name = interner.resolve(firstName)
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(name, nullability: nullability, types: sema.types) {
                return builtin
            }
            if path.count == 1,
               let scope,
               let typeParameterSymbol = resolveTypeParameterSymbol(firstName, scope: scope, sema: sema)
            {
                return sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: nullability)))
            }
            do {
                let fqCandidates = sema.symbols.lookupAll(fqName: [firstName]).filter { symbolID in
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
                    sema.symbols.lookupByShortName(firstName).filter { symbolID in
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

    // MARK: - Typealias Expansion

    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    private static let maxAliasExpansionDepth = 32

    /// Expand a typealias symbol to its underlying type, substituting type arguments.
    /// Handles generic aliases, cycle detection, and depth limiting.
    func expandTypeAlias(
        _ symbolID: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        visited: Set<SymbolID>,
        depth: Int,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID? {
        // Cycle detection
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        // Depth limit
        guard depth < TypeCheckHelpers.maxAliasExpansionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-DEPTH",
                "Typealias expansion exceeded maximum depth of \(TypeCheckHelpers.maxAliasExpansionDepth).",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard let underlying = sema.symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        // Substitute type parameters
        let expanded = substituteTypeAliasParamsForTypeCheck(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            sema: sema,
            diagnostics: diagnostics
        )
        // Validate variance constraints after expansion
        validateVarianceAfterExpansion(
            expanded, aliasSymbol: symbolID, typeArgs: typeArgs,
            sema: sema, diagnostics: diagnostics
        )
        // If expanded type is itself a typealias, continue expansion
        if case let .classType(classType) = sema.types.kind(of: expanded),
           let targetSymbol = sema.symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        {
            var newVisited = visited
            newVisited.insert(symbolID)
            let chainArgs = classType.args
            if let resolved = expandTypeAlias(
                classType.classSymbol,
                typeArgs: chainArgs,
                sema: sema,
                visited: newVisited,
                depth: depth + 1,
                diagnostics: diagnostics
            ) {
                if classType.nullability == .nullable {
                    return applyNullabilityForTypeCheck(resolved, types: sema.types)
                }
                return resolved
            }
            return nil
        }
        return expanded
    }

    /// Substitute type alias type parameters with provided type arguments.
    private func substituteTypeAliasParamsForTypeCheck(
        _ typeID: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
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
        return applyAliasSubstitution(typeID, argSubstitution: argSubstitution, sema: sema)
    }

    /// Recursively apply type argument substitution to a type.
    func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if let replacement = argSubstitution[tp.symbol] {
                let replacementType: TypeID = switch replacement {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    inner
                case .star:
                    types.nullableAnyType
                }
                if tp.nullability == .nullable {
                    return applyNullabilityForTypeCheck(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case let .classType(ct):
            let newArgs = ct.args.map { arg -> TypeArg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            if newArgs == ct.args { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol, args: newArgs, nullability: ct.nullability
            )))
        case let .functionType(ft):
            let newReceiver = ft.receiver.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newParams = ft.params.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReturn = applyAliasSubstitution(
                ft.returnType, argSubstitution: argSubstitution, sema: sema
            )
            if newReceiver == ft.receiver, newParams == ft.params, newReturn == ft.returnType {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                receiver: newReceiver, params: newParams, returnType: newReturn,
                isSuspend: ft.isSuspend, nullability: ft.nullability
            )))
        case let .intersection(parts):
            let newParts = parts.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            if newParts == parts { return typeID }
            return types.make(.intersection(newParts))
        default:
            return typeID
        }
    }

    // MARK: - @Deprecated Annotation Checking (ANNO-001)

    /// Checks whether `symbol` has a `@Deprecated` annotation and emits an appropriate
    /// diagnostic at `range` (the call/reference site).
    ///
    /// - `@Deprecated("msg")` or `@Deprecated("msg", level = WARNING)` → warning
    /// - `@Deprecated("msg", level = ERROR)` → error
    func checkDeprecation(
        for symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = sema.symbols.annotations(for: symbolID)
        for ann in annotations where ann.annotationFQName == "Deprecated" || ann.annotationFQName == "kotlin.Deprecated" {
            let symbolName = if let sym = sema.symbols.symbol(symbolID) {
                sym.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } else {
                "<unknown>"
            }
            // Extract the deprecation message (first positional argument, if any).
            let message = ann.arguments.first.map { arg in
                arg.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } ?? ""

            // Determine severity from the `level` argument.
            let isError = ann.arguments.contains { arg in
                let normalized = arg.replacingOccurrences(of: " ", with: "")
                return normalized.contains("level=DeprecationLevel.ERROR")
                    || normalized.contains("level=ERROR")
            }

            let deprecationMessage = message.isEmpty
                ? "'\(symbolName)' is deprecated."
                : "'\(symbolName)' is deprecated. \(message)"

            if isError {
                diagnostics.error(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            }
            return // Only emit one deprecation diagnostic per symbol reference.
        }
    }
}
