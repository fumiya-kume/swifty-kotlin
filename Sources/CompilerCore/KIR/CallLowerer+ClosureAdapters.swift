/// Closure-argument synthesis and callable-adapter helpers for
/// CallLowerer: `appendClosureArgumentsIfNeeded`,
/// `makeCollectionHOFCallableAdapter`, `makeClosureThunkCallableAdapter`.
///
/// Split out from `CallLowerer.swift`.
extension CallLowerer {
    func appendCallableCaptureLoads(
        callableInfo: KIRCallableValueInfo,
        closureExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let arrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendTemporary(type: captureType
                )
                body.append(.call(
                    symbol: nil,
                    callee: arrayGet,
                    arguments: [closureExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                callArguments.append(loadedExpr)
            }
        } else if !callableInfo.captureArguments.isEmpty {
            callArguments.append(closureExpr)
        }
        return callArguments
    }

    func makeBoxedCallableCaptureArguments(
        callableInfo: KIRCallableValueInfo,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        if callableInfo.captureArguments.count >= 2 {
            let slotCountExpr = arena.appendExpr(
                .intLiteral(Int64(2 + callableInfo.captureArguments.count)),
                type: sema.types.intType
            )
            instructions.append(.constValue(
                result: slotCountExpr,
                value: .intLiteral(Int64(2 + callableInfo.captureArguments.count))
            ))
            let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
            let closureObjExpr = arena.appendTemporary(type: sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: closureObjExpr,
                canThrow: false,
                thrownResult: nil
            ))
            for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                let offsetExpr = arena.appendExpr(
                    .intLiteral(Int64(captureIndex + 2)),
                    type: sema.types.intType
                )
                instructions.append(.constValue(
                    result: offsetExpr,
                    value: .intLiteral(Int64(captureIndex + 2))
                ))
                let unusedResult = arena.appendTemporary(type: sema.types.anyType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [closureObjExpr, offsetExpr, captureArg],
                    result: unusedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return [closureObjExpr]
        }
        return callableInfo.captureArguments
    }

    func makeClosureThunkExpandedArguments(
        prefixArguments: [KIRExprID] = [],
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var finalArgs = prefixArguments
        var lambdaID = loweredArgID
        var resolvedCallableInfo = driver.ctx.callableValueInfo(for: lambdaID)
        if let callableInfo = resolvedCallableInfo,
           !callableInfo.hasClosureParam,
           let adaptedInfo = makeClosureThunkCallableAdapter(
               callableInfo: callableInfo,
               loweredArgID: lambdaID,
               argExprID: argExprID,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
            )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adaptedInfo.symbol),
                type: arena.exprType(lambdaID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adaptedInfo.symbol,
                callee: adaptedInfo.callee,
                captureArguments: adaptedInfo.captureArguments,
                hasClosureParam: adaptedInfo.hasClosureParam
            )
            lambdaID = adaptedExpr
            resolvedCallableInfo = adaptedInfo
        }
        guard let callableInfo = resolvedCallableInfo else {
            // No compile-time callable info: the argument is a callable *value*
            // (e.g. a function-typed parameter of a bundled Kotlin-source
            // wrapper such as kotlin.synchronized, whose lambda was boxed by
            // kk_function_create_0 at the user call site). Passing it as a raw
            // fnPtr would make the runtime call into an object pointer, so
            // recover the (fnPtr, closureRaw) pair at runtime instead.
            let intType = sema.types.intType
            let fnPtrResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_fn_ptr"),
                arguments: [lambdaID],
                result: fnPtrResult,
                canThrow: false,
                thrownResult: nil
            ))
            let closureRawResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_closure_raw"),
                arguments: [lambdaID],
                result: closureRawResult,
                canThrow: false,
                thrownResult: nil
            ))
            finalArgs.append(fnPtrResult)
            finalArgs.append(closureRawResult)
            return finalArgs
        }
        let fnPtrExpr = arena.appendExpr(.symbolRef(callableInfo.symbol), type: sema.types.intType)
        instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
        finalArgs.append(fnPtrExpr)
        finalArgs.append(makeClosureRawOrBoxedArgument(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ))
        return finalArgs
    }

    func makeCollectionHOFExpandedArguments(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        adaptOnlyWhenCapturing: Bool = false,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var loweredCallableID = loweredArgID
        var callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if let originalCallableInfo = callableInfo,
           !originalCallableInfo.hasClosureParam,
           !adaptOnlyWhenCapturing || !originalCallableInfo.captureArguments.isEmpty,
           let adapted = makeCollectionHOFCallableAdapter(
                callableInfo: originalCallableInfo,
                loweredArgID: loweredArgID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_compare_values_hof_adapter",
                symbolIDOffsetBase: -710_000
           )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adapted.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adapted.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adapted.symbol,
                callee: adapted.callee,
                captureArguments: adapted.captureArguments,
                hasClosureParam: adapted.hasClosureParam
            )
            loweredCallableID = adaptedExpr
            callableInfo = adapted
        }

        var finalArgs: [KIRExprID] = [loweredCallableID]
        finalArgs.append(makeClosureRawOrBoxedArgument(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ))
        return finalArgs
    }

    private func makeCollectionHOFSelectorArgument(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (loweredArgID: KIRExprID, callableInfo: KIRCallableValueInfo?) {
        let loweredSelectorID = loweredArgID
        var selectorCallableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if selectorCallableInfo == nil,
           case let .symbolRef(symbol)? = arena.expr(loweredSelectorID),
           let function = arena.function(for: symbol)
        {
            selectorCallableInfo = KIRCallableValueInfo(
                symbol: function.symbol,
                callee: function.name,
                captureArguments: arena.lambdaCaptureArgsBySymbol[function.symbol] ?? [],
                hasClosureParam: function.params.count >= 2
            )
        }
        if let callableInfo = selectorCallableInfo,
           !callableInfo.hasClosureParam,
           let adaptedInfo = makeCollectionHOFCallableAdapter(
                callableInfo: callableInfo,
                loweredArgID: loweredSelectorID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_compare_values_hof_adapter",
                symbolIDOffsetBase: -710_000
           )
        {
            selectorCallableInfo = adaptedInfo
        }
        // callableInfo.symbol is always the raw function pointer to invoke through.
        // loweredArgID may instead be a boxed/materialized callable value (e.g. a
        // selector read from a local variable rather than an inline lambda literal),
        // so re-point the selector at a fresh reference to the resolved symbol
        // instead of reusing loweredArgID, which would pass the boxed object where
        // a function pointer is expected.
        guard let callableInfo = selectorCallableInfo else {
            return (loweredSelectorID, nil)
        }
        let fnPtrExpr = arena.appendExpr(
            .symbolRef(callableInfo.symbol),
            type: arena.exprType(loweredSelectorID) ?? sema.types.anyType
        )
        instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
        driver.ctx.registerCallableValue(
            fnPtrExpr,
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: callableInfo.hasClosureParam
        )
        return (fnPtrExpr, callableInfo)
    }

    private func makeClosureRawArgument(
        callableInfo: KIRCallableValueInfo?,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let callableInfo,
           let closureRaw = callableInfo.captureArguments.first
        {
            return closureRaw
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    /// Builds the single `closureRaw` slot for the `(fnPtr, closureRaw)` ABI:
    /// 2+ captures are packed into a boxed closure object (so the lambda body's
    /// `kk_array_get_inbounds` unpacking has something valid to read), a single
    /// capture is passed raw, and no captures / no callable info yields 0.
    /// Every call site that produces a closureRaw argument for a
    /// collection-HOF-marked lambda must go through this — using
    /// `callableInfo.captureArguments.first` directly silently drops captures
    /// beyond the first once there are 2 or more.
    private func makeClosureRawOrBoxedArgument(
        callableInfo: KIRCallableValueInfo?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let callableInfo else {
            return makeClosureRawArgument(callableInfo: nil, sema: sema, arena: arena, instructions: &instructions)
        }
        let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let boxedCaptureArgument = boxedCaptureArguments.first {
            return boxedCaptureArgument
        }
        return makeClosureRawArgument(callableInfo: callableInfo, sema: sema, arena: arena, instructions: &instructions)
    }

    func materializeFunctionValueArgument(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        functionType: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Suspend callables are lowered through coroutine launcher/invoke paths,
        // not the ordinary kk_function_create_N function-value ABI.
        guard !functionType.isSuspend else {
            return loweredArgID
        }

        var loweredCallableID = loweredArgID
        var callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if callableInfo == nil,
           case let .symbolRef(symbol)? = arena.expr(loweredCallableID),
           let function = arena.function(for: symbol)
        {
            callableInfo = KIRCallableValueInfo(
                symbol: function.symbol,
                callee: function.name,
                captureArguments: arena.lambdaCaptureArgsBySymbol[function.symbol] ?? [],
                hasClosureParam: function.params.count >= functionType.params.count + 1
            )
        }

        guard var resolvedCallableInfo = callableInfo else {
            return loweredArgID
        }

        if !resolvedCallableInfo.hasClosureParam,
           let adaptedInfo = makeCollectionHOFCallableAdapter(
                callableInfo: resolvedCallableInfo,
                loweredArgID: loweredCallableID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_function_value_adapter",
                symbolIDOffsetBase: -720_000,
                erasedFunctionType: functionType
           )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adaptedInfo.symbol),
                type: arena.exprType(loweredCallableID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adaptedInfo.symbol,
                callee: adaptedInfo.callee,
                captureArguments: adaptedInfo.captureArguments,
                hasClosureParam: adaptedInfo.hasClosureParam
            )
            loweredCallableID = adaptedExpr
            resolvedCallableInfo = adaptedInfo
        }

        let valueArity = functionType.params.count + (functionType.receiver == nil ? 0 : 1)
        let createCallee: InternedString
        switch valueArity {
        case 0:
            createCallee = interner.intern("kk_function_create_0")
        case 1:
            createCallee = interner.intern("kk_function_create_1")
        case 2:
            createCallee = interner.intern("kk_function_create_2")
        case 3:
            createCallee = interner.intern("kk_function_create_3")
        case 4:
            createCallee = interner.intern("kk_function_create_4")
        default:
            return loweredArgID
        }

        let fnPtrExpr = arena.appendExpr(
            .symbolRef(resolvedCallableInfo.symbol),
            type: sema.types.intType
        )
        instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(resolvedCallableInfo.symbol)))
        let closureRaw = makeFunctionValueClosureRawArgument(
            callableInfo: resolvedCallableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let materialized = arena.appendTemporary(type: sema.types.make(.functionType(functionType)))
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [fnPtrExpr, closureRaw],
            result: materialized,
            canThrow: false,
            thrownResult: nil
        ))
        driver.ctx.registerCallableValue(
            materialized,
            symbol: resolvedCallableInfo.symbol,
            callee: resolvedCallableInfo.callee,
            captureArguments: [closureRaw],
            hasClosureParam: true
        )
        return materialized
    }

    func materializeSourceBackedFunctionValueArguments(
        chosenCallee: SymbolID?,
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return
        }

        let symbol = sema.symbols.symbol(chosenCallee)
        let isImported = symbol?.flags.contains(.importedLibrary) == true
        let isInline = symbol?.flags.contains(.inlineFunction) == true

        // Source-backed inline functions are fully expanded in the same
        // module, so lambda arguments can be consumed directly there.
        if isInline, !isImported {
            return
        }

        // Runtime bridges and C ABI stubs use explicit (fnPtr, closureRaw) or
        // raw function-pointer expansion; they must not receive a wrapped
        // function-value object. Imported Kotlin functions compiled to .kklib
        // carry a `kk_fn_` C symbol and still need materialization.
        if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           !externalLinkName.isEmpty,
           !externalLinkName.hasPrefix("kk_fn_") {
            return
        }

        let valueArgOffset = signature.receiverType == nil ? 0 : 1
        // A trailing lambda binds to the callee's LAST parameter regardless of
        // how many defaulted parameters sit before it (e.g. `windowed(3) { ...
        // }` skips `step`/`partialWindows` via their defaults) -- so
        // `sourceArgExprs` (the arguments as the user actually wrote them) can
        // be shorter than `signature.parameterTypes` by exactly that gap.
        // Naively indexing `sourceArgExprs[parameterIndex]` then misses the
        // trailing lambda argument entirely for the real last parameter,
        // silently skipping its materialization (dropping the wrapped
        // function-value handle and, with it, any captured closure state).
        let lastParameterIndex = signature.parameterTypes.count - 1
        let hasTrailingLambdaGap = sourceArgExprs.count < signature.parameterTypes.count
            && !sourceArgExprs.isEmpty
        for parameterIndex in signature.parameterTypes.indices {
            let finalArgIndex = valueArgOffset + parameterIndex
            let sourceArgExprIndex = (hasTrailingLambdaGap && parameterIndex == lastParameterIndex)
                ? sourceArgExprs.count - 1
                : parameterIndex
            guard finalArgIndex < arguments.count,
                  sourceArgExprs.indices.contains(sourceArgExprIndex),
                  !signature.valueParameterIsVararg.indices.contains(parameterIndex)
                    || !signature.valueParameterIsVararg[parameterIndex]
            else {
                continue
            }
            let parameterType = sema.types.makeNonNullable(signature.parameterTypes[parameterIndex])
            guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                continue
            }
            // A non-local return must be expanded into its caller. Wrapping
            // that lambda in a Function object hides its body from imported
            // inline expansion and turns the return into a runtime callback.
            if isInline,
               let callable = driver.ctx.callableValueInfo(for: arguments[finalArgIndex]),
               arena.function(for: callable.symbol)?.isInlineOnly == true
            {
                continue
            }
            arguments[finalArgIndex] = materializeFunctionValueArgument(
                loweredArgID: arguments[finalArgIndex],
                argExprID: sourceArgExprs[sourceArgExprIndex],
                functionType: functionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
    }

    private func appendCollectionHOFSelectorPair(
        _ selector: (loweredArgID: KIRExprID, callableInfo: KIRCallableValueInfo?),
        to arrayExpr: KIRExprID,
        selectorOffset: Int,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let fnIndexExpr = arena.appendExpr(.intLiteral(Int64(selectorOffset * 2)), type: sema.types.intType)
        instructions.append(.constValue(result: fnIndexExpr, value: .intLiteral(Int64(selectorOffset * 2))))
        let fnSetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [arrayExpr, fnIndexExpr, selector.loweredArgID],
            result: fnSetResult,
            canThrow: false,
            thrownResult: nil
        ))

        let closureRaw = makeClosureRawOrBoxedArgument(
            callableInfo: selector.callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let closureIndexExpr = arena.appendExpr(.intLiteral(Int64(selectorOffset * 2 + 1)), type: sema.types.intType)
        instructions.append(.constValue(result: closureIndexExpr, value: .intLiteral(Int64(selectorOffset * 2 + 1))))
        let closureSetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [arrayExpr, closureIndexExpr, closureRaw],
            result: closureSetResult,
            canThrow: false,
            thrownResult: nil
        ))
    }

    /// KSP-500: Wrap a generateSequence nextFunction closure so its returned
    /// primitive is boxed before the runtime stores it as a sequence element.
    ///
    /// Unlike sequenceOf(...)/listOf(...), which box each element explicitly at
    /// the call site, generateSequence's elements are produced lazily by
    /// repeatedly invoking the closure at runtime — there's no fixed set of
    /// argument exprs to box up front. Whether the *closure's own* compiled
    /// body ends up boxing its return value turns out to depend on incidental
    /// KIR shape (e.g. an `if/else` with a `null` branch happens to trigger
    /// ABILoweringPass's copy-boxing, but a bare `{ it + 1 }` or `{ 42 }` does
    /// not), so that can't be relied on. This adapter forwards to the original
    /// closure and boxes the result explicitly, giving a shape-independent
    /// guarantee, and drops in as a replacement fnPtr with the same
    /// (closureRaw, ...values, outThrown) -> result ABI the original closure
    /// already has.
    private func makeGenerateSequenceBoxingAdapter(
        callableInfo: KIRCallableValueInfo,
        valueParamTypes: [TypeID],
        returnType: TypeID,
        boxCallee: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRCallableValueInfo {
        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_generate_sequence_box_adapter_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = valueParamTypes.map { type in
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: type)
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        // The original callable is always collection-HOF-shaped here (callers
        // guard on isCollectionHOFLambdaExpr before building this adapter), so
        // it already has its own closureParam slot as its first parameter —
        // forward this adapter's closureExpr straight through as-is. Don't use
        // appendCallableCaptureLoads: that helper is for adapting a *non*-HOF
        // callable (e.g. a callable reference) into the HOF shape by unpacking
        // captures into separate leading arguments, which is the wrong shape
        // here and silently drops the closureParam argument entirely when the
        // original closure has zero captures.
        var callArguments = [closureExpr]
        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }

        let lambdaCanThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        let callResult = arena.appendTemporary(type: returnType)
        let thrownResult = lambdaCanThrow
            ? arena.appendTemporary(type: sema.types.nullableAnyType)
            : nil
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: lambdaCanThrow,
            thrownResult: thrownResult
        ))
        if let thrownResult {
            let continueLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            body.append(.jump(continueLabel))
            body.append(.label(rethrowLabel))
            body.append(.rethrow(value: thrownResult))
            body.append(.label(continueLabel))
        }

        let boxedResult = arena.appendTemporary(type: returnType)
        emitBoxCallWithValueClassTag(
            boxCallee: boxCallee,
            value: callResult,
            rawSourceKind: sema.types.kind(of: returnType),
            result: boxedResult,
            resultType: returnType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            into: &body
        )
        body.append(.returnValue(boxedResult))
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam] + valueParams,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: true
        )
    }

    /// KSP-500: expand a generateSequence nextFunction closure to (fnPtr, closureRaw),
    /// boxing its returned primitive via a synthesized adapter when the element
    /// type needs it (returns the original closure's fnPtr unchanged otherwise,
    /// e.g. for String/class element types).
    ///
    /// Not private: also called from CallLowerer.swift's three generateSequence
    /// early-return special cases, none of which go through
    /// appendClosureArgumentsIfNeeded (each constructs its `.call` directly —
    /// see those call sites for why), so this is the one place that centralizes
    /// the (fnPtr, closureRaw) expansion + boxing for all of them.
    func expandGenerateSequenceNextFunction(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (fnPtr: KIRExprID, closureRaw: KIRExprID) {
        var fnPtr = loweredArgID
        // Runtime sequence bridges consume the same `(closureRaw, value,
        // outThrown)` ABI as collection HOFs. The source-backed wrapper is
        // generic and does not need a name-specific semantic marker, so recover
        // callable metadata directly from the materialized function value.
        var callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if callableInfo == nil {
            // A function-typed argument can already be boxed as a Kotlin
            // function value before this bridge is lowered. Recover its ABI
            // pair instead of passing the object handle as a C function pointer.
            let intType = sema.types.intType
            let fnPtr = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_fn_ptr"),
                arguments: [loweredArgID],
                result: fnPtr,
                canThrow: false,
                thrownResult: nil
            ))
            let closureRaw = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_closure_raw"),
                arguments: [loweredArgID],
                result: closureRaw,
                canThrow: false,
                thrownResult: nil
            ))
            return (fnPtr, closureRaw)
        }
        if let originalCallableInfo = callableInfo,
           let nextFunctionType = sema.bindings.exprTypes[argExprID],
           case let .functionType(nextFT) = sema.types.kind(of: nextFunctionType),
           let boxCallee = BoxingCalleeTable(interner: interner).boxCallee(
               for: resolveValueClassKind(
                   sema.types.kind(of: nextFT.returnType),
                   types: sema.types,
                   symbols: sema.symbols
               ),
               requireNonNull: false
           )
        {
            let adapterInfo = makeGenerateSequenceBoxingAdapter(
                callableInfo: originalCallableInfo,
                valueParamTypes: nextFT.params,
                returnType: nextFT.returnType,
                boxCallee: boxCallee,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let adapterExpr = arena.appendExpr(
                .symbolRef(adapterInfo.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterInfo.symbol)))
            driver.ctx.registerCallableValue(
                adapterExpr,
                symbol: adapterInfo.symbol,
                callee: adapterInfo.callee,
                captureArguments: adapterInfo.captureArguments,
                hasClosureParam: true
            )
            fnPtr = adapterExpr
            callableInfo = adapterInfo
        }
        // KSP-500 + master's multi-capture fix: route through the shared
        // helper instead of reading captureArguments.first directly — a
        // nextFunction closure with 2+ captures needs them packed into a
        // boxed closure object here (see makeClosureRawOrBoxedArgument's
        // doc comment), otherwise the closure body's kk_array_get_inbounds
        // unpacking misreads a single raw capture value as that object.
        let closureRaw = makeClosureRawOrBoxedArgument(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return (fnPtr, closureRaw)
    }

    func appendClosureArgumentsIfNeeded(
        _ loweredArguments: [KIRExprID],
        originalArgs: [CallArgument],
        chosenCallee: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee) else {
            return loweredArguments
        }

        // Worker.execute has an explicit receiver followed by:
        // (mode, producer, job). The runtime ABI expects both lambdas as
        // (fnPtr, closureRaw) pairs.
        if externalLinkName == "kk_worker_execute",
           loweredArguments.count == originalArgs.count + 1,
           originalArgs.count == 3
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[2],
                argExprID: originalArgs[1].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[3],
                argExprID: originalArgs[2].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return [loweredArguments[0], loweredArguments[1]] + producerArgs + jobArgs
        }
        if externalLinkName == "kk_worker_execute",
           loweredArguments.count == originalArgs.count,
           originalArgs.count == 4
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[2],
                argExprID: originalArgs[2].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[3],
                argExprID: originalArgs[3].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return [loweredArguments[0], loweredArguments[1]] + producerArgs + jobArgs
        }

        guard loweredArguments.count == originalArgs.count else {
            return loweredArguments
        }

        if externalLinkName == "kk_suspend_coroutine", loweredArguments.count == 1 {
            return makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // STDLIB-SEQ-002: 1-arg generateSequence(nextFunction) uses the private bridge.
        if externalLinkName == "__kk_sequence_generate_noarg", loweredArguments.count == 1 {
            let expanded = expandGenerateSequenceNextFunction(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return [expanded.fnPtr, expanded.closureRaw]
        }

        // sequence { ... } builder: expand the receiver lambda to (fnPtr, closureRaw).
        // Capturing builder lambdas need the same closure-aware adapter shape as
        // collection HOFs so the runtime can call (closureRaw, builderRaw, outThrown).
        if externalLinkName == "__kk_sequence_builder_build", loweredArguments.count == 1 {
            return makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        let legacyNames: Set = ["__kk_sequence_generate"]
        if legacyNames.contains(externalLinkName), loweredArguments.count == 2 {
            var seedArgument = loweredArguments[0]
            if externalLinkName == "__kk_sequence_generate",
               let seedCallableInfo = driver.ctx.callableValueInfo(for: loweredArguments[0]),
               let seedFunctionType = sema.bindings.exprTypes[originalArgs[0].expr],
               case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
               functionType.params.isEmpty
            {
                let seedResult = arena.appendTemporary(type: sema.types.makeNonNullable(functionType.returnType)
                )
                instructions.append(.call(
                    symbol: seedCallableInfo.symbol,
                    callee: seedCallableInfo.callee,
                    arguments: seedCallableInfo.captureArguments,
                    result: seedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                seedArgument = seedResult
            }

            var finalArgs = [seedArgument]
            if externalLinkName == "__kk_sequence_generate" {
                let expanded = expandGenerateSequenceNextFunction(
                    loweredArgID: loweredArguments[1],
                    argExprID: originalArgs[1].expr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArgs.append(expanded.fnPtr)
                finalArgs.append(expanded.closureRaw)
            } else {
                // Multi-capture lambdas (>= 2 captures) must be packed into a
                // closure object here, matching the (closureRaw, ...) ABI that
                // LambdaLowerer generates for these collection-HOF-marked
                // lambdas. Forwarding captureArguments.first directly hands the
                // lambda body a raw capture value instead of a closure object,
                // which it then misreads via kk_array_get_inbounds — wrong
                // values for small offsets, out-of-bounds crashes for larger
                // ones.
                let callableInfo = sema.bindings.isCollectionHOFLambdaExpr(originalArgs[1].expr)
                    ? driver.ctx.callableValueInfo(for: loweredArguments[1])
                    : nil
                finalArgs.append(loweredArguments[1])
                finalArgs.append(makeClosureRawOrBoxedArgument(
                    callableInfo: callableInfo,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ))
            }
            return finalArgs
        }

        // STDLIB-590 / STDLIB-KOTLIN-ROOT-CLOSE-001: Function0 runtime entry
        // points receive lambda arguments as (fnPtr, closureRaw).
        let function0RuntimeNames: Set<String> = [
            "__kk_auto_closeable_create",
            "kk_runtime_result_run_catching",
        ]
        if function0RuntimeNames.contains(externalLinkName), loweredArguments.count == 1 {
            return makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // STDLIB-325 / KSP-618: __kkSynchronized(lock, block) — expand the block
        // argument to (lock, fnPtr, closureRaw) while preserving the runtime
        // outThrown slot.
        if externalLinkName == "__kk_synchronized", loweredArguments.count == 2 {
            return makeClosureThunkExpandedArguments(
                prefixArguments: [loweredArguments[0]],
                loweredArgID: loweredArguments[1],
                argExprID: originalArgs[1].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // kotlin.DeepRecursiveFunction { block } — expand the callable argument
        // to (fnPtr, closureRaw) so runtime can retain both the entry point and
        // the captured environment. Multi-capture lambdas are packed into a
        // closure object, reusing the same adapter strategy as collection HOFs.
        if externalLinkName == "__kk_deep_recursive_function_new", loweredArguments.count == 1 {
            return makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                adaptOnlyWhenCapturing: true,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        return loweredArguments
    }

    private func makeFunctionValueClosureRawArgument(
        callableInfo: KIRCallableValueInfo,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let closureRaw = boxedCaptureArguments.first {
            return closureRaw
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    func makeClosureThunkCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType),
              functionType.params.isEmpty
        else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_closure_thunk_adapter_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let callArguments = appendCallableCaptureLoads(
            callableInfo: callableInfo,
            closureExpr: closureExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )

        let lambdaCanThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        let callResult = arena.appendTemporary(type: functionType.returnType
        )
        let thrownResult = lambdaCanThrow
            ? arena.appendTemporary(type: sema.types.nullableAnyType
            )
            : nil
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: lambdaCanThrow,
            thrownResult: thrownResult
        ))
        if let thrownResult {
            let continueLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            body.append(.jump(continueLabel))
            body.append(.label(rethrowLabel))
            body.append(.rethrow(value: thrownResult))
            body.append(.label(continueLabel))
        }

        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam],
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let adapterCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: adapterCaptureArguments,
            hasClosureParam: true
        )
    }

}
