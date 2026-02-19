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
            ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
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
            ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
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
            ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
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
        var thenLocals = locals
        let thenType = inferExpr(thenExpr, ctx: ctx, locals: &thenLocals, expectedType: expectedType)
        let resolvedType: TypeID
        if let elseExpr {
            var elseLocals = locals
            let elseType = inferExpr(elseExpr, ctx: ctx, locals: &elseLocals, expectedType: expectedType)
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
        var branchTypes: [TypeID] = []
        branchTypes.append(inferExpr(body, ctx: ctx, locals: &locals, expectedType: expectedType))
        for clause in catchClauses {
            var catchLocals = locals
            if let paramName = clause.paramName {
                let catchParamSymbol = sema.symbols.define(
                    kind: .local,
                    name: paramName,
                    fqName: [paramName],
                    declSite: clause.range,
                    visibility: .internal
                )
                sema.symbols.setPropertyType(sema.types.anyType, for: catchParamSymbol)
                catchLocals[paramName] = (sema.types.anyType, catchParamSymbol, false, true)
                sema.bindings.bindIdentifier(clause.body, symbol: catchParamSymbol)
            }
            branchTypes.append(inferExpr(clause.body, ctx: ctx, locals: &catchLocals, expectedType: expectedType))
        }
        if let finallyExpr {
            _ = inferExpr(finallyExpr, ctx: ctx, locals: &locals, expectedType: nil)
        }
        let resolvedType = sema.types.lub(branchTypes)
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
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
            for branch in branches {
                var isNullBranch = false
                var branchSmartCastType: TypeID?
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
                    branchSmartCastType = smartCastTypeForWhenSubjectCase(
                        conditionID: cond, subjectType: subjectType,
                        ast: ast, sema: sema, interner: interner
                    )
                }
                var branchLocals = locals
                if let subjectLocalBinding, subjectLocalBinding.isStable {
                    if let branchSmartCastType {
                        branchLocals[subjectLocalBinding.name] = (
                            branchSmartCastType, subjectLocalBinding.symbol, subjectLocalBinding.isMutable, true
                        )
                    } else if hasExplicitNullBranch && !isNullBranch {
                        branchLocals[subjectLocalBinding.name] = (
                            makeNonNullable(subjectLocalBinding.type, types: sema.types),
                            subjectLocalBinding.symbol,
                            subjectLocalBinding.isMutable, true
                        )
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ctx: ctx, locals: &branchLocals, expectedType: expectedType)
                )
            }

            if let elseExpr {
                var elseLocals = locals
                if let subjectLocalBinding,
                   subjectLocalBinding.isStable,
                   hasExplicitNullBranch {
                    elseLocals[subjectLocalBinding.name] = (
                        makeNonNullable(subjectLocalBinding.type, types: sema.types),
                        subjectLocalBinding.symbol,
                        subjectLocalBinding.isMutable, true
                    )
                }
                branchTypes.append(
                    inferExpr(elseExpr, ctx: ctx, locals: &elseLocals, expectedType: expectedType)
                )
            }

            let summary = WhenBranchSummary(
                coveredSymbols: covered, hasElse: elseExpr != nil,
                hasNullCase: hasNullCase, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            if !ctx.dataFlow.isWhenExhaustive(subjectType: subjectType, branches: summary, sema: sema) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        } else {
            var branchTypes: [TypeID] = []
            for branch in branches {
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ctx: ctx, locals: &locals)
                    if condType != boolType && condType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0032",
                            "Subject-less when branch condition must be a Boolean expression.",
                            range: branch.range
                        )
                    }
                }
                var branchLocals = locals
                branchTypes.append(
                    inferExpr(branch.body, ctx: ctx, locals: &branchLocals, expectedType: expectedType)
                )
            }

            if let elseExpr {
                var elseLocals = locals
                branchTypes.append(
                    inferExpr(elseExpr, ctx: ctx, locals: &elseLocals, expectedType: expectedType)
                )
            }

            let summary = WhenBranchSummary(
                coveredSymbols: [], hasElse: elseExpr != nil,
                hasNullCase: false, hasTrueCase: false,
                hasFalseCase: false
            )
            if !ctx.dataFlow.isWhenExhaustive(subjectType: boolType, branches: summary, sema: sema) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
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
                paramType = resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner)
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
            resolvedReturnType = resolveTypeRef(returnTypeRef, ast: ast, sema: sema, interner: interner)
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
