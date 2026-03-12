public struct VariableFlowState: Equatable {
    public var possibleTypes: Set<TypeID>
    public var nullability: Nullability
    public var isStable: Bool

    public init(possibleTypes: Set<TypeID>, nullability: Nullability, isStable: Bool) {
        self.possibleTypes = possibleTypes
        self.nullability = nullability
        self.isStable = isStable
    }
}

public struct DataFlowState: Equatable {
    public var variables: [SymbolID: VariableFlowState]

    public init(variables: [SymbolID: VariableFlowState] = [:]) {
        self.variables = variables
    }
}

public struct WhenBranchSummary {
    public let coveredSymbols: Set<InternedString>
    public let hasElse: Bool
    public let hasNullCase: Bool
    public let hasTrueCase: Bool
    public let hasFalseCase: Bool

    public init(
        coveredSymbols: Set<InternedString>,
        hasElse: Bool,
        hasNullCase: Bool = false,
        hasTrueCase: Bool? = nil,
        hasFalseCase: Bool? = nil
    ) {
        self.coveredSymbols = coveredSymbols
        self.hasElse = hasElse
        self.hasNullCase = hasNullCase
        self.hasTrueCase = hasTrueCase ?? coveredSymbols.contains(InternedString(rawValue: 1))
        self.hasFalseCase = hasFalseCase ?? coveredSymbols.contains(InternedString(rawValue: 2))
    }
}

public struct ConditionBranch: Equatable {
    public let trueState: DataFlowState
    public let falseState: DataFlowState

    public init(trueState: DataFlowState, falseState: DataFlowState) {
        self.trueState = trueState
        self.falseState = falseState
    }
}

public final class DataFlowAnalyzer {
    public init() {}

