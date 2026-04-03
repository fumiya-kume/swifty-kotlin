import Foundation

extension CoroutineLoweringPass {
    struct LauncherThunkSynthesisContext {
        let module: KIRModule
        let interner: StringInterner
        let anyType: TypeID?
        let intType: TypeID?
        let launcherArgGetCallee: InternedString
        let loweredBySymbol: [SymbolID: LoweredSuspendFunction]
        let continuationTypeByLoweredSymbol: [SymbolID: TypeID]
    }

    func synthesizeLauncherThunks(
        suspendFunctions: [KIRFunction],
        nextSyntheticSymbol: inout Int32,
        existingFunctionNames: inout Set<InternedString>,
        using synthesis: LauncherThunkSynthesisContext
    ) -> [SymbolID: LoweredSuspendFunction] {
        var launcherThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction] = [:]

        for suspendFunction in suspendFunctions where suspendFunction.params.count > 0 {
            guard let loweredTarget = synthesis.loweredBySymbol[suspendFunction.symbol] else {
                continue
            }
            let rawThunkName = synthesis.interner.intern(
                "kk_launcher_thunk_" + synthesis.interner.resolve(suspendFunction.name)
            )
            let thunkName = uniqueFunctionName(
                preferred: rawThunkName,
                existingFunctionNames: &existingFunctionNames,
                interner: synthesis.interner
            )
            let thunkSymbol = allocateSyntheticSymbol(&nextSyntheticSymbol)
            let thunkContParamSymbol = allocateSyntheticSymbol(&nextSyntheticSymbol)
            let contType = synthesis.continuationTypeByLoweredSymbol[loweredTarget.symbol]
                ?? synthesis.anyType ?? suspendFunction.returnType

            let thunkBody = buildLauncherThunkBody(
                suspendFunction: suspendFunction,
                loweredTarget: loweredTarget,
                thunkContParamSymbol: thunkContParamSymbol,
                module: synthesis.module,
                intType: synthesis.intType,
                contType: contType,
                launcherArgGetCallee: synthesis.launcherArgGetCallee
            )

            let thunkFunction = KIRFunction(
                symbol: thunkSymbol,
                name: thunkName,
                params: [KIRParameter(symbol: thunkContParamSymbol, type: contType)],
                returnType: contType,
                body: thunkBody,
                isSuspend: false,
                isInline: false
            )
            _ = synthesis.module.arena.appendDecl(.function(thunkFunction))
            launcherThunkByOriginalSymbol[suspendFunction.symbol] = (name: thunkName, symbol: thunkSymbol)
        }

