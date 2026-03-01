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

        case .stringTemplate(let parts, _):
            for part in parts {
                if case .expression(let exprID) = part {
                    _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
                }
            }
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .nameRef(let name, let nameRange):
            return inferNameRefExpr(id, name: name, nameRange: nameRange, ctx: ctx, locals: &locals)

        case .forExpr(let loopVariable, let iterableExpr, let bodyExpr, let label, let range):
            return driver.controlFlowChecker.inferForExpr(id, loopVariable: loopVariable, iterableExpr: iterableExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case .whileExpr(let conditionExpr, let bodyExpr, let label, let range):
            return driver.controlFlowChecker.inferWhileExpr(id, conditionExpr: conditionExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case .doWhileExpr(let bodyExpr, let conditionExpr, let label, let range):
            return driver.controlFlowChecker.inferDoWhileExpr(id, bodyExpr: bodyExpr, conditionExpr: conditionExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case .breakExpr(let label, let range):
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

        case .continueExpr(let label, let range):
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

        case .localDecl(let name, let isMutable, let typeAnnotation, let initializer, let range):
            return driver.localDeclChecker.inferLocalDeclExpr(id, name: name, isMutable: isMutable, typeAnnotation: typeAnnotation, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case .localAssign(let name, let value, let range):
            return driver.localDeclChecker.inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case .memberAssign(let receiverExpr, _, let valueExpr, _):
            // Type-check the receiver and value, bind as unit-typed expression.
            _ = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
            _ = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .indexedAccess(let receiverExpr, let indices, let range):
            return driver.localDeclChecker.inferIndexedAccessExpr(id, receiverExpr: receiverExpr, indices: indices, range: range, ctx: ctx, locals: &locals)

        case .indexedAssign(let receiverExpr, let indices, let valueExpr, let range):
            return driver.localDeclChecker.inferIndexedAssignExpr(id, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .returnExpr(let value, let label, let range):
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

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            return driver.controlFlowChecker.inferIfExpr(id, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            return driver.controlFlowChecker.inferTryExpr(id, body: body, catchClauses: catchClauses, finallyExpr: finallyExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .binary(let op, let lhsID, let rhsID, let range):
            return inferBinaryExpr(id, op: op, lhsID: lhsID, rhsID: rhsID, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .call(let calleeID, let typeArgRefs, let args, let range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .memberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .unaryExpr(let op, let operandID, let range):
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

        case .isCheck(let exprID, let typeRefID, let negated, let range):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            // Resolve the target type and validate it (P5-101)
            let targetType = driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            // Emit erasure warning for generic type checks with non-star type arguments
            if let typeRef = ast.arena.typeRef(typeRefID),
               case .named(_, let argRefs, _) = typeRef, !argRefs.isEmpty {
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
            let _ = negated
            let _ = targetType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .asCast(let exprID, let typeRefID, let isSafe, _):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            let targetType = driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            let type: TypeID
            if isSafe {
                type = sema.types.makeNullable(targetType)
            } else {
                type = targetType
            }
            // Smart cast: after `x as T`, narrow x to intersection of original & T (P5-97/P5-100)
            if !isSafe,
               let castSubjectExpr = ast.arena.expr(exprID),
               case .nameRef(let castVarName, _) = castSubjectExpr,
               let castLocal = locals[castVarName],
               driver.helpers.isStableLocalSymbol(castLocal.symbol, sema: sema) {
                let refinedType: TypeID
                if sema.types.isSubtype(castLocal.0, targetType) {
                    refinedType = castLocal.0  // already a subtype, no need for intersection
                } else if sema.types.isSubtype(targetType, castLocal.0) {
                    refinedType = targetType  // target is more specific
                } else {
                    refinedType = sema.types.make(.intersection([castLocal.0, targetType]))
                }
                locals[castVarName] = (refinedType, castLocal.symbol, castLocal.isMutable, castLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .nullAssert(let exprID, _):
            let operandType = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            let type = sema.types.makeNonNullable(operandType)
            // Smart cast: after `x!!`, narrow x to non-null in subsequent code (P5-66)
            if let assertSubjectExpr = ast.arena.expr(exprID),
               case .nameRef(let assertVarName, _) = assertSubjectExpr,
               let assertLocal = locals[assertVarName],
               driver.helpers.isStableLocalSymbol(assertLocal.symbol, sema: sema) {
                locals[assertVarName] = (type, assertLocal.symbol, assertLocal.isMutable, assertLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .safeMemberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferSafeMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .compoundAssign(let op, let name, let valueExpr, let range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .indexedCompoundAssign(let op, let receiverExpr, let indices, let valueExpr, let range):
            return driver.localDeclChecker.inferIndexedCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            return driver.controlFlowChecker.inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .throwExpr(let value, _):
            _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case .lambdaLiteral(let params, let body, _, _):
            return inferLambdaLiteralExpr(id, params: params, body: body, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .objectLiteral(let superTypes, _):
            let objectType = superTypes.first.map {
                driver.helpers.resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: objectType)
            return objectType

        case .callableRef(let receiver, let member, let range):
            return inferCallableRefExpr(id, receiver: receiver, member: member, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .blockExpr(let statements, let trailingExpr, _):
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
                   !outerLocal.isInitialized && blockLocal.isInitialized {
                    locals[name] = (outerLocal.type, outerLocal.symbol, outerLocal.isMutable, true)
                }
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case .localFunDecl(let name, let valueParams, let returnTypeRef, let body, let range):
            return driver.localDeclChecker.inferLocalFunDeclExpr(id, name: name, valueParams: valueParams, returnTypeRef: returnTypeRef, body: body, range: range, ctx: ctx, locals: &locals)

        case .superRef(let range):
            return inferSuperRefExpr(id, range: range, ctx: ctx)

        case .thisRef(let label, let range):
            return inferThisRefExpr(id, label: label, range: range, ctx: ctx)

        case .inExpr(let lhsID, let rhsID, _):
            _ = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            _ = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .notInExpr(let lhsID, let rhsID, _):
            _ = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            _ = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .destructuringDecl(let names, let isMutable, let initializer, let range):
            return driver.controlFlowChecker.inferDestructuringDeclExpr(id, names: names, isMutable: isMutable, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case .forDestructuringExpr(let names, let iterableExpr, let bodyExpr, let range):
            return driver.controlFlowChecker.inferForDestructuringExpr(id, names: names, iterableExpr: iterableExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)
        }
    }
}
