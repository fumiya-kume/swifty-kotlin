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

        case .memberAssign(let receiverExpr, let member, let valueExpr, let range):
            // P5-111: Type-check member property assignment (e.g. Counter.n = 3).
            let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
            let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
            // Resolve the member property on the receiver type.
            if let propResult = driver.helpers.lookupMemberProperty(
                named: member,
                receiverType: receiverType,
                sema: sema
            ) {
                sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: propResult.type,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "Unresolved member property '\(ctx.interner.resolve(member))'.",
                    range: range
                )
            }
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

    // MARK: - Flow State Helpers

    func applyFlowStateToLocals(
        _ state: DataFlowState,
        locals: inout LocalBindings,
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

    // MARK: - Binary Expression Inference

    func inferBinaryExpr(
        _ id: ExprID,
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let longType = sema.types.longType
        let floatType = sema.types.floatType
        let doubleType = sema.types.doubleType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        let lhs = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
        let rhs = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
        let lhsIsPrimitive: Bool
        if case .primitive = sema.types.kind(of: lhs) { lhsIsPrimitive = true } else { lhsIsPrimitive = false }
        let operatorName = driver.helpers.binaryOperatorFunctionName(for: op, interner: interner)
        let memberOperatorCandidates = lhsIsPrimitive ? [] : driver.helpers.collectMemberFunctionCandidates(
            named: operatorName,
            receiverType: lhs,
            sema: sema
        )
        let operatorCandidates: [SymbolID]
        if !memberOperatorCandidates.isEmpty {
            operatorCandidates = memberOperatorCandidates
        } else if !lhsIsPrimitive {
            operatorCandidates = ctx.cachedScopeLookup(operatorName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
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
            let returnType = driver.callChecker.bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            // compareTo desugaring: comparison operators (<, <=, >, >=) that resolve
            // to a compareTo method should produce Bool, not the compareTo return type (Int).
            // The KIR lowerer will emit: compareTo(a, b) <op> 0
            let effectiveType: TypeID
            switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                effectiveType = boolType
            default:
                effectiveType = returnType
            }
            sema.bindings.bindExprType(id, type: effectiveType)
            return effectiveType
        }
        let type: TypeID
        switch op {
        case .add:
            if lhs == stringType || rhs == stringType {
                type = stringType
            } else if lhs == charType && rhs == intType {
                // Char + Int -> Char
                type = charType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .subtract:
            if lhs == charType && rhs == charType {
                // Char - Char -> Int
                type = intType
            } else if lhs == charType && rhs == intType {
                // Char - Int -> Char
                type = charType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .multiply, .divide, .modulo:
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
            driver.emitSubtypeConstraint(
                left: lhs, right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.emitSubtypeConstraint(
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
               driver.helpers.isTerminatingExpr(rhsExpr) {
                if let lhsExpr = ast.arena.expr(lhsID),
                   case .nameRef(let elvisVarName, _) = lhsExpr,
                   let elvisLocal = locals[elvisVarName],
                   driver.helpers.isStableLocalSymbol(elvisLocal.symbol, sema: sema) {
                    let nonNullType = sema.types.makeNonNullable(elvisLocal.type)
                    locals[elvisVarName] = (nonNullType, elvisLocal.symbol, elvisLocal.isMutable, elvisLocal.isInitialized)
                }
            }
        case .rangeTo, .rangeUntil, .downTo, .step:
            type = sema.types.intType
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor:
            if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .shl, .shr, .ushr:
            // Shift operators: result type depends only on the left operand.
            // The shift amount (rhs) is always Int in Kotlin.
            type = lhs == longType ? longType : intType
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    // MARK: - Compound Assignment

    func inferCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        name: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let intType = sema.types.intType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
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
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            let resultType: TypeID
            switch underlyingOp {
            case .add:
                if local.type == stringType || valueType == stringType {
                    resultType = stringType
                } else if local.type == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .subtract:
                if local.type == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .multiply, .divide, .modulo:
                resultType = intType
            default:
                resultType = local.type
            }
            locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Fall back to top-level property lookup for compound assignments like `counter += 1`
        // where `counter` is a top-level var.
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        // Only match top-level properties, not class member properties.
        // Top-level properties have no parentSymbol set (nil) or parent is a package.
        // Class member properties always have parentSymbol set to a class/object/interface.
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package
        }) {
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.anyType
            if !propSymbol.flags.contains(.mutable) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            }
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            let resultType: TypeID
            switch underlyingOp {
            case .add:
                if propType == stringType || valueType == stringType {
                    resultType = stringType
                } else if propType == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .subtract:
                if propType == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .multiply, .divide, .modulo:
                resultType = intType
            default:
                resultType = propType
            }
            _ = resultType  // top-level property type not updated in locals
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0013",
            "Unresolved local variable '\(interner.resolve(name))'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    // MARK: - Specific Expression Cases (from +ExprInferCases.swift)

    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        if interner.resolve(name) == "null" {
            sema.bindings.bindExprType(id, type: sema.types.nullableNothingType)
            return sema.types.nullableNothingType
        }
        if interner.resolve(name) == "this",
           let receiverType = ctx.implicitReceiverType {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        if let local = locals[name] {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            // Propagate collection marks through variable references (P5-84).
            if sema.bindings.isCollectionSymbol(local.symbol) {
                sema.bindings.markCollectionExpr(id)
            }
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, invisibleSyms) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if candidates.isEmpty {
            if let firstInvisible = invisibleSyms.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '\(interner.resolve(name))'.",
                    range: nameRange
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let first = candidates.first {
            sema.bindings.bindIdentifier(id, symbol: first.id)
        }
        let resolvedType = candidates.first.flatMap { symbol in
            if let signature = sema.symbols.functionSignature(for: symbol.id) {
                return signature.returnType
            }
            if symbol.kind == .property || symbol.kind == .field {
                return sema.symbols.propertyType(for: symbol.id)
            }
            // Objects are singletons – always resolve to their nominal type so
            // that `ObjectName.member()` works (P5-111).
            if symbol.kind == .object {
                return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
            }
            // For class/interface/enum symbols, only resolve to nominal type when
            // they have a companion object so that `ClassName.companionMember()`
            // can resolve.  Without a companion, keep the previous anyType
            // fallback so that `ClassName.instanceMethod()` correctly errors.
            if (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass),
               sema.symbols.companionObjectSymbol(for: symbol.id) != nil {
                return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
            }
            return nil
        } ?? sema.types.anyType
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    func inferLambdaLiteralExpr(
        _ id: ExprID,
        params: [InternedString],
        body: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema

        let expectedFunctionType: FunctionType?
        if let expectedType,
           case .functionType(let functionType) = sema.types.kind(of: expectedType) {
            expectedFunctionType = functionType
        } else {
            expectedFunctionType = nil
        }

        var lambdaLocals = locals
        let outerSymbols = Set(locals.values.map { $0.symbol })
        let parameterTypes: [TypeID]
        if let expectedFunctionType, expectedFunctionType.params.count == params.count {
            parameterTypes = expectedFunctionType.params
        } else {
            parameterTypes = Array(repeating: sema.types.anyType, count: params.count)
        }
        for (offset, param) in params.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
            let parameterType = offset < parameterTypes.count ? parameterTypes[offset] : sema.types.anyType
            lambdaLocals[param] = (
                type: parameterType,
                symbol: syntheticSymbol,
                isMutable: false,
                isInitialized: true
            )
        }

        let inferredBodyType = driver.inferExpr(
            body,
            ctx: ctx,
            locals: &lambdaLocals,
            expectedType: expectedFunctionType?.returnType
        )
        let captures = driver.captureAnalyzer.collectCapturedOuterSymbols(
            in: body,
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols
        )
        sema.bindings.bindCaptureSymbols(id, symbols: captures)

        if let expectedType, let expectedFunctionType {
            driver.emitSubtypeConstraint(
                left: inferredBodyType,
                right: expectedFunctionType.returnType,
                range: ast.arena.exprRange(body),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
        }

        let inferredFunctionType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: inferredBodyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: inferredFunctionType)
        return inferredFunctionType
    }

    func inferCallableRefExpr(
        _ id: ExprID,
        receiver: ExprID?,
        member: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let outerSymbols = Set(locals.values.map { $0.symbol })

        let receiverType: TypeID?
        if let receiver {
            receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            receiverType = nil
        }

        var candidates: [SymbolID] = []
        if let receiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema
            )
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let declaredReceiver = signature.receiverType else {
                        return false
                    }
                    return sema.types.isSubtype(nonNullReceiver, declaredReceiver)
                }
            }
        } else {
            candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = ctx.cachedSymbol(local.symbol),
               localSymbol.kind == .function {
                candidates = [local.symbol]
            }
        }

        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedType,
            bindReceiver: receiver != nil,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen) {
            let inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: receiver != nil,
                sema: sema
            )
            let resultType: TypeID
            if let expectedType,
               case .functionType = sema.types.kind(of: expectedType) {
                driver.emitSubtypeConstraint(
                    left: inferredType,
                    right: expectedType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                resultType = expectedType
            } else {
                resultType = inferredType
            }
            sema.bindings.bindIdentifier(id, symbol: chosen)
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let captures = receiver.map { recv in
                driver.captureAnalyzer.collectCapturedOuterSymbols(
                    in: recv,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerSymbols
                )
            } ?? []
            sema.bindings.bindCaptureSymbols(id, symbols: captures)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        let fallbackType: TypeID
        if let expectedType,
           case .functionType = sema.types.kind(of: expectedType) {
            fallbackType = expectedType
        } else {
            fallbackType = sema.types.anyType
        }
        let fallbackCaptures = receiver.map { recv in
            driver.captureAnalyzer.collectCapturedOuterSymbols(
                in: recv,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            )
        } ?? []
        sema.bindings.bindCaptureSymbols(id, symbols: fallbackCaptures)
        sema.bindings.bindExprType(id, type: fallbackType)
        return fallbackType
    }

    func inferSuperRefExpr(
        _ id: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0050",
                "'super' is not allowed outside of a class body.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let classSymbol = driver.helpers.nominalSymbol(of: receiverType, types: sema.types) {
            let supertypes = sema.symbols.directSupertypes(for: classSymbol)
            let classSupertypes = supertypes.filter {
                let kind = ctx.cachedSymbol($0)?.kind
                return kind == .class || kind == .enumClass
            }
            if let superclass = classSupertypes.first {
                let superType = sema.types.make(.classType(ClassType(classSymbol: superclass)))
                sema.bindings.bindExprType(id, type: superType)
                return superType
            }
        }
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0052",
            "Class has no superclass.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func inferThisRefExpr(
        _ id: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0051",
                "'this' is not allowed in this context.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let label {
            if let qualifiedType = ctx.resolveQualifiedThis(label: label) {
                sema.bindings.bindExprType(id, type: qualifiedType)
                return qualifiedType
            }
            let labelStr = ctx.interner.resolve(label)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0053",
                "Unresolved label '\(labelStr)' for qualified 'this'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        sema.bindings.bindExprType(id, type: receiverType)
        return receiverType
    }
}
