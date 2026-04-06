import Foundation

final class ControlFlowTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func bindLoopIterationOperators(
        exprID: ExprID,
        iterableType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)

        guard case .classType = sema.types.kind(of: nonNullIterableType) else {
            return nil
        }

        let iteratorName = interner.intern("iterator")
        let iteratorCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullIterableType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  !symbol.flags.contains(.synthetic),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        guard !iteratorCandidates.isEmpty else {
            return nil
        }

        let iteratorResolved = ctx.resolver.resolveCall(
            candidates: iteratorCandidates,
            call: CallExpr(range: range, calleeName: iteratorName, args: []),
            expectedType: nil,
            implicitReceiverType: nonNullIterableType,
            ctx: ctx.semaCtx
        )

        guard let iteratorChosen = iteratorResolved.chosenCallee,
              let iteratorSignature = sema.symbols.functionSignature(for: iteratorChosen)
        else {
            return nil
        }

        let iteratorCall = CallBinding(
            chosenCallee: iteratorChosen,
            substitutedTypeArguments: iteratorResolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { (key: TypeVarID, value: TypeID) in value },
            parameterMapping: iteratorResolved.parameterMapping
        )

        let iteratorType = substituteResolvedType(
            iteratorSignature.returnType,
            signature: iteratorSignature,
            substitutedTypeArguments: iteratorResolved.substitutedTypeArguments,
            sema: sema
        )

        let hasNextName = interner.intern("hasNext")
        let hasNextCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: hasNextName,
            receiverType: iteratorType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        let nextName = interner.intern("next")
        let nextCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: nextName,
            receiverType: iteratorType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        guard !hasNextCandidates.isEmpty, !nextCandidates.isEmpty else {
            return nil
        }

        let hasNextResolved = ctx.resolver.resolveCall(
            candidates: hasNextCandidates,
            call: CallExpr(range: range, calleeName: hasNextName, args: []),
            expectedType: nil,
            implicitReceiverType: iteratorType,
            ctx: ctx.semaCtx
        )
        let nextResolved = ctx.resolver.resolveCall(
            candidates: nextCandidates,
            call: CallExpr(range: range, calleeName: nextName, args: []),
            expectedType: nil,
            implicitReceiverType: iteratorType,
            ctx: ctx.semaCtx
        )

        guard let hasNextChosen = hasNextResolved.chosenCallee,
              let nextChosen = nextResolved.chosenCallee,
              let nextSignature = sema.symbols.functionSignature(for: nextChosen)
        else {
            return nil
        }

        let hasNextCall = CallBinding(
            chosenCallee: hasNextChosen,
            substitutedTypeArguments: hasNextResolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { (key: TypeVarID, value: TypeID) in value },
            parameterMapping: hasNextResolved.parameterMapping
        )
        let nextCall = CallBinding(
            chosenCallee: nextChosen,
            substitutedTypeArguments: nextResolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { (key: TypeVarID, value: TypeID) in value },
            parameterMapping: nextResolved.parameterMapping
        )

        let elementType = substituteResolvedType(
            nextSignature.returnType,
            signature: nextSignature,
            substitutedTypeArguments: nextResolved.substitutedTypeArguments,
            sema: sema
        )

        sema.bindings.bindLoopIteration(
            exprID,
            binding: LoopIterationBinding(
                iteratorCall: iteratorCall,
                hasNextCall: hasNextCall,
                nextCall: nextCall,
                iteratorType: iteratorType,
                elementType: elementType
            )
        )
        return elementType
    }

    private func substituteResolvedType(
        _ type: TypeID,
        signature: FunctionSignature,
        substitutedTypeArguments: [TypeVarID: TypeID],
        sema: SemaModule
    ) -> TypeID {
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: type,
            substitution: substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func inferForExpr(
        _ id: ExprID,
        loopVariable: InternedString?,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        var bodyLocals = locals
        if let loopVariable {
            let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
            let elementType = bindLoopIterationOperators(
                exprID: id,
                iterableType: iterableType,
                range: range,
                ctx: ctx
            ) ?? driver.helpers.iterableElementType(
                for: iterableType,
                isRangeExpr: isRangeExpr,
                sema: sema,
                interner: ctx.interner
            ) ?? sema.types.anyType
            let loopVariableSymbol = sema.symbols.define(
                kind: .local,
                name: loopVariable,
                fqName: [
                    ctx.interner.intern("__for_\(id.rawValue)"),
                    loopVariable,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            bodyLocals[loopVariable] = (elementType, loopVariableSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: loopVariableSymbol)
        }
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1, loopLabelStack: newLabelStack),
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
        label: InternedString?,
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
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
        )
        var bodyLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &bodyLocals, sema: sema)
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        let bodyCtx = ctx.copying(loopDepth: ctx.loopDepth + 1, loopLabelStack: newLabelStack, flowState: branch.trueState)
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
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.booleanType
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        var bodyLocals = locals
        let bodyCtx = ctx.copying(
            loopDepth: ctx.loopDepth + 1,
            loopLabelStack: newLabelStack,
            exportBlockLocalsForExpr: bodyExpr
        )
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
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
               bodyLocal.symbol == local.symbol
            {
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
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
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
                   elseLocal.symbol == local.symbol
                {
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
        let preTryLocals = locals
        var branchTypes: [TypeID] = []
        var normalCompletionLocals: [LocalBindings] = []

        var tryBodyLocals = preTryLocals
        let tryBodyType = driver.inferExpr(body, ctx: ctx, locals: &tryBodyLocals, expectedType: expectedType)
        branchTypes.append(tryBodyType)
        if tryBodyType != sema.types.nothingType {
            normalCompletionLocals.append(tryBodyLocals)
        }

        for (index, clause) in catchClauses.enumerated() {
            var catchLocals = preTryLocals
            let catchParamType = resolveCatchClauseParameterType(
                clause.paramTypeName,
                sema: sema,
                interner: interner,
                diagnostics: ctx.semaCtx.diagnostics,
                range: clause.range
            )
            var catchParamSymbol = SymbolID.invalid
            if let paramName = clause.paramName {
                catchParamSymbol = sema.symbols.define(
                    kind: .local,
                    name: paramName,
                    fqName: [
                        interner.intern("__try_\(id.rawValue)_catch_\(index)"),
                        paramName,
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
            let catchType = driver.inferExpr(clause.body, ctx: ctx, locals: &catchLocals, expectedType: expectedType)
            branchTypes.append(catchType)
            if catchType != sema.types.nothingType {
                normalCompletionLocals.append(catchLocals)
            }
        }

        if let finallyExpr {
            // Finally is always checked for side effects, but it does not participate in try-expr type inference.
            var finallyLocals = locals
            _ = driver.inferExpr(finallyExpr, ctx: ctx, locals: &finallyLocals, expectedType: nil)
            locals = finallyLocals
        }

        if !normalCompletionLocals.isEmpty {
            for (name, local) in preTryLocals where !local.isInitialized {
                let initializedInAllNormalBranches = normalCompletionLocals.allSatisfy { branchLocals in
                    guard let branchLocal = branchLocals[name], branchLocal.symbol == local.symbol else {
                        return false
                    }
                    return branchLocal.isInitialized
                }
                guard initializedInAllNormalBranches else {
                    continue
                }
                if let current = locals[name], current.symbol == local.symbol {
                    locals[name] = (current.type, current.symbol, current.isMutable, true)
                } else {
                    locals[name] = (local.type, local.symbol, local.isMutable, true)
                }
            }
        }

        let resolvedType = sema.types.lub(branchTypes)
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveCatchClauseParameterType(
        _ typeName: InternedString?,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        range: SourceRange?
    ) -> TypeID {
        guard let typeName else {
            return sema.types.anyType
        }
        if let builtin = driver.helpers.resolveBuiltinTypeName(typeName, types: sema.types, interner: interner) {
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
        let resolvedCandidates = if !candidates.isEmpty {
            candidates
        } else {
            sema.symbols.lookupByShortName(typeName)
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
        }
        guard let symbol = resolvedCandidates.first else {
            diagnostics.error(
                "KSWIFTK-SEMA-0085",
                "Unresolved exception type '\(interner.resolve(typeName))' in catch clause.",
                range: range
            )
            return sema.types.errorType
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
    }
}
