
extension ExprTypeChecker {
    func applyFlowStateToLocals(
        _ state: DataFlowState,
        locals: inout LocalBindings,
        sema _: SemaModule
    ) {
        for (name, local) in locals {
            guard let varState = state.variables[local.symbol],
                  varState.possibleTypes.count == 1,
                  let narrowed = varState.possibleTypes.first
            else {
                continue
            }
            locals[name] = (narrowed, local.symbol, local.isMutable, local.isInitialized)
        }
    }

    // MARK: - Binary Expression Inference

    // swiftlint:disable:next cyclomatic_complexity
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
        let ulongType = sema.types.ulongType
        let uintType = sema.types.uintType

        if op == .logicalAnd || op == .logicalOr {
            let lhs = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            driver.emitSubtypeConstraint(
                left: lhs,
                right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let lhsBranch = ctx.dataFlow.branchOnCondition(
                lhsID,
                base: ctx.flowState,
                locals: locals,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope
            )
            let rhsState = op == .logicalAnd ? lhsBranch.trueState : lhsBranch.falseState
            var rhsLocals = locals
            applyFlowStateToLocals(rhsState, locals: &rhsLocals, sema: sema)
            let rhs = driver.inferExpr(
                rhsID,
                ctx: ctx.copying(flowState: rhsState),
                locals: &rhsLocals
            )
            driver.emitSubtypeConstraint(
                left: rhs,
                right: boolType,
                range: ast.arena.exprRange(rhsID) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }

        let lhs = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
        // Elvis can narrow an integer literal on the right side to the overall
        // expected type, e.g. `val b: Byte = parsed ?: 0`.
        let rhsExpectedType: TypeID? = if op == .elvis { expectedType } else { nil }
        let rhs = driver.inferExpr(rhsID, ctx: ctx, locals: &locals, expectedType: rhsExpectedType)
        // `===`/`!==` are raw identity comparisons: unlike `==`/`!=` they never
        // dispatch through a user-defined (or inherited Any) `equals()` override,
        // so they must bypass the operator-candidate resolution below entirely —
        // any two types are comparable, and the result is always Boolean.
        if op == .identityEqual || op == .notIdentityEqual {
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        if op == .add,
           isCoroutineContextLikeType(lhs, sema: sema, interner: interner),
           isCoroutineContextLikeType(rhs, sema: sema, interner: interner),
           let coroutineContextType = coroutineContextType(sema: sema, interner: interner)
        {
            sema.bindings.bindExprType(id, type: coroutineContextType)
            return coroutineContextType
        }
        let lhsIsPrimitive = if case .primitive = sema.types.kind(of: lhs) { true } else { false }
        let operatorNames = operatorFunctionNames(for: op, interner: interner)
        let operatorName = operatorNames[0]
        let shouldUseInheritedEqualityDispatch: Bool = switch op {
        case .equal, .notEqual:
            sema.types.isDefinitelyNonNull(lhs) && sema.types.isDefinitelyNonNull(rhs)
        default:
            true
        }
        let collectedOperatorCandidates: [SymbolID] = if shouldUseInheritedEqualityDispatch {
            collectOperatorCandidates(
                names: operatorNames,
                receiverType: lhs,
                ctx: ctx
            )
        } else {
            []
        }
        let operatorCandidates = driver.callChecker.preferMostSpecificMemberReceiverCandidates(
            collectedOperatorCandidates,
            receiverType: lhs,
            argumentTypes: [rhs],
            sema: sema,
            interner: interner
        )
        // Kotlin's `+` resolves against the LHS (receiver) type: `String.plus(Any?)`
        // accepts any RHS, but non-String receivers don't get string concatenation
        // just because the RHS happens to be a String (e.g. `1 + "x"` is not valid
        // Kotlin, and `listOf("x") + "y"` must resolve via the List plus fallback
        // below, not collapse to `String`).
        if op == .add, sema.types.isString(lhs) {
            sema.bindings.bindExprType(id, type: stringType)
            return stringType
        }
        // STDLIB-345: List/Sequence plus/minus operators
        if !lhsIsPrimitive, op == .add || op == .subtract {
            let isListLhs = driver.callChecker.isListLikeType(lhs, sema: sema, interner: interner)
            let isSeqLhs = driver.callChecker.isSequenceLikeType(lhs, sema: sema, interner: interner)
            let isCollExpr = sema.bindings.isCollectionExpr(lhsID)
            // For lists and plain collection exprs: fall back only when no operator candidates exist.
            // For sequences: also fall back when candidates exist but none accepts the RHS type
            // (e.g. `seq + element` where only `plus(Sequence<Any>)` is registered).
            let shouldFallBack = (isListLhs || isCollExpr) && operatorCandidates.isEmpty
                || isSeqLhs && operatorCandidates.isEmpty
            if shouldFallBack {
                sema.bindings.bindExprType(id, type: lhs)
                sema.bindings.markCollectionExpr(id)
                return lhs
            }
        }
        let lhsIsAny = lhs == sema.types.anyType || lhs == sema.types.nullableAnyType
        let rhsIsAny = rhs == sema.types.anyType || rhs == sema.types.nullableAnyType
        if !lhsIsPrimitive, !lhsIsAny, !rhsIsAny, operatorCandidates.isEmpty, lhs != sema.types.errorType, rhs != sema.types.errorType {
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
            // Comparison operators desugar to compareTo(), which always returns Int.
            // The binary expression itself is Boolean, so do not pass that as the
            // call's expected return type; otherwise Int <: Boolean fails.
            let operatorExpectedType: TypeID? = switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                intType
            default:
                expectedType
            }
            let isSeqLhs = driver.callChecker.isSequenceLikeType(lhs, sema: sema, interner: interner)
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: operatorName,
                    args: [CallArg(type: rhs)]
                ),
                expectedType: operatorExpectedType,
                implicitReceiverType: lhs,
                ctx: ctx.semaCtx
            )
            if isSeqLhs, resolved.chosenCallee == nil {
                sema.bindings.bindExprType(id, type: lhs)
                sema.bindings.markCollectionExpr(id)
                return lhs
            }
            if let diagnostic = resolved.diagnostic {
                if let fallbackType = bindComparableUpperBoundOperatorFallback(
                    id,
                    op: op,
                    lhs: lhs,
                    rhs: rhs,
                    candidates: operatorCandidates,
                    sema: sema
                ) {
                    return fallbackType
                }
                if lhs != sema.types.errorType, rhs != sema.types.errorType {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                if let fallbackType = bindComparableUpperBoundOperatorFallback(
                    id,
                    op: op,
                    lhs: lhs,
                    rhs: rhs,
                    candidates: operatorCandidates,
                    sema: sema
                ) {
                    return fallbackType
                }
                if lhs != sema.types.errorType, rhs != sema.types.errorType {
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
            let effectiveType: TypeID = switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                boolType
            default:
                returnType
            }
            if [.rangeTo, .rangeUntil, .downTo, .step].contains(op) {
                // Source-backed range operators do not reach the legacy range
                // marker path below when ordinary operator resolution succeeds.
                driver.callChecker.markRangeCallBindings(
                    id,
                    chosen: chosen,
                    returnType: returnType,
                    sema: sema
                )
                if [.rangeTo, .rangeUntil, .downTo].contains(op) {
                    sema.bindings.markRangeExpr(id)
                    if lhs == ulongType || rhs == ulongType {
                        sema.bindings.markULongRangeExpr(id)
                    } else if lhs == uintType || rhs == uintType {
                        sema.bindings.markUIntRangeExpr(id)
                    }
                    if lhs == charType || rhs == charType {
                        sema.bindings.markCharRangeExpr(id)
                    }
                } else {
                    sema.bindings.markRangeExpr(id)
                    if lhs == uintType || sema.bindings.isUIntRangeExpr(lhsID) {
                        sema.bindings.markUIntRangeExpr(id)
                    }
                    if lhs == ulongType || sema.bindings.isULongRangeExpr(lhsID) {
                        sema.bindings.markULongRangeExpr(id)
                    }
                    if sema.bindings.isCharRangeExpr(lhsID) {
                        sema.bindings.markCharRangeExpr(id)
                    }
                }
            }
            sema.bindings.bindExprType(id, type: effectiveType)
            return effectiveType
        }
        let type: TypeID
        let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
        let ushortType = sema.types.make(.primitive(.ushort, .nonNull))

        let lhsIsSigned = sema.types.isSigned(lhs)
        let rhsIsUnsigned = sema.types.isUnsigned(rhs)
        let lhsIsUnsigned = sema.types.isUnsigned(lhs)
        let rhsIsSigned = sema.types.isSigned(rhs)

        // Kotlin's UIntProgression.step(Int) and ULongProgression.step(Long)
        // take a signed parameter, so mixed signedness is valid only when the
        // receiver is unsigned and the step operand matches the expected signed
        // type: Int for UIntProgression, Int or Long for ULongProgression
        // (Int is implicitly widened to Long in Kotlin).
        // The reverse (signed..signed step unsigned) is rejected because
        // IntProgression.step takes Int, not UInt.
        let allowsMixedSignedness: Bool = {
            if case .step = op, lhsIsUnsigned, rhsIsSigned {
                // UIntProgression.step expects Int
                if lhs == uintType { return rhs == intType }
                // ULongProgression.step expects Long. Kotlin does not perform
                // implicit numeric widening for non-literals; only integer
                // literal constants adapt to the expected parameter type.
                // Accept Int only when the rhs is a literal constant.
                if lhs == ulongType {
                    if rhs == longType { return true }
                    if rhs == intType {
                        if let rhsExpr = ast.arena.expr(rhsID),
                           case .intLiteral = rhsExpr {
                            return true
                        }
                        return false
                    }
                }
            }
            return false
        }()

        if !allowsMixedSignedness, (lhsIsSigned && rhsIsUnsigned) || (lhsIsUnsigned && rhsIsSigned) {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0043",
                "Operator '\(interner.resolve(operatorName))' cannot be applied to '(signed, unsigned)' or '(unsigned, signed)' types.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        switch op {
        case .add:
            if sema.types.isString(lhs) || sema.types.isString(rhs) {
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
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhs == uintType || rhs == uintType {
                type = uintType
            } else if lhs == ushortType || rhs == ushortType {
                type = ushortType
            } else if lhs == ubyteType || rhs == ubyteType {
                type = ubyteType
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
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhs == uintType || rhs == uintType {
                type = uintType
            } else if lhs == ushortType || rhs == ushortType {
                type = ushortType
            } else if lhs == ubyteType || rhs == ubyteType {
                type = ubyteType
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
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhs == uintType || rhs == uintType {
                type = uintType
            } else if lhs == ushortType || rhs == ushortType {
                type = ushortType
            } else if lhs == ubyteType || rhs == ubyteType {
                type = ubyteType
            } else {
                type = intType
            }
        case .equal, .notEqual, .identityEqual, .notIdentityEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
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
               driver.helpers.isTerminatingExpr(rhsExpr)
            {
                if let lhsExpr = ast.arena.expr(lhsID),
                   case let .nameRef(elvisVarName, _) = lhsExpr,
                   let elvisLocal = locals[elvisVarName],
                   driver.helpers.isStableLocalSymbol(elvisLocal.symbol, sema: sema)
                {
                    let nonNullType = sema.types.makeNonNullable(elvisLocal.type)
                    locals[elvisVarName] = (nonNullType, elvisLocal.symbol, elvisLocal.isMutable, elvisLocal.isInitialized)
                }
            }
        case .rangeTo, .rangeUntil, .downTo:
            // LongRange when either operand is Long; ULongRange when ULong (STDLIB-524);
            // UIntRange when UInt (STDLIB-523); IntRange otherwise.
            if lhs == longType || rhs == longType {
                type = longType
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
                sema.bindings.markULongRangeExpr(id)
            } else if lhs == uintType || rhs == uintType {
                type = uintType
                sema.bindings.markUIntRangeExpr(id)
            } else {
                type = intType
            }
            sema.bindings.markRangeExpr(id)
            if lhs == sema.types.doubleType || rhs == sema.types.doubleType ||
                lhs == sema.types.floatType || rhs == sema.types.floatType
            {
                let elementType = lhs == sema.types.floatType || rhs == sema.types.floatType
                    ? sema.types.floatType
                    : sema.types.doubleType
                sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id)
            }
            // Detect CharRange: if either operand is Char, mark as char range (STDLIB-290)
            if lhs == sema.types.charType || rhs == sema.types.charType {
                sema.bindings.markCharRangeExpr(id)
            }
        case .step:
            // LongRange when the receiver (lhs) is Long; ULongRange when ULong (STDLIB-524);
            // UIntRange when UInt (STDLIB-523); IntRange otherwise.
            if lhs == longType {
                type = longType
            } else if lhs == ulongType {
                type = ulongType
            } else if lhs == uintType {
                type = uintType
                sema.bindings.markUIntRangeExpr(id)
            } else {
                type = intType
            }
            sema.bindings.markRangeExpr(id)
            // For step, inherit CharRange flag from the receiver (the range expression)
            if sema.bindings.isCharRangeExpr(lhsID) {
                sema.bindings.markCharRangeExpr(id)
            }
            // Inherit ULong range flag from the receiver (STDLIB-524)
            if sema.bindings.isULongRangeExpr(lhsID) {
                sema.bindings.markULongRangeExpr(id)
            }
            if sema.bindings.isUIntRangeExpr(lhsID) {
                sema.bindings.markUIntRangeExpr(id)
            }
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be parsed as infix member calls")
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    private func bindComparableUpperBoundOperatorFallback(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: TypeID,
        rhs: TypeID,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            break
        default:
            return nil
        }
        guard case let .typeParam(lhsParam) = sema.types.kind(of: lhs),
              rhs == lhs || sema.types.isSubtype(rhs, lhs),
              let comparableSymbol = sema.types.comparableInterfaceSymbol,
              typeParameter(lhsParam.symbol, hasComparableSelfBound: lhs, comparableSymbol: comparableSymbol, sema: sema),
              let chosen = candidates.first(where: { candidate in
                  guard let signature = sema.symbols.functionSignature(for: candidate) else {
                      return false
                  }
                  return signature.receiverType != nil && signature.parameterTypes.count == 1
              })
        else {
            return nil
        }

        sema.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [lhs],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(exprID, target: .symbol(chosen))
        sema.bindings.bindExprType(exprID, type: sema.types.booleanType)
        return sema.types.booleanType
    }

    private func typeParameter(
        _ symbol: SymbolID,
        hasComparableSelfBound targetType: TypeID,
        comparableSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.typeParameterUpperBounds(for: symbol).contains { bound in
            comparableSelfBoundContains(
                bound,
                targetType: targetType,
                comparableSymbol: comparableSymbol,
                sema: sema
            )
        }
    }

    private func comparableSelfBoundContains(
        _ bound: TypeID,
        targetType: TypeID,
        comparableSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        switch sema.types.kind(of: bound) {
        case let .classType(classType):
            guard classType.classSymbol == comparableSymbol,
                  classType.args.count == 1
            else {
                return false
            }

            // Support both invariant and contravariant Comparable bounds
            let argumentType: TypeID
            switch classType.args[0] {
            case let .invariant(type):
                argumentType = type
            case let .in(type):
                argumentType = type
            default:
                return false
            }

            return argumentType == targetType

        case let .intersection(parts):
            return parts.contains {
                comparableSelfBoundContains(
                    $0,
                    targetType: targetType,
                    comparableSymbol: comparableSymbol,
                    sema: sema
                )
            }

        default:
            return false
        }
    }

    private func coroutineContextType(sema: SemaModule, interner: StringInterner) -> TypeID? {
        // CoroutineContext lives in kotlin.coroutines (not kotlinx.coroutines)
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("CoroutineContext"),
        ]
        guard let symbol = sema.symbols.lookup(fqName: fqName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func isCoroutineContextLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let kotlinxCoroutinesPkg = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        // CoroutineContext lives in kotlin.coroutines, others in kotlinx.coroutines
        let kotlinCoroutinesPkg = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        guard symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg) else {
            return false
        }
        let typeName = interner.resolve(symbol.name)
        return typeName == "CoroutineContext"
            || typeName == "CoroutineDispatcher"
            || typeName == "CoroutineName"
            || typeName == "CoroutineExceptionHandler"
            || typeName == "Job"
    }

    // MARK: - Compound Assignment
}
