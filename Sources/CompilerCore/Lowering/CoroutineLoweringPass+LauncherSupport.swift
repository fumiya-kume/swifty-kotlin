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

    func rewriteLauncherCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.symbol == nil,
              let runtimeLauncherCallee = rewrite.kxMiniLauncherRuntimeCallees[call.callee]
        else {
            return nil
        }

        guard call.arguments.count >= 1 else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0001",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' expects at least one suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
            let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
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

    func rewriteZeroArgLauncherCall(
        runtimeLauncherCallee: InternedString,
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

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: runtimeLauncherCallee,
                arguments: [entryPointExpr, entryFunctionID],
                result: call.result,
                canThrow: call.canThrow,
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
                canThrow: call.canThrow,
                thrownResult: nil
            )
        )
        return rewritten
    }
}