    public func branchOnCondition(
        _ conditionID: ExprID,
        base: DataFlowState,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        switch conditionExpr {
        case let .binary(op, lhsID, rhsID, _):
            return branchOnBinary(
                op: op, lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
        case let .unaryExpr(.not, operandID, _):
            let inner = branchOnCondition(
                operandID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            return ConditionBranch(trueState: inner.falseState, falseState: inner.trueState)
        case let .isCheck(exprID, typeRefID, negated, _):
            let branch = branchOnIsCheck(
                exprID: exprID, typeRefID: typeRefID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            if negated {
                return ConditionBranch(trueState: branch.falseState, falseState: branch.trueState)
            }
            return branch
        default:
            return ConditionBranch(trueState: base, falseState: base)
        }
    }

    private func branchOnBinary(
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        switch op {
        case .equal, .notEqual:
            let nullResult = branchOnNullComparison(
                lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            if let nullResult {
                if op == .notEqual {
                    return ConditionBranch(trueState: nullResult.falseState, falseState: nullResult.trueState)
                }
                return nullResult
            }
            return ConditionBranch(trueState: base, falseState: base)
        case .logicalAnd:
            let left = branchOnCondition(
                lhsID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let right = branchOnCondition(
                rhsID, base: left.trueState, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let trueState = right.trueState
            let falseState = merge(left.falseState, right.falseState)
            return ConditionBranch(trueState: trueState, falseState: falseState)
        case .logicalOr:
            let left = branchOnCondition(
                lhsID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let right = branchOnCondition(
                rhsID, base: left.falseState, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let trueState = merge(left.trueState, right.trueState)
            let falseState = right.falseState
            return ConditionBranch(trueState: trueState, falseState: falseState)
        default:
            return ConditionBranch(trueState: base, falseState: base)
        }
    }

    private func branchOnNullComparison(
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ConditionBranch? {
        let variableID: ExprID
        if isNullLiteral(rhsID, ast: ast, interner: interner) {
            variableID = lhsID
        } else if isNullLiteral(lhsID, ast: ast, interner: interner) {
            variableID = rhsID
        } else {
            return nil
        }
        guard let (symbol, currentType, isStable) = resolveLocalVariable(
            variableID, locals: locals, ast: ast, sema: sema, interner: interner
        ), isStable else {
            return nil
        }
        let effectiveType: TypeID = if let baseState = base.variables[symbol], baseState.possibleTypes.count == 1,
                                       let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        let nonNullType = makeTypeNonNullable(effectiveType, types: sema.types)
        var trueVars = base.variables
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [effectiveType],
            nullability: .nullable,
            isStable: true
        )
        var falseVars = base.variables
        falseVars[symbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return ConditionBranch(
            trueState: DataFlowState(variables: trueVars),
            falseState: DataFlowState(variables: falseVars)
        )
    }

    private func branchOnIsCheck(
        exprID: ExprID,
        typeRefID: TypeRefID,
        base: DataFlowState,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        guard let (symbol, currentType, isStable) = resolveLocalVariable(
            exprID, locals: locals, ast: ast, sema: sema, interner: interner
        ), isStable else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        guard let targetType = resolveIsCheckTargetType(
            typeRefID: typeRefID,
            scope: scope,
            ast: ast,
            sema: sema,
            interner: interner
        ) else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        let targetNullability = sema.types.nullability(of: targetType)
        // Use intersection with previous flow state type for chained is-checks (P5-97)
        let narrowedType: TypeID = if let baseState = base.variables[symbol],
                                      baseState.possibleTypes.count == 1,
                                      let existingType = baseState.possibleTypes.first
        {
            if sema.types.isSubtype(existingType, targetType) {
                // Existing flow type is already more specific; keep it.
                existingType
            } else if sema.types.isSubtype(targetType, existingType) {
                // New target type is more specific; use it.
                targetType
            } else {
                // Types are unrelated; intersect them for chained is-checks.
                sema.types.make(.intersection([existingType, targetType]))
            }
        } else {
            targetType
        }
        var trueVars = base.variables
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [narrowedType],
            nullability: targetNullability,
            isStable: true
        )
        let falseType: TypeID = if let baseState = base.variables[symbol], baseState.possibleTypes.count == 1,
                                   let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        var falseVars = base.variables
        falseVars[symbol] = VariableFlowState(
            possibleTypes: [falseType],
            nullability: base.variables[symbol]?.nullability ?? (makeTypeNonNullable(falseType, types: sema.types) != falseType ? .nullable : .nonNull),
            isStable: true
        )
        return ConditionBranch(
            trueState: DataFlowState(variables: trueVars),
            falseState: DataFlowState(variables: falseVars)
        )
    }

    public func branchOnWhenSubject(
        subjectSymbol: SymbolID,
        subjectType: TypeID,
        conditionID: ExprID,
        base: DataFlowState,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> DataFlowState {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return base
        }
        switch conditionExpr {
        case let .nameRef(name, _):
            if name == KnownCompilerNames(interner: interner).null {
                var vars = base.variables
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [subjectType],
                    nullability: .nullable,
                    isStable: true
                )
                return DataFlowState(variables: vars)
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID] else {
                return base
            }
            return narrowedStateForConditionSymbol(
                conditionSymbolID,
                subjectSymbol: subjectSymbol, subjectType: subjectType,
                base: base, sema: sema
            )
        case let .memberCall(_, _, _, args, _):
            guard args.isEmpty,
                  let conditionSymbolID = sema.bindings.identifierSymbols[conditionID]
            else {
                return base
            }
            return narrowedStateForConditionSymbol(
                conditionSymbolID,
                subjectSymbol: subjectSymbol, subjectType: subjectType,
                base: base, sema: sema
            )
        case .boolLiteral:
            if case .primitive(.boolean, _) = sema.types.kind(of: subjectType) {
                let narrowed = sema.types.make(.primitive(.boolean, .nonNull))
                var vars = base.variables
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [narrowed],
                    nullability: .nonNull,
                    isStable: true
                )
                return DataFlowState(variables: vars)
            }
            return base
        case let .isCheck(exprID, typeRefID, negated, _):
            return narrowedStateForIsCheck(
                exprID: exprID, typeRefID: typeRefID, negated: negated,
                subjectSymbol: subjectSymbol, conditionID: conditionID,
                base: base, ast: ast, sema: sema, interner: interner, scope: scope
            )
        default:
            return base
        }
    }

    private func narrowedStateForConditionSymbol(
        _ conditionSymbolID: SymbolID,
        subjectSymbol: SymbolID,
        subjectType: TypeID,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        guard let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
            return base
        }
        switch conditionSymbol.kind {
        case .field:
            guard let ownerID = enumOwnerSymbolID(for: conditionSymbol, symbols: sema.symbols),
                  nominalSymbolID(of: subjectType, types: sema.types) == ownerID
            else {
                return base
            }
            let narrowed = sema.types.make(.classType(ClassType(
                classSymbol: ownerID, args: [], nullability: .nonNull
            )))
            var vars = base.variables
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true
            )
            return DataFlowState(variables: vars)
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            guard let subjectNominal = nominalSymbolID(of: subjectType, types: sema.types),
                  isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols)
            else {
                return base
            }
            let narrowed = sema.types.make(.classType(ClassType(
                classSymbol: conditionSymbolID, args: [], nullability: .nonNull
            )))
            var vars = base.variables
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true
            )
            return DataFlowState(variables: vars)
        default:
            return base
        }
    }

    private func narrowedStateForIsCheck(
        exprID: ExprID,
        typeRefID: TypeRefID,
        negated: Bool,
        subjectSymbol: SymbolID,
        conditionID _: ExprID,
        base: DataFlowState,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> DataFlowState {
        // Only narrow when the isCheck's expr refers to the when subject.
        // This prevents incorrect narrowing for `when(x) { y is String -> ... }`.
        if let checkedSymbol = sema.bindings.identifierSymbols[exprID],
           checkedSymbol != subjectSymbol
        {
            return base
        }
        guard !negated else { return base }
        guard let narrowed = resolveIsCheckTargetType(
            typeRefID: typeRefID, scope: scope, ast: ast, sema: sema, interner: interner
        ) else {
            return base
        }
        let narrowedNullability = sema.types.nullability(of: narrowed)
        var vars = base.variables
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [narrowed], nullability: narrowedNullability, isStable: true
        )
        return DataFlowState(variables: vars)
    }

    public func whenElseState(
        subjectSymbol: SymbolID,
        subjectType: TypeID,
        hasExplicitNullBranch: Bool,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        guard hasExplicitNullBranch else {
            return base
        }
        let nonNullType = makeTypeNonNullable(subjectType, types: sema.types)
        var vars = base.variables
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return DataFlowState(variables: vars)
    }

    public func whenNonNullBranchState(
        subjectSymbol: SymbolID,
        subjectType: TypeID,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        let nonNullType = makeTypeNonNullable(subjectType, types: sema.types)
        var vars = base.variables
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return DataFlowState(variables: vars)
    }

    public func resolvedTypeFromFlowState(
        _ state: DataFlowState,
        symbol: SymbolID
    ) -> TypeID? {
        guard let flowState = state.variables[symbol],
              flowState.possibleTypes.count == 1,
              let narrowed = flowState.possibleTypes.first
        else {
            return nil
        }
        return narrowed
    }

    private func isNullLiteral(_ id: ExprID, ast: ASTModule, interner: StringInterner) -> Bool {
        guard let expr = ast.arena.expr(id),
              case let .nameRef(name, _) = expr
        else {
            return false
        }
        return name == KnownCompilerNames(interner: interner).null
    }

    private func resolveLocalVariable(
        _ id: ExprID,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> (symbol: SymbolID, type: TypeID, isStable: Bool)? {
        guard let expr = ast.arena.expr(id) else {
            return nil
        }
        let local: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)
        switch expr {
        case let .nameRef(name, _):
            guard let resolved = locals[name] else { return nil }
            local = resolved
        case let .thisRef(label, _) where label == nil:
            let thisName = interner.intern("this")
            guard let resolved = locals[thisName] else { return nil }
            local = resolved
        default:
            return nil
        }
        let isStable: Bool = if let symbol = sema.symbols.symbol(local.symbol) {
            switch symbol.kind {
            case .valueParameter, .local:
                !symbol.flags.contains(.mutable)
            default:
                false
            }
        } else {
            !local.isMutable
        }
        return (local.symbol, local.type, isStable)
    }

    private func makeTypeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nullable):
            types.anyType
        case let .primitive(primitive, .nullable):
            types.make(.primitive(primitive, .nonNull))
        case let .classType(classType) where classType.nullability == .nullable:
            types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nonNull
            )))
        case let .typeParam(typeParam) where typeParam.nullability == .nullable:
            types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nonNull
            )))
        case let .functionType(functionType) where functionType.nullability == .nullable:
            types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nonNull
            )))
        default:
            type
        }
    }

    private func nominalSymbolID(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case let .classType(classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }

    private func isNominalSubtype(
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

    private func enumOwnerSymbolID(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    /// Narrow a variable to non-null in the given flow state.
    /// Infrastructure for future smart cast call sites (e.g., property narrowing, when-subject exhaustive narrowing).
    public func narrowToNonNull(
        symbol: SymbolID,
        type: TypeID,
        base: DataFlowState,
        types: TypeSystem
    ) -> DataFlowState {
        let nonNullType = makeTypeNonNullable(type, types: types)
        var vars = base.variables
        vars[symbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return DataFlowState(variables: vars)
    }

    /// Invalidate (remove) smart cast information for a variable after reassignment.
    /// Infrastructure for future DataFlowState-level invalidation (locals-level invalidation is already handled
    /// by `inferLocalAssignExpr` resetting `locals[name]` to the declared type).
    public func invalidateVariable(
        symbol: SymbolID,
        base: DataFlowState
    ) -> DataFlowState {
        var vars = base.variables
        vars.removeValue(forKey: symbol)
        return DataFlowState(variables: vars)
    }

    public func merge(_ lhs: DataFlowState, _ rhs: DataFlowState) -> DataFlowState {
        var merged: [SymbolID: VariableFlowState] = [:]
        for (symbol, lhsState) in lhs.variables {
            guard let rhsState = rhs.variables[symbol] else { continue }
            let types = lhsState.possibleTypes.union(rhsState.possibleTypes)
            let nullability: Nullability = (lhsState.nullability == .nullable || rhsState.nullability == .nullable)
                ? .nullable
                : .nonNull
            merged[symbol] = VariableFlowState(
                possibleTypes: types,
                nullability: nullability,
                isStable: lhsState.isStable && rhsState.isStable
            )
        }
        return DataFlowState(variables: merged)
    }

    public func isWhenExhaustive(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        if branches.hasElse {
            return true
        }
        let kind = sema.types.kind(of: subjectType)
        switch kind {
        case .primitive(.boolean, .nonNull):
            return branches.hasTrueCase && branches.hasFalseCase
        case .primitive(.boolean, .nullable):
            return branches.hasTrueCase && branches.hasFalseCase && branches.hasNullCase
        case let .classType(classType):
            return isClassWhenExhaustive(
                classType: classType,
                branches: branches,
                sema: sema
            )
        case .any(.nullable):
            return false
        default:
            return false
        }
    }

    /// P5-78: Returns the set of missing sealed subtype InternedString names for diagnostic purposes.
    /// Returns nil if the type is not a sealed type or if all branches are covered.
    public func missingSealedBranches(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> [InternedString]? {
        if branches.hasElse {
            return nil
        }
        let kind = sema.types.kind(of: subjectType)
        guard case let .classType(classType) = kind else {
            return nil
        }
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol),
              classSymbol.flags.contains(.sealedType)
        else {
            return nil
        }
        let subtypeNames = sealedSubtypeNames(for: classSymbol, sema: sema)
        guard !subtypeNames.isEmpty else {
            return nil
        }
        let missing = subtypeNames.filter { !branches.coveredSymbols.contains($0) }
        guard !missing.isEmpty else {
            return nil
        }
        return Array(missing)
    }

    private func isClassWhenExhaustive(
        classType: ClassType,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }

        switch classSymbol.kind {
        case .enumClass:
            let enumEntryNames = enumEntryNames(for: classSymbol, sema: sema)
            guard !enumEntryNames.isEmpty else {
                return false
            }
            let hasAllEnumEntries = enumEntryNames.isSubset(of: branches.coveredSymbols)
            if classType.nullability == .nullable {
                return hasAllEnumEntries && branches.hasNullCase
            }
            return hasAllEnumEntries

        default:
            if classSymbol.flags.contains(.sealedType) {
                let subtypeNames = sealedSubtypeNames(for: classSymbol, sema: sema)
                guard !subtypeNames.isEmpty else {
                    return false
                }
                let hasAllSealedSubtypes = subtypeNames.isSubset(of: branches.coveredSymbols)
                if classType.nullability == .nullable {
                    return hasAllSealedSubtypes && branches.hasNullCase
                }
                return hasAllSealedSubtypes
            }
            return false
        }
    }

    /// P5-78: Get sealed subtype names, using sealedSubclasses metadata for cross-module support,
    /// falling back to directSubtypes for same-module sealed types.
    private func sealedSubtypeNames(for classSymbol: SemanticSymbol, sema: SemaModule) -> Set<InternedString> {
        // First try sealedSubclasses (populated from metadata for cross-module)
        if let sealedSubs = sema.symbols.sealedSubclasses(for: classSymbol.id) {
            return Set(sealedSubs.compactMap { sema.symbols.symbol($0)?.name })
        }
        // Fall back to directSubtypes (same-module)
        return Set(sema.symbols.directSubtypes(of: classSymbol.id).compactMap { subtype in
            sema.symbols.symbol(subtype)?.name
        })
    }

    /// Resolve TypeArgRef array into TypeArg array, mapping builtin type names to their TypeIDs.
    /// Shared by branchOnIsCheck and branchOnWhenSubject for consistent generic type arg resolution (P5-101).
    private func resolveIsCheckTargetType(
        typeRefID: TypeRefID,
        scope: Scope,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let typeRef = ast.arena.typeRef(typeRefID),
              case let .named(path, argRefs, nullable) = typeRef,
              let shortName = path.last
        else {
            return nil
        }

        let nullability: Nullability = nullable ? .nullable : .nonNull
        if path.count == 1,
           let typeParameterSymbol = resolveTypeParameterSymbol(shortName, scope: scope, sema: sema),
           let typeParameter = sema.symbols.symbol(typeParameterSymbol),
           typeParameter.flags.contains(.reifiedTypeParameter)
        {
            return sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: nullability)))
        }

        let targetName = interner.resolve(shortName)
        if let primitiveType = resolveBuiltinTypeName(targetName, types: sema.types) {
            return nullability == .nullable ? sema.types.makeNullable(primitiveType) : primitiveType
        }

        let candidates: [SymbolID] = {
            let fqCandidates = sema.symbols.lookupAll(fqName: path).filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                switch sym.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            if !fqCandidates.isEmpty {
                return fqCandidates
            }
            return resolveNominalCandidates(forName: shortName, sema: sema)
        }()
        guard let targetSymbolID = candidates.first else {
            return nil
        }
        let resolvedArgs: [TypeArg] = resolveTypeArgRefs(argRefs, ast: ast, interner: interner, types: sema.types)
        return sema.types.make(.classType(ClassType(
            classSymbol: targetSymbolID,
            args: resolvedArgs,
            nullability: nullability
        )))
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

    private func resolveTypeArgRefs(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        interner: StringInterner,
        types: TypeSystem
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case let .invariant(innerRef):
                guard let inner = ast.arena.typeRef(innerRef),
                      case let .named(innerPath, _, innerNullable) = inner,
                      let innerFirst = innerPath.first
                else {
                    return .star
                }
                let innerName = interner.resolve(innerFirst)
                if let builtin = resolveBuiltinTypeName(innerName, types: types) {
                    let resolved = innerNullable ? types.makeNullable(builtin) : builtin
                    return .invariant(resolved)
                }
                return .star
            case let .out(innerRef):
                guard let inner = ast.arena.typeRef(innerRef),
                      case let .named(innerPath, _, innerNullable) = inner,
                      let innerFirst = innerPath.first
                else {
                    return .star
                }
                let innerName = interner.resolve(innerFirst)
                if let builtin = resolveBuiltinTypeName(innerName, types: types) {
                    let resolved = innerNullable ? types.makeNullable(builtin) : builtin
                    return .out(resolved)
                }
                return .star
            case let .in(innerRef):
                guard let inner = ast.arena.typeRef(innerRef),
                      case let .named(innerPath, _, innerNullable) = inner,
                      let innerFirst = innerPath.first
                else {
                    return .star
                }
                let innerName = interner.resolve(innerFirst)
                if let builtin = resolveBuiltinTypeName(innerName, types: types) {
                    let resolved = innerNullable ? types.makeNullable(builtin) : builtin
                    return .in(resolved)
                }
                return .star
            case .star:
                return .star
            }
        }
    }

    private func resolveNominalCandidates(forName name: InternedString, sema: SemaModule) -> [SymbolID] {
        func isNominalOrAlias(_ symbolID: SymbolID) -> Bool {
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            switch sym.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias: return true
            default: return false
            }
        }
        let fqCandidates = sema.symbols.lookupAll(fqName: [name])
            .filter { isNominalOrAlias($0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
        if !fqCandidates.isEmpty { return fqCandidates }
        return sema.symbols.lookupByShortName(name)
            .filter { isNominalOrAlias($0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
    }

    private func resolveBuiltinTypeName(_ name: String, types: TypeSystem) -> TypeID? {
        switch name {
        case "Byte": types.intType
        case "Short": types.intType
        case "Int": types.intType
        case "Long": types.longType
        case "Float": types.floatType
        case "Double": types.doubleType
        case "Boolean": types.booleanType
        case "Char": types.charType
        case "String": types.stringType
        case "UInt": types.uintType
        case "ULong": types.ulongType
        case "UByte": types.ubyteType
        case "UShort": types.ushortType
        case "Any": types.anyType
        case "Unit": types.unitType
        case "Nothing": types.nothingType
        default: nil
        }
    }

    private func enumEntryNames(for enumSymbol: SemanticSymbol, sema: SemaModule) -> Set<InternedString> {
        let childIDs = sema.symbols.children(ofFQName: enumSymbol.fqName)
        var names: Set<InternedString> = []
        for childID in childIDs {
            guard let child = sema.symbols.symbol(childID),
                  child.kind == .field
            else {
                continue
            }
            names.insert(child.name)
        }
        return names
    }
}
