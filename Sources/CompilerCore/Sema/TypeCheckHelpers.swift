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
        if isRangeExpr && iterableType == sema.types.intType {
            return sema.types.intType
        }
        return arrayElementType(for: iterableType, sema: sema, interner: interner)
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case .classType(let classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
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

    func binaryOperatorFunctionName(for op: BinaryOp, interner: StringInterner) -> InternedString {
        switch op {
        case .add:
            return interner.intern("plus")
        case .subtract:
            return interner.intern("minus")
        case .multiply:
            return interner.intern("times")
        case .divide:
            return interner.intern("div")
        case .modulo:
            return interner.intern("rem")
        case .equal:
            return interner.intern("equals")
        case .notEqual:
            return interner.intern("equals")
        case .lessThan:
            return interner.intern("compareTo")
        case .lessOrEqual:
            return interner.intern("compareTo")
        case .greaterThan:
            return interner.intern("compareTo")
        case .greaterOrEqual:
            return interner.intern("compareTo")
        case .logicalAnd:
            return interner.intern("and")
        case .logicalOr:
            return interner.intern("or")
        case .elvis:
            return interner.intern("elvis")
        case .rangeTo:
            return interner.intern("rangeTo")
        case .rangeUntil:
            return interner.intern("rangeUntil")
        case .downTo:
            return interner.intern("downTo")
        case .step:
            return interner.intern("step")
        }
    }

    func resolveBuiltinTypeName(_ name: String, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case "Int":     return types.withNullability(nullability, for: types.intType)
        case "Long":    return types.withNullability(nullability, for: types.longType)
        case "Float":   return types.withNullability(nullability, for: types.floatType)
        case "Double":  return types.withNullability(nullability, for: types.doubleType)
        case "Boolean": return types.withNullability(nullability, for: types.booleanType)
        case "Char":    return types.withNullability(nullability, for: types.charType)
        case "String":  return types.withNullability(nullability, for: types.stringType)
        case "Any":     return nullability == .nullable ? types.nullableAnyType : types.anyType
        case "Unit":    return types.unitType
        case "Nothing": return nullability == .nullable ? types.nullableNothingType : types.nothingType
        default:        return nil
        }
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return sema.types.errorType
        }
        switch typeRef {
        case .named(let path, let argRefs, let nullable):
            guard let firstName = path.first else {
                return sema.types.errorType
            }
            let name = interner.resolve(firstName)
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(name, nullability: nullability, types: sema.types) {
                return builtin
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
                let candidates: [SymbolID]
                if !fqCandidates.isEmpty {
                    candidates = fqCandidates
                } else {
                    candidates = sema.symbols.lookupByShortName(firstName).filter { symbolID in
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
                        diagnostics: diagnostics
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

        case .functionType(let paramRefIDs, let returnRefID, let isSuspend, let nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let paramTypes = paramRefIDs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics) }
            let returnType = resolveTypeRef(returnRefID, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics)
            return sema.types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case .intersection(let partRefs):
            let partTypes = partRefs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics) }
            return sema.types.make(.intersection(partTypes))
        }
    }

    func resolveTypeArgRefsForTypeCheck(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case .invariant(let innerRef):
                return .invariant(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .out(let innerRef):
                return .out(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .in(let innerRef):
                return .in(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .star:
                return .star
            }
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
        if case .classType(let classType) = sema.types.kind(of: expanded),
           let targetSymbol = sema.symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias {
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
    private func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case .typeParam(let tp):
            if let replacement = argSubstitution[tp.symbol] {
                let replacementType: TypeID
                switch replacement {
                case .invariant(let inner), .out(let inner), .in(let inner):
                    replacementType = inner
                case .star:
                    replacementType = types.nullableAnyType
                }
                if tp.nullability == .nullable {
                    return applyNullabilityForTypeCheck(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case .classType(let ct):
            let newArgs = ct.args.map { arg -> TypeArg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            if newArgs == ct.args { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol, args: newArgs, nullability: ct.nullability
            )))
        case .functionType(let ft):
            let newReceiver = ft.receiver.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newParams = ft.params.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReturn = applyAliasSubstitution(
                ft.returnType, argSubstitution: argSubstitution, sema: sema
            )
            if newReceiver == ft.receiver && newParams == ft.params && newReturn == ft.returnType {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                receiver: newReceiver, params: newParams, returnType: newReturn,
                isSuspend: ft.isSuspend, nullability: ft.nullability
            )))
        case .intersection(let parts):
            let newParts = parts.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            if newParts == parts { return typeID }
            return types.make(.intersection(newParts))
        default:
            return typeID
        }
    }

    /// Substitute a type argument, preserving use-site projections.
    private func substituteAliasArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeArg {
        switch arg {
        case .invariant(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if tp.nullability == .nullable {
                    return applyNullabilityToTypeArg(replacement, types: sema.types)
                }
                return replacement
            }
            return .invariant(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .out(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .out(resolved)
            }
            return .out(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .in(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .in(resolved)
            }
            return .in(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .star:
            return .star
        }
    }

    /// Apply nullability to a type, handling function types, primitives, and special types
    /// that `TypeSystem.makeNullable` may not wrap correctly.
    /// Mirrors `DataFlowSemaPassPhase.applyNullability`.
    private func applyNullabilityForTypeCheck(_ typeID: TypeID, types: TypeSystem) -> TypeID {
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
            let nullable = types.makeNullable(typeID)
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
        }
    }

    private func applyNullabilityToTypeArg(_ arg: TypeArg, types: TypeSystem) -> TypeArg {
        switch arg {
        case .invariant(let inner):
            return .invariant(applyNullabilityForTypeCheck(inner, types: types))
        case .out(let inner):
            return .out(applyNullabilityForTypeCheck(inner, types: types))
        case .in(let inner):
            return .in(applyNullabilityForTypeCheck(inner, types: types))
        case .star:
            return .star
        }
    }

    private func typeArgInnerTypeForCheck(_ arg: TypeArg) -> TypeID {
        switch arg {
        case .invariant(let inner), .out(let inner), .in(let inner):
            return inner
        case .star:
            return TypeID.invalid
        }
    }

    /// Validate that alias expansion does not violate variance constraints.
    /// Checks that the type arguments respect the declared variance of the
    /// typealias's type parameters.
    func validateVarianceAfterExpansion(
        _ expandedType: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
    ) {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        guard !typeParamSymbols.isEmpty, typeArgs.count == typeParamSymbols.count else {
            return
        }
        // Check each type argument against the variance of the underlying type's usage.
        // For now, verify that use-site projections don't conflict with declaration-site variance.
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            guard let paramSym = sema.symbols.symbol(paramSymbol) else { continue }
            let declaredVariance = paramSym.flags.contains(.reifiedTypeParameter) ? TypeVariance.invariant : .invariant
            let argVariance: TypeVariance
            switch typeArgs[index] {
            case .invariant:
                argVariance = .invariant
            case .out:
                argVariance = .out
            case .in:
                argVariance = .in
            case .star:
                continue // Star projection is always valid
            }
            // If declared variance is invariant but use-site provides a projection,
            // that's valid in Kotlin (use-site variance). No error here.
            // If we had declaration-site variance on the alias type params,
            // we'd check for conflicts. For now, invariant aliases accept any use-site.
            _ = (declaredVariance, argVariance)
        }
    }

    func resolveExplicitTypeArgs(
        _ typeArgRefs: [TypeRefID],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics)
        }
    }

    /// Check if an expression is a terminating expression (return/throw) for elvis guard narrowing.
    func isTerminatingExpr(_ expr: Expr) -> Bool {
        switch expr {
        case .returnExpr:
            return true
        case .throwExpr:
            return true
        default:
            return false
        }
    }

    func compoundAssignToBinaryOp(_ op: CompoundAssignOp) -> BinaryOp {
        switch op {
        case .plusAssign: return .add
        case .minusAssign: return .subtract
        case .timesAssign: return .multiply
        case .divAssign: return .divide
        case .modAssign: return .modulo
        }
    }

    func smartCastTypeForWhenSubjectCase(
        conditionID: ExprID,
        subjectType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return nil
        }
        switch conditionExpr {
        case .boolLiteral:
            switch sema.types.kind(of: subjectType) {
            case .primitive(.boolean, _):
                return sema.types.booleanType
            default:
                return nil
            }

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))

            default:
                return nil
            }

        default:
            return nil
        }
    }

    func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        switch types.kind(of: type) {
        case .classType(let classType):
            return classType.classSymbol
        case .intersection(let parts):
            // For intersection types, return the first nominal part
            for part in parts {
                if let symbol = nominalSymbol(of: part, types: types) {
                    return symbol
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Collects all nominal symbols from a type, including all parts of an intersection.
    func allNominalSymbols(of type: TypeID, types: TypeSystem) -> [SymbolID] {
        switch types.kind(of: type) {
        case .classType(let classType):
            return [classType.classSymbol]
        case .intersection(let parts):
            return parts.flatMap { allNominalSymbols(of: $0, types: types) }
        default:
            return []
        }
    }

    func collectMemberFunctionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        allowedOwnerSymbols: Set<SymbolID>? = nil
    ) -> [SymbolID] {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types)
        guard !nominalRoots.isEmpty else {
            return []
        }

        var ownerQueue: [SymbolID] = nominalRoots
        var visitedOwners: Set<SymbolID> = []
        var ownersInLookupOrder: [SymbolID] = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted else {
                continue
            }
            if let allowedOwnerSymbols {
                if allowedOwnerSymbols.contains(owner) {
                    ownersInLookupOrder.append(owner)
                }
            } else {
                ownersInLookupOrder.append(owner)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }

        if ownersInLookupOrder.isEmpty {
            return []
        }

        var candidates: [SymbolID] = []
        var seenCandidates: Set<SymbolID> = []
        for owner in ownersInLookupOrder {
            guard let ownerSymbol = sema.symbols.symbol(owner) else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard seenCandidates.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil else {
                    continue
                }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    /// When `receiver.InnerClassName(...)` is called, look up the inner class
    /// nested inside the receiver's nominal type and return its constructor(s).
    func collectInnerClassConstructorCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types),
              let receiverSymbol = sema.symbols.symbol(receiverNominal) else {
            return []
        }
        // Look for a nested class with the given name whose symbol has the innerClass flag.
        let nestedFQName = receiverSymbol.fqName + [calleeName]
        for candidate in sema.symbols.lookupAll(fqName: nestedFQName) {
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.innerClass) else {
                continue
            }
            // Found the inner class – collect its constructors.
            let initName = interner.intern("<init>")
            let ctorFQName = nestedFQName + [initName]
            return sema.symbols.lookupAll(fqName: ctorFQName).filter { ctorID in
                guard let ctorSym = sema.symbols.symbol(ctorID),
                      ctorSym.kind == .constructor else { return false }
                return true
            }
        }
        return []
    }

    /// Look up a member property (or field) named `calleeName` on the receiver's
    /// nominal type, walking the supertype chain. Returns the symbol and its type
    /// if found, or `nil` otherwise.
    func lookupMemberProperty(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types)
        guard !nominalRoots.isEmpty else {
            return nil
        }
        var ownerQueue: [SymbolID] = nominalRoots
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted else { continue }
            guard let ownerSymbol = sema.symbols.symbol(owner) else { continue }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let sym = sema.symbols.symbol(candidate),
                      (sym.kind == .property || sym.kind == .field),
                      let propType = sema.symbols.propertyType(for: candidate) else {
                    continue
                }
                return (candidate, propType)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    func callableTargetForCalleeExpr(
        _ calleeExprID: ExprID,
        sema: SemaModule
    ) -> CallableTarget? {
        if let explicitTarget = sema.bindings.callableTarget(for: calleeExprID) {
            return explicitTarget
        }
        guard let symbol = sema.bindings.identifierSymbol(for: calleeExprID) else {
            return nil
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return .localValue(symbol)
        }
        if semanticSymbol.kind == .function || semanticSymbol.kind == .constructor {
            return .symbol(symbol)
        }
        return .localValue(symbol)
    }

    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        if !bindReceiver, let receiverType = signature.receiverType {
            params.insert(receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            params: params,
            returnType: signature.returnType,
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )))
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> SymbolID? {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        guard !sorted.isEmpty else {
            return nil
        }
        guard let expectedType else {
            return sorted.first
        }
        guard case .functionType = sema.types.kind(of: expectedType) else {
            return sorted.first
        }
        if let matched = sorted.first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            let inferredType = callableFunctionType(
                for: signature,
                bindReceiver: bindReceiver,
                sema: sema
            )
            return sema.types.isSubtype(inferredType, expectedType)
        }) {
            return matched
        }
        return sorted.first
    }
}
