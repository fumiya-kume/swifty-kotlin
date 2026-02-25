import Foundation

/// Handles control flow expression type inference (for, while, do-while, if, try, when).
/// Derived from TypeCheckSemaPass+InferControlFlow.swift.
final class ControlFlowTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferForExpr(
        _ id: ExprID,
        loopVariable: InternedString?,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        var bodyLocals = locals
        if let loopVariable {
            let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
            let elementType = driver.helpers.iterableElementType(for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: ctx.interner) ?? sema.types.anyType
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
        var loopCtx = ctx.copying(loopDepth: ctx.loopDepth + 1)
        if let userLabel = ctx.ast.arena.loopLabel(for: id) {
            loopCtx = loopCtx.withLoopLabel(userLabel)
        }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: loopCtx,
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
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        let conditionType = driver.inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
        driver.emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        // Smart cast: apply condition branching to the while body (P5-66)
        let branch = ctx.dataFlow.branchOnCondition(
            conditionExpr, base: ctx.flowState, locals: locals,
            ast: ast, sema: sema, interner: interner
        )
        var bodyLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &bodyLocals, sema: sema)
        var bodyCtx = ctx.copying(loopDepth: ctx.loopDepth + 1, flowState: branch.trueState)
        if let userLabel = ctx.ast.arena.loopLabel(for: id) {
            bodyCtx = bodyCtx.withLoopLabel(userLabel)
        }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
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
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.booleanType
        var bodyLocals = locals
        var loopCtx = ctx.copying(loopDepth: ctx.loopDepth + 1)
        if let userLabel = ctx.ast.arena.loopLabel(for: id) {
            loopCtx = loopCtx.withLoopLabel(userLabel)
        }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: loopCtx,
            locals: &bodyLocals,
            expectedType: nil
        )
        let conditionType = driver.inferExpr(conditionExpr, ctx: ctx, locals: &bodyLocals, expectedType: boolType)
        driver.emitSubtypeConstraint(
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
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        let conditionType = driver.inferExpr(condition, ctx: ctx, locals: &locals)
        if conditionType != boolType {
            driver.emitSubtypeConstraint(
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
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &thenLocals, sema: sema)
        let thenCtx = ctx.copying(flowState: branch.trueState)
        let thenType = driver.inferExpr(thenExpr, ctx: thenCtx, locals: &thenLocals, expectedType: expectedType)
        let resolvedType: TypeID
        if let elseExpr {
            var elseLocals = locals
            driver.exprChecker.applyFlowStateToLocals(branch.falseState, locals: &elseLocals, sema: sema)
            let elseCtx = ctx.copying(flowState: branch.falseState)
            let elseType = driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
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
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        var branchTypes: [TypeID] = []
        var tryBodyLocals = locals
        branchTypes.append(driver.inferExpr(body, ctx: ctx, locals: &tryBodyLocals, expectedType: expectedType))
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
                sema.bindings.bindIdentifier(clause.body, symbol: catchParamSymbol)
            }
            sema.bindings.bindCatchClause(
                clause.body,
                binding: CatchClauseBinding(parameterSymbol: catchParamSymbol, parameterType: catchParamType)
            )
            branchTypes.append(driver.inferExpr(clause.body, ctx: ctx, locals: &catchLocals, expectedType: expectedType))
        }
        if let finallyExpr {
            _ = driver.inferExpr(finallyExpr, ctx: ctx, locals: &locals, expectedType: nil)
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
        let name = interner.resolve(typeName)
        if let builtin = driver.helpers.resolveBuiltinTypeName(name, types: sema.types) {
            return builtin
        }
        let candidates = sema.symbols.lookupAll(fqName: [typeName])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
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

    func inferWhenExpr(
        _ id: ExprID,
        subjectID: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType

        if let subjectID {
            let subjectType = driver.inferExpr(subjectID, ctx: ctx, locals: &locals)
            let subjectLocalBinding: (name: InternedString, type: TypeID, symbol: SymbolID, isStable: Bool, isMutable: Bool)? = {
                guard let subjectExpr = ast.arena.expr(subjectID),
                      case .nameRef(let subjectName, _) = subjectExpr,
                      let local = locals[subjectName] else {
                    return nil
                }
                return (
                    subjectName, local.type, local.symbol,
                    driver.helpers.isStableLocalSymbol(local.symbol, sema: sema),
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
            var allBranchLocals: [LocalBindings] = []
            for branch in branches {
                var isNullBranch = false
                if let cond = branch.condition {
                    let condType = driver.inferExpr(cond, ctx: ctx, locals: &locals)
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
                            driver.exprChecker.applyFlowStateToLocals(nonNullState, locals: &branchLocals, sema: sema)
                        }
                    }
                }
                branchTypes.append(
                    driver.inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType)
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
                    driver.exprChecker.applyFlowStateToLocals(elseFlowState, locals: &elseLocals, sema: sema)
                }
                branchTypes.append(
                    driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
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
                // P5-78: enhanced diagnostic for sealed types listing missing branches
                if let missingBranches = ctx.dataFlow.missingSealedBranches(
                    subjectType: subjectType, branches: summary, sema: sema
                ) {
                    let missingNames = missingBranches.map { interner.resolve($0) }.sorted()
                    let missingList = missingNames.joined(separator: ", ")
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0071",
                        "Non-exhaustive when expression on sealed type. Missing branches: \(missingList).",
                        range: range
                    )
                } else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0004",
                        "Non-exhaustive when expression.",
                        range: range
                    )
                }
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
            var allBranchLocals: [LocalBindings] = []
            var hasTrueCase = false
            var hasFalseCase = false
            var cumulativeFalseState = ctx.flowState
            for branch in branches {
                var branchLocals = locals
                let condCtx = ctx.copying(flowState: cumulativeFalseState)
                driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
                var branchCtx = condCtx
                if let cond = branch.condition {
                    let condType = driver.inferExpr(cond, ctx: condCtx, locals: &branchLocals)
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
                    driver.exprChecker.applyFlowStateToLocals(condBranch.trueState, locals: &branchLocals, sema: sema)
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
                    driver.inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType)
                )
                allBranchLocals.append(branchLocals)
            }

            if let elseExpr {
                var elseLocals = locals
                let elseCtx = ctx.copying(flowState: cumulativeFalseState)
                driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &elseLocals, sema: sema)
                branchTypes.append(
                    driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
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

    /// Returns true if the given expression is a range/progression operator
    /// (rangeTo, rangeUntil, downTo, step).
    // MARK: - Destructuring Declarations

    func inferDestructuringDeclExpr(
        _ id: ExprID,
        names: [InternedString?],
        isMutable: Bool,
        initializer: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        // Infer the type of the RHS initializer
        let rhsType = driver.inferExpr(initializer, ctx: ctx, locals: &locals)

        // For each name, resolve componentN() on the RHS type
        for (index, name) in names.enumerated() {
            guard let name else {
                // Underscore — skip this component
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            // Look up componentN as a member function on the RHS type
            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: rhsType,
                sema: sema
            )

            let componentType: TypeID
            if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate) {
                componentType = signature.returnType
            } else {
                // Fallback: try to find componentN via scope lookup
                let scopeCandidates = sema.symbols.lookupAll(fqName: [componentName]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let sig = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return sig.receiverType != nil
                }
                if let candidate = scopeCandidates.first,
                   let signature = sema.symbols.functionSignature(for: candidate) {
                    componentType = signature.returnType
                } else {
                    componentType = sema.types.anyType
                }
            }

            let flags: SymbolFlags = isMutable ? [.mutable] : []
            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__destructuring_\(id.rawValue)"),
                    name
                ],
                declSite: range,
                visibility: .private,
                flags: flags
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            locals[name] = (componentType, symbol, isMutable, true)
        }

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferForDestructuringExpr(
        _ id: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
        let elementType = driver.helpers.iterableElementType(for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: interner) ?? sema.types.anyType

        var bodyLocals = locals

        // For each destructuring name, resolve componentN on the element type
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: elementType,
                sema: sema
            )

            let componentType: TypeID
            if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate) {
                componentType = signature.returnType
            } else {
                componentType = sema.types.anyType
            }

            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__for_destructuring_\(id.rawValue)"),
                    name
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            bodyLocals[name] = (componentType, symbol, false, true)
        }

        var loopCtx = ctx.copying(loopDepth: ctx.loopDepth + 1)
        if let userLabel = ctx.ast.arena.loopLabel(for: id) {
            loopCtx = loopCtx.withLoopLabel(userLabel)
        }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: loopCtx,
            locals: &bodyLocals,
            expectedType: nil
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    static func isRangeExpression(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case .binary(let op, _, _, _):
            switch op {
            case .rangeTo, .rangeUntil, .downTo, .step:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
