
final class ExprTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Main Dispatch (from +ExprInference.swift)

    // swiftlint:disable:next cyclomatic_complexity
    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID? = nil,
        isStatementContext: Bool = false
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
        case let .intLiteral(value, _):
            // An unsuffixed integer literal takes on Long/UInt/ULong when that is
            // the expected type at this position (e.g. `Millis(1500)` where the
            // value class's single field is declared `Long`), matching Kotlin's
            // literal-widening rule. Falls back to Int otherwise.
            let literalType = intLiteralType(expectedType: expectedType, sema: sema, defaultType: intType, literalValue: value)
            sema.bindings.bindExprType(id, type: literalType)
            return literalType

        case .longLiteral:
            sema.bindings.bindExprType(id, type: longType)
            return longType

        case let .uintLiteral(value, _):
            let literalType = uintLiteralType(
                expectedType: expectedType,
                sema: sema,
                literalValue: value
            )
            sema.bindings.bindExprType(id, type: literalType)
            return literalType

        case .ulongLiteral:
            sema.bindings.bindExprType(id, type: sema.types.ulongType)
            return sema.types.ulongType

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

        case let .localDecl(name, isMutable, typeAnnotation, initializer, isDelegated, range):
            return driver.localDeclChecker.inferLocalDeclExpr(
                id,
                name: name,
                isMutable: isMutable,
                typeAnnotation: typeAnnotation,
                initializer: initializer,
                isDelegated: isDelegated,
                range: range,
                ctx: ctx,
                locals: &locals
            )

        case let .localAssign(name, value, range):
            return driver.localDeclChecker.inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case let .memberAssign(receiverExpr, calleeName, valueExpr, _):
            // Type-check the receiver and value, bind as unit-typed expression.
            let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
            _ = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
            // Bind the property symbol so KIR lowering can emit a direct field
            // store (kk_array_set) rather than falling back to a setter call.
            // This is required when the receiver is an explicit `this` reference.
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            if let propResult = driver.helpers.lookupMemberProperty(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema
            ) {
                sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case let .indexedAccess(receiverExpr, indices, range):
            return driver.localDeclChecker.inferIndexedAccessExpr(id, receiverExpr: receiverExpr, indices: indices, range: range, ctx: ctx, locals: &locals)

        case let .indexedAssign(receiverExpr, indices, valueExpr, range):
            return driver.localDeclChecker.inferIndexedAssignExpr(id, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .returnExpr(value, label, range):
            if let label, !ctx.hasLambdaLabel(label) {
                let labelName = interner.resolve(label)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0042",
                    "'return@\(labelName)' does not reference a valid enclosing lambda.",
                    range: range
                )
            }
            if let value {
                let resolved = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: expectedType)
                // Emit subtype constraint: return value must conform to expected (function) return type.
                // Range expressions keep their runtime representation separate from the
                // source-level range interface (they infer as the scalar element type),
                // so `fun f(): IntRange = a..b` skips the nominal subtype check, matching
                // the local-declaration rule in LocalDeclTypeChecker.
                let returnsRangeExpr = expectedType.map {
                    driver.helpers.rangeExprMatchesDeclaredElementType(
                        bodyExprID: value,
                        bodyType: resolved,
                        declaredType: $0,
                        sema: sema,
                        interner: interner
                    )
                } ?? false
                if let expectedType, !returnsRangeExpr {
                    driver.emitSubtypeConstraint(
                        left: resolved,
                        right: expectedType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics,
                        suppressPlatformWarning: ctx.suppressPlatformReturnWarning
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
                    diagnostics: ctx.semaCtx.diagnostics,
                    suppressPlatformWarning: ctx.suppressPlatformReturnWarning
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
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case let .memberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferMemberCallExpr(
                id, receiverID: receiverID, calleeName: calleeName,
                args: args, range: range, ctx: ctx, locals: &locals,
                expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
            )

        case let .unaryExpr(op, operandID, range):
            let type: TypeID
            switch op {
            case .not:
                let operandType = driver.inferExpr(operandID, ctx: ctx, locals: &locals)
                if let overloadedType = inferUnaryOperatorExpr(
                    id,
                    op: op,
                    operandType: operandType,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType
                ) {
                    return overloadedType
                }
                driver.emitSubtypeConstraint(
                    left: operandType, right: boolType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(), sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            case .unaryPlus, .unaryMinus:
                // Constant-fold unary +/- over an integer literal so that e.g.
                // `val x: Byte = -1` can resolve to Byte without a full constant
                // propagation pass.
                if case let .intLiteral(literalValue, _) = ast.arena.expr(operandID) {
                    let foldedValue = op == .unaryMinus ? -literalValue : literalValue
                    type = intLiteralType(
                        expectedType: expectedType,
                        sema: sema,
                        defaultType: intType,
                        literalValue: foldedValue
                    )
                    _ = driver.inferExpr(operandID, ctx: ctx, locals: &locals, expectedType: nil)
                } else {
                    let operandType = driver.inferExpr(operandID, ctx: ctx, locals: &locals, expectedType: expectedType)
                    if let overloadedType = inferUnaryOperatorExpr(
                        id,
                        op: op,
                        operandType: operandType,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType
                    ) {
                        return overloadedType
                    }
                    type = operandType
                }
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .isCheck(exprID, typeRefID, negated, range):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            // Resolve the target type and validate it (P5-101)
            let targetType = driver.helpers.resolveTypeRef(
                typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
            if case let .typeParam(typeParam) = sema.types.kind(of: targetType),
               let typeParameterSymbol = sema.symbols.symbol(typeParam.symbol),
               !typeParameterSymbol.flags.contains(.reifiedTypeParameter)
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0084",
                    "Cannot check for instance of non-reified type parameter '\(interner.resolve(typeParameterSymbol.name))'.",
                    range: range
                )
            }
            // Emit erasure warning for generic type checks with non-star type arguments
            if let typeRef = ast.arena.typeRef(typeRefID),
               case let .named(_, argRefs, _) = typeRef, !argRefs.isEmpty
            {
                let hasNonStarArg = argRefs.contains { arg in
                    if case .star = arg { return false }
                    return true
                }
                if hasNonStarArg {
                    ctx.semaCtx.diagnostics.warning(
                        "KSWIFTK-SEMA-ERASED-TYPE",
                        "Cannot check for instance of erased type: type arguments are not available at runtime. Use star-projection, e.g. 'is List<*>'.",
                        range: range
                    )
                }
            }
            sema.bindings.bindIsCheckTargetType(id, type: targetType)
            _ = negated
            _ = targetType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .asCast(exprID, typeRefID, isSafe, range):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            let targetType = driver.helpers.resolveTypeRef(
                typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
            let type: TypeID = if isSafe {
                sema.types.makeNullable(targetType)
            } else {
                targetType
            }
            sema.bindings.bindCastTargetType(id, type: targetType)
            if let typeRef = ast.arena.typeRef(typeRefID),
               case let .named(_, argRefs, _) = typeRef,
               !argRefs.isEmpty
            {
                let hasNonStarArg = argRefs.contains { arg in
                    if case .star = arg {
                        return false
                    }
                    return true
                }
                if hasNonStarArg {
                    let operatorText = isSafe ? "as?" : "as"
                    ctx.semaCtx.diagnostics.warning(
                        "KSWIFTK-SEMA-UNCHECKED-CAST",
                        "Unchecked cast '\(operatorText)' to generic type erases type arguments at runtime.",
                        range: range
                    )
                }
            }
            // Smart cast: after `x as T`, narrow x to intersection of original & T (P5-97/P5-100)
            if !isSafe,
               let castSubjectExpr = ast.arena.expr(exprID),
               case let .nameRef(castVarName, _) = castSubjectExpr,
               let castLocal = locals[castVarName],
               driver.helpers.isStableLocalSymbol(castLocal.symbol, sema: sema)
            {
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
               driver.helpers.isStableLocalSymbol(assertLocal.symbol, sema: sema)
            {
                locals[assertVarName] = (type, assertLocal.symbol, assertLocal.isMutable, assertLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .safeMemberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.semaCtx.diagnostics)
            return driver.callChecker.inferSafeMemberCallExpr(
                id, receiverID: receiverID, calleeName: calleeName,
                args: args, range: range, ctx: ctx, locals: &locals,
                expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
            )

        case let .compoundAssign(op, name, valueExpr, range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .indexedCompoundAssign(op, receiverExpr, indices, valueExpr, range):
            return driver.localDeclChecker.inferIndexedCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .memberCompoundAssign(op, receiverExpr, calleeName, valueExpr, range):
            return inferMemberCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, calleeName: calleeName, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .whenExpr(subjectID, branches, elseExpr, range):
            return driver.controlFlowChecker.inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)

        case let .throwExpr(value, _):
            _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .lambdaLiteral(params, body, _, _):
            return inferLambdaLiteralExpr(id, params: params, body: body, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .objectLiteral(superTypes, declID, _):
            return inferObjectLiteralExpr(id, superTypes: superTypes, declID: declID, ctx: ctx, locals: &locals)

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
                    _ = driver.inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil, isStatementContext: true)
                    continue
                }
                let stmtType = driver.inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil, isStatementContext: true)
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
                    _ = driver.inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                }
                resultType = sema.types.nothingType
            } else if let trailingExpr {
                resultType = driver.inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType, isStatementContext: isStatementContext)
            } else {
                resultType = sema.types.unitType
            }
            if ctx.exportBlockLocalsForExpr == id {
                // do-while bodies expose their block locals to the loop condition.
                locals = blockLocals
            } else {
                for (name, outerLocal) in locals {
                    if let blockLocal = blockLocals[name],
                       blockLocal.symbol == outerLocal.symbol,
                       !outerLocal.isInitialized, blockLocal.isInitialized
                    {
                        locals[name] = (outerLocal.type, outerLocal.symbol, outerLocal.isMutable, true)
                    }
                }
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case let .localFunDecl(name, valueParams, returnTypeRef, body, isSuspend, range):
            return driver.localDeclChecker.inferLocalFunDeclExpr(id, name: name, valueParams: valueParams, returnTypeRef: returnTypeRef, body: body, isSuspend: isSuspend, range: range, ctx: ctx, locals: &locals)

        case let .superRef(interfaceQualifier, range):
            return inferSuperRefExpr(id, interfaceQualifier: interfaceQualifier, range: range, ctx: ctx)

        case let .thisRef(label, range):
            return inferThisRefExpr(id, label: label, range: range, ctx: ctx, locals: locals)

        case let .inExpr(lhsID, rhsID, range):
            let lhsType = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhsType = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            // Resolve operator fun contains on the RHS (container) type for custom classes (STDLIB-OP-032)
            inferContainsCallBinding(
                exprID: id,
                containerExpr: rhsID,
                elementType: lhsType,
                containerType: rhsType,
                range: range,
                ctx: ctx
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .notInExpr(lhsID, rhsID, range):
            let lhsType = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhsType = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            // Resolve operator fun contains on the RHS (container) type for custom classes (STDLIB-OP-032)
            inferContainsCallBinding(
                exprID: id,
                containerExpr: rhsID,
                elementType: lhsType,
                containerType: rhsType,
                range: range,
                ctx: ctx
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .destructuringDecl(names, isMutable, initializer, range):
            return driver.controlFlowChecker.inferDestructuringDeclExpr(id, names: names, isMutable: isMutable, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, range):
            return driver.controlFlowChecker.inferForDestructuringExpr(id, names: names, iterableExpr: iterableExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)
        }
    }

    /// Resolves operator fun contains on the container type and records a CallBinding
    /// so KIR lowering can dispatch to the user-defined contains() instead of the
    /// generic kk_op_contains runtime stub.
    private func inferContainsCallBinding(
        exprID: ExprID,
        containerExpr: ExprID,
        elementType: TypeID,
        containerType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        let containsName = interner.intern("contains")

        // Range expressions carry an Int lowering type until their member call
        // is resolved. If a user operator extension is in scope, recover the
        // source-level IntRange receiver before the primitive fast path can
        // route `in` to the generic runtime helper.
        if let rangeSourceReceiverType = driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ),
        MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) == .intRange {
            let scopedRangeUserCandidates = driver.callChecker
                .collectScopedRangeUserExtensionCandidates(
                    named: containsName,
                    receiverType: rangeSourceReceiverType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                )
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.flags.contains(SymbolFlags.operatorFunction)
                    else {
                        return false
                    }
                    return driver.callChecker.isIntRangeCrossTypeContainsCandidate(
                        candidate,
                        sema: sema
                    )
                }
            if !scopedRangeUserCandidates.isEmpty {
                let resolved = ctx.resolver.resolveCall(
                    candidates: scopedRangeUserCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)]
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.semaCtx
                )
                if let chosen = resolved.chosenCallee {
                    sema.bindings.bindCall(
                        exprID,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: resolved.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map { _, value in value },
                            parameterMapping: resolved.parameterMapping
                        )
                    )
                    return
                }
                let hasBundledRangeCandidate = driver.callChecker
                    .hasIntRangeSourceBackedContainsCandidate(
                        receiverType: rangeSourceReceiverType,
                        argumentType: sema.types.makeNonNullable(elementType),
                        sema: sema,
                        interner: interner
                    )
                let rangeMemberCandidates = driver.helpers
                    .collectMemberFunctionCandidates(
                        named: containsName,
                        receiverType: rangeSourceReceiverType,
                        sema: sema,
                        interner: interner
                    )
                    .filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.flags.contains(SymbolFlags.operatorFunction),
                              let signature = sema.symbols.functionSignature(for: candidate)
                        else {
                            return false
                        }
                        return signature.parameterTypes.count == 1
                    }
                let hasApplicableRangeMember = ctx.resolver.resolveCall(
                    candidates: rangeMemberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)]
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.semaCtx
                ).chosenCallee != nil
                if !hasBundledRangeCandidate,
                   !hasApplicableRangeMember,
                   let diagnostic = resolved.diagnostic
                {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return
                }
            }
        }

        // Skip primitive and range types — they are handled by kk_op_contains at runtime.
        // String is `.stringStruct`, not `.classType` (KSWIFTK-INTERNAL-0001), but it does
        // have a bundled-Kotlin-source `contains` to dispatch to (KSP-408), so it must not
        // be skipped here — unlike genuine primitives/ranges, kk_op_contains has no String
        // case at all, and falling through to it would silently return false for every
        // `x in someString` regardless of the actual contents.
        let nonNullContainerType = sema.types.makeNonNullable(containerType)
        switch sema.types.kind(of: nonNullContainerType) {
        case .classType, .stringStruct:
            break
        default:
            return
        }

        let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: containsName,
            receiverType: nonNullContainerType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1
            else {
                return false
            }
            return true
        }

        // Bundle Kotlin source extension functions such as `List.contains` live at
        // package scope, so the direct owner+name member lookup above misses them.
        // Fall back to scope lookup and filter by receiver type, mirroring the
        // extension-function resolution path in `inferRegularMemberCall`.
        let scopeCandidates = ctx.cachedScopeLookup(containsName).filter { candidate in
            guard !memberCandidates.contains(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let receiverType = signature.receiverType
            else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullContainerType,
                declaredReceiver: receiverType,
                sema: sema
            )
        }

        // Extension functions are excluded from scope by the scope builder so they
        // don't shadow top-level calls. Fall back to a direct symbol-table lookup
        // by short name to find synthetic extension functions (e.g. the
        // String.contains(regex: Regex) synthetic stub used by the `in` operator).
        // This mirrors the fallback in `inferRegularMemberCall` for member-style calls.
        let syntheticExtensionCandidates = sema.symbols.lookupByShortName(containsName).filter { candidate in
            guard !memberCandidates.contains(candidate),
                  !scopeCandidates.contains(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let receiverType = signature.receiverType
            else {
                return false
            }
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parentSym = sema.symbols.symbol(parentID),
               parentSym.kind == .property
            {
                return false
            }
            guard symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate) else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullContainerType,
                declaredReceiver: receiverType,
                sema: sema
            )
        }

        var candidates = memberCandidates
        candidates.append(contentsOf: scopeCandidates)
        candidates.append(contentsOf: syntheticExtensionCandidates)

        // Drop synthetic supertype candidates when a bundled source implementation
        // exists on a subtype. Overload resolution currently treats extension
        // functions as having no class type parameters, which makes a synthetic
        // Collection.contains look more specific than List.contains; prefer the
        // source member from the more-derived receiver.
        func receiverClassSymbol(of signature: FunctionSignature?) -> SymbolID? {
            guard let receiverType = signature?.receiverType else { return nil }
            let nonNull = sema.types.makeNonNullable(receiverType)
            guard case let .classType(classType) = sema.types.kind(of: nonNull) else {
                return nil
            }
            return classType.classSymbol
        }
        let sourceCandidates = candidates.filter { sema.symbols.isSourceBackedSymbol($0) }
        if !sourceCandidates.isEmpty {
            let sourceReceiverClasses = Set(sourceCandidates.compactMap { receiverClassSymbol(of: sema.symbols.functionSignature(for: $0)) })
            candidates = candidates.filter { candidate in
                guard sema.symbols.symbol(candidate) != nil,
                      !sema.symbols.isSourceBackedSymbol(candidate),
                      let candidateClass = receiverClassSymbol(of: sema.symbols.functionSignature(for: candidate))
                else {
                    return true
                }
                if sourceReceiverClasses.contains(candidateClass) {
                    return false
                }
                return !sourceReceiverClasses.contains(where: {
                    sema.types.isNominalSubtypeSymbol($0, of: candidateClass)
                })
            }
        }

        guard !candidates.isEmpty else { return }

        let callArgs = [CallArg(type: elementType)]
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: containsName,
                args: callArgs
            ),
            expectedType: nil,
            implicitReceiverType: nonNullContainerType,
            ctx: ctx.semaCtx
        )

        guard let chosen = resolved.chosenCallee else { return }

        sema.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map { _, value in value },
                parameterMapping: resolved.parameterMapping
            )
        )
    }

    func operatorFunctionNames(for op: BinaryOp, interner: StringInterner) -> [InternedString] {
        switch op {
        case .modulo:
            return [interner.intern("rem"), interner.intern("mod")]
        default:
            return [interner.intern(op.kotlinFunctionName)]
        }
    }

    func operatorFunctionNames(for op: UnaryOp, interner: StringInterner) -> [InternedString] {
        [interner.intern(op.kotlinFunctionName)]
    }

    func operatorFunctionNames(for op: CompoundAssignOp, interner: StringInterner) -> [InternedString] {
        switch op {
        case .modAssign:
            return [interner.intern("remAssign"), interner.intern("modAssign")]
        default:
            return [interner.intern(op.kotlinFunctionName)]
        }
    }

    func collectOperatorCandidates(
        names: [InternedString],
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let interner = ctx.interner
        let isPrimitive = if case .primitive = sema.types.kind(of: receiverType) { true } else { false }
        let allowedOnPrimitive = names.contains { name in
            switch interner.resolve(name) {
            case "downTo", "rangeTo", "rangeUntil", "step":
                return true
            default:
                return false
            }
        }
        guard !isPrimitive || allowedOnPrimitive else { return [] }

        // STDLIB-OP-031: Names that are inherently operator functions in Kotlin
        // (e.g. equals, compareTo). Overrides of these inherit operator status
        // even without the explicit `operator` keyword.
        let inheritedOperatorNames: Set<String> = ["equals", "compareTo"]

        var candidates: [SymbolID] = []
        var seen: Set<SymbolID> = []

        func operatorCandidateMatchesReceiver(_ candidate: SymbolID) -> Bool {
            guard receiverType != sema.types.errorType else {
                return false
            }
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let signatureReceiverType = signature.receiverType
            else {
                return true
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: signatureReceiverType,
                sema: sema
            )
        }

        for name in names {
            let nameStr = ctx.interner.resolve(name)
            let isInheritedOperator = inheritedOperatorNames.contains(nameStr)
            for candidate in driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            ) {
                guard seen.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate)
                else {
                    continue
                }
                guard operatorCandidateMatchesReceiver(candidate) else {
                    continue
                }
                // Accept explicit operator functions, and also accept overrides
                // of inherited operator functions (equals, compareTo) that may
                // omit the `operator` keyword. In Kotlin, overrides of Any.equals
                // and Comparable.compareTo inherit operator status.
                if symbol.flags.contains(SymbolFlags.operatorFunction) {
                    candidates.append(candidate)
                } else if isInheritedOperator,
                          symbol.kind == .function,
                          symbol.flags.contains(SymbolFlags.overrideMember) {
                    candidates.append(candidate)
                }
            }

            guard isInheritedOperator else {
                continue
            }

            let nominalRoots = driver.helpers.allNominalSymbols(
                of: receiverType,
                types: sema.types,
                symbols: sema.symbols
            )
            var ownerQueue: [SymbolID] = nominalRoots
            var visitedOwners: Set<SymbolID> = []
            while !ownerQueue.isEmpty {
                let owner = ownerQueue.removeFirst()
                guard visitedOwners.insert(owner).inserted,
                      let ownerSymbol = sema.symbols.symbol(owner)
                else {
                    continue
                }
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
                let memberFQName = ownerSymbol.fqName + [name]
                for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                    guard seen.insert(candidate).inserted,
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.flags.contains(.overrideMember),
                          sema.symbols.parentSymbol(for: candidate) == owner
                    else {
                        continue
                    }
                    guard operatorCandidateMatchesReceiver(candidate) else {
                        continue
                    }
                    candidates.append(candidate)
                }
            }
        }

        if !candidates.isEmpty {
            return candidates
        }

        for name in names {
            for candidate in ctx.cachedScopeLookup(name) {
                guard seen.insert(candidate).inserted,
                      let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let signatureReceiverType = signature.receiverType
                else {
                    continue
                }
                guard receiverType != sema.types.errorType,
                      driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                          callSiteReceiver: receiverType,
                          declaredReceiver: signatureReceiverType,
                          sema: sema
                      )
                else {
                    continue
                }
                candidates.append(candidate)
            }
        }

        // Imported library extension operators are deliberately omitted from
        // file scopes, just like other imported extensions. Recover them by
        // short name when scoped lookup produced no receiver-compatible
        // candidate; the receiver check above remains the source of truth.
        if candidates.isEmpty {
            for name in names {
                for candidate in sema.symbols.lookupByShortName(name) {
                    guard seen.insert(candidate).inserted,
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.flags.contains(.synthetic),
                          symbol.flags.contains(.operatorFunction),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let signatureReceiverType = signature.receiverType,
                          receiverType != sema.types.errorType,
                          driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                              callSiteReceiver: receiverType,
                              declaredReceiver: signatureReceiverType,
                              sema: sema
                          )
                    else {
                        continue
                    }
                    candidates.append(candidate)
                }
            }
        }

        // A precompiled extension can provide a concrete operator for the
        // receiver while the synthetic Comparable<T> interface contributes a
        // generic fallback. Prefer the exact nominal receiver in that case;
        // otherwise both candidates are indistinguishable to the overload
        // solver even though Kotlin selects the concrete extension.
        if candidates.count > 1,
           case let .classType(actualClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        {
            let exactReceiverCandidates = candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiver))
                else {
                    return false
                }
                return receiverClassType.classSymbol == actualClassType.classSymbol
            }
            if !exactReceiverCandidates.isEmpty {
                return exactReceiverCandidates
            }
        }

        return candidates
    }

    private func inferUnaryOperatorExpr(
        _ id: ExprID,
        op: UnaryOp,
        operandType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let lhsIsPrimitive = if case .primitive = sema.types.kind(of: operandType) { true } else { false }
        let operatorNames = operatorFunctionNames(for: op, interner: interner)
        let operatorCandidates = collectOperatorCandidates(
            names: operatorNames,
            receiverType: operandType,
            ctx: ctx
        )
        let displayOperatorName = interner.resolve(operatorNames[0])

        if !operatorCandidates.isEmpty {
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: operatorNames[0],
                    args: []
                ),
                expectedType: expectedType,
                implicitReceiverType: operandType,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(displayOperatorName)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let returnType = driver.callChecker.bindCallAndResolveReturnType(
                id,
                chosen: chosen,
                resolved: resolved,
                sema: sema
            )
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        if !lhsIsPrimitive,
           operandType != sema.types.anyType,
           operandType != sema.types.nullableAnyType,
           operandType != sema.types.errorType
        {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(displayOperatorName)'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        return nil
    }

    /// Resolves the type of an unsuffixed integer literal given the expected
    /// type at its use site. Kotlin widens such literals to `Long`/`UInt`/`ULong`
    /// when that is the expected type (e.g. a value class field declared `Long`
    /// receiving a plain `1500`); any other expected type falls back to `Int`.
    /// `literalValue` is used to reject out-of-range constants for `Byte`/`Short`
    /// and negative constants for unsigned types.
    private func intLiteralType(expectedType: TypeID?, sema: SemaModule, defaultType: TypeID, literalValue: Int64 = 0) -> TypeID {
        guard let expectedType else { return defaultType }
        let nonNullExpected = sema.types.makeNonNullable(expectedType)
        guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullExpected) else {
            return defaultType
        }
        switch primitive {
        case .long: return sema.types.longType
        case .uint: return literalValue >= 0 ? sema.types.uintType : defaultType
        case .ulong: return literalValue >= 0 ? sema.types.ulongType : defaultType
        case .byte: return (literalValue >= -128 && literalValue <= 127) ? sema.types.byteType : defaultType
        case .short: return (literalValue >= -32768 && literalValue <= 32767) ? sema.types.shortType : defaultType
        default: return defaultType
        }
    }

    /// Resolves a suffixed unsigned integer literal against an expected unsigned
    /// type. Kotlin permits constant unsigned literals such as 1u to narrow to
    /// UByte/UShort (and widen to ULong) at a call site when the value fits.
    private func uintLiteralType(expectedType: TypeID?, sema: SemaModule, literalValue: UInt64) -> TypeID {
        guard let expectedType else {
            return sema.types.uintType
        }
        let nonNullExpected = sema.types.makeNonNullable(expectedType)
        guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullExpected) else {
            return sema.types.uintType
        }
        switch primitive {
        case .ulong:
            return sema.types.ulongType
        case .ubyte:
            return literalValue <= UInt64(UInt8.max) ? sema.types.ubyteType : sema.types.uintType
        case .ushort:
            return literalValue <= UInt64(UInt16.max) ? sema.types.ushortType : sema.types.uintType
        default:
            return sema.types.uintType
        }
    }
}
