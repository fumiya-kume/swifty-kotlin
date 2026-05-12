/// Lowerings for the `takeIf` / `takeUnless` (STDLIB-160) and the
/// `let` / `also` / `apply` / `run` / `with` scope-function family.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {

    // MARK: - takeIf / takeUnless Lowering (STDLIB-160)

    /// Attempts to lower a takeIf / takeUnless extension call.
    /// Returns nil if the expression is not a takeIf/takeUnless call.
    func tryTakeIfTakeUnlessLowering(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil
    ) -> KIRExprID? {
        guard let takeKind = sema.bindings.takeIfTakeUnlessKind(for: exprID),
              args.count == 1
        else { return nil }

        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Lower lambda: predicate(receiver) -> Boolean (like scopeLet: lambda takes `it`)
        let loweredLambdaID = driver.lowerExpr(
            args[0].expr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
            return nil
        }

        let predicateResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boolType
        )
        let callArgs: [KIRExprID]
        if info.hasClosureParam {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
        } else {
            callArgs = info.captureArguments + [loweredReceiverID]
        }
        instructions.append(.call(
            symbol: info.symbol,
            callee: info.callee,
            arguments: callArgs,
            result: predicateResult,
            canThrow: false,
            thrownResult: nil
        ))

        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        let useReceiverLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let testValue: Bool = takeKind == .takeIf
        let testExpr = arena.appendExpr(.boolLiteral(testValue), type: boolType)
        instructions.append(.constValue(result: testExpr, value: .boolLiteral(testValue)))

        // takeIf: jump to useReceiver when predicate == true
        // takeUnless: jump to useReceiver when predicate == false
        instructions.append(.jumpIfEqual(lhs: predicateResult, rhs: testExpr, target: useReceiverLabel))

        // Predicate failed: write null to result
        let nullVal = arena.appendExpr(.unit, type: boundType)
        instructions.append(.constValue(result: nullVal, value: .null))
        instructions.append(.copy(from: nullVal, to: result))
        instructions.append(.jump(endLabel))

        // Predicate passed: forward the lowered receiver as-is.
        // The surrounding lowering/codegen path will box later if needed.
        instructions.append(.label(useReceiverLabel))
        instructions.append(.copy(from: loweredReceiverID, to: result))
        instructions.append(.label(endLabel))

        return result
    }

    // MARK: - Scope Function Lowering (STDLIB-004)

    /// Attempts to lower a scope function call (let/run/apply/also).
    /// Returns nil if the expression is not a scope function call.
    func tryScopeFunctionLowering(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil
    ) -> KIRExprID? {
        guard let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
              args.count == 1
        else { return nil }

        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        // Lower the receiver expression (or use precomputed one for safe calls).
        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        switch scopeKind {
        case .scopeLet, .scopeAlso:
            // let/also: lambda takes `it` as explicit parameter.
            // Lower lambda normally, then call it with receiver as argument.
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                let callArgs: [KIRExprID]
                if info.hasClosureParam {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
                } else {
                    callArgs = info.captureArguments + [loweredReceiverID]
                }
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: callArgs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Non-lambda-literal argument (e.g. function reference);
                // fall back to normal member call lowering.
                return nil
            }
            if scopeKind == .scopeAlso {
                // also: result is the receiver, not the lambda return value.
                instructions.append(.copy(from: loweredReceiverID, to: result))
            }
            return result

        case .scopeRun, .scopeApply:
            // run/apply: lambda has `this` as implicit receiver.
            // Set the implicit receiver to the lowered receiver before lowering
            // the lambda so that the lambda captures it.
            let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverSymExpr))

            let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
            let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
            driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)

            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Non-lambda-literal argument (e.g. function reference);
                // restore state and fall back to normal member call lowering.
                driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
                return nil
            }
            if scopeKind == .scopeApply {
                // apply: result is the receiver, not the lambda return value.
                instructions.append(.copy(from: loweredReceiverID, to: result))
            }
            return result

        case .scopeUse:
            // use: like `let`, lambda takes `it` as explicit parameter,
            // but receiver.close() is called in a finally block (try-finally semantics).
            // If the block throws, close() is still called before the exception propagates.
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
                return nil
            }

            let intType = sema.types.make(.primitive(.int, .nonNull))

            // Exception tracking slots for try-finally.
            let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.nullableAnyType)
            let exceptionTypeSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nullExceptionValue, value: .null))
            instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            let finallyLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()

            // try: invoke the block lambda.
            var blockInstructions: [KIRInstruction] = []
            let callArgs: [KIRExprID]
            if info.hasClosureParam {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                blockInstructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
            } else {
                callArgs = info.captureArguments + [loweredReceiverID]
            }
            blockInstructions.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: callArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))

            // Wrap block call with throw-aware instructions so exceptions are
            // captured into exceptionSlot and control jumps to finallyLabel.
            driver.controlFlowLowerer.appendThrowAwareInstructions(
                blockInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.jump(finallyLabel))

            // finally: call close() on the receiver via virtual dispatch.
            // close() is an interface method on Closeable and requires dynamic dispatch
            // through the itable so that concrete implementations are invoked correctly.
            instructions.append(.label(finallyLabel))
            let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
            let shouldGuardNullableClose = receiverTypeForDispatch.map {
                sema.types.nullability(of: $0) != .nonNull
            } ?? false
            let closeEndLabel: Int32? = shouldGuardNullableClose ? driver.ctx.makeLoopLabel() : nil
            if shouldGuardNullableClose, let closeEndLabel {
                let closeCallLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: closeCallLabel))
                instructions.append(.jump(closeEndLabel))
                instructions.append(.label(closeCallLabel))
            }
            let closeName = interner.intern("close")
            let closeResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.unitType
            )
            // Resolve the close() symbol from the Closeable interface and use
            // virtualCall with interface dispatch instead of a static .call.
            let closeableFQName: [InternedString] = [
                interner.intern("kotlin"), interner.intern("io"), interner.intern("Closeable")
            ]
            let closeFQName = closeableFQName + [closeName]
            let closeSymbol = sema.symbols.lookup(fqName: closeFQName)
            let closeDispatch: KIRDispatchKind? = closeSymbol.flatMap { sym in
                resolveVirtualDispatch(callee: sym, receiverTypeID: receiverTypeForDispatch, sema: sema)
            }
            if let closeDispatch, let closeSymbol {
                instructions.append(.virtualCall(
                    symbol: closeSymbol,
                    callee: closeName,
                    receiver: loweredReceiverID,
                    arguments: [],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil,
                    dispatch: closeDispatch
                ))
            } else {
                // Fallback: if virtual dispatch is not needed (e.g. final class with
                // no subtypes), resolve the concrete close() method on the receiver type
                // so that the static call targets the correct mangled name.
                var concreteCloseSymbol: SymbolID? = nil
                var concreteCloseName = closeName
                if let recvTypeID = receiverTypeForDispatch,
                   case let .classType(recvClass) = sema.types.kind(of: recvTypeID)
                {
                    let recvSymbol = recvClass.classSymbol
                    if let recvInfo = sema.symbols.symbol(recvSymbol) {
                        let closeCandidateFQ = recvInfo.fqName + [closeName]
                        if let concreteSym = sema.symbols.lookup(fqName: closeCandidateFQ) {
                            concreteCloseSymbol = concreteSym
                            // Prefer the externalLinkName (e.g. kk_buffered_writer_close) over
                            // the Kotlin symbol name (which would just be "close") so that the
                            // generated .call instruction targets the correct runtime C function.
                            if let extLink = sema.symbols.externalLinkName(for: concreteSym),
                               !extLink.isEmpty
                            {
                                concreteCloseName = interner.intern(extLink)
                            } else {
                                concreteCloseName = sema.symbols.symbol(concreteSym)?.name ?? closeName
                            }
                        }
                    }
                }
                let callSymbol = concreteCloseSymbol ?? closeSymbol
                instructions.append(.call(
                    symbol: callSymbol,
                    callee: concreteCloseName,
                    arguments: [loweredReceiverID],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil
                ))
            }
            if let closeEndLabel {
                instructions.append(.label(closeEndLabel))
            }

            // After finally: rethrow if an exception was caught, otherwise continue.
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            return result

        case .scopeWith:
            return nil // with is handled in lowerCallExpr

        case .scopeContext:
            return nil // context is handled in lowerCallExpr

        case .scopeTopLevelRun:
            return nil // top-level run is handled in lowerCallExpr
        }
    }
}
