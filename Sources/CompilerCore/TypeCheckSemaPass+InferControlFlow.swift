import Foundation

extension TypeCheckSemaPassPhase {
    func inferForExpr(
        _ id: ExprID,
        loopVariable: InternedString?,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let sema = ctx.sema
        let iterableType = inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        var bodyLocals = locals
        if let loopVariable {
            let elementType = arrayElementType(for: iterableType, sema: sema, interner: ctx.interner) ?? sema.types.anyType
            let loopVariableSymbol = sema.symbols.define(
                kind: .local,
                name: loopVariable,
                fqName: [
                    ctx.interner.intern("__for_\(id.rawValue)"),
                    loopVariable
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            bodyLocals[loopVariable] = (elementType, loopVariableSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: loopVariableSymbol)
        }
        _ = inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1),
            locals: &bodyLocals,
            expectedType: nil
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferWhileExpr(
        _ id: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let conditionType = inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
        emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        var bodyLocals = locals
        _ = inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1),
            locals: &bodyLocals,
            expectedType: nil
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferDoWhileExpr(
        _ id: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        var bodyLocals = locals
        _ = inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1),
            locals: &bodyLocals,
            expectedType: nil
        )
        let conditionType = inferExpr(conditionExpr, ctx: ctx, locals: &bodyLocals, expectedType: boolType)
        emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        for (name, local) in locals {
            if !local.isInitialized,
               let bodyLocal = bodyLocals[name], bodyLocal.isInitialized,
               bodyLocal.symbol == local.symbol {
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferIfExpr(
        _ id: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let conditionType = inferExpr(condition, ctx: ctx, locals: &locals)
        if conditionType != boolType {
            emitSubtypeConstraint(
                left: conditionType,
                right: boolType,
                range: ast.arena.exprRange(condition),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        let branch = ctx.dataFlow.branchOnCondition(
            condition, base: ctx.flowState, locals: locals,
            ast: ast, sema: sema, interner: interner
        )
        var thenLocals = locals
        applyFlowStateToLocals(branch.trueState, locals: &thenLocals, sema: sema)
        let thenCtx = ctx.copying(flowState: branch.trueState)
        let thenType = inferExpr(thenExpr, ctx: thenCtx, locals: &thenLocals, expectedType: expectedType)
        let resolvedType: TypeID
        if let elseExpr {
            var elseLocals = locals
            applyFlowStateToLocals(branch.falseState, locals: &elseLocals, sema: sema)
            let elseCtx = ctx.copying(flowState: branch.falseState)
            let elseType = inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
            resolvedType = sema.types.lub([thenType, elseType])
            for (name, local) in locals {
                if !local.isInitialized,
                   let thenLocal = thenLocals[name], thenLocal.isInitialized,
                   thenLocal.symbol == local.symbol,
                   let elseLocal = elseLocals[name], elseLocal.isInitialized,
                   elseLocal.symbol == local.symbol {
                    locals[name] = (local.type, local.symbol, local.isMutable, true)
                }
            }
        } else {
            resolvedType = sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    func inferTryExpr(
        _ id: ExprID,
        body: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        var branchTypes: [TypeID] = []
        // Use a separate copy for the try body so that initialization state
        // from inside the try block doesn't leak into catch clauses. The try
        // body may throw before reaching an initialization, so catch clauses
        // must see the pre-try state of locals.
        var tryBodyLocals = locals
        branchTypes.append(inferExpr(body, ctx: ctx, locals: &tryBodyLocals, expectedType: expectedType))
        for (index, clause) in catchClauses.enumerated() {
            var catchLocals = locals
            let catchParamType = resolveCatchClauseParameterType(
                clause.paramTypeName,
                sema: sema,
                interner: interner
            )
            var catchParamSymbol = SymbolID.invalid
            if let paramName = clause.paramName {
                catchParamSymbol = sema.symbols.define(
                    kind: .local,
                    name: paramName,
                    fqName: [
                        interner.intern("__try_\(id.rawValue)_catch_\(index)"),
                        paramName
                    ],
                    declSite: clause.range,
                    visibility: .internal
                )
                sema.symbols.setPropertyType(catchParamType, for: catchParamSymbol)
                catchLocals[paramName] = (catchParamType, catchParamSymbol, false, true)
                // Keep legacy binding for lowering while explicit catch bindings are adopted.
                sema.bindings.bindIdentifier(clause.body, symbol: catchParamSymbol)
            }
            sema.bindings.bindCatchClause(
                clause.body,
                binding: CatchClauseBinding(parameterSymbol: catchParamSymbol, parameterType: catchParamType)
            )
            branchTypes.append(inferExpr(clause.body, ctx: ctx, locals: &catchLocals, expectedType: expectedType))
        }
        if let finallyExpr {
            _ = inferExpr(finallyExpr, ctx: ctx, locals: &locals, expectedType: nil)
        }
        let resolvedType = sema.types.lub(branchTypes)
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveCatchClauseParameterType(
        _ typeName: InternedString?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let typeName else {
            return sema.types.anyType
        }
        switch interner.resolve(typeName) {
        case "Int":
            return sema.types.make(.primitive(.int, .nonNull))
        case "Long":
            return sema.types.make(.primitive(.long, .nonNull))
        case "Float":
            return sema.types.make(.primitive(.float, .nonNull))
        case "Double":
            return sema.types.make(.primitive(.double, .nonNull))
        case "Boolean":
            return sema.types.make(.primitive(.boolean, .nonNull))
        case "Char":
            return sema.types.make(.primitive(.char, .nonNull))
        case "String":
            return sema.types.make(.primitive(.string, .nonNull))
        case "Any":
            return sema.types.anyType
        case "Unit":
            return sema.types.unitType
        case "Nothing":
            return sema.types.nothingType
        default:
            let candidates = sema.symbols.lookupAll(fqName: [typeName])
                .filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                .sorted { $0.rawValue < $1.rawValue }
            guard let symbol = candidates.first else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        }
    }

    func inferWhenExpr(
        _ id: ExprID,
        subjectID: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        if let subjectID {
            let subjectType = inferExpr(subjectID, ctx: ctx, locals: &locals)
            let subjectLocalBinding: (name: InternedString, type: TypeID, symbol: SymbolID, isStable: Bool, isMutable: Bool)? = {
                guard let subjectExpr = ast.arena.expr(subjectID),
                      case .nameRef(let subjectName, _) = subjectExpr,
                      let local = locals[subjectName] else {
                    return nil
                }
                return (
                    subjectName, local.type, local.symbol,
                    isStableLocalSymbol(local.symbol, sema: sema),
                    local.isMutable
                )
            }()
            let hasExplicitNullBranch = branches.contains { branch in
                guard let condition = branch.condition,
                      let conditionExpr = ast.arena.expr(condition),
                      case .nameRef(let name, _) = conditionExpr else {
                    return false
                }
                return interner.resolve(name) == "null"
            }
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            var hasNullCase = false
            var hasTrueCase = false
            var hasFalseCase = false
            var allBranchLocals: [[InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]] = []
            for branch in branches {
                var isNullBranch = false
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ctx: ctx, locals: &locals)
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            if condType == boolType { hasTrueCase = true }
                            covered.insert(interner.intern("true"))
                        case .boolLiteral(false, _):
                            if condType == boolType { hasFalseCase = true }
                            covered.insert(interner.intern("false"))
                        case .nameRef(let name, _):
                            if interner.resolve(name) == "null" {
                                hasNullCase = true
                                isNullBranch = true
                            } else {
                                covered.insert(name)
                            }
                        default:
                            break
                        }
                    }
                }
                var branchLocals = locals
                var branchCtx = ctx
                if let subjectLocalBinding, subjectLocalBinding.isStable {
                    if let cond = branch.condition {
                        let branchFlowState = ctx.dataFlow.branchOnWhenSubject(
                            subjectSymbol: subjectLocalBinding.symbol,
                            subjectType: subjectType,
                            conditionID: cond,
                            base: ctx.flowState,
                            ast: ast, sema: sema, interner: interner
                        )
                        branchCtx = ctx.copying(flowState: branchFlowState)
                        if let narrowedType = ctx.dataFlow.resolvedTypeFromFlowState(
                            branchFlowState, symbol: subjectLocalBinding.symbol
                        ) {
                            branchLocals[subjectLocalBinding.name] = (
                                narrowedType, subjectLocalBinding.symbol, subjectLocalBinding.isMutable, true
                            )
                        } else if hasExplicitNullBranch && !isNullBranch {
                            let nonNullState = ctx.dataFlow.whenNonNullBranchState(
                                subjectSymbol: subjectLocalBinding.symbol,
                                subjectType: subjectLocalBinding.type,
                                base: ctx.flowState, sema: sema
                            )
                            branchCtx = ctx.copying(flowState: nonNullState)
                            applyFlowStateToLocals(nonNullState, locals: &branchLocals, sema: sema)
                        }
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType)
                )
                allBranchLocals.append(branchLocals)
            }

            if let elseExpr {
                var elseLocals = locals
                var elseCtx = ctx
                if let subjectLocalBinding, subjectLocalBinding.isStable, hasExplicitNullBranch {
                    let elseFlowState = ctx.dataFlow.whenElseState(
                        subjectSymbol: subjectLocalBinding.symbol,
                        subjectType: subjectLocalBinding.type,
                        hasExplicitNullBranch: hasExplicitNullBranch,
                        base: ctx.flowState, sema: sema
                    )
                    elseCtx = ctx.copying(flowState: elseFlowState)
                    applyFlowStateToLocals(elseFlowState, locals: &elseLocals, sema: sema)
                }
                branchTypes.append(
                    inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
                )
                allBranchLocals.append(elseLocals)
            }

            let summary = WhenBranchSummary(
                coveredSymbols: covered, hasElse: elseExpr != nil,
                hasNullCase: hasNullCase, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            let isExhaustive = ctx.dataFlow.isWhenExhaustive(subjectType: subjectType, branches: summary, sema: sema)
            if !isExhaustive {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            // Propagate definite initialization across exhaustive when branches.
            if isExhaustive && !allBranchLocals.isEmpty {
                for (name, local) in locals {
                    if !local.isInitialized {
                        let allInit = allBranchLocals.allSatisfy { branchLocal in
                            guard let bl = branchLocal[name] else { return false }
                            return bl.isInitialized && bl.symbol == local.symbol
                        }
                        if allInit {
                            locals[name] = (local.type, local.symbol, local.isMutable, true)
                        }
                    }
                }
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        } else {
            var branchTypes: [TypeID] = []
            var allBranchLocals: [[InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]] = []
            var hasTrueCase = false
            var hasFalseCase = false
            var cumulativeFalseState = ctx.flowState
            for branch in branches {
                var branchLocals = locals
                let condCtx = ctx.copying(flowState: cumulativeFalseState)
                applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
                var branchCtx = condCtx
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ctx: condCtx, locals: &branchLocals)
                    if condType != boolType && condType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0032",
                            "Subject-less when branch condition must be a Boolean expression.",
                            range: branch.range
                        )
                    }
                    let condBranch = ctx.dataFlow.branchOnCondition(
                        cond, base: cumulativeFalseState, locals: branchLocals,
                        ast: ast, sema: sema, interner: interner
                    )
                    branchCtx = ctx.copying(flowState: condBranch.trueState)
                    applyFlowStateToLocals(condBranch.trueState, locals: &branchLocals, sema: sema)
                    cumulativeFalseState = condBranch.falseState
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            hasTrueCase = true
                        case .boolLiteral(false, _):
                            hasFalseCase = true
                        default:
                            break
                        }
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType)
                )
                allBranchLocals.append(branchLocals)
            }

            if let elseExpr {
                var elseLocals = locals
                let elseCtx = ctx.copying(flowState: cumulativeFalseState)
                applyFlowStateToLocals(cumulativeFalseState, locals: &elseLocals, sema: sema)
                branchTypes.append(
                    inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
                )
                allBranchLocals.append(elseLocals)
            }

            let summary = WhenBranchSummary(
                coveredSymbols: [], hasElse: elseExpr != nil,
                hasNullCase: false, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            let isExhaustive = ctx.dataFlow.isWhenExhaustive(subjectType: boolType, branches: summary, sema: sema)
            if !isExhaustive {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            // Propagate definite initialization across exhaustive when branches.
            if isExhaustive && !allBranchLocals.isEmpty {
                for (name, local) in locals {
                    if !local.isInitialized {
                        let allInit = allBranchLocals.allSatisfy { branchLocal in
                            guard let bl = branchLocal[name] else { return false }
                            return bl.isInitialized && bl.symbol == local.symbol
                        }
                        if allInit {
                            locals[name] = (local.type, local.symbol, local.isMutable, true)
                        }
                    }
                }
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        }
    }

    func inferLocalFunDeclExpr(
        _ id: ExprID,
        name: InternedString,
        valueParams: [ValueParamDecl],
        returnTypeRef: TypeRefID?,
        body: FunctionBody,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var parameterTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in valueParams {
            let paramType: TypeID
            if let typeRefID = param.type {
                paramType = resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } else {
                paramType = sema.types.anyType
            }
            parameterTypes.append(paramType)
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: param.name,
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    param.name
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let resolvedReturnType: TypeID
        if let returnTypeRef {
            resolvedReturnType = resolveTypeRef(returnTypeRef, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            resolvedReturnType = sema.types.unitType
        }

        let funSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: [
                interner.intern("__localfun_\(id.rawValue)"),
                name
            ],
            declSite: range,
            visibility: .private,
            flags: []
        )

        let signature = FunctionSignature(
            parameterTypes: parameterTypes,
            returnType: resolvedReturnType,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: valueParams.map { $0.hasDefaultValue },
            valueParameterIsVararg: valueParams.map { $0.isVararg }
        )
        sema.symbols.setFunctionSignature(signature, for: funSymbol)

        let funType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))

        var bodyLocals = locals
        for (i, param) in valueParams.enumerated() {
            bodyLocals[param.name] = (parameterTypes[i], paramSymbols[i], false, true)
        }
        bodyLocals[name] = (funType, funSymbol, false, true)
        switch body {
        case .block(let exprs, _):
            for (index, expr) in exprs.enumerated() {
                let isLast = index == exprs.count - 1
                let expected = isLast ? resolvedReturnType : nil
                _ = inferExpr(expr, ctx: ctx, locals: &bodyLocals, expectedType: expected)
            }
        case .expr(let exprID, _):
            _ = inferExpr(exprID, ctx: ctx, locals: &bodyLocals, expectedType: resolvedReturnType)
        case .unit:
            break
        }
        locals[name] = (funType, funSymbol, false, true)
        sema.bindings.bindIdentifier(id, symbol: funSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
