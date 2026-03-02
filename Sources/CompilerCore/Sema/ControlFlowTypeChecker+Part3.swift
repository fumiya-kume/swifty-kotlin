import Foundation

// Handles control flow expression type inference (for, while, do-while, if, try, when).
// Derived from TypeCheckSemaPhase+InferControlFlow.swift.

extension ControlFlowTypeChecker {
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
                      case let .nameRef(subjectName, _) = subjectExpr,
                      let local = locals[subjectName]
                else {
                    return nil
                }
                return (
                    subjectName, local.type, local.symbol,
                    driver.helpers.isStableLocalSymbol(local.symbol, sema: sema),
                    local.isMutable
                )
            }()
            let hasExplicitNullBranch = branches.contains { branch in
                branch.conditions.contains { cond in
                    guard let conditionExpr = ast.arena.expr(cond),
                          case let .nameRef(name, _) = conditionExpr
                    else {
                        return false
                    }
                    return interner.resolve(name) == "null"
                }
            }
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            var hasNullCase = false
            var hasTrueCase = false
            var hasFalseCase = false
            var allBranchLocals: [LocalBindings] = []
            for branch in branches {
                var isNullBranch = false
                // Type-check and collect coverage for ALL conditions in this branch (OR semantics)
                for cond in branch.conditions {
                    let condType = driver.inferExpr(cond, ctx: ctx, locals: &locals)
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            if condType == boolType { hasTrueCase = true }
                            covered.insert(interner.intern("true"))
                        case .boolLiteral(false, _):
                            if condType == boolType { hasFalseCase = true }
                            covered.insert(interner.intern("false"))
                        case let .nameRef(name, _):
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
                    // Known limitation: Currently only the first condition contributes to flow-state narrowing for subject-ful `when` branches.
                    //                  Extend this to support all conditions in the branch (OR semantics) for more precise narrowing.
                    if let cond = branch.conditions.first {
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
                        } else if hasExplicitNullBranch, !isNullBranch {
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
            if isExhaustive, !allBranchLocals.isEmpty {
                for (name, local) in locals where !local.isInitialized {
                    let allInit = allBranchLocals.allSatisfy { branchLocal in
                        guard let bl = branchLocal[name] else { return false }
                        return bl.isInitialized && bl.symbol == local.symbol
                    }
                    if allInit {
                        locals[name] = (local.type, local.symbol, local.isMutable, true)
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
                var condCtx = ctx.copying(flowState: cumulativeFalseState)
                driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
                var branchCtx = condCtx
                // Subject-less when: each condition must be Boolean; multiple conditions = OR.
                // Collect all true-states and merge them (join) for the body context,
                // since the body executes when ANY condition is true.
                // condCtx is updated after each condition so subsequent conditions see
                // the narrowing from prior conditions being false (short-circuit OR semantics).
                var trueStates: [DataFlowState] = []
                for cond in branch.conditions {
                    let condType = driver.inferExpr(cond, ctx: condCtx, locals: &branchLocals)
                    if condType != boolType, condType != sema.types.errorType {
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
                    trueStates.append(condBranch.trueState)
                    // Chain false-state: branch is false only when ALL conditions are false
                    cumulativeFalseState = condBranch.falseState
                    // Update condCtx so subsequent conditions see prior conditions' false-state narrowing
                    condCtx = ctx.copying(flowState: cumulativeFalseState)
                    driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
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
                // Join all true-states: body sees the union (OR) of all conditions' narrowings
                if let firstTrue = trueStates.first {
                    var joinedState = firstTrue
                    for state in trueStates.dropFirst() {
                        joinedState = ctx.dataFlow.merge(joinedState, state)
                    }
                    branchCtx = ctx.copying(flowState: joinedState)
                    branchLocals = locals
                    driver.exprChecker.applyFlowStateToLocals(joinedState, locals: &branchLocals, sema: sema)
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
            if isExhaustive, !allBranchLocals.isEmpty {
                for (name, local) in locals where !local.isInitialized {
                    let allInit = allBranchLocals.allSatisfy { branchLocal in
                        guard let bl = branchLocal[name] else { return false }
                        return bl.isInitialized && bl.symbol == local.symbol
                    }
                    if allInit {
                        locals[name] = (local.type, local.symbol, local.isMutable, true)
                    }
                }
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        }
    }

    // MARK: - Destructuring Declarations
}
