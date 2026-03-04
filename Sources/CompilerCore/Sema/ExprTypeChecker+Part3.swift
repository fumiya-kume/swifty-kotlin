import Foundation

// Handles expression type inference dispatch and specific expression cases.
// Derived from TypeCheckSemaPhase+ExprInference.swift and TypeCheckSemaPhase+ExprInferCases.swift.

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
        let rhs = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
        let lhsIsPrimitive = if case .primitive = sema.types.kind(of: lhs) { true } else { false }
        let operatorName = interner.intern(op.kotlinFunctionName)
        let memberOperatorCandidates = lhsIsPrimitive ? [] : driver.helpers.collectMemberFunctionCandidates(
            named: operatorName,
            receiverType: lhs,
            sema: sema
        )
        let operatorCandidates: [SymbolID] = if !memberOperatorCandidates.isEmpty {
            memberOperatorCandidates
        } else if !lhsIsPrimitive {
            ctx.cachedScopeLookup(operatorName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType != nil
            }
        } else {
            []
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
                if lhs != sema.types.errorType, rhs != sema.types.errorType {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
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
            sema.bindings.bindExprType(id, type: effectiveType)
            return effectiveType
        }
        let type: TypeID
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let uintType = sema.types.uintType
        let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
        let ushortType = sema.types.make(.primitive(.ushort, .nonNull))

        let lhsIsSigned = sema.types.isSigned(lhs)
        let rhsIsUnsigned = sema.types.isUnsigned(rhs)
        let lhsIsUnsigned = sema.types.isUnsigned(lhs)
        let rhsIsSigned = sema.types.isSigned(rhs)

        if (lhsIsSigned && rhsIsUnsigned) || (lhsIsUnsigned && rhsIsSigned) {
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
        case .rangeTo, .rangeUntil, .downTo, .step:
            type = sema.types.intType
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be parsed as infix member calls")
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    // MARK: - Compound Assignment
}
