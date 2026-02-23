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
        interner: StringInterner
    ) -> ConditionBranch {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        switch conditionExpr {
        case .binary(let op, let lhsID, let rhsID, _):
            return branchOnBinary(
                op: op, lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
        case .unaryExpr(.not, let operandID, _):
            let inner = branchOnCondition(
                operandID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            return ConditionBranch(trueState: inner.falseState, falseState: inner.trueState)
        case .isCheck(let exprID, let typeRefID, let negated, _):
            let branch = branchOnIsCheck(
                exprID: exprID, typeRefID: typeRefID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
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
        interner: StringInterner
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
                ast: ast, sema: sema, interner: interner
            )
            let right = branchOnCondition(
                rhsID, base: left.trueState, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            let trueState = right.trueState
            let falseState = merge(left.falseState, right.falseState)
            return ConditionBranch(trueState: trueState, falseState: falseState)
        case .logicalOr:
            let left = branchOnCondition(
                lhsID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            let right = branchOnCondition(
                rhsID, base: left.falseState, locals: locals,
                ast: ast, sema: sema, interner: interner
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
        let effectiveType: TypeID
        if let baseState = base.variables[symbol], baseState.possibleTypes.count == 1,
           let baseType = baseState.possibleTypes.first {
            effectiveType = baseType
        } else {
            effectiveType = currentType
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
        interner: StringInterner
    ) -> ConditionBranch {
        guard let (symbol, currentType, isStable) = resolveLocalVariable(
            exprID, locals: locals, ast: ast, sema: sema, interner: interner
        ), isStable else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        guard let typeRef = ast.arena.typeRef(typeRefID),
              case .named(let path, _, let nullable) = typeRef,
              let firstName = path.first else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        let candidates = sema.symbols.lookupAll(fqName: [firstName]).filter { symbolID in
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            switch sym.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                return true
            default:
                return false
            }
        }
        guard let targetSymbolID = candidates.first else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        let narrowedType = sema.types.make(.classType(ClassType(
            classSymbol: targetSymbolID,
            args: [],
            nullability: nullable ? .nullable : .nonNull
        )))
        var trueVars = base.variables
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [narrowedType],
            nullability: nullable ? .nullable : .nonNull,
            isStable: true
        )
        let falseType: TypeID
        if let baseState = base.variables[symbol], baseState.possibleTypes.count == 1,
           let baseType = baseState.possibleTypes.first {
            falseType = baseType
        } else {
            falseType = currentType
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
        interner: StringInterner
    ) -> DataFlowState {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return base
        }
        switch conditionExpr {
        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                var vars = base.variables
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [subjectType],
                    nullability: .nullable,
                    isStable: true
                )
                return DataFlowState(variables: vars)
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return base
            }
            switch conditionSymbol.kind {
            case .field:
                guard let ownerID = enumOwnerSymbolID(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbolID(of: subjectType, types: sema.types) == ownerID else {
                    return base
                }
                let narrowed = sema.types.make(.classType(ClassType(
                    classSymbol: ownerID,
                    args: [],
                    nullability: .nonNull
                )))
                var vars = base.variables
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [narrowed],
                    nullability: .nonNull,
                    isStable: true
                )
                return DataFlowState(variables: vars)
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbolID(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
                    return base
                }
                let narrowed = sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))
                var vars = base.variables
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [narrowed],
                    nullability: .nonNull,
                    isStable: true
                )
                return DataFlowState(variables: vars)
            default:
                return base
            }
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
        case .isCheck(_, let typeRefID, let negated, _):
            guard !negated else {
                return base
            }
            guard let typeRef = ast.arena.typeRef(typeRefID),
                  case .named(let path, _, let nullable) = typeRef,
                  let firstName = path.first else {
                return base
            }
            let candidates = sema.symbols.lookupAll(fqName: [firstName]).filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                switch sym.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            guard let targetSymbolID = candidates.first else {
                return base
            }
            let narrowed = sema.types.make(.classType(ClassType(
                classSymbol: targetSymbolID,
                args: [],
                nullability: nullable ? .nullable : .nonNull
            )))
            var vars = base.variables
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed],
                nullability: nullable ? .nullable : .nonNull,
                isStable: true
            )
            return DataFlowState(variables: vars)
        default:
            return base
        }
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
              let narrowed = flowState.possibleTypes.first else {
            return nil
        }
        return narrowed
    }

    private func isNullLiteral(_ id: ExprID, ast: ASTModule, interner: StringInterner) -> Bool {
        guard let expr = ast.arena.expr(id),
              case .nameRef(let name, _) = expr else {
            return false
        }
        return interner.resolve(name) == "null"
    }

    private func resolveLocalVariable(
        _ id: ExprID,
        locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> (symbol: SymbolID, type: TypeID, isStable: Bool)? {
        guard let expr = ast.arena.expr(id),
              case .nameRef(let name, _) = expr,
              let local = locals[name] else {
            return nil
        }
        guard let symbol = sema.symbols.symbol(local.symbol) else {
            return nil
        }
        let isStable: Bool
        switch symbol.kind {
        case .valueParameter, .local:
            isStable = !symbol.flags.contains(.mutable)
        default:
            isStable = false
        }
        return (local.symbol, local.type, isStable)
    }

    private func makeTypeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nullable):
            return types.anyType
        case .primitive(let primitive, .nullable):
            return types.make(.primitive(primitive, .nonNull))
        case .classType(let classType) where classType.nullability == .nullable:
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nonNull
            )))
        case .typeParam(let typeParam) where typeParam.nullability == .nullable:
            return types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nonNull
            )))
        case .functionType(let functionType) where functionType.nullability == .nullable:
            return types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nonNull
            )))
        default:
            return type
        }
    }

    private func nominalSymbolID(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case .classType(let classType) = types.kind(of: type) {
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
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    /// Narrow a variable to non-null in the given flow state.
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
        case .classType(let classType):
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
                let subtypeNames = Set(sema.symbols.directSubtypes(of: classSymbol.id).compactMap { subtype in
                    sema.symbols.symbol(subtype)?.name
                })
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

    private func enumEntryNames(for enumSymbol: SemanticSymbol, sema: SemaModule) -> Set<InternedString> {
        let enumFQName = enumSymbol.fqName
        let expectedCount = enumFQName.count + 1
        let entries = sema.symbols.allSymbols().filter { symbol in
            guard symbol.kind == .field else {
                return false
            }
            guard symbol.fqName.count == expectedCount else {
                return false
            }
            return Array(symbol.fqName.dropLast()) == enumFQName
        }
        return Set(entries.map(\.name))
    }
}
