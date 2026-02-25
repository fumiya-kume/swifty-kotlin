import Foundation

/// Delegate class for KIR lowering: CallLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class CallLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Invoke operator calls are lowered as member calls: the callee expr
        // becomes the receiver and the invoke method is the callee.
        if sema.bindings.isInvokeOperatorCall(exprID) {
            let invokeName = interner.intern("invoke")
            return lowerMemberCallExpr(
                exprID,
                receiverExpr: calleeExpr,
                calleeName: invokeName,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredCalleeExprID = driver.lowerExpr(
            calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let loweredCallable = driver.ctx.callableValueInfoByExprID[loweredCalleeExprID]
        let sourceCalleeName: InternedString
        if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
            sourceCalleeName = name
        } else if let loweredCallable {
            sourceCalleeName = loweredCallable.callee
        } else {
            sourceCalleeName = interner.intern("<unknown>")
        }
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let callBinding = sema.bindings.callBindings[exprID]
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let chosen = callBinding?.chosenCallee
        let callNormalized: NormalizedCallResult
        if callBinding != nil {
            callNormalized = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            callNormalized = NormalizedCallResult(
                arguments: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableValueCallBinding,
                    sema: sema
                ),
                defaultMask: 0
            )
        }
        var finalArgIDs = callNormalized.arguments
        if let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
                  sema.symbols.symbol(chosen)?.kind == .constructor {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_array_new(slotCount) and prepend it to the argument list.
            // Derive slot count from NominalLayout.instanceSizeWords of the owning class.
            let allocType = boundType ?? sema.types.anyType
            let intType = sema.types.make(.primitive(.int, .nonNull))
            var slotCount: Int64 = 1
            if let parentClassID = sema.symbols.parentSymbol(for: chosen),
               let layout = sema.symbols.nominalLayout(for: parentClassID) {
                slotCount = Int64(max(layout.instanceSizeWords, 1))
            }
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
            instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_new"),
                arguments: [slotCountExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            finalArgIDs.insert(allocatedObj, at: 0)
        } else if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil,
           let implicitReceiver = driver.ctx.currentImplicitReceiverExprID {
            finalArgIDs.insert(implicitReceiver, at: 0)
        }

        // Inject callable value captures for coroutine launcher arguments.
        // When a suspend lambda/closure with captures is passed to a launcher
        // (runBlocking/launch/async), the capture values must be included in
        // the call arguments so the CoroutineLoweringPass can store them in
        // the continuation via launcherArgs and forward them through the thunk.
        // Guard on chosen == nil && loweredCallable == nil to avoid misfiring
        // on user-defined functions that happen to share a launcher name.
        // Only expand captures for the first argument (the launcher entry
        // function reference); subsequent arguments are value args for the
        // referenced suspend function and should not be expanded.
        if chosen == nil,
           loweredCallable == nil {
            let resolvedSourceCallee = interner.resolve(sourceCalleeName)
            if resolvedSourceCallee == "runBlocking"
                || resolvedSourceCallee == "launch"
                || resolvedSourceCallee == "async",
               let firstArg = finalArgIDs.first,
               let callableInfo = driver.ctx.callableValueInfoByExprID[firstArg],
               !callableInfo.captureArguments.isEmpty {
                finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 1)
            }
        }
        if callNormalized.defaultMask != 0, let chosen {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            appendDefaultMaskArgument(
                callNormalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let stubName = interner.intern(interner.resolve(sourceCalleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let loweredCalleeName: InternedString
            if let chosen {
                loweredCalleeName = loweredCalleeNameForSymbol(
                    chosenCallee: chosen,
                    fallback: sourceCalleeName,
                    sema: sema,
                    interner: interner
                )
            } else if let loweredCallable {
                loweredCalleeName = loweredCallable.callee
            } else if chosen == nil {
                loweredCalleeName = driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    interner: interner
                ) ?? sourceCalleeName
            } else {
                loweredCalleeName = sourceCalleeName
            }
            instructions.append(.call(
                symbol: chosen ?? loweredCallable?.symbol,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return result
    }

    private func appendReifiedTypeTokens(
        chosenCallee: SymbolID?,
        callBinding: CallBinding?,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let callBinding,
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              !signature.reifiedTypeParameterIndices.isEmpty else {
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        for index in signature.reifiedTypeParameterIndices.sorted() {
            let concreteType = index < callBinding.substitutedTypeArguments.count
                ? callBinding.substitutedTypeArguments[index]
                : sema.types.anyType
            let tokenExpr = arena.appendExpr(
                .intLiteral(Int64(concreteType.rawValue)),
                type: intType
            )
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
            arguments.append(tokenExpr)
        }
    }

    private func appendDefaultMaskArgument(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskExpr = arena.appendExpr(.intLiteral(defaultMask), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(defaultMask)))
        arguments.append(maskExpr)
    }

    private func loweredCalleeNameForSymbol(
        chosenCallee: SymbolID,
        fallback: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              !externalLinkName.isEmpty else {
            return fallback
        }
        return interner.intern(externalLinkName)
    }

    private func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case .functionType(let functionType) = sema.types.kind(of: callableValueCallBinding.functionType) else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }

}
