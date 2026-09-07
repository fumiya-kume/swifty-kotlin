struct KIRCallableValueInfo {
    let symbol: SymbolID
    let callee: InternedString
    let captureArguments: [KIRExprID]
    /// True when lambda has closure param for C HOF ABI (filter, map, etc.).
    let hasClosureParam: Bool
}

final class LambdaLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    private func normalizeHOFPrimitiveParameter(
        _ exprID: KIRExprID,
        type: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        isRawCallbackParameter: Bool = false
    ) -> KIRExprID {
        let kind = sema.types.kind(of: type)
        // String parameters of raw-callback lambdas are bridged from raw handle
        // to flat aggregate by the backend at function entry. Unboxing them here
        // again would pass an already-flat aggregate to kk_string_to_flat and
        // crash, so skip the KIR-level unboxing only for those parameters.
        if isRawCallbackParameter, isNonNullableStringStruct(kind) {
            return exprID
        }
        let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
            for: kind,
            requireNonNull: true
        )
        guard let unboxCallee else {
            return exprID
        }
        let normalizedExpr = emitNonThrowingCall(
            callee: unboxCallee,
            arg: exprID,
            resultType: type,
            arena: arena,
            into: &instructions
        )
        return normalizedExpr
    }

    private func isNonNullableStringStruct(_ kind: TypeKind) -> Bool {
        guard case let .stringStruct(nullability) = kind else {
            return false
        }
        return nullability == .nonNull
    }

    /// Best-effort scan for whether a lowered lambda body performs a call that
    /// requires a suspend context (`.await()`/`.join()`/`delay`/`yield`/a generic
    /// suspend-function-invoke/a Flow operation, or a call to another
    /// already-lowered suspend function). Used to correct a lambda literal's
    /// `isSuspend` when the contextual/expected type it was checked against is
    /// non-suspend (e.g. `List.map`'s plain `(T) -> R` `transform` parameter)
    /// but the body suspends anyway -- see the call sites for why trusting the
    /// contextual type alone causes suspend calls to run without a valid
    /// continuation.
    private func lambdaBodyRequiresSuspend(
        _ body: [KIRInstruction],
        arena: KIRArena,
        interner: StringInterner
    ) -> Bool {
        let suspendIndicatorNames: Set<String> = [
            "kk_kxmini_async_await",
            "kk_job_join",
            "kk_job_await_completion",
            "kk_kxmini_delay",
            "kk_coroutine_yield",
            "__kk_sequence_builder_yield",
            "__kk_iterator_builder_yield",
            "kk_suspend_function_invoke_0",
            "kk_suspend_function_invoke",
            "kk_suspend_function_invoke_2",
            "kk_suspend_coroutine",
            "kk_with_timeout",
            "kk_with_timeout_or_null",
            "kk_flow_collect",
            "__kk_flow_collectLatest",
            "kk_flow_emit",
        ]
        for instruction in body {
            let calleeInfo: (symbol: SymbolID?, callee: InternedString)?
            switch instruction {
            case let .call(symbol, callee, _, _, _, _, _, _):
                calleeInfo = (symbol, callee)
            case let .virtualCall(symbol, callee, _, _, _, _, _, _):
                calleeInfo = (symbol, callee)
            default:
                calleeInfo = nil
            }
            guard let calleeInfo else { continue }
            if suspendIndicatorNames.contains(interner.resolve(calleeInfo.callee)) {
                return true
            }
            if let symbol = calleeInfo.symbol, arena.function(for: symbol)?.isSuspend == true {
                return true
            }
        }
        return false
    }

    func lowerLambdaLiteralExpr(
        _ exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        allowsNonLocalReturn: Bool = false,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        // For SAM-converted lambdas, the bound type is the interface type.
        // Use the stored underlying function type instead.
        let effectiveFuncTypeID: TypeID? = {
            if sema.bindings.isSamConversion(exprID),
               let samFuncType = sema.bindings.samUnderlyingFunctionType(for: exprID)
            {
                return samFuncType
            }
            return boundType
        }()
        let functionType = effectiveFuncTypeID.flatMap { typeID -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                return nil
            }
            return functionType
        }

        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let isSamConversion = sema.bindings.isSamConversion(exprID)
        let lambdaSymbol: SymbolID = if isSamConversion {
            sema.symbols.define(
                kind: .function,
                name: lambdaName,
                fqName: [lambdaName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        } else {
            driver.ctx.syntheticLambdaSymbol(for: exprID)
        }

        // Enhanced receiver parameter handling for lambda with receiver types
        let hasReceiverParam = functionType?.receiver != nil
        let needsClosureParam = sema.bindings.isCollectionHOFLambdaExpr(exprID) && !isSamConversion
        let activeReceiverSatisfiesExpectedType: Bool = {
            guard let expectedReceiverType = functionType?.receiver,
                  let activeReceiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                  let activeReceiverType = arena.exprType(activeReceiverExprID)
            else {
                return false
            }
            return sema.types.isSubtype(
                sema.types.makeNonNullable(activeReceiverType),
                sema.types.makeNonNullable(expectedReceiverType)
            )
        }()
        let needsExplicitReceiver = hasReceiverParam && !activeReceiverSatisfiesExpectedType
        let effectiveParamCount: Int = {
            let baseCount: Int = if params.isEmpty, let functionType, !functionType.params.isEmpty {
                functionType.params.count
            } else {
                params.count
            }
            // For receiver lambdas (e.g., StringBuilder.() -> Unit), the receiver
            // is implicitly passed as the first parameter, but only if there's no
            // active implicit receiver in the current scope
            return baseCount + (needsExplicitReceiver ? 1 : 0)
        }()

        let lambdaParameterTypes: [TypeID] = {
            var types: [TypeID] = []
            // Add receiver parameter first if needed
            if needsExplicitReceiver, let receiverType = functionType?.receiver {
                types.append(receiverType)
            }
            let valueParamCount = effectiveParamCount - (needsExplicitReceiver ? 1 : 0)
            for index in 0 ..< valueParamCount {
                if let functionType, index < functionType.params.count {
                    types.append(functionType.params[index])
                } else {
                    types.append(sema.types.anyType)
                }
            }
            return types
        }()
        let substitutedReturnType = functionType?.returnType
            ?? sema.bindings.exprTypes[bodyExpr]
            ?? sema.types.anyType
        // A return the callee declares as a type parameter carries a boxed value
        // at runtime even though the body is checked against the substituted
        // concrete type, so box on the way out.
        let returnsErasedGeneric = !needsClosureParam && !isSamConversion
            && driver.ctx.lambdaReturnsErasedGeneric(for: exprID, ast: ast, sema: sema)
        let lambdaReturnType = erasedLambdaReturnType(
            substitutedReturnType,
            returnsErasedGeneric: returnsErasedGeneric,
            sema: sema,
            interner: interner
        )

        let captureSymbols = computeCaptureSymbolsForLambda(
            lambdaExprID: exprID,
            lambdaParamCount: effectiveParamCount,
            lambdaBodyExprID: bodyExpr,
            ast: ast,
            sema: sema,
            hasExplicitReceiver: needsExplicitReceiver
        )

        // Non-capturing lambda optimization: if no captures, use function pointer directly
        let isNonCapturingLambda = captureSymbols.isEmpty && !needsClosureParam
        if isNonCapturingLambda {
            return lowerNonCapturingLambda(
                exprID: exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                effectiveParamCount: effectiveParamCount,
                hasExplicitReceiverParam: needsExplicitReceiver,
                lambdaParameterTypes: lambdaParameterTypes,
                lambdaReturnType: lambdaReturnType,
                substitutedReturnType: substitutedReturnType,
                returnsErasedGeneric: returnsErasedGeneric,
                functionType: functionType,
                isSamConversion: isSamConversion,
                boundType: boundType,
                effectiveFuncTypeID: effectiveFuncTypeID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)] = []
        captureBindings.reserveCapacity(captureSymbols.count)
        for (index, symbol) in captureSymbols.enumerated() {
            let declaredType = driver.ctx.localDeclaredType(for: symbol) ?? typeForSymbolReference(symbol, sema: sema)
            guard let captureValueExpr = captureValueExpr(
                for: symbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) else {
                continue
            }
            let captureType = arena.exprType(captureValueExpr) ?? typeForSymbolReference(symbol, sema: sema)
            let captureParamSymbol = syntheticLambdaCaptureParamSymbol(
                lambdaExprID: exprID,
                captureIndex: index
            )
            let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
            captureBindings.append((
                capturedSymbol: symbol,
                param: captureParam,
                valueExpr: captureValueExpr,
                declaredType: declaredType
            ))
        }

        // For lambdas passed to C HOFs (filter, map, toComponents, etc.),
        // Runtime expects (closureRaw, ...valueParams, outThrown). Add closure param as first param.
        let lambdaParameters: [KIRParameter]
        if needsClosureParam {
            let closureParamType = captureBindings.count == 1
                ? captureBindings[0].param.type
                : sema.types.intType
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: closureParamType
            )
            let valueParams = (0 ..< effectiveParamCount).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
            lambdaParameters = [closureParam] + valueParams
        } else {
            lambdaParameters = (0 ..< effectiveParamCount).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
        }
        let usesClosureRawCapture = needsClosureParam && captureBindings.count == 1
        let usesClosureObjectCapture = needsClosureParam && captureBindings.count >= 2
        let functionCaptureBindings = (usesClosureRawCapture || usesClosureObjectCapture) ? [] : captureBindings

        let scopeSnapshot = driver.ctx.saveScope()
        let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.currentLambdaAllowsNonLocalReturn = allowsNonLocalReturn

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in functionCaptureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            bindCapturedLambdaValue(captureExpr, capture: capture, sema: sema)
            if capture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
            }
        }
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            let normalizedParamExpr: KIRExprID
            if needsClosureParam, paramIndex > 0 {
                normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: lambdaParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &lambdaBody,
                    isRawCallbackParameter: true
                )
            } else {
                normalizedParamExpr = paramExpr
            }
            driver.ctx.setLocalValue(normalizedParamExpr, for: lambdaParam.symbol)
            // When a parameter is the explicit receiver (from a function-with-receiver type),
            // set it as the implicit receiver so that member calls resolve correctly.
            // For collection-HOF lambdas the closure param is first, so the receiver
            // follows it.
            let receiverParamIndex = needsClosureParam ? 1 : 0
            if needsExplicitReceiver, paramIndex == receiverParamIndex {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: normalizedParamExpr)
            }
        }
        if usesClosureRawCapture,
           let closureCapture = captureBindings.first,
           let closureParam = lambdaParameters.first,
           let closureExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            bindCapturedLambdaValue(closureExpr, capture: closureCapture, sema: sema)
            if closureCapture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: closureParam.symbol, exprID: closureExpr)
            }
        }
        // Multi-capture HOF lambda: closureRaw is a packed closure object.
        // Load each capture from the object via kk_array_get_inbounds.
        if usesClosureObjectCapture,
           let closureParam = lambdaParameters.first,
           let closureObjExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            let kkArrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, capture) in captureBindings.enumerated() {
                let fieldOffset = Int64(captureIndex + 2)
                let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: sema.types.intType)
                lambdaBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                let loadedExpr = arena.appendTemporary(type: capture.param.type)
                lambdaBody.append(.call(
                    symbol: nil,
                    callee: kkArrayGet,
                    arguments: [closureObjExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                bindCapturedLambdaValue(loadedExpr, capture: capture, sema: sema)
                if capture.capturedSymbol == savedReceiverSymbol {
                    driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: loadedExpr)
                }
            }
        }
        // Map param names → symbols for nameRef fallback when identifierSymbols is unbound.
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        // Value parameters start after the closure environment parameter (HOF
        // lambdas) and after the explicit receiver parameter (receiver lambdas
        // such as `DeepRecursiveScope<T, R>.(T) -> R`); without the receiver
        // offset a named parameter would alias the receiver slot.
        let valueParamStart = (needsClosureParam ? 1 : 0) + (needsExplicitReceiver ? 1 : 0)
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
        let returnedBody = boxErasedReturnValue(
            loweredBody,
            returnType: substitutedReturnType,
            returnsErasedGeneric: returnsErasedGeneric,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &lambdaBody
        )
        lambdaBody.append(.returnValue(returnedBody))
        lambdaBody.append(.endBlock)

        // Coroutine launcher lambdas with an explicit receiver use launcher slot 0
        // for that receiver (for example, the Channel receiver of `produce {}`).
        // Keep that receiver first in the lowered function ABI; ordinary captured
        // lambdas retain the historical capture-first layout.
        let receiverFirstLauncherABI = sema.bindings.isCoroutineLauncherLambdaExpr(exprID)
            && needsExplicitReceiver
        let functionParameters = receiverFirstLauncherABI
            ? lambdaParameters + functionCaptureBindings.map(\.param)
            : functionCaptureBindings.map(\.param) + lambdaParameters

        // The expected/contextual function type (e.g. a plain `(T) -> R)` HOF
        // parameter like `List.map`'s `transform`) doesn't always match what the
        // lambda body actually does: Kotlin only requires the *parameter* to be
        // `suspend` when the argument lambda calls suspend functions, but KSwiftK
        // currently still permits a suspend call inside a lambda literal checked
        // against a non-suspend expected type (matching real Kotlin's behavior for
        // `inline` HOFs, but without requiring the HOF itself to be inlined away).
        // If such a lambda is lowered as `isSuspend: false` anyway, it never gets
        // picked up by CoroutineLoweringPass's CPS transform, so its suspend calls
        // run without a valid continuation and corrupt memory at runtime instead
        // of suspending. Detect that mismatch directly from the lowered body so
        // the declared isSuspend always matches what the body actually needs.
        let effectiveIsSuspend = (functionType?.isSuspend ?? false)
            || lambdaBodyRequiresSuspend(lambdaBody, arena: arena, interner: interner)
        let hasNonLocalReturn = lambdaBody.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }

        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: functionParameters,
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: effectiveIsSuspend,
                    isInline: false,
                    isInlineOnly: hasNonLocalReturn
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceType: interfaceType,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: captureBindings,
               samMethodParamTypes: lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // For SAM-converted lambdas, use the function type (not the interface
        // type) so the KIR callable value machinery dispatches correctly.
        let lambdaValueType = effectiveFuncTypeID
            ?? boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: effectiveIsSuspend,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))
        let captureArgs = (usesClosureRawCapture || usesClosureObjectCapture) ? captureBindings.map(\.valueExpr) : functionCaptureBindings.map(\.valueExpr)
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: captureArgs,
            hasClosureParam: needsClosureParam
        )
        if !captureArgs.isEmpty {
            arena.registerLambdaCaptureArgs(lambdaSymbol, captureArgs: captureArgs)
        }
        // Lambdas passed to runBlocking/launch/async/produce are excluded: their
        // captures are forwarded through CoroutineLoweringPass+LauncherSupport's
        // own launcher-continuation rewrite (BUG-049), which expects to resolve
        // the raw lambda symbol directly rather than a kk_function_create_N
        // boxed closure -- see the coroutineLauncherLambdaExprIDs doc comment.
        if !captureArgs.isEmpty,
           !needsClosureParam,
           !isSamConversion,
           !sema.bindings.isCoroutineLauncherLambdaExpr(exprID),
           let functionType
        {
            if let materialized = materializeEscapingCallableValue(
                exprID: exprID,
                lambdaSymbol: lambdaSymbol,
                lambdaReturnType: lambdaReturnType,
                functionType: functionType,
                captureArguments: captureArgs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return materialized
            }
        }
        return lambdaValueExpr
    }

    /// Re-establishes one captured symbol's value inside a lambda body's
    /// fresh scope (`resetScopeForFunction()` clears the outer scope's
    /// bindings, including delegate storage -- see `ScopeSnapshot`), keyed
    /// off the *kind* of thing `capturedValue` holds:
    /// - a mutable local's captured value is a box cell (`setMutableCaptureCell`)
    /// - a delegated local's (KSP-491: `val x by lazy { ... }`/`by Prop()`)
    ///   captured value is the delegate *instance*, not a value
    ///   (`setLocalDelegateStorage`) -- reads inside the lambda body must
    ///   still call getValue fresh, exactly like reads in the declaring
    ///   scope (see `ExprLowerer.readLocalDelegateValue`), or a vetoable/
    ///   observable delegate's writes wouldn't be observed from inside the
    ///   lambda
    /// - anything else is a plain captured value (`setLocalValue`)
    private func bindCapturedLambdaValue(
        _ capturedValue: KIRExprID,
        capture: (capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID),
        sema: SemaModule
    ) {
        if sema.symbols.delegateGetValueSymbol(for: capture.capturedSymbol) != nil {
            driver.ctx.setLocalDelegateStorage(capturedValue, for: capture.capturedSymbol)
        } else if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
                  semanticSymbol.kind == .local,
                  semanticSymbol.flags.contains(.mutable)
        {
            driver.ctx.setMutableCaptureCell(capturedValue, for: capture.capturedSymbol)
        } else {
            driver.ctx.setLocalValue(capturedValue, for: capture.capturedSymbol)
        }
        driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
        if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
           semanticSymbol.kind == .typeParameter,
           semanticSymbol.flags.contains(.reifiedTypeParameter)
        {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: capture.capturedSymbol)
            driver.ctx.setLocalValue(capturedValue, for: tokenSymbol)
            driver.ctx.setLocalDeclaredType(sema.types.intType, for: tokenSymbol)
        }
    }

    private func materializeEscapingCallableValue(
        exprID: ExprID,
        lambdaSymbol: SymbolID,
        lambdaReturnType: TypeID,
        functionType: FunctionType,
        captureArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // The kk_function_create_N ABI has no receiver slot, so a receiver-bearing
        // callable (e.g. `DeepRecursiveScope<T, R>.(T) -> R`) cannot be boxed here
        // without dropping the receiver. Keep the raw lambda instead: call sites
        // that consume such callables adapt them through
        // makeCollectionHOFCallableAdapter, which forwards the receiver explicitly.
        guard functionType.receiver == nil else {
            return nil
        }
        let createCallee: InternedString
        switch functionType.params.count {
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
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_function_value_adapter_\(exprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = functionType.params.enumerated().map { index, type in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 100 + index),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let arrayGet = interner.intern("kk_array_get_inbounds")
        var callArguments: [KIRExprID] = []
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let loadedExpr = arena.appendTemporary(type: captureType)
            body.append(.call(
                symbol: nil,
                callee: arrayGet,
                arguments: [closureExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            let normalizedLoadedExpr = normalizeHOFPrimitiveParameter(
                loadedExpr,
                type: captureType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body,
                isRawCallbackParameter: true
            )
            callArguments.append(normalizedLoadedExpr)
        }

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }

        let lambdaCanThrow = adapterRequiresThrownChannel(lambdaSymbol: lambdaSymbol, arena: arena)
        let callResult = arena.appendTemporary(type: lambdaReturnType)
        let thrownResult = lambdaCanThrow
            ? arena.appendTemporary(type: sema.types.nullableAnyType
            )
            : nil
        body.append(.call(
            symbol: lambdaSymbol,
            callee: syntheticLambdaName(for: exprID, interner: interner),
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
        switch sema.types.kind(of: lambdaReturnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
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
                    params: [closureParam] + valueParams,
                    returnType: lambdaReturnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(2 + captureArguments.count)), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(2 + captureArguments.count))))
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObj = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: closureObj,
            canThrow: false,
            thrownResult: nil
        ))
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let setResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [closureObj, offsetExpr, captureExpr],
                result: setResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let materializedExpr = arena.appendTemporary(type: sema.types.make(.functionType(functionType)))
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [adapterExpr, closureObj],
            result: materializedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        driver.ctx.registerCallableValue(
            materializedExpr,
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: [closureObj],
            hasClosureParam: false
        )
        return materializedExpr
    }

    private func adapterRequiresThrownChannel(lambdaSymbol: SymbolID, arena: KIRArena) -> Bool {
        guard let function = arena.function(for: lambdaSymbol) else {
            return false
        }
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, _, _, canThrow, _, _, _), let .virtualCall(_, _, _, _, _, canThrow, _, _):
                if canThrow {
                    return true
                }
            case .rethrow:
                return true
            default:
                continue
            }
        }
        return false
    }

    private func lowerSamWrapperValue(
        _ exprID: ExprID,
        interfaceType: ClassType,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)],
        samMethodParamTypes: [TypeID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let interfaceSymbol = interfaceType.classSymbol
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface),
              let samMethod = samMethodSymbolAndSignature(for: interfaceSymbol, sema: sema)
        else {
            return nil
        }

        let wrapperName = interner.intern("kk_sam_wrapper_\(exprID.rawValue)")
        let wrapperFQName = [wrapperName]
        let wrapperSymbol = sema.symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.symbols.setSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var nextFieldOffset = 2
        let captureFieldSymbols = captureBindings.enumerated().map { index, capture in
            let fieldName = interner.intern("$sam_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(capture.param.type, for: fieldSymbol)
            fieldOffsets[fieldSymbol] = nextFieldOffset
            nextFieldOffset += 1
            return fieldSymbol
        }

        let methodName = samMethod.info.name
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)

        let methodParamSymbols: [SymbolID] = samMethodParamTypes.enumerated().map { index, type in
            let paramName = interner.intern("$p\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: wrapperFQName + [methodName, paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: wrapperType,
                parameterTypes: samMethodParamTypes,
                returnType: lambdaReturnType,
                isSuspend: samMethod.signature.isSuspend,
                valueParameterSymbols: methodParamSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: methodParamSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: methodParamSymbols.count),
                typeParameterSymbols: []
            ),
            for: methodSymbol
        )
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFieldSymbols.count,
                instanceSizeWords: max(2 + captureFieldSymbols.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [methodSymbol: 0, samMethod.symbol: 0],
                itableSlots: [interfaceSymbol: 0],
                vtableSize: 1,
                superClass: nil
            ),
            for: wrapperSymbol
        )

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(methodSymbol)

        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)

        let methodParams = [KIRParameter(symbol: receiverSymbol, type: wrapperType)]
            + zip(methodParamSymbols, samMethodParamTypes).map { KIRParameter(symbol: $0.0, type: $0.1) }
        var methodBody: [KIRInstruction] = [.beginBlock]
        methodBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))

        var loadedCaptureExprs: [KIRExprID] = []
        for (index, fieldSymbol) in captureFieldSymbols.enumerated() {
            guard let fieldOffset = fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            methodBody.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureType = captureBindings[index].param.type
            let loadedExpr = arena.appendTemporary(type: captureType)
            methodBody.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            loadedCaptureExprs.append(loadedExpr)
        }

        let loweredMethodParamExprs = zip(methodParamSymbols, samMethodParamTypes).map { symbol, type in
            let expr = arena.appendExpr(.symbolRef(symbol), type: type)
            methodBody.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }

        let callResult = arena.appendTemporary(type: lambdaReturnType)
        methodBody.append(.call(
            symbol: lambdaSymbol,
            callee: lambdaName,
            arguments: loadedCaptureExprs + loweredMethodParamExprs,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        if lambdaReturnType == sema.types.unitType {
            methodBody.append(.returnUnit)
        } else {
            methodBody.append(.returnValue(callResult))
        }
        methodBody.append(.endBlock)

        let methodDeclID = arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: methodName,
            params: methodParams,
            returnType: lambdaReturnType,
            body: methodBody,
            isSuspend: samMethod.signature.isSuspend,
            isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(methodDeclID)
        driver.ctx.restoreScope(scopeSnapshot)

        let slotCount = Int64(max(2 + captureFieldSymbols.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let wrapperValue = arena.appendTemporary(type: sema.types.make(.classType(ClassType(
                classSymbol: interfaceSymbol,
                args: interfaceType.args,
                nullability: .nonNull
            )))
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false,
            thrownResult: nil
        ))

        let childTypeExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: childTypeExpr, value: .intLiteral(classIDValue)))
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let registerResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_type_register_iface"),
            arguments: [childTypeExpr, interfaceTypeExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
        // BUG-224: `wrapperSymbol` is a KIR-synthetic identity with no Sema
        // supertype entry of its own, so the edge above must stay explicit —
        // but `interfaceSymbol` (the SAM/fun interface being implemented) is
        // a real declared nominal, and if it itself extends another
        // interface that edge needs registering too, or a comparison through
        // that further ancestor would never reach this wrapper.
        appendTypeAncestryRegistrations(
            rootSymbol: interfaceSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let ifaceSlot = Int64(sema.symbols.nominalLayout(for: wrapperSymbol)?.itableSlots[interfaceSymbol] ?? 0)
        let methodSlot = Int64(sema.symbols.nominalLayout(for: interfaceSymbol)?.vtableSlots[samMethod.symbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: sema.types.intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
        let registerIfaceResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [wrapperValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerIfaceResult,
            canThrow: false,
            thrownResult: nil
        ))
        let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: sema.types.intType)
        instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
        let registeredMethodSymbol = itableBridgeSymbolForMethod(
            interfaceMethod: samMethod.symbol,
            implementation: methodSymbol,
            nominalSymbol: wrapperSymbol,
            driver: driver,
            arena: arena,
            sema: sema,
            interner: interner
        )
        let methodFnExpr = arena.appendExpr(.symbolRef(registeredMethodSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredMethodSymbol)))
        let registerMethodResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_method"),
            arguments: [wrapperValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
            result: registerMethodResult,
            canThrow: false,
            thrownResult: nil
        ))

        // Expose the SAM wrapper as an invokable comparator value so stdlib
        // comparison lowering can call `compare` directly when needed.
        driver.ctx.registerCallableValue(
            wrapperValue,
            symbol: methodSymbol,
            callee: methodName,
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )

        for (index, capture) in captureBindings.enumerated() {
            guard index < captureFieldSymbols.count,
                  let fieldOffset = fieldOffsets[captureFieldSymbols[index]]
            else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture.valueExpr],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        _ = samMethodParamTypes
        return wrapperValue
    }

    private func samMethodSymbolAndSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> (symbol: SymbolID, info: SemanticSymbol, signature: FunctionSignature)? {
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface)
        else {
            return nil
        }
        let abstractMethods = sema.symbols.children(ofFQName: interfaceInfo.fqName).compactMap { childID -> (SymbolID, SemanticSymbol, FunctionSignature)? in
            guard let childInfo = sema.symbols.symbol(childID),
                  childInfo.kind == .function,
                  childInfo.flags.contains(.abstractType),
                  let signature = sema.symbols.functionSignature(for: childID)
            else {
                return nil
            }
            return (childID, childInfo, signature)
        }
        guard abstractMethods.count == 1 else {
            return nil
        }
        return abstractMethods[0]
    }

    /// Lowers a SAM-converted callable reference (`Comparator<Int>(::myCompare)`)
    /// into a wrapper object implementing the functional interface.  A thunk with
    /// the lambda calling convention `(captures..., params...) -> R` is generated
    /// so the shared SAM wrapper synthesis can delegate to the referenced callable.
    private func lowerCallableRefSamWrapperValue(
        _ exprID: ExprID,
        targetSymbol: SymbolID,
        captureArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let interfaceTypeID = sema.bindings.samInterfaceType(for: exprID),
              case let .classType(interfaceType) = sema.types.kind(of: interfaceTypeID),
              let samFunctionTypeID = sema.bindings.samUnderlyingFunctionType(for: exprID),
              case let .functionType(samFunctionType) = sema.types.kind(of: samFunctionTypeID)
        else {
            return nil
        }

        let samMethodParamTypes = samFunctionType.params
        let returnType = samFunctionType.returnType

        let thunkName = interner.intern("kk_sam_ref_thunk_\(exprID.rawValue)")
        let thunkSymbol = sema.symbols.define(
            kind: .function,
            name: thunkName,
            fqName: [thunkName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
            KIRParameter(
                symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                type: arena.exprType(captureExpr) ?? sema.types.anyType
            )
        }
        let valueParams: [KIRParameter] = samMethodParamTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        var callArguments: [KIRExprID] = []
        for param in captureParams + valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }
        let callResult = arena.appendTemporary(type: returnType)
        body.append(.call(
            symbol: targetSymbol,
            callee: callableTargetName(for: targetSymbol, sema: sema, interner: interner),
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        switch sema.types.kind(of: returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let thunkDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: thunkSymbol,
                    name: thunkName,
                    params: captureParams + valueParams,
                    returnType: returnType,
                    body: body,
                    isSuspend: samFunctionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(thunkDecl)

        let captureBindings = zip(captureParams, captureArguments).map { param, valueExpr in
            (capturedSymbol: param.symbol, param: param, valueExpr: valueExpr, declaredType: param.type)
        }

        return lowerSamWrapperValue(
            exprID,
            interfaceType: interfaceType,
            lambdaSymbol: thunkSymbol,
            lambdaName: thunkName,
            lambdaReturnType: returnType,
            captureBindings: captureBindings,
            samMethodParamTypes: samMethodParamTypes,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func lowerCallableRefExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let isUnbound = sema.bindings.isUnboundCallableRef(exprID)
        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )
        // KSP-505: a property ref whose owner is a genuine singleton
        // (`.object` — companion object or plain `object`) never captures a
        // receiver, in *either* bare or explicit-receiver form. Kotlin
        // guarantees exactly one instance for these, so
        // ensurePropertyReferenceAccessor (in
        // LambdaLowerer+PropertyReferenceLowering.swift) reads/writes a
        // single module-level global slot rather than a per-instance field —
        // there is nothing for a captured receiver to do. Capturing one
        // anyway (e.g. the explicit-receiver branch below unconditionally
        // did before this fix) mismatches that accessor's now-receiver-less
        // signature and previously crashed: for singletons that implement no
        // interface and declare no virtual dispatch, no real heap instance
        // is ever allocated, so the "receiver" being captured was frequently
        // a null placeholder in the first place.
        //
        // Deliberately excludes `.enumClass`: unlike `.object`, an enum
        // class has multiple instances (one per entry), so a property
        // declared directly in its own body is a genuine per-instance field,
        // not shared global storage — confirmed by testing (see the matching
        // note in ExprTypeChecker+NameLambdaAndCallableRefInference.swift).
        let isSingletonOwnedPropertyRef: Bool = {
            guard sema.bindings.callableRefKind(for: exprID) == .propertyRef,
                  let targetSymbol,
                  let parentSymbol = sema.symbols.parentSymbol(for: targetSymbol),
                  let parentKind = sema.symbols.symbol(parentSymbol)?.kind
            else { return false }
            return parentKind == .object
        }()
        var captureArguments: [KIRExprID] = []
        if let receiverExpr {
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // For unbound type references (Type::member), the receiver is
            // not captured — it becomes a parameter of the function type.
            if !isUnbound, !isSingletonOwnedPropertyRef {
                captureArguments.append(loweredReceiver)
            }
        } else if !isUnbound,
                  !isSingletonOwnedPropertyRef,
                  sema.bindings.callableRefKind(for: exprID) == .propertyRef,
                  let targetSymbol,
                  let parentSymbol = sema.symbols.parentSymbol(for: targetSymbol),
                  isCaptureEligibleInstanceContainerSymbol(parentSymbol, sema: sema),
                  let implicitReceiver = driver.ctx.activeImplicitReceiverExprID(),
                  implicitReceiverMatchesOwner(
                      implicitReceiver,
                      ownerSymbol: parentSymbol,
                      sema: sema,
                      arena: arena
                  )
        {
            // KSP-496: a bare `::member` reference to a member property of the
            // enclosing class is implicitly bound to `this` in Kotlin (the
            // same shape as an explicit `this::member`), so it needs the same
            // receiver capture — otherwise the generated wrapper's accessor
            // has no instance to read/write, and calling `.get()`/`.set()`
            // on it crashes (KSWIFTK-RUNTIME-0001 out-of-bounds read).
            //
            // Restricted to `.class` (see
            // isCaptureEligibleInstanceContainerSymbol; singleton owners are
            // excluded above, not here) and guarded by
            // implicitReceiverMatchesOwner: the implicit receiver at this
            // lowering point is a single "current" value (KIRLoweringContext
            // has no receiver stack), so it can be a *different*
            // receiver-scope's instance — e.g. `with(sb) { ::v }` inside a
            // member function sees `sb` (StringBuilder), not `this` (the
            // property's real owner), while it's active. When this guard
            // doesn't hold, no capture is added and the reference falls
            // through to the same (pre-existing, argument-count-mismatch)
            // crash bare `::member` already had for a receiver it can't
            // safely resolve — not memory corruption from reading a
            // wrong-typed object's fields.
            captureArguments.append(implicitReceiver)
        }

        // BUG-162: KProperty0/1 references need a real object implementing the
        // bundled KProperty and Function interfaces. A raw property symbol is
        // sufficient for a direct getter call, but it has no itable entries for
        // KProperty.get/invoke/set and cannot carry the bound receiver safely.
        if sema.bindings.callableRefKind(for: exprID) == .propertyRef,
           let propertyValue = lowerPropertyReferenceWrapperValue(
               exprID,
               targetSymbol: targetSymbol,
               memberName: memberName,
               boundType: boundType,
               isUnbound: isUnbound,
               captureArguments: captureArguments,
               ast: ast,
               sema: sema,
               arena: arena,
               interner: interner,
               propertyConstantInitializers: propertyConstantInitializers,
               instructions: &instructions
           )
        {
            return propertyValue
        }

        // BUG-048: A callable reference in SAM-conversion position must become an
        // object implementing the functional interface (with an itable entry), the
        // same way a SAM-converted lambda literal does.  Lowering it as a bare
        // callable value makes interface dispatch on the result fail at runtime.
        if sema.bindings.isSamConversion(exprID),
           let targetSymbol,
           let samValue = lowerCallableRefSamWrapperValue(
               exprID,
               targetSymbol: targetSymbol,
               captureArguments: captureArguments,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // REFL-003: When a callable ref is used as a collection HOF argument
        // (e.g. `list.map(::double)`), we must generate a wrapper thunk with the
        // HOF ABI: (closureRaw, value, outThrown) -> result.  The target function
        // itself uses a plain ABI (value) -> result, so we cannot pass its
        // pointer directly to the runtime HOF implementation.
        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)

        let callableSymbol: SymbolID
        let callableName: InternedString
        if let targetSymbol, needsHOFWrapper {
            // Generate a HOF-ABI wrapper that delegates to the target function.
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)

            let targetName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let valueParamTypes = functionType?.params ?? []
            let returnType = functionType?.returnType ?? sema.types.anyType

            // Build wrapper params: (closureRaw, value0, ..., valueN)
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            let valueParams: [KIRParameter] = valueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            let wrapperParams = [closureParam] + valueParams

            // Build wrapper body: call the target function with the value params,
            // then return its result.
            var body: [KIRInstruction] = [.beginBlock]
            var callArgExprs: [KIRExprID] = []
            // If the callable ref has a bound receiver, pass capture args first.
            for _ in captureArguments {
                let captureRef = arena.appendExpr(
                    .symbolRef(closureParam.symbol),
                    type: closureParam.type
                )
                body.append(.constValue(result: captureRef, value: .symbolRef(closureParam.symbol)))
                callArgExprs.append(captureRef)
            }
            for valueParam in valueParams {
                let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
                let normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: valueParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body,
                    isRawCallbackParameter: true
                )
                callArgExprs.append(normalizedParamExpr)
            }
            let callResult = arena.appendTemporary(type: returnType
            )
            body.append(.call(
                symbol: targetSymbol,
                callee: targetName,
                arguments: callArgExprs,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
            switch sema.types.kind(of: returnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                body.append(.returnValue(callResult))
            }
            body.append(.endBlock)

            let wrapperDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: wrapperParams,
                        returnType: returnType,
                        body: body,
                        isSuspend: functionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(wrapperDecl)
        } else if let targetSymbol {
            callableSymbol = targetSymbol
            callableName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
        } else {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let fallbackFunctionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                    return nil
                }
                return functionType
            }
            let fallbackValueParamTypes = fallbackFunctionType?.params ?? []
            let fallbackReturnType = fallbackFunctionType?.returnType ?? sema.types.anyType

            let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(captureExpr) ?? sema.types.anyType
                )
            }
            let valueParams: [KIRParameter] = fallbackValueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            var body: [KIRInstruction] = [.beginBlock]
            switch sema.types.kind(of: fallbackReturnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                let zero = arena.appendExpr(.intLiteral(0), type: fallbackReturnType)
                body.append(.constValue(result: zero, value: .intLiteral(0)))
                body.append(.returnValue(zero))
            }
            body.append(.endBlock)

            let fallbackDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: captureParams + valueParams,
                        returnType: fallbackReturnType,
                        body: body,
                        isSuspend: fallbackFunctionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(fallbackDecl)
        }

        let callableType = boundType ?? typeForSymbolReference(callableSymbol, sema: sema)
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: captureArguments
        )

        // Collection HOF runtimes expect a raw function pointer plus closure payload.
        // Returning a tagged callable reference here would pass the reflection wrapper
        // object to runtime HOF entry points instead of the generated thunk symbol.
        if needsHOFWrapper {
            return callableExpr
        }

        // REFL-003: Emit KFunction / KProperty type identity tag.
        // The tagging call wraps the callable value with reflection
        // metadata (name, arity, KFunction vs KProperty).  We register
        // the tagged expression with the same callable-value metadata so
        // that downstream callable-value-call lowering resolves the
        // correct target symbol and capture arguments.
        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableExpr,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            driver.ctx.registerCallableValue(
                taggedExpr,
                symbol: callableSymbol,
                callee: callableName,
                captureArguments: captureArguments
            )
            return taggedExpr
        }

        return callableExpr
    }

    // MARK: - REFL-003: Callable reference type identity

    /// Emits a runtime tagging call that annotates a callable reference value
    /// with KFunction or KProperty type identity. Returns a new KIR expression
    /// representing the tagged value.  The caller must use the returned
    /// expression (and register it for callable-value resolution) so that the
    /// tagged value propagates through the program.
    func emitCallableRefTypeTag(
        callableExpr: KIRExprID,
        callableType: TypeID,
        refKind: CallableRefKind,
        memberName: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Compute arity and isSuspend from the function type.
        let arity: Int64
        let isSuspendFlag: Int64
        if case let .functionType(functionType) = sema.types.kind(of: callableType) {
            arity = Int64(functionType.params.count)
            isSuspendFlag = functionType.isSuspend ? 1 : 0
        } else {
            // Property references have arity 0 (no value params, just a getter).
            arity = 0
            isSuspendFlag = 0
        }

        // Emit the name string literal.
        let nameExpr = arena.appendExpr(
            .stringLiteral(memberName),
            type: sema.types.stringType
        )
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(memberName)))

        // KCallable.returnType is represented by the same compact type-name
        // handle used by KClass reflection metadata.
        let returnType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: callableType) {
            functionType.returnType
        } else {
            sema.types.anyType
        }
        let returnTypeName = interner.intern(
            sema.types.displayName(of: returnType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExpr = arena.appendExpr(
            .stringLiteral(returnTypeName),
            type: sema.types.stringType
        )
        instructions.append(.constValue(
            result: returnTypeExpr,
            value: .stringLiteral(returnTypeName)
        ))

        // Emit the arity literal.
        let arityExpr = arena.appendExpr(.intLiteral(arity), type: sema.types.intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(arity)))

        // Choose the tagging callee based on callable reference kind.
        let tagCallee: String = switch refKind {
        case .functionRef:
            "kk_callable_ref_tag_kfunction"
        case .propertyRef:
            "kk_callable_ref_tag_kproperty"
        }

        // For function refs, emit the isSuspend flag after the metadata fields.
        var tagArguments: [KIRExprID] = [callableExpr, nameExpr, returnTypeExpr, arityExpr]
        if refKind == .functionRef {
            let isSuspendExpr = arena.appendExpr(.intLiteral(isSuspendFlag), type: sema.types.intType)
            instructions.append(.constValue(result: isSuspendExpr, value: .intLiteral(isSuspendFlag)))
            tagArguments.append(isSuspendExpr)
        }

        // Emit the tagging call.
        let taggedExpr = arena.appendTemporary(type: callableType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(tagCallee),
            arguments: tagArguments,
            result: taggedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return taggedExpr
    }

    // MARK: - Non-Capturing Lambda Optimization

    /// Lowers a non-capturing lambda with optimized function pointer generation
    private func lowerNonCapturingLambda(
        exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        allowsNonLocalReturn: Bool,
        effectiveParamCount: Int,
        hasExplicitReceiverParam: Bool,
        lambdaParameterTypes: [TypeID],
        lambdaReturnType: TypeID,
        substitutedReturnType: TypeID,
        returnsErasedGeneric: Bool,
        functionType: FunctionType?,
        isSamConversion: Bool,
        boundType: TypeID?,
        effectiveFuncTypeID: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let lambdaSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)

        // Create optimized lambda parameters (no capture parameters needed)
        let lambdaParameters = (0 ..< effectiveParamCount).map { index in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        // Generate optimized lambda body
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.currentLambdaAllowsNonLocalReturn = allowsNonLocalReturn

        var lambdaBody: [KIRInstruction] = [.beginBlock]

        // Set up parameters only (no captures)
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: lambdaParam.symbol)

            // Handle receiver parameter if needed
            if paramIndex == 0, hasExplicitReceiverParam {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: paramExpr)
            }
        }

        // Set up parameter name mapping for `it` parameter
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        // Named parameters follow the explicit receiver parameter, if any.
        let valueParamStart = hasExplicitReceiverParam ? 1 : 0
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        // Lower the body
        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
        let returnedBody = boxErasedReturnValue(
            loweredBody,
            returnType: substitutedReturnType,
            returnsErasedGeneric: returnsErasedGeneric,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &lambdaBody
        )
        lambdaBody.append(.returnValue(returnedBody))
        lambdaBody.append(.endBlock)

        // See the matching comment in lowerLambdaLiteralExpr: the expected/
        // contextual functionType doesn't always match what the body actually
        // does, so trust the lowered body over a non-suspend contextual type.
        let effectiveIsSuspend = (functionType?.isSuspend ?? false)
            || lambdaBodyRequiresSuspend(lambdaBody, arena: arena, interner: interner)
        let hasNonLocalReturn = lambdaBody.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }

        // Create optimized function declaration
        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: lambdaParameters, // No capture parameters
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: effectiveIsSuspend,
                    isInline: true, // Mark as inline for better optimization
                    isInlineOnly: hasNonLocalReturn
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        // Handle SAM conversion if needed
        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceType: interfaceType,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: [], // No captures for non-capturing lambda
               samMethodParamTypes: lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // Create optimized lambda value
        let lambdaValueType = effectiveFuncTypeID
            ?? boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: effectiveIsSuspend,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))

        // Register with no capture arguments for optimization
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: [], // Empty for non-capturing lambda
            hasClosureParam: false
        )

        return lambdaValueExpr
    }
}
