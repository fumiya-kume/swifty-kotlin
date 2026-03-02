import Foundation

/// Handles expression type inference dispatch and specific expression cases.
/// Derived from TypeCheckSemaPass+ExprInference.swift and TypeCheckSemaPass+ExprInferCases.swift.
final class ExprTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Main Dispatch (from +ExprInference.swift)

    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
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

        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(exprID) = part {
                    _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
                }
            }
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case let .nameRef(name, nameRange):
            return inferNameRefExpr(id, name: name, nameRange: nameRange, ctx: ctx, locals: &locals)

        case let .forExpr(loopVariable, iterableExpr, bodyExpr, label, range):
            return driver.controlFlowChecker.inferForExpr(id, loopVariable: loopVariable, iterableExpr: iterableExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .whileExpr(conditionExpr, bodyExpr, label, range):
            return driver.controlFlowChecker.inferWhileExpr(id, conditionExpr: conditionExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .doWhileExpr(bodyExpr, conditionExpr, label, range):
            return driver.controlFlowChecker.inferDoWhileExpr(id, bodyExpr: bodyExpr, conditionExpr: conditionExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .breakExpr(label, range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0018",
                    "'break' is only allowed inside loop bodies.",
                    range: range
                )
            } else if let label, !ctx.loopLabelStack.contains(label) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0097",
                    "'break' with label '@\(interner.resolve(label))' does not reference a valid enclosing loop.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .continueExpr(label, range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0019",
                    "'continue' is only allowed inside loop bodies.",
                    range: range
                )
            } else if let label, !ctx.loopLabelStack.contains(label) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0098",
                    "'continue' with label '@\(interner.resolve(label))' does not reference a valid enclosing loop.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .localDecl(name, isMutable, typeAnnotation, initializer, range):
            return driver.localDeclChecker.inferLocalDeclExpr(id, name: name, isMutable: isMutable, typeAnnotation: typeAnnotation, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case let .localAssign(name, value, range):
            return driver.localDeclChecker.inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case let .memberAssign(receiverExpr, _, valueExpr, _):
            // Type-check the receiver and value, bind as unit-typed expression.
            _ = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
            _ = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case let .indexedAccess(receiverExpr, indices, range):
            return driver.localDeclChecker.inferIndexedAccessExpr(id, receiverExpr: receiverExpr, indices: indices, range: range, ctx: ctx, locals: &locals)

        case let .indexedAssign(receiverExpr, indices, valueExpr, range):
            return driver.localDeclChecker.inferIndexedAssignExpr(id, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .returnExpr(value, label, range):
            if let label {
                let labelName = interner.resolve(label)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0042",
                    "Labeled return 'return@\(labelName)' is not yet supported.",
                    range: range
                )
            }
            if let value {
                let resolved = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: expectedType)
                // Emit subtype constraint: return value must conform to expected (function) return type
                if let expectedType {
                    driver.emitSubtypeConstraint(
                        left: resolved,
                        right: expectedType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }
            } else if let expectedType {
                // Bare `return` is equivalent to `return Unit`; check Unit <: expectedType
                driver.emitSubtypeConstraint(
                    left: sema.types.unitType,
                    right: expectedType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return driver.controlFlowChecker.inferIfExpr(id, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .tryExpr(body, catchClauses, finallyExpr, _):
            return driver.controlFlowChecker.inferTryExpr(id, body: body, catchClauses: catchClauses, finallyExpr: finallyExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .binary(op, lhsID, rhsID, range):
            return inferBinaryExpr(id, op: op, lhsID: lhsID, rhsID: rhsID, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .call(calleeID, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case let .memberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case let .unaryExpr(op, operandID, range):
            let operandType = driver.inferExpr(operandID, ctx: ctx, locals: &locals)
            let type: TypeID
            switch op {
            case .not:
                driver.emitSubtypeConstraint(
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

        case let .isCheck(exprID, typeRefID, negated, range):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            // Resolve the target type and validate it (P5-101)
            let targetType = driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            // Emit erasure warning for generic type checks with non-star type arguments
            if let typeRef = ast.arena.typeRef(typeRefID),
               case let .named(_, argRefs, _) = typeRef, !argRefs.isEmpty {
                let hasNonStarArg = argRefs.contains { arg in
                    if case .star = arg { return false }
                    return true
                }
                if hasNonStarArg {
                    ctx.semaCtx.diagnostics.warning(
                        "KSWIFTK-SEMA-0080",
                        "Cannot check for instance of erased type. Use '*' for type arguments in 'is' checks, e.g. 'is List<*>'.",
                        range: range
                    )
                }
            }
            _ = negated
            _ = targetType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .asCast(exprID, typeRefID, isSafe, _):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            let targetType = driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            let type: TypeID = if isSafe {
                sema.types.makeNullable(targetType)
            } else {
                targetType
            }
            // Smart cast: after `x as T`, narrow x to intersection of original & T (P5-97/P5-100)
            if !isSafe,
               let castSubjectExpr = ast.arena.expr(exprID),
               case let .nameRef(castVarName, _) = castSubjectExpr,
               let castLocal = locals[castVarName],
               driver.helpers.isStableLocalSymbol(castLocal.symbol, sema: sema) {
                let refinedType: TypeID = if sema.types.isSubtype(castLocal.0, targetType) {
                    castLocal.0 // already a subtype, no need for intersection
                } else if sema.types.isSubtype(targetType, castLocal.0) {
                    targetType // target is more specific
                } else {
                    sema.types.make(.intersection([castLocal.0, targetType]))
                }
                locals[castVarName] = (refinedType, castLocal.symbol, castLocal.isMutable, castLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .nullAssert(exprID, _):
            let operandType = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            let type = sema.types.makeNonNullable(operandType)
            // Smart cast: after `x!!`, narrow x to non-null in subsequent code (P5-66)
            if let assertSubjectExpr = ast.arena.expr(exprID),
               case let .nameRef(assertVarName, _) = assertSubjectExpr,
               let assertLocal = locals[assertVarName],
               driver.helpers.isStableLocalSymbol(assertLocal.symbol, sema: sema) {
                locals[assertVarName] = (type, assertLocal.symbol, assertLocal.isMutable, assertLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .safeMemberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferSafeMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case let .compoundAssign(op, name, valueExpr, range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .indexedCompoundAssign(op, receiverExpr, indices, valueExpr, range):
            return driver.localDeclChecker.inferIndexedCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .whenExpr(subjectID, branches, elseExpr, range):
            return driver.controlFlowChecker.inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .throwExpr(value, _):
            _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .lambdaLiteral(params, body, _, _):
            return inferLambdaLiteralExpr(id, params: params, body: body, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .objectLiteral(superTypes, _):
            let objectType = superTypes.first.map {
                driver.helpers.resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: objectType)
            return objectType

        case let .callableRef(receiver, member, range):
            return inferCallableRefExpr(id, receiver: receiver, member: member, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .blockExpr(statements, trailingExpr, _):
            var blockLocals = locals
            var reachedNothing = false
            for stmt in statements {
                if reachedNothing {
                    // Emit unreachable code diagnostic for statements after Nothing-typed expression
                    if let stmtRange = ast.arena.exprRange(stmt) {
                        ctx.semaCtx.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: stmtRange
                        )
                    }
                    // Still type-check for completeness but skip further unreachable warnings
                    _ = driver.inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil)
                    continue
                }
                let stmtType = driver.inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil)
                if stmtType == sema.types.nothingType {
                    reachedNothing = true
                }
            }
            let resultType: TypeID
            if reachedNothing {
                if let trailingExpr {
                    if let trailingRange = ast.arena.exprRange(trailingExpr) {
                        ctx.semaCtx.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: trailingRange
                        )
                    }
                    _ = driver.inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType)
                }
                resultType = sema.types.nothingType
            } else if let trailingExpr {
                resultType = driver.inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType)
            } else {
                resultType = sema.types.unitType
            }
            for (name, outerLocal) in locals {
                if let blockLocal = blockLocals[name],
                   blockLocal.symbol == outerLocal.symbol,
                   !outerLocal.isInitialized, blockLocal.isInitialized {
                    locals[name] = (outerLocal.type, outerLocal.symbol, outerLocal.isMutable, true)
                }
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case let .localFunDecl(name, valueParams, returnTypeRef, body, range):
            return driver.localDeclChecker.inferLocalFunDeclExpr(id, name: name, valueParams: valueParams, returnTypeRef: returnTypeRef, body: body, range: range, ctx: ctx, locals: &locals)

        case let .superRef(range):
            return inferSuperRefExpr(id, range: range, ctx: ctx)

        case let .thisRef(label, range):
            return inferThisRefExpr(id, label: label, range: range, ctx: ctx)

        case let .inExpr(lhsID, rhsID, _):
            _ = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            _ = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .notInExpr(lhsID, rhsID, _):
            _ = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            _ = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .destructuringDecl(names, isMutable, initializer, range):
            return driver.controlFlowChecker.inferDestructuringDeclExpr(id, names: names, isMutable: isMutable, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, range):
            return driver.controlFlowChecker.inferForDestructuringExpr(id, names: names, iterableExpr: iterableExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)
        }
    }
}
