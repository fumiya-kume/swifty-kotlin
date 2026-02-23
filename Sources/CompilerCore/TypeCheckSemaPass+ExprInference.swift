import Foundation

extension TypeCheckSemaPassPhase {
    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID? = nil
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let expr = ast.arena.expr(id) else {
            return sema.types.errorType
        }

        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let longType = sema.types.longType
        let floatType = sema.types.floatType
        let doubleType = sema.types.doubleType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        switch expr {
        case .intLiteral:
            sema.bindings.bindExprType(id, type: intType)
            return intType

        case .longLiteral:
            sema.bindings.bindExprType(id, type: longType)
            return longType

        case .floatLiteral:
            sema.bindings.bindExprType(id, type: floatType)
            return floatType

        case .doubleLiteral:
            sema.bindings.bindExprType(id, type: doubleType)
            return doubleType

        case .charLiteral:
            sema.bindings.bindExprType(id, type: charType)
            return charType

        case .boolLiteral:
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .stringLiteral:
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .stringTemplate(let parts, _):
            for part in parts {
                if case .expression(let exprID) = part {
                    _ = inferExpr(exprID, ctx: ctx, locals: &locals)
                }
            }
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .nameRef(let name, let nameRange):
            return inferNameRefExpr(id, name: name, nameRange: nameRange, ctx: ctx, locals: &locals)

        case .forExpr(let loopVariable, let iterableExpr, let bodyExpr, let range):
            return inferForExpr(id, loopVariable: loopVariable, iterableExpr: iterableExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)

        case .whileExpr(let conditionExpr, let bodyExpr, let range):
            return inferWhileExpr(id, conditionExpr: conditionExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)

        case .doWhileExpr(let bodyExpr, let conditionExpr, let range):
            return inferDoWhileExpr(id, bodyExpr: bodyExpr, conditionExpr: conditionExpr, range: range, ctx: ctx, locals: &locals)

        case .breakExpr(let range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0018",
                    "'break' is only allowed inside loop bodies.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .continueExpr(let range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0019",
                    "'continue' is only allowed inside loop bodies.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .localDecl(let name, let isMutable, let typeAnnotation, let initializer, let range):
            return inferLocalDeclExpr(id, name: name, isMutable: isMutable, typeAnnotation: typeAnnotation, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case .localAssign(let name, let value, let range):
            return inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case .arrayAccess(let arrayExpr, let indexExpr, let range):
            return inferArrayAccessExpr(id, arrayExpr: arrayExpr, indexExpr: indexExpr, range: range, ctx: ctx, locals: &locals)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, let range):
            return inferArrayAssignExpr(id, arrayExpr: arrayExpr, indexExpr: indexExpr, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .returnExpr(let value, _):
            let resolved: TypeID
            if let value {
                resolved = inferExpr(value, ctx: ctx, locals: &locals, expectedType: expectedType)
            } else {
                resolved = sema.types.unitType
            }
            sema.bindings.bindExprType(id, type: resolved)
            return resolved

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            return inferIfExpr(id, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            return inferTryExpr(id, body: body, catchClauses: catchClauses, finallyExpr: finallyExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .binary(let op, let lhsID, let rhsID, let range):
            return inferBinaryExpr(id, op: op, lhsID: lhsID, rhsID: rhsID, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .call(let calleeID, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .memberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .unaryExpr(let op, let operandID, let range):
            let operandType = inferExpr(operandID, ctx: ctx, locals: &locals)
            let type: TypeID
            switch op {
            case .not:
                emitSubtypeConstraint(
                    left: operandType, right: boolType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(), sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            case .unaryPlus, .unaryMinus:
                type = operandType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .isCheck(let exprID, _, let negated, let range):
            _ = inferExpr(exprID, ctx: ctx, locals: &locals)
            let _ = negated
            let _ = range
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .asCast(let exprID, let typeRefID, let isSafe, _):
            _ = inferExpr(exprID, ctx: ctx, locals: &locals)
            let targetType = resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            let type: TypeID
            if isSafe {
                type = sema.types.makeNullable(targetType)
            } else {
                type = targetType
            }
            // Smart cast: after `x as T`, narrow x to T in flow state (P5-100)
            if !isSafe,
               let castSubjectExpr = ast.arena.expr(exprID),
               case .nameRef(let castVarName, _) = castSubjectExpr,
               let castLocal = locals[castVarName],
               isStableLocalSymbol(castLocal.symbol, sema: sema) {
                locals[castVarName] = (targetType, castLocal.symbol, castLocal.isMutable, castLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .nullAssert(let exprID, _):
            let operandType = inferExpr(exprID, ctx: ctx, locals: &locals)
            let type = sema.types.makeNonNullable(operandType)
            // Smart cast: after `x!!`, narrow x to non-null in subsequent code (P5-66)
            if let assertSubjectExpr = ast.arena.expr(exprID),
               case .nameRef(let assertVarName, _) = assertSubjectExpr,
               let assertLocal = locals[assertVarName],
               isStableLocalSymbol(assertLocal.symbol, sema: sema) {
                locals[assertVarName] = (type, assertLocal.symbol, assertLocal.isMutable, assertLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .safeMemberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferSafeMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .compoundAssign(let op, let name, let valueExpr, let range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            return inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .throwExpr(let value, _):
            _ = inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case .lambdaLiteral(let params, let body, _):
            return inferLambdaLiteralExpr(id, params: params, body: body, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .objectLiteral(let superTypes, _):
            let objectType = superTypes.first.map {
                resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: objectType)
            return objectType

        case .callableRef(let receiver, let member, let range):
            return inferCallableRefExpr(id, receiver: receiver, member: member, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .blockExpr(let statements, let trailingExpr, _):
            var blockLocals = locals
            for stmt in statements {
                _ = inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil)
            }
            let resultType: TypeID
            if let trailingExpr {
                resultType = inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType)
            } else {
                resultType = sema.types.unitType
            }
            // Propagate initialization state changes for outer-scope variables
            // back to the caller. New locals declared inside the block are not
            // propagated (they go out of scope), but if a variable that already
            // existed in `locals` was initialized inside the block, the updated
            // state should be visible to the caller.
            for (name, outerLocal) in locals {
                if let blockLocal = blockLocals[name],
                   blockLocal.symbol == outerLocal.symbol,
                   !outerLocal.isInitialized && blockLocal.isInitialized {
                    locals[name] = (outerLocal.type, outerLocal.symbol, outerLocal.isMutable, true)
                }
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case .localFunDecl(let name, let valueParams, let returnTypeRef, let body, let range):
            return inferLocalFunDeclExpr(id, name: name, valueParams: valueParams, returnTypeRef: returnTypeRef, body: body, range: range, ctx: ctx, locals: &locals)

        case .superRef(let range):
            return inferSuperRefExpr(id, range: range, ctx: ctx)

        case .thisRef(let label, let range):
            return inferThisRefExpr(id, label: label, range: range, ctx: ctx)
        }
    }

    func applyFlowStateToLocals(
        _ state: DataFlowState,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        sema: SemaModule
    ) {
        for (name, local) in locals {
            guard let varState = state.variables[local.symbol],
                  varState.possibleTypes.count == 1,
                  let narrowed = varState.possibleTypes.first else {
                continue
            }
            locals[name] = (narrowed, local.symbol, local.isMutable, local.isInitialized)
        }
    }

    func inferBinaryExpr(
        _ id: ExprID,
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let longType = sema.types.longType
        let floatType = sema.types.floatType
        let doubleType = sema.types.doubleType
        let stringType = sema.types.stringType

        let lhs = inferExpr(lhsID, ctx: ctx, locals: &locals)
        let rhs = inferExpr(rhsID, ctx: ctx, locals: &locals)
        let lhsIsPrimitive: Bool
        if case .primitive = sema.types.kind(of: lhs) { lhsIsPrimitive = true } else { lhsIsPrimitive = false }
        let operatorName = binaryOperatorFunctionName(for: op, interner: interner)
        let memberOperatorCandidates = lhsIsPrimitive ? [] : collectMemberFunctionCandidates(
            named: operatorName,
            receiverType: lhs,
            sema: sema
        )
        let operatorCandidates: [SymbolID]
        if !memberOperatorCandidates.isEmpty {
            operatorCandidates = memberOperatorCandidates
        } else if !lhsIsPrimitive {
            operatorCandidates = scope.lookup(operatorName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType != nil
            }
        } else {
            operatorCandidates = []
        }
        let lhsIsAny = lhs == sema.types.anyType || lhs == sema.types.nullableAnyType
        let rhsIsAny = rhs == sema.types.anyType || rhs == sema.types.nullableAnyType
        if !lhsIsPrimitive && !lhsIsAny && !rhsIsAny && operatorCandidates.isEmpty && lhs != sema.types.errorType && rhs != sema.types.errorType {
            switch op {
            case .add, .subtract, .multiply, .divide, .modulo:
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            default:
                break
            }
        }
        if !operatorCandidates.isEmpty {
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: operatorName,
                    args: [CallArg(type: rhs)]
                ),
                expectedType: expectedType,
                implicitReceiverType: lhs,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                if lhs != sema.types.errorType && rhs != sema.types.errorType {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                if lhs != sema.types.errorType && rhs != sema.types.errorType {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                        range: range
                    )
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        let type: TypeID
        switch op {
        case .add:
            if lhs == stringType || rhs == stringType {
                type = stringType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .subtract, .multiply, .divide, .modulo:
            if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            type = boolType
        case .logicalAnd, .logicalOr:
            emitSubtypeConstraint(
                left: lhs, right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            emitSubtypeConstraint(
                left: rhs, right: boolType,
                range: ast.arena.exprRange(rhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            type = boolType
        case .elvis:
            let nonNullLhs = sema.types.makeNonNullable(lhs)
            type = sema.types.lub([nonNullLhs, rhs])
            // Smart cast: `x ?: return` / `x ?: throw` narrows x to non-null (P5-66)
            if let rhsExpr = ast.arena.expr(rhsID),
               isTerminatingExpr(rhsExpr) {
                if let lhsExpr = ast.arena.expr(lhsID),
                   case .nameRef(let elvisVarName, _) = lhsExpr,
                   let elvisLocal = locals[elvisVarName],
                   isStableLocalSymbol(elvisLocal.symbol, sema: sema) {
                    let nonNullType = sema.types.makeNonNullable(elvisLocal.type)
                    locals[elvisVarName] = (nonNullType, elvisLocal.symbol, elvisLocal.isMutable, elvisLocal.isInitialized)
                }
            }
        case .rangeTo:
            type = sema.types.anyType
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    func inferCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        name: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let intType = sema.types.intType
        let stringType = sema.types.stringType

        let valueType = inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        guard let local = locals[name] else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        sema.bindings.bindIdentifier(id, symbol: local.symbol)
        if !local.isInitialized {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0031",
                "Variable '\(interner.resolve(name))' must be initialized before use.",
                range: range
            )
        }
        if !local.isMutable {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        }
        let underlyingOp = compoundAssignToBinaryOp(op)
        let resultType: TypeID
        switch underlyingOp {
        case .add:
            resultType = (local.type == stringType || valueType == stringType) ? stringType : intType
        case .subtract, .multiply, .divide, .modulo:
            resultType = intType
        default:
            resultType = local.type
        }
        locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
