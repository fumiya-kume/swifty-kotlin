
extension CoroutineLoweringPass {
    struct SuspendRewriteContext {
        let module: KIRModule
        let ctx: KIRContext
        let anyType: TypeID?
        let intType: TypeID?
        let unitType: TypeID?
        let flowCollectCallee: InternedString
        let flowCollectLatestCallee: InternedString
        let withContextCallee: InternedString
        let runtimeWithContextCallee: InternedString
        let withTimeoutCallee: InternedString
        let runtimeWithTimeoutCallee: InternedString
        let withTimeoutOrNullCallee: InternedString
        let runtimeWithTimeoutOrNullCallee: InternedString
        let yieldCallee: InternedString
        let runtimeYieldCallee: InternedString
        let startCoroutineCallee: InternedString
        let createCoroutineCallee: InternedString
        let createCoroutineUninterceptedCallee: InternedString
        let startCoroutineUninterceptedOrReturnCallee: InternedString
        let runtimeCreateCoroutineUninterceptedCallee: InternedString
        let runtimeStartCoroutineUninterceptedOrReturnCallee: InternedString
        let runtimeContinuationResumeCallee: InternedString
        let continuationFactory: InternedString
        let directSuspendCallCallee: InternedString
        let launcherArgSetCallee: InternedString
        let runtimeRunBlockingWithContCallee: InternedString
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString]
        let kxMiniLauncherWithContCallees: [InternedString: InternedString]
        let coroutineScopeLaunchCallee: InternedString
        let sequenceBuilderBuildCallee: InternedString
        let sequenceBuilderBuildCoroCallee: InternedString
        let sequenceBuilderYieldAllCallee: InternedString
        let sequenceBuilderYieldCallee: InternedString
        let sequenceClassSymbol: SymbolID?
        let iteratorBuilderBuildCallee: InternedString
        let iteratorBuilderBuildCoroCallee: InternedString
        let sequenceBuilderThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction]
        let loweredBySymbol: [SymbolID: LoweredSuspendFunction]
        let originalByLoweredName: [InternedString: (original: SymbolID, lowered: LoweredSuspendFunction)]
        let continuationTypeByLoweredSymbol: [SymbolID: TypeID]
        let suspendFunctionArityBySymbol: [SymbolID: Int]
        let loweredByUniqueNameArity: [SuspendCallLookupKey: LoweredSuspendFunction]
        let loweredByUniqueName: [InternedString: LoweredSuspendFunction]
        let launcherThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction]
    }

    struct CallRewriteInput {
        let instruction: KIRInstruction
        let symbol: SymbolID?
        let callee: InternedString
        let arguments: [KIRExprID]
        let result: KIRExprID?
        let canThrow: Bool
        let thrownResult: KIRExprID?
        let isSuperCall: Bool
    }

    func rewriteSuspendFunctionsAndCallSites(using rewrite: SuspendRewriteContext) {
        rewrite.module.arena.transformFunctions { function in
            var updated = function
            if function.isSuspend,
               let wrapperBody = buildSuspendWrapperBody(for: function, using: rewrite)
            {
                updated.replaceBody(wrapperBody)
                updated.replaceInstructionLocations(Array(repeating: nil, count: wrapperBody.count))
                return updated
            }

            updated.replaceBody(rewriteFunctionBody(function, using: rewrite))
            return updated
        }
        rewrite.module.arena.transformFunctions { function in
            var updated = function
            updated.replaceBody(rewriteCoroutineBuilderBuildCalls(function, using: rewrite))
            return updated
        }
    }

    func buildSuspendWrapperBody(
        for function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = rewrite.loweredBySymbol[function.symbol] else {
            return nil
        }

        let continuationType = rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol]
            ?? rewrite.anyType
            ?? function.returnType
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: continuationType
        )

        var wrapperBody: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        let entryPointSymbol: SymbolID
        if function.params.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[function.symbol] else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            appendWrapperArgumentSetup(
                for: function,
                continuationExpr: continuationExpr,
                using: rewrite,
                into: &wrapperBody
            )
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callResult = rewrite.module.arena.appendTemporary(type: function.returnType
        )
        wrapperBody.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeRunBlockingWithContCallee,
                arguments: [entryPointExpr, continuationExpr],
                result: callResult,
                canThrow: true,
                thrownResult: nil
            )
        )
        wrapperBody.append(.returnValue(callResult))
        return wrapperBody
    }

    func appendWrapperArgumentSetup(
        for function: KIRFunction,
        continuationExpr: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into wrapperBody: inout [KIRInstruction]
    ) {
        for (index, parameter) in function.params.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            let argumentExpr = rewrite.module.arena.appendExpr(
                .symbolRef(parameter.symbol),
                type: parameter.type
            )
            wrapperBody.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argumentExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }
    }

    func rewriteFunctionBody(
        _ function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
        // A callable value which is materialized by LambdaLowerer is normally
        // recorded in callableValueInfoByExprID.  Closure conversion can
        // leave only the `kk_function_create_N` instruction in the body,
        // however, so recover that ABI information from the producer as well.
        // Flow builders need the original adapter symbol and its packed
        // closure object to rebuild the launcher continuation below.
        var functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo] = [:]
        for instruction in function.body {
            guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
                  rewrite.ctx.interner.resolve(callee).hasPrefix("kk_function_create_"),
                  let result,
                  arguments.count >= 2,
                  let functionSymbol = symbolReference(
                      for: arguments[0],
                      module: rewrite.module,
                      propagatedSymbols: symbolByExprRaw
                  )
            else {
                continue
            }
            functionValueInfoByExprRaw[result.rawValue] = KIRCallableValueInfo(
                symbol: functionSymbol,
                callee: callee,
                captureArguments: [arguments[1]],
                hasClosureParam: false
            )
        }
        // STDLIB-CORO-BUG-01: a lowered suspend function's own continuation is
        // always its last parameter (see CoroutineLoweringPass.run appending
        // continuationParameterSymbol). rewriteDirectSuspendCall needs it to
        // relay a nested suspend call's completion back to this function's
        // own suspend point instead of orphaning it on a throwaway
        // continuation. `isSuspend` alone can't distinguish a lowered suspend
        // function from an ordinary non-suspend function with parameters (both
        // have isSuspend == false), and resolveLoweredTarget's name/arity
        // fallback means a same-named/arity non-suspend function can still
        // match a suspend target -- so positively check that `function` is
        // itself a lowered suspend body (present as a key in
        // continuationTypeByLoweredSymbol) rather than inferring it from
        // isSuspend being false.
        let callerContinuationSymbol = rewrite.continuationTypeByLoweredSymbol[function.symbol] != nil
            ? function.params.last?.symbol
            : nil
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count)

        for instruction in function.body {
            guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }
            let call = CallRewriteInput(
                instruction: instruction,
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )

            if let launcherInstructions = rewriteLauncherCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: launcherInstructions)
                continue
            }

            if let collectInstructions = rewriteFlowCollectCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: collectInstructions)
                continue
            }

            if let producerFlowCreateInstructions = rewriteProducerFlowCreateCall(
                call: call,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: producerFlowCreateInstructions)
                continue
            }

            if let flowCreateInstructions = rewriteFlowCreateCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: flowCreateInstructions)
                continue
            }

            if let withContextInstructions = rewriteWithContextCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: withContextInstructions)
                continue
            }

            if let withTimeoutInstructions = rewriteWithTimeoutCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: withTimeoutInstructions)
                continue
            }

            if let yieldInstruction = rewriteYieldCall(
                call: call,
                using: rewrite
            ) {
                loweredBody.append(yieldInstruction)
                continue
            }

            if let builderInstruction = rewriteCoroutineBuilderBuildCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(builderInstruction)
                continue
            }

            if let createCoroutineInstructions = rewriteCreateCoroutineUninterceptedCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: createCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineUninterceptedOrReturnCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: startCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: startCoroutineInstructions)
                continue
            }

            if let directCallInstructions = rewriteDirectSuspendCall(
                call: call,
                callerContinuationSymbol: callerContinuationSymbol,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: directCallInstructions)
                continue
            }

            loweredBody.append(instruction)
        }
        return loweredBody
    }

    func rewriteCoroutineBuilderBuildCalls(
        _ function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count)

        for instruction in function.body {
            guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }
            let call = CallRewriteInput(
                instruction: instruction,
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )
            if let builderInstruction = rewriteCoroutineBuilderBuildCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(builderInstruction)
            } else {
                loweredBody.append(instruction)
            }
        }
        return loweredBody
    }

    func propagatedSymbolReferences(
        for function: KIRFunction,
        callableRefTagFunctionCallee: InternedString
    ) -> [Int32: SymbolID] {
        var symbolByExprRaw: [Int32: SymbolID] = [:]
        var ambiguousSymbolExprRaws: Set<Int32> = []

        func markAmbiguousSymbolExpr(_ raw: Int32) -> Bool {
            var changed = false
            if symbolByExprRaw.removeValue(forKey: raw) != nil {
                changed = true
            }
            if ambiguousSymbolExprRaws.insert(raw).inserted {
                changed = true
            }
            return changed
        }

        for instruction in function.body {
            guard case let .constValue(result, .symbolRef(symbol)) = instruction else {
                continue
            }
            let raw = result.rawValue
            if let existing = symbolByExprRaw[raw], existing != symbol {
                _ = markAmbiguousSymbolExpr(raw)
            } else if !ambiguousSymbolExprRaws.contains(raw) {
                symbolByExprRaw[raw] = symbol
            }
        }

        func propagateSymbol(from source: KIRExprID, to destination: KIRExprID) -> Bool {
            let sourceRaw = source.rawValue
            let destinationRaw = destination.rawValue
            if ambiguousSymbolExprRaws.contains(sourceRaw) {
                return markAmbiguousSymbolExpr(destinationRaw)
            }
            guard let symbol = symbolByExprRaw[sourceRaw],
                  !ambiguousSymbolExprRaws.contains(destinationRaw)
            else {
                return false
            }
            if let existing = symbolByExprRaw[destinationRaw] {
                if existing != symbol {
                    return markAmbiguousSymbolExpr(destinationRaw)
                }
                return false
            }
            symbolByExprRaw[destinationRaw] = symbol
            return true
        }

        var propagated = true

        while propagated {
            propagated = false
            for instruction in function.body {
                switch instruction {
                case let .copy(from, to):
                    if propagateSymbol(from: from, to: to) {
                        propagated = true
                    }
                case let .call(_, callee, arguments, result, _, _, _, _):
                    guard callee == callableRefTagFunctionCallee,
                          let result,
                          let callableExpr = arguments.first
                    else {
                        continue
                    }
                    if propagateSymbol(from: callableExpr, to: result) {
                        propagated = true
                    }
                default:
                    continue
                }
            }
        }

        return symbolByExprRaw
    }

    func symbolReference(
        for exprID: KIRExprID,
        module: KIRModule,
        propagatedSymbols: [Int32: SymbolID]
    ) -> SymbolID? {
        if let expr = module.arena.expr(exprID),
           case let .symbolRef(symbol) = expr
        {
            return symbol
        }
        if let symbol = propagatedSymbols[exprID.rawValue] {
            return symbol
        }
        return module.arena.callableValueInfo(for: exprID)?.symbol
    }

    func rewriteFlowCollectCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.flowCollectCallee || call.callee == rewrite.flowCollectLatestCallee,
              call.arguments.count == 3
        else {
            return nil
        }
        let collectorExpr = call.arguments[1]
        let collectorSymbol = symbolReference(
            for: collectorExpr,
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        let collectorCallableInfo = rewrite.module.arena.callableValueInfo(for: collectorExpr)

        var prefixInstructions: [KIRInstruction] = []
        let collectorEntryPoint: KIRExprID
        let collectorEnvPtr: KIRExprID
        let collectorContinuationArg: KIRExprID
        if let collectorSymbol, let loweredCollector = rewrite.loweredBySymbol[collectorSymbol] {
            // Suspend collector: its body contains a suspend call (e.g.
            // `collect { delay(1); ... }`), so it was CPS-rewritten. Route
            // through its suspend entry point; the runtime treats a nonzero
            // fourth argument as the function ID used to build a new
            // continuation for the suspend collector ABI.
            collectorEntryPoint = rewrite.module.arena.appendExpr(
                .symbolRef(loweredCollector.symbol),
                type: rewrite.intType
            )
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(loweredCollector.symbol.rawValue)),
                type: rewrite.intType
            )
            collectorEnvPtr = flowCollectorEnvironmentPointerExpr(
                for: collectorExpr,
                using: rewrite,
                into: &prefixInstructions
            )
        } else if let collectorSymbol,
                  let callableInfo = collectorCallableInfo,
                  callableInfo.symbol == collectorSymbol,
                  callableInfo.hasClosureParam,
                  let function = rewrite.module.arena.function(for: collectorSymbol),
                  !function.isInlineOnly
        {
            // Non-suspend collector that has already been adapted to the
            // `(closureRaw, value, outThrown) -> result` ABI used by the
            // runtime (e.g. a local `val` lambda that CallLowerer wrapped in
            // a collection-HOF adapter). Invoke it directly and pass the
            // packed capture environment.
            collectorEntryPoint = rewrite.module.arena.appendExpr(
                .symbolRef(collectorSymbol),
                type: rewrite.intType
            )
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
            collectorEnvPtr = flowCollectorEnvironmentPointerExpr(
                for: collectorExpr,
                using: rewrite,
                into: &prefixInstructions
            )
        } else {
            // BUG-134: the collector expression is a boxed `Function1` value
            // (e.g. a lambda passed through a function parameter or a variable)
            // rather than a raw closure-aware function pointer. The runtime ABI
            // needs a `(closureRaw, value, outThrown) -> result` entry point and
            // its closure, so recover them with the same `kk_function_value_*`
            // accessors `CallLowerer.splitCallableLambdaArgument` uses for
            // ordinary collection HOF arguments.
            let fnPtrResult = rewrite.module.arena.appendTemporary(type: rewrite.intType)
            prefixInstructions.append(.call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_function_value_fn_ptr"),
                arguments: [collectorExpr],
                result: fnPtrResult,
                canThrow: false,
                thrownResult: nil
            ))
            let closureRawResult = rewrite.module.arena.appendTemporary(type: rewrite.intType)
            prefixInstructions.append(.call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_function_value_closure_raw"),
                arguments: [collectorExpr],
                result: closureRawResult,
                canThrow: false,
                thrownResult: nil
            ))
            collectorEntryPoint = fnPtrResult
            collectorEnvPtr = closureRawResult
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
        }

        prefixInstructions.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [call.arguments[0], collectorEntryPoint, collectorEnvPtr, collectorContinuationArg],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return prefixInstructions
    }

    /// Threads a capturing `flow { }` builder's captured values into its emitter.
    ///
    /// `lowerFlowExpressions` rewrites `flow { }` to `kk_flow_create(emitter, 0)`
    /// before suspend lowering exists, so the second argument is a placeholder and
    /// the emitter's captured values are dropped (the runtime invoked it with a
    /// null environment). By this point the emitter lambda has been lowered to a
    /// suspend state machine with a launcher thunk that reads its captures from a
    /// continuation's launcher-arg slots — the same mechanism `launch { }` uses.
    /// Populate such a continuation and route `kk_flow_create` through the thunk.
    /// Non-capturing builders keep the direct-emitter ABI and are left untouched.
    func rewriteFlowCreateCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.ctx.interner.intern("kk_flow_create"),
              call.arguments.count == 2,
              let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
                  ?? functionValueInfoByExprRaw[call.arguments[0].rawValue],
              !callableInfo.captureArguments.isEmpty,
              let loweredTarget = rewrite.loweredBySymbol[callableInfo.symbol],
              let thunk = rewrite.launcherThunkByOriginalSymbol[callableInfo.symbol]
        else {
            return nil
        }

        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType)
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

        for (index, argExpr) in callableInfo.captureArguments.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType)
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [thunkRefExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return rewritten
    }

    /// Threads the producer receiver and captured values into a real channel
    /// builder. The runtime bridge uses the same launcher-continuation layout
    /// as `produce { }`, but stores the channel handle in slot zero so the
    /// lowered `ProducerScope` receiver is reconstructed by the launcher thunk.
    func rewriteProducerFlowCreateCall(
        call: CallRewriteInput,
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let interner = rewrite.ctx.interner
        guard call.callee == interner.intern("kk_channel_flow_create")
            || call.callee == interner.intern("kk_callback_flow_create"),
            call.arguments.count == 2
        else {
            return nil
        }

        guard let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
            ?? functionValueInfoByExprRaw[call.arguments[0].rawValue],
            let loweredTarget = rewrite.loweredBySymbol[callableInfo.symbol]
        else {
            return nil
        }
        let originalSymbol = callableInfo.symbol
        let captureArguments = callableInfo.captureArguments
        let entryPointSymbol: SymbolID
        let targetArity = rewrite.suspendFunctionArityBySymbol[loweredTarget.symbol] ?? 0
        if targetArity == 0 {
            entryPointSymbol = loweredTarget.symbol
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol] else {
                return nil
            }
            entryPointSymbol = thunk.symbol
        }

        let continuationFunctionID = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(
            type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )
        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // Slot zero is reserved for the runtime-created channel and becomes
        // the ProducerScope receiver. Lexical captures follow it.
        for (index, argExpr) in captureArguments.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index + 1)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return rewritten
    }

    /// Recovers the closure-capture environment pointer for a Flow collector
    /// lambda, matching the `(fnPtr, envPtr)` convention ordinary HOF callees
    /// use (e.g. `kk_list_map`). Falls back to a null pointer when the lambda
    /// captures nothing, and packs multiple captures into a closure object
    /// the same way `CallLowerer.splitCallableLambdaArgument` does.
    func flowCollectorEnvironmentPointerExpr(
        for lambdaID: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let captureArguments = rewrite.module.arena.callableValueInfo(for: lambdaID)?.captureArguments,
              !captureArguments.isEmpty
        else {
            let zeroExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        if captureArguments.count == 1 {
            return captureArguments[0]
        }

        let kkObjectNew = rewrite.ctx.interner.intern("kk_object_new")
        let kkArraySet = rewrite.ctx.interner.intern("kk_array_set")
        let slotCount = Int64(2 + captureArguments.count)
        let slotCountExpr = rewrite.module.arena.appendExpr(.intLiteral(slotCount), type: rewrite.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObjExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: kkObjectNew,
            arguments: [slotCountExpr, classIDExpr],
            result: closureObjExpr,
            canThrow: false,
            thrownResult: nil
        ))
        for (captureIndex, captureArg) in captureArguments.enumerated() {
            let fieldOffset = Int64(captureIndex + 2)
            let offsetExpr = rewrite.module.arena.appendExpr(.intLiteral(fieldOffset), type: rewrite.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
            let unusedResult = rewrite.module.arena.appendTemporary(type: rewrite.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: kkArraySet,
                arguments: [closureObjExpr, offsetExpr, captureArg],
                result: unusedResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return closureObjExpr
    }

    func rewriteWithContextCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.withContextCallee,
              call.arguments.count >= 2,
              let referencedSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let dispatcherExpr = call.arguments[0]
        let extraArgs = Array(call.arguments.dropFirst(2))
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0004",
                "withContext block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        var rewritten: [KIRInstruction] = []
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.runtimeWithContextCallee,
            arguments: [dispatcherExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    func rewriteDirectSuspendCall(
        call: CallRewriteInput,
        callerContinuationSymbol: SymbolID?,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = resolveLoweredTarget(
            symbol: call.symbol,
            callee: call.callee,
            arity: call.arguments.count,
            using: rewrite
        ) else {
            return nil
        }
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        // Synthetic KIR fixtures and non-suspend callers do not carry a lowered
        // caller continuation. Preserve their historical continuation argument
        // shape; only lowered suspend bodies can use the relay ABI below.
        guard let callerContinuationSymbol else {
            let continuationTemp = rewrite.module.arena.appendTemporary(
                type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
            )
            return [
                .constValue(
                    result: continuationFunctionID,
                    value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                ),
                .call(
                    symbol: nil,
                    callee: rewrite.continuationFactory,
                    arguments: [continuationFunctionID],
                    result: continuationTemp,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: loweredTarget.symbol,
                    callee: loweredTarget.name,
                    arguments: call.arguments + [continuationTemp],
                    result: call.result,
                    canThrow: call.canThrow,
                    thrownResult: call.thrownResult,
                    isSuperCall: call.isSuperCall
                ),
            ]
        }

        // STDLIB-CORO-BUG-01: a direct call from one suspend function's body to
        // another must relay the callee's completion back into this function's
        // own suspend point through kk_coroutine_call_direct_suspend.
        let childContinuationTemp = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        var instructions: [KIRInstruction] = [
            .constValue(
                result: continuationFunctionID,
                value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
            ),
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: childContinuationTemp,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // A suspend function with parameters is invoked through its launcher
        // thunk (the same adapter launch/async/runBlocking use), which reads
        // the real arguments back out of the child continuation's launcher-arg
        // storage. A 0-arg suspend function's lowered form already matches the
        // (continuation) -> Int entry-point shape directly.
        let entryPointSymbol: SymbolID
        if call.arguments.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            let originalSymbol = call.symbol ?? rewrite.originalByLoweredName[loweredTarget.name]?.original
            guard let originalSymbol,
                  let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol]
            else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            for (index, argumentExpr) in call.arguments.enumerated() {
                let slotExpr = rewrite.module.arena.appendExpr(
                    .intLiteral(Int64(index)),
                    type: rewrite.intType
                )
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: rewrite.launcherArgSetCallee,
                        arguments: [childContinuationTemp, slotExpr, argumentExpr],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
            }
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callerContinuationExpr = rewrite.module.arena.appendExpr(
            .symbolRef(callerContinuationSymbol),
            type: rewrite.anyType
        )
        instructions.append(
            .call(
                symbol: nil,
                callee: rewrite.directSuspendCallCallee,
                arguments: [entryPointExpr, childContinuationTemp, callerContinuationExpr],
                result: call.result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: call.isSuperCall
            )
        )
        return instructions
    }

    func rewriteWithTimeoutCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let runtimeCallee: InternedString
        if call.callee == rewrite.withTimeoutCallee {
            runtimeCallee = rewrite.runtimeWithTimeoutCallee
        } else if call.callee == rewrite.withTimeoutOrNullCallee {
            runtimeCallee = rewrite.runtimeWithTimeoutOrNullCallee
        } else {
            return nil
        }

        guard call.arguments.count >= 2,
              let referencedSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let timeMillisExpr = call.arguments[0]
        let extraArgs = Array(call.arguments.dropFirst(2))
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0005",
                "withTimeout block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        var rewritten: [KIRInstruction] = []
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [timeMillisExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    func rewriteYieldCall(
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        guard call.callee == rewrite.yieldCallee else {
            return nil
        }
        return .call(
            symbol: nil,
            callee: rewrite.runtimeYieldCallee,
            arguments: call.arguments,
            result: call.result,
            canThrow: false,
            thrownResult: nil
        )
    }

    func rewriteCoroutineBuilderBuildCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        let replacementCallee: InternedString
        if call.callee == rewrite.sequenceBuilderBuildCallee {
            replacementCallee = rewrite.sequenceBuilderBuildCoroCallee
        } else if call.callee == rewrite.iteratorBuilderBuildCallee {
            replacementCallee = rewrite.iteratorBuilderBuildCoroCallee
        } else {
            return nil
        }

        guard let callableExpr = call.arguments.first,
              let referencedSymbol = symbolReference(
                  for: callableExpr,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let producer: (original: SymbolID, lowered: LoweredSuspendFunction, entryPoint: SymbolID)?
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let innerProducer = sequenceBuilderInnerProducer(
               from: loweredTarget.symbol,
               symbolByExprRaw: symbolByExprRaw,
               using: rewrite
           ),
           let builderThunk = rewrite.sequenceBuilderThunkByOriginalSymbol[innerProducer.original]
        {
            producer = (
                original: innerProducer.original,
                lowered: innerProducer.lowered,
                entryPoint: builderThunk.symbol
            )
        } else {
            producer = nil
        }
        let producerOriginalSymbol = producer?.original ?? referencedSymbol
        let producerLoweredTarget = producer?.lowered ?? loweredTarget

        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsAnyCallee(
               symbol: producerLoweredTarget.symbol,
               callees: [
                   rewrite.ctx.interner.intern("kk_coroutine_continuation_new"),
               ],
               module: rewrite.module
           ),
           !loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.directSuspendCallCallee,
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCalleeNamedLike(
               symbol: producerLoweredTarget.symbol,
               module: rewrite.module,
               interner: rewrite.ctx.interner,
               isMatch: { name in
                   name.hasPrefix("kk_lambda_") || name.hasPrefix("kk_suspend_kk_lambda_")
               }
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.sequenceBuilderYieldCallee,
               module: rewrite.module
           ),
           loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.sequenceBuilderYieldAllCallee,
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.sequenceBuilderYieldAllCallee,
               module: rewrite.module
           ),
           !loweredFunctionContainsYieldAllOfSequence(
               symbol: producerLoweredTarget.symbol,
               module: rewrite.module,
               using: rewrite
           )
        {
            return nil
        }

        let chosenEntryPoint: SymbolID
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let producerEntryPoint = producer?.entryPoint {
            chosenEntryPoint = producerEntryPoint
        } else if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
                  let builderThunk = rewrite.sequenceBuilderThunkByOriginalSymbol[producerOriginalSymbol] {
            chosenEntryPoint = builderThunk.symbol
        } else {
            chosenEntryPoint = entryPointSymbol(
                for: producerOriginalSymbol,
                loweredTarget: producerLoweredTarget,
                hasLauncherArg: true,
                using: rewrite
            )
        }
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(chosenEntryPoint),
            type: rewrite.intType
        )
        let functionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(producerLoweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let closureRawExpr: KIRExprID
        if call.arguments.count >= 2 {
            closureRawExpr = call.arguments[1]
        } else {
            closureRawExpr = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
        }

        return .call(
            symbol: nil,
            callee: replacementCallee,
            arguments: [entryPointExpr, functionIDExpr, closureRawExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        )
    }

    private func sequenceBuilderInnerProducer(
        from loweredAdapterSymbol: SymbolID,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> (original: SymbolID, lowered: LoweredSuspendFunction)? {
        var candidates: [(original: SymbolID, lowered: LoweredSuspendFunction)] = []

        func appendProducer(for entryPointSymbol: SymbolID) {
            if let producer = rewrite.launcherThunkByOriginalSymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            }),
               let lowered = rewrite.loweredBySymbol[producer.key]
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: lowered))
                }
                return
            }

            if let producer = rewrite.sequenceBuilderThunkByOriginalSymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            }),
               let lowered = rewrite.loweredBySymbol[producer.key]
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: lowered))
                }
                return
            }

            if let producer = rewrite.loweredBySymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            })
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: producer.value))
                }
            }
        }

        for decl in rewrite.module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == loweredAdapterSymbol
            else {
                continue
            }
            for instruction in function.body {
                let callee: InternedString?
                switch instruction {
                case let .call(_, instructionCallee, _, _, _, _, _, _):
                    callee = instructionCallee
                case let .virtualCall(_, instructionCallee, _, _, _, _, _, _):
                    callee = instructionCallee
                default:
                    callee = nil
                }

                if callee == rewrite.directSuspendCallCallee,
                   case let .call(_, _, arguments, _, _, _, _, _) = instruction,
                   let entryPointExpr = arguments.first,
                   let entryPointSymbol = symbolReference(
                       for: entryPointExpr,
                       module: rewrite.module,
                       propagatedSymbols: symbolByExprRaw
                   )
                {
                    appendProducer(for: entryPointSymbol)
                    continue
                }

                guard let callee,
                      let producer = rewrite.originalByLoweredName[callee],
                      producer.lowered.symbol != loweredAdapterSymbol
                else {
                    continue
                }
                if !candidates.contains(where: { $0.original == producer.original }) {
                    candidates.append(producer)
                }
            }
            break
        }
        guard candidates.count == 1 else {
            return nil
        }
        return candidates[0]
    }

    private func loweredFunctionContainsYieldAllOfSequence(
        symbol: SymbolID,
        module: KIRModule,
        using rewrite: SuspendRewriteContext
    ) -> Bool {
        guard let sequenceClassSymbol = rewrite.sequenceClassSymbol,
              let types = rewrite.ctx.sema?.types
        else {
            return false
        }
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == symbol
            else {
                continue
            }
            for instruction in function.body {
                let callSymbol: SymbolID?
                let instructionCallee: InternedString
                switch instruction {
                case let .call(sym, callee, _, _, _, _, _, _):
                    callSymbol = sym
                    instructionCallee = callee
                case let .virtualCall(sym, callee, _, _, _, _, _, _):
                    callSymbol = sym
                    instructionCallee = callee
                default:
                    continue
                }
                guard instructionCallee == rewrite.sequenceBuilderYieldAllCallee,
                      let callSymbol,
                      let calleeFunction = module.arena.function(for: callSymbol),
                      let firstParamType = calleeFunction.params.first?.type
                else {
                    continue
                }
                let normalizedType = types.makeNonNullable(firstParamType)
                if case let .classType(classType) = types.kind(of: normalizedType),
                   classType.classSymbol == sequenceClassSymbol {
                    return true
                }
            }
            return false
        }
        return false
    }

    private func loweredFunctionContainsCallee(
        symbol: SymbolID,
        callee: InternedString,
        module: KIRModule
    ) -> Bool {
        loweredFunctionContainsAnyCallee(symbol: symbol, callees: [callee], module: module)
    }

    private func loweredFunctionContainsAnyCallee(
        symbol: SymbolID,
        callees: Set<InternedString>,
        module: KIRModule
    ) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == symbol
            else {
                continue
            }
            return function.body.contains { instruction in
                if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return callees.contains(instructionCallee)
                }
                if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return callees.contains(instructionCallee)
                }
                return false
            }
        }
        return false
    }

    private func loweredFunctionContainsCalleeNamedLike(
        symbol: SymbolID,
        module: KIRModule,
        interner: StringInterner,
        isMatch: (String) -> Bool
    ) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == symbol
            else {
                continue
            }
            return function.body.contains { instruction in
                if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return isMatch(interner.resolve(instructionCallee))
                }
                if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return isMatch(interner.resolve(instructionCallee))
                }
                return false
            }
        }
        return false
    }

    func rewriteCreateCoroutineUninterceptedCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.createCoroutineUninterceptedCallee || call.callee == rewrite.createCoroutineCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = call.result ?? rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            )
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        return rewritten
    }

    func rewriteStartCoroutineUninterceptedOrReturnCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.startCoroutineUninterceptedOrReturnCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeStartCoroutineUninterceptedOrReturnCallee,
                arguments: [entryPointExpr, continuationExpr],
                result: call.result,
                canThrow: true,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    func rewriteStartCoroutineCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.startCoroutineCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )
        let unitExpr = rewrite.module.arena.appendExpr(
            .unit,
            type: rewrite.unitType
        )

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeContinuationResumeCallee,
                arguments: [continuationExpr, unitExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            )
        )

        if let result = call.result {
            rewritten.append(.constValue(result: result, value: .unit))
        }
        return rewritten
    }

    private func entryPointSymbol(
        for referencedSymbol: SymbolID,
        loweredTarget: LoweredSuspendFunction,
        hasLauncherArg: Bool,
        using rewrite: SuspendRewriteContext
    ) -> SymbolID {
        if hasLauncherArg,
           let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol]
        {
            return thunk.symbol
        }
        return loweredTarget.symbol
    }

    func resolveLoweredTarget(
        symbol: SymbolID?,
        callee: InternedString,
        arity: Int,
        using rewrite: SuspendRewriteContext
    ) -> LoweredSuspendFunction? {
        if let symbol {
            if let loweredBySymbol = rewrite.loweredBySymbol[symbol] {
                return loweredBySymbol
            }
            // Name/arity fallback is only valid for unresolved/runtime calls.
            // A resolved non-suspend declaration must not be rebound to the
            // unique suspend function with the same name (for example,
            // kotlin.ranges.toList versus Flow.toList after KSP-499).
            if let signature = rewrite.ctx.sema?.symbols.functionSignature(for: symbol),
               !signature.isSuspend
            {
                return nil
            }
        }
        let byNameArityKey = SuspendCallLookupKey(name: callee, arity: arity)
        if let loweredByNameArity = rewrite.loweredByUniqueNameArity[byNameArityKey] {
            return loweredByNameArity
        }
        return rewrite.loweredByUniqueName[callee]
    }
}