        return launcherThunkByOriginalSymbol
    }

    func buildLauncherThunkBody(
        suspendFunction: KIRFunction,
        loweredTarget: LoweredSuspendFunction,
        thunkContParamSymbol: SymbolID,
        module: KIRModule,
        intType: TypeID?,
        contType: TypeID,
        launcherArgGetCallee: InternedString
    ) -> [KIRInstruction] {
        var thunkBody: [KIRInstruction] = []
        let contRef = module.arena.appendExpr(
            .symbolRef(thunkContParamSymbol),
            type: contType
        )

        var callArgExprs: [KIRExprID] = []
        for paramIndex in 0 ..< suspendFunction.params.count {
            let slotExpr = module.arena.appendExpr(
                .intLiteral(Int64(paramIndex)),
                type: intType
            )
            let argResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: suspendFunction.params[paramIndex].type
            )
            thunkBody.append(
                .call(
                    symbol: nil,
                    callee: launcherArgGetCallee,
                    arguments: [contRef, slotExpr],
                    result: argResult,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            callArgExprs.append(argResult)
        }

        callArgExprs.append(contRef)
        let callResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: contType
        )
        thunkBody.append(
            .call(
                symbol: loweredTarget.symbol,
                callee: loweredTarget.name,
                arguments: callArgExprs,
                result: callResult,
                canThrow: true,
                thrownResult: nil
            )
        )
        thunkBody.append(.returnValue(callResult))
        return thunkBody
    }

    /// Returns true if the callee of a call is a known dispatcher factory function.
    private func isDispatcherCalleeExpr(
        _ exprID: KIRExprID,
        module: KIRModule
    ) -> Bool {
        // A dispatcher is produced by one of kk_dispatcher_default/io/main.
        // In KIR these appear as constValue(.intLiteral) carrying the dispatcher tag,
        // or as a call result from kk_dispatcher_*. Since they are Int-typed constants
        // we cannot distinguish them from a regular Int constant at this stage.
        // The heuristic we use: if the expression has NO known symbol reference
        // (i.e. it is not pointing at a suspend function symbol), treat it as a
        // potential dispatcher expression when the callee name is "launch".
        // This is validated downstream by the fact that the *next* argument must
        // resolve to a suspend function.
        return true // Intentionally broad; validated by caller.
    }

    func rewriteLauncherCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let runtimeLauncherCallee = rewrite.kxMiniLauncherRuntimeCallees[call.callee]
        else {
            return nil
        }
        let produceCallee = rewrite.ctx.interner.intern("produce")
        let runtimeProduceCallee = rewrite.ctx.interner.intern("kk_produce")

        guard call.arguments.count >= 1 else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0001",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' expects at least one suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        // STDLIB-CORO-072: Check if the first argument is a dispatcher (not a suspend function).
        // launch(Dispatchers.IO) { } has the dispatcher as arguments[0] and the lambda as arguments[1].
        let firstArgSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        let firstLowered = firstArgSymbol.flatMap { rewrite.loweredBySymbol[$0] }

        if firstLowered == nil && call.arguments.count >= 2 {
            // First argument is not a suspend function. Try to interpret it as a dispatcher.
            let launchCallee = rewrite.ctx.interner.intern("launch")
            guard call.callee == launchCallee else {
                // Dispatcher-aware pattern is only valid for `launch`.
                rewrite.ctx.diagnostics.error(
                    "KSWIFTK-CORO-0002",
                    "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                    range: nil
                )
                return [call.instruction]
            }

            let dispatcherExpr = call.arguments[0]
            let suspendArgExpr = call.arguments[1]

            if let suspendSymbol = symbolReference(
                for: suspendArgExpr,
                module: rewrite.module,
                propagatedSymbols: symbolByExprRaw
            ), let loweredTarget = rewrite.loweredBySymbol[suspendSymbol] {
                let targetArity = rewrite.suspendFunctionArityBySymbol[suspendSymbol] ?? 0
                let extraArgs = Array(call.arguments.dropFirst(2))
                guard extraArgs.count == targetArity else {
                    rewrite.ctx.diagnostics.error(
                        "KSWIFTK-CORO-0003",
                        "Coroutine launcher 'launch' passed \(extraArgs.count) capture argument(s) but referenced suspend function expects \(targetArity).",
                        range: nil
                    )
                    return [call.instruction]
                }

                if targetArity == 0 {
                    return rewriteZeroArgDispatcherLauncherCall(
                        dispatcherExpr: dispatcherExpr,
                        loweredTarget: loweredTarget,
                        call: call,
                        using: rewrite
                    )
                }

                guard let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol] else {
                    assertionFailure("Internal compiler error: launcher thunk missing for dispatcher-aware launch")
                    return [call.instruction]
                }
                return rewriteArgBearingDispatcherLauncherCall(
                    dispatcherExpr: dispatcherExpr,
                    loweredTarget: loweredTarget,
                    thunk: thunk,
                    extraArgs: extraArgs,
                    call: call,
                    using: rewrite
                )
            }
            // Fall through to normal error path if we still cannot resolve.
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        guard let referencedSymbol = firstArgSymbol,
              let loweredTarget = firstLowered
        else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        let extraArgs = Array(call.arguments.dropFirst())
        if call.callee == produceCallee || call.callee == runtimeProduceCallee {
            let expectedExtraArgs = max(0, targetArity - 1)
            guard extraArgs.count == expectedExtraArgs else {
                rewrite.ctx.diagnostics.error(
                    "KSWIFTK-CORO-0003",
                    "Coroutine launcher 'produce' passed \(extraArgs.count) argument(s) but referenced suspend function expects \(expectedExtraArgs) after reserving the produced channel receiver.",
                    range: nil
                )
                return [call.instruction]
            }

            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol],
                  let runtimeWithContCallee = rewrite.kxMiniLauncherWithContCallees[call.callee]
            else {
                assertionFailure("Internal compiler error: launcher thunk or _with_cont callee missing for '\(rewrite.ctx.interner.resolve(call.callee))'")
                return [call.instruction]
            }

            return rewriteProduceLauncherCall(
                runtimeWithContCallee: runtimeWithContCallee,
                loweredTarget: loweredTarget,
                thunk: thunk,
                extraArgs: extraArgs,
                call: call,
                using: rewrite
            )
        }
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0003",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' passed \(extraArgs.count) argument(s) but referenced suspend function expects \(targetArity).",
                range: nil
            )
            return [call.instruction]
        }

        if targetArity == 0 {
            return rewriteZeroArgLauncherCall(
                runtimeLauncherCallee: runtimeLauncherCallee,
                loweredTarget: loweredTarget,
                call: call,
                using: rewrite
            )
        }

        guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol],
              let runtimeWithContCallee = rewrite.kxMiniLauncherWithContCallees[call.callee]
        else {
            assertionFailure("Internal compiler error: launcher thunk or _with_cont callee missing for '\(rewrite.ctx.interner.resolve(call.callee))'")
            return [call.instruction]
        }

        return rewriteArgBearingLauncherCall(
            runtimeWithContCallee: runtimeWithContCallee,
            loweredTarget: loweredTarget,
            thunk: thunk,
            extraArgs: extraArgs,
            call: call,
            using: rewrite
        )
    }

    // STDLIB-CORO-072: Rewrite launch(dispatcher) { } with no captures
    func rewriteZeroArgDispatcherLauncherCall(
        dispatcherExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        let entryFunctionID = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        let runtimeCallee = rewrite.ctx.interner.intern("kk_kxmini_launch_with_dispatcher")

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [entryPointExpr, entryFunctionID, dispatcherExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ),
        ]
    }

    // STDLIB-CORO-072: Rewrite launch(dispatcher) { captures } with captures
    func rewriteArgBearingDispatcherLauncherCall(
        dispatcherExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        let runtimeCallee = rewrite.ctx.interner.intern("kk_kxmini_launch_with_dispatcher_and_cont")

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [thunkRefExpr, continuationExpr, dispatcherExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: nil
            )
        )
        return rewritten
    }

    func rewriteZeroArgLauncherCall(
        runtimeLauncherCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let structuredBlockingRuntimes: Set<InternedString> = [
            rewrite.ctx.interner.intern("kk_kxmini_run_blocking"),
            rewrite.ctx.interner.intern("kk_coroutine_scope_run"),
            rewrite.ctx.interner.intern("kk_supervisor_scope_run"),
        ]
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        let entryFunctionID = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: runtimeLauncherCallee,
                arguments: [entryPointExpr, entryFunctionID],
                result: call.result,
                canThrow: call.canThrow || structuredBlockingRuntimes.contains(runtimeLauncherCallee),
                thrownResult: call.thrownResult
            ),
        ]
    }

    func rewriteArgBearingLauncherCall(
        runtimeWithContCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let structuredBlockingRuntimes: Set<InternedString> = [
            rewrite.ctx.interner.intern("kk_kxmini_run_blocking_with_cont"),
            rewrite.ctx.interner.intern("kk_coroutine_scope_run_with_cont"),
            rewrite.ctx.interner.intern("kk_supervisor_scope_run_with_cont"),
        ]
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeWithContCallee,
                arguments: [thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow || structuredBlockingRuntimes.contains(runtimeWithContCallee),
                thrownResult: nil
            )
        )
        return rewritten
    }

    func rewriteProduceLauncherCall(
        runtimeWithContCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // Slot 0 is reserved for the produced channel receiver.
        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index + 1)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendExpr(
            .temporary(Int32(rewrite.module.arena.expressions.count)),
            type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeWithContCallee,
                arguments: [thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }
}
