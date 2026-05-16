// swiftlint:disable file_length
import Foundation

/// Compatibility entry point for legacy safe member-call lowering.
///
/// The newer shared-context overload remains in `CallLowerer+SafeMemberCalls.swift`.
extension CallLowerer {
    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let lateinitStatus = tryLowerLateinitIsInitialized(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return lateinitStatus
        }

        // --- takeIf / takeUnless with safe call (STDLIB-160) ---
        if sema.bindings.takeIfTakeUnlessKind(for: exprID) != nil {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
            let nullVal = arena.appendExpr(.unit, type: boundType)
            instructions.append(.constValue(result: nullVal, value: .null))
            instructions.append(.copy(from: nullVal, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            if let takeResult = tryTakeIfTakeUnlessLowering(
                exprID,
                receiverExpr: receiverExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions,
                precomputedReceiver: loweredReceiver
            ) {
                instructions.append(.copy(from: takeResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        // --- Scope functions with safe call: ?.let, ?.run, etc. (STDLIB-004) ---
        // For safe-call (?.let etc.), we need a null guard: if receiver is null,
        // skip the lambda and produce null; otherwise invoke normally.
        if sema.bindings.scopeFunctionKind(for: exprID) != nil {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nullableResultType = sema.types.makeNullable(boundType)
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: nullableResultType
            )
            // Lower receiver first for null check
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            // Jump to nonNullLabel if receiver is not null
            instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
            // Null path: produce null result
            let nullVal = arena.appendExpr(.unit, type: nullableResultType)
            instructions.append(.constValue(result: nullVal, value: .null))
            instructions.append(.copy(from: nullVal, to: result))
            instructions.append(.jump(endLabel))
            // Non-null path: invoke the scope function
            instructions.append(.label(nonNullLabel))
            if let scopeResult = tryScopeFunctionLowering(
                exprID,
                receiverExpr: receiverExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions,
                precomputedReceiver: loweredReceiver
            ) {
                instructions.append(.copy(from: scopeResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        let safeReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullSafeReceiverType = sema.types.makeNonNullable(safeReceiverType)
        let safeBooleanCallee = interner.resolve(effectiveCalleeName)
        if sema.types.isSubtype(nonNullSafeReceiverType, sema.types.booleanType) {
            let boolRuntimeCallee: InternedString? = switch safeBooleanCallee {
            case "not" where args.isEmpty:
                interner.intern("kk_op_not")
            case "and" where args.count == 1:
                interner.intern("kk_bitwise_and")
            case "or" where args.count == 1:
                interner.intern("kk_bitwise_or")
            case "xor" where args.count == 1:
                interner.intern("kk_bitwise_xor")
            default:
                nil
            }
            if let boolRuntimeCallee {
                let boundType = sema.types.makeNullable(sema.types.booleanType)
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
                let nullVal = arena.appendExpr(.unit, type: boundType)
                instructions.append(.constValue(result: nullVal, value: .null))
                instructions.append(.copy(from: nullVal, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                let nonNullResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.booleanType)
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(
                        argument.expr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                let callArguments = [loweredReceiver] + loweredArgIDs
                instructions.append(.call(
                    symbol: nil,
                    callee: boolRuntimeCallee,
                    arguments: callArguments,
                    result: nonNullResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.copy(from: nonNullResult, to: result))
                instructions.append(.label(endLabel))
                return result
            }
        }

        // Int/Long/Double/Float.coerceIn(range) safe-call: null guard + range decomposition (STDLIB-525, STDLIB-CONV-006)
        // The generic lowerMemberLikeCallExpr path does not emit a null guard for
        // safe-call receivers, so we must handle coerceIn(range) here.
        if args.count == 1, interner.resolve(effectiveCalleeName) == "coerceIn" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let argExprID = args[0].expr
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if let rangeElementType = coerceInRangeElementType(
                    for: argExprID,
                    sema: sema,
                    interner: interner
                ),
                rangeElementType == nonNullReceiverType
                {
                    let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
                    let result = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: boundType
                    )
                    let loweredReceiver = driver.lowerExpr(
                        receiverExpr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let loweredRangeArg = driver.lowerExpr(
                        argExprID,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let callLabel = driver.ctx.makeLoopLabel()
                    let endLabel = driver.ctx.makeLoopLabel()
                    instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
                    let nullExpr = arena.appendExpr(.null, type: boundType)
                    instructions.append(.constValue(result: nullExpr, value: .null))
                    instructions.append(.copy(from: nullExpr, to: result))
                    instructions.append(.jump(endLabel))
                    instructions.append(.label(callLabel))
                    emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiver,
                        loweredRangeArgID: loweredRangeArg,
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    instructions.append(.label(endLabel))
                    return result
                }
            }
        }

        // Int/Long/Double/Float.coerceIn(min, max) safe-call: null guard (STDLIB-150, STDLIB-500)
        if args.count == 2, interner.resolve(effectiveCalleeName) == "coerceIn" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(
                        argument.expr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                let callLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
                let nullExpr = arena.appendExpr(.null, type: boundType)
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(callLabel))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(prefix + "_coerceIn"),
                    arguments: [loweredReceiver, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.label(endLabel))
                return result
            }
        }

        // General safe-call: emit null guard around the member call so that
        // when the receiver is null the entire expression short-circuits to null.
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        let loweredReceiver = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
        let nullExpr = arena.appendExpr(.null, type: boundType)
        instructions.append(.constValue(result: nullExpr, value: .null))
        instructions.append(.copy(from: nullExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(callLabel))
        let innerResult = lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: true,
            prependReceiverForUnresolvedCollectionCall: false,
            instructions: &instructions
        )
        instructions.append(.copy(from: innerResult, to: result))
        instructions.append(.label(endLabel))
        return result
    }

}
