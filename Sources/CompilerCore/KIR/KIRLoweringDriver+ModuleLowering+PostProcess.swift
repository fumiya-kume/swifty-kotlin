
extension KIRLoweringDriver {
    func postProcessTopLevelInitializersAndDelegates(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext,
        arena: KIRArena,
        allTopLevelInitInstructions: KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID]
    ) {
        guard !allTopLevelInitInstructions.isEmpty || !delegateStorageSymbolByPropertySymbol.isEmpty else { return }

        let interner = compilationCtx.interner
        let mainName = interner.intern("main")

        arena.transformFunctions { function in
            var updated = function

            if function.name == mainName, !allTopLevelInitInstructions.isEmpty {
                updated.replaceBody(injectTopLevelInits(
                    body: function.body, inits: allTopLevelInitInstructions
                ))
            }

            if !delegateStorageSymbolByPropertySymbol.isEmpty {
                updated.replaceBody(rewriteDelegateAccesses(
                    body: updated.body, sema: sema,
                    storageMap: delegateStorageSymbolByPropertySymbol, interner: interner
                ))
            }

            return updated
        }
    }

    // MARK: - Top-Level Init Injection

    private func injectTopLevelInits(
        body: [KIRInstruction],
        inits: KIRLoweringEmitContext
    ) -> [KIRInstruction] {
        // The initializers were lowered under their own function scopes, so
        // their labels restart from the same base as `main`'s own body.
        let relocatedInits = KIRLabelRelocation.relocatingLabels(
            of: inits.instructions,
            toAvoidCollisionsWith: body
        )
        var newBody: KIRLoweringEmitContext = []
        if let first = body.first, case .beginBlock = first {
            newBody.append(first)
            newBody.append(contentsOf: relocatedInits)
            newBody.append(contentsOf: body.dropFirst())
        } else {
            newBody.append(contentsOf: relocatedInits)
            newBody.append(contentsOf: body)
        }
        return newBody.instructions
    }

    // MARK: - Delegate Access Rewriting

    /// Rewrites top-level delegated-property access sites (read/write, outside
    /// the property's own module) to call the synthesized `get`/`set`
    /// accessor functions instead of touching `$delegate_x`'s storage global
    /// directly. Every delegate kind (`lazy`/`Delegates.observable/vetoable/
    /// notNull`/custom) shares this path since KSP-491: they all resolve
    /// `getValue`/`setValue` through the same operator convention and get the
    /// same synthesized accessors (`emitDelegateAccessorsIfCustom`).
    private func rewriteDelegateAccesses(
        body: [KIRInstruction],
        sema: SemaModule,
        storageMap: [SymbolID: SymbolID],
        interner: StringInterner
    ) -> [KIRInstruction] {
        var fullStorageMap = storageMap
        for symbol in sema.symbols.allSymbols() where symbol.kind == .property {
            if let storageSymbol = sema.symbols.delegateStorageSymbol(for: symbol.id) {
                fullStorageMap[symbol.id] = storageSymbol
            }
        }
        var propertyByStorageSymbol: [SymbolID: SymbolID] = [:]
        for (propertySymbol, storageSymbol) in fullStorageMap {
            propertyByStorageSymbol[storageSymbol] = propertySymbol
        }
        let getValueName = interner.intern("getValue")
        let setValueName = interner.intern("setValue")

        // Pass 1: collect copy targets to distinguish getter vs setter paths.
        var copyTargetExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .copy(_, toExpr) = instruction { copyTargetExprs.insert(toExpr) }
        }

        // Pass 2: rewrite instructions.
        var targets: [KIRExprID: SymbolID] = [:]
        var result: KIRLoweringEmitContext = []
        result.reserveCapacity(body.count)

        for instruction in body {
            if case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
               let storageSymbol = symbol,
               propertyByStorageSymbol[storageSymbol] != nil,
               callee == getValueName || callee == setValueName
            {
                // Already a well-formed getValue/setValue call emitted by the
                // delegate's own accessor function -- nothing to rewrite.
                result.append(instruction)
                continue
            }

            if case let .loadGlobal(res, sym) = instruction,
               fullStorageMap[sym] != nil
            {
                result.append(
                    .call(
                        symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                        callee: interner.intern("get"),
                        arguments: [],
                        result: res,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                continue
            }

            if case let .constValue(res, value) = instruction,
               case let .symbolRef(sym) = value,
               fullStorageMap[sym] != nil
            {
                if copyTargetExprs.contains(res) {
                    targets[res] = sym
                    // This symbol reference is only the marker pairing the
                    // assignment target with its following copy. The copy is
                    // rewritten to the delegate setter below, so retaining
                    // the marker would let PropertyLowering reinterpret it as
                    // a getter read before the setter (notably breaking an
                    // uninitialized `Delegates.notNull()` property).
                } else {
                    result.append(
                        .call(
                            symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                            callee: interner.intern("get"),
                            arguments: [],
                            result: res,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                }
                continue
            }

            if case let .copy(fromExpr, toExpr) = instruction,
               let propSym = targets.removeValue(forKey: toExpr),
               fullStorageMap[propSym] != nil
            {
                result.append(
                    .call(
                        symbol: SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propSym),
                        callee: interner.intern("set"),
                        arguments: [fromExpr],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                continue
            }

            result.append(instruction)
        }
        return result.instructions
    }
}

extension KIRLoweringDriver {
    /// Creates a lambda function from the delegate body.
    ///
    /// A class-member delegate body (`lazy { }`, `Delegates.observable(...) { }`)
    /// may reference other instance fields by bare name (e.g. `initCount += 1`,
    /// DEBT-KIR-008/BUG-170). The generated function is invoked later through
    /// the delegate's stored function pointer (`LazyImpl`'s `initializer` for
    /// `.lazy`, or the callback captured by the source-backed observable and
    /// vetoable delegate objects). These callbacks cannot simply gain an extra
    /// KIR parameter because the runtime side always invokes them through a
    /// fixed dispatch entry point
    /// (`kk_function_invoke_0` for `.lazy`, `kk_function_invoke_3` for
    /// `.observable`/`.vetoable`) that already distinguishes a raw thunk
    /// pointer from a boxed `Function0`/`Function3` closure value (BUG-151
    /// made the latter dispatch safe for `.observable`/`.vetoable` too, by
    /// unboxing through the same arity-tagged `RuntimeFunctionValueBox` the
    /// general closure-invocation path uses). So a captured receiver is
    /// threaded in by materializing a closure object instead, mirroring
    /// `LambdaLowerer.materializeEscapingCallableValue`'s `(closureRaw) -> T`
    /// adapter pattern.
    func lowerDelegateLambdaBody(
        delegateBody: FunctionBody?,
        delegateBodyParams: [InternedString] = [],
        valueType: TypeID? = nil,
        propertySymbol: SymbolID,
        paramCount: Int,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        // Top-level delegate properties have no enclosing receiver, so this is
        // nil and the capture machinery below is a no-op for them.
        let outerReceiver = ctx.activeImplicitReceiver()

        let scopeSnapshot = ctx.saveScope()
        defer { ctx.restoreScope(scopeSnapshot) }
        ctx.resetScopeForFunction()

        let lambdaSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let lambdaName = interner.intern("kk_delegate_lambda_\(propertySymbol.rawValue)")

        var numberedParams: [KIRParameter] = []
        for i in 0 ..< paramCount {
            let paramSymbol = SyntheticSymbolScheme.delegateLambdaParameterSymbol(
                for: propertySymbol, at: i
            )
            // `(property, oldValue, newValue)`: only the two value parameters
            // carry the property's type; typing them keeps operations on them
            // (comparisons, string templates) from treating the raw value as an
            // untyped object handle.
            let paramType = i == 0 ? sema.types.anyType : (valueType ?? sema.types.anyType)
            numberedParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
        }
        let receiverParam: KIRParameter? = outerReceiver.map { receiver in
            KIRParameter(
                symbol: ctx.allocateSyntheticGeneratedSymbol(),
                type: arena.exprType(receiver.exprID) ?? sema.types.anyType
            )
        }
        let params = (receiverParam.map { [$0] } ?? []) + numberedParams

        var lambdaBody: KIRLoweringEmitContext = [.beginBlock]
        if let receiverParam {
            let receiverExpr = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverParam.type)
            lambdaBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)))
            ctx.setLocalValue(receiverExpr, for: receiverParam.symbol)
            // Bare-name instance-field references inside this body must resolve
            // against the captured receiver, not the enclosing constructor's —
            // this standalone function has no way to see that one.
            ctx.setImplicitReceiver(symbol: receiverParam.symbol, exprID: receiverExpr)
        }
        // Names the callback lambda declared for its parameters
        // (`{ property, old, new -> ... }`) must resolve to the synthetic
        // parameters below while the body is lowered. `resetScopeForFunction`/
        // `restoreScope` above already isolate this from the enclosing scope,
        // so no manual save/restore of individual bindings is needed here.
        let underscore = interner.intern("_")
        for (index, param) in numberedParams.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
            guard index < delegateBodyParams.count else { continue }
            let name = delegateBodyParams[index]
            guard name != underscore else { continue }
            ctx.registerLambdaParam(symbol: param.symbol, forName: name)
        }

        switch delegateBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            for exprID in exprIDs {
                lastValue = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            }
            if let lastValue {
                lambdaBody.append(.returnValue(lastValue))
            } else {
                lambdaBody.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            lambdaBody.append(.returnValue(value))
        case .unit, nil:
            lambdaBody.append(.returnUnit)
        }
        lambdaBody.append(.endBlock)

        let lambdaDecl = arena.appendDecl(.function(KIRFunction(
            symbol: lambdaSymbol, name: lambdaName, params: params,
            returnType: sema.types.anyType, body: lambdaBody,
            isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(lambdaDecl)

        guard let outerReceiver else {
            // KSP-491: `lambdaSymbol` above was previously returned bare (a
            // "raw thunk" `(numberedParams...) -> T` function pointer),
            // relying on it only ever being invoked through
            // kk_function_invoke_0/_3's raw-thunk branch. Passed instead to a
            // real Kotlin closure-typed parameter (`LazyImpl`'s
            // `initializer`, `ObservableProperty`'s callback, ...)
            // and invoked there through ordinary closure-call syntax, the
            // value must be a genuine boxed FunctionN -- but
            // `kk_function_create_N` boxes a `(closureRaw, args..., outThrown)`-
            // shaped pointer, one parameter more than `lambdaSymbol` has, so
            // boxing it directly shifts every argument by one slot at
            // invocation. Wrap it in a trivial closure-shaped adapter (an
            // unused leading parameter, forwarding the rest) first, mirroring
            // `materializeCapturingDelegateLambda` below minus the actual
            // capture load this receiverless case has nothing to load.
            let adapterSymbol = boxableDelegateLambdaAdapter(
                innerLambdaSymbol: lambdaSymbol,
                innerLambdaName: lambdaName,
                numberedParams: numberedParams,
                sema: sema,
                arena: arena,
                interner: interner
            )
            let lambdaRefExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.anyType)
            instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(adapterSymbol)))
            return boxDelegateLambdaAsClosure(
                lambdaRefExpr: lambdaRefExpr,
                paramCount: paramCount,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        return materializeCapturingDelegateLambda(
            innerLambdaSymbol: lambdaSymbol,
            innerLambdaName: lambdaName,
            receiverExpr: outerReceiver.exprID,
            numberedParams: numberedParams,
            returnType: sema.types.anyType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Wraps `innerLambdaSymbol` (a plain `(numberedParams...) -> T` function,
    /// no closure parameter) in a trivial adapter of shape
    /// `(closureRaw, numberedParams...) -> T` that ignores `closureRaw` and
    /// forwards the rest -- the shape `kk_function_create_N`'s boxed value
    /// expects its `fnPtr` to already have (see `boxDelegateLambdaAsClosure`).
    private func boxableDelegateLambdaAdapter(
        innerLambdaSymbol: SymbolID,
        innerLambdaName: InternedString,
        numberedParams: [KIRParameter],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> SymbolID {
        let adapterSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_delegate_lambda_noop_adapter_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: sema.types.intType)
        let adapterNumberedParams = numberedParams.map {
            KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: $0.type)
        }
        let adapterParams = [closureParam] + adapterNumberedParams

        var body: KIRLoweringEmitContext = [.beginBlock]
        var forwardedArgs: [KIRExprID] = []
        for param in adapterNumberedParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            forwardedArgs.append(paramExpr)
        }
        let callResult = arena.appendTemporary(type: sema.types.anyType)
        body.append(.call(
            symbol: innerLambdaSymbol,
            callee: innerLambdaName,
            arguments: forwardedArgs,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(callResult))
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(.function(KIRFunction(
            symbol: adapterSymbol, name: adapterName, params: adapterParams,
            returnType: sema.types.anyType, body: body, isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(adapterDecl)
        return adapterSymbol
    }

    /// Boxes a raw delegate-lambda thunk reference (no outer receiver to
    /// capture) into a genuine `FunctionN` closure value via
    /// `kk_function_create_N` with an empty (`0`) closure environment, so
    /// ordinary Kotlin closure-call syntax (`onChange(a, b, c)`) can invoke
    /// it -- mirroring the tail of `materializeCapturingDelegateLambda`
    /// below, minus the capture-loading adapter this receiverless case
    /// doesn't need.
    private func boxDelegateLambdaAsClosure(
        lambdaRefExpr: KIRExprID,
        paramCount: Int,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let zeroClosureExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroClosureExpr, value: .intLiteral(0)))
        let createCallee: InternedString = switch paramCount {
        case 0: interner.intern("kk_function_create_0")
        case 1: interner.intern("kk_function_create_1")
        case 2: interner.intern("kk_function_create_2")
        case 3: interner.intern("kk_function_create_3")
        case 4: interner.intern("kk_function_create_4")
        default: preconditionFailure("Unsupported delegate callback arity: \(paramCount)")
        }
        let materializedExpr = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [lambdaRefExpr, zeroClosureExpr],
            result: materializedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return materializedExpr
    }

    /// Wraps `innerLambdaSymbol` (a `(receiver, [property, old, new]) -> T`
    /// function) into a boxed `Function0`/`Function3` closure value carrying
    /// `receiverExpr` as captured state, so it can be invoked through
    /// `kk_function_invoke_0`'s (arity 0, `.lazy`) or `kk_function_invoke_3`'s
    /// (arity 3, `.observable`/`.vetoable`) boxed-closure path with only the
    /// numbered arguments (if any) at the call site — the receiver arrives via
    /// the closure object, not as a visible argument. See
    /// `lowerDelegateLambdaBody` for why this indirection (rather than a
    /// plain extra KIR parameter on the inner lambda) is needed: the runtime
    /// dispatch entry points invoke a fixed, arity-tagged function-pointer
    /// shape that has no room for one.
    private func materializeCapturingDelegateLambda(
        innerLambdaSymbol: SymbolID,
        innerLambdaName: InternedString,
        receiverExpr: KIRExprID,
        numberedParams: [KIRParameter],
        returnType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let adapterSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_delegate_lambda_adapter_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: sema.types.intType)
        let captureOffset = Int64(2)
        // The adapter needs its own parameter symbols for the numbered
        // (property/old/new) arguments — KIR functions can't share parameter
        // symbols with the inner lambda — but forwards the same values through
        // unchanged, so the types match.
        let adapterNumberedParams = numberedParams.map {
            KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: $0.type)
        }
        let adapterParams = [closureParam] + adapterNumberedParams

        var body: KIRLoweringEmitContext = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let receiverType = arena.exprType(receiverExpr) ?? sema.types.anyType
        let loadOffsetExpr = arena.appendExpr(.intLiteral(captureOffset), type: sema.types.intType)
        body.append(.constValue(result: loadOffsetExpr, value: .intLiteral(captureOffset)))
        let loadedReceiver = arena.appendTemporary(type: receiverType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [closureExpr, loadOffsetExpr],
            result: loadedReceiver,
            canThrow: false,
            thrownResult: nil
        ))

        var forwardedArgs: [KIRExprID] = [loadedReceiver]
        for param in adapterNumberedParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            forwardedArgs.append(paramExpr)
        }

        let callResult = arena.appendTemporary(type: returnType)
        body.append(.call(
            symbol: innerLambdaSymbol,
            callee: innerLambdaName,
            arguments: forwardedArgs,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(callResult))
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(.function(KIRFunction(
            symbol: adapterSymbol, name: adapterName, params: adapterParams,
            returnType: returnType, body: body, isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(adapterDecl)

        let slotCountExpr = arena.appendExpr(.intLiteral(3), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(3)))
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
        let storeOffsetExpr = arena.appendExpr(.intLiteral(captureOffset), type: sema.types.intType)
        instructions.append(.constValue(result: storeOffsetExpr, value: .intLiteral(captureOffset)))
        let setResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [closureObj, storeOffsetExpr, receiverExpr],
            result: setResult,
            canThrow: true,
            thrownResult: nil
        ))

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let materializedExpr = arena.appendTemporary(type: sema.types.anyType)
        let createCallee: InternedString = switch adapterNumberedParams.count {
        case 0: interner.intern("kk_function_create_0")
        case 1: interner.intern("kk_function_create_1")
        case 2: interner.intern("kk_function_create_2")
        case 3: interner.intern("kk_function_create_3")
        case 4: interner.intern("kk_function_create_4")
        default: preconditionFailure("Unsupported delegate callback arity: \(adapterNumberedParams.count)")
        }
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [adapterExpr, closureObj],
            result: materializedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return materializedExpr
    }

}
