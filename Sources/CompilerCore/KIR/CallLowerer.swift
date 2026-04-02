import Foundation

final class CallLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    /// Maps a numeric receiver type (nullable or non-nullable) to its runtime
    /// symbol prefix (e.g. "kk_int", "kk_long", "kk_double", "kk_float"), or
    /// nil if the receiver is not one of the four coercion-eligible numeric
    /// types. Nullable receivers are normalized to non-nullable for dispatch.
    /// Shared by both normal and safe-call member lowering paths.
    func numericCoercionRuntimePrefix(
        receiverType: TypeID,
        sema: SemaModule
    ) -> String? {
        let nonNull = sema.types.makeNonNullable(receiverType)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        if nonNull == intType { return "kk_int" }
        if nonNull == longType { return "kk_long" }
        if nonNull == doubleType { return "kk_double" }
        if nonNull == floatType { return "kk_float" }
        return nil
    }

    /// Shared helper for coerceIn(range) lowering (STDLIB-525, STDLIB-CONV-006).
    /// Decomposes a range argument into first/last bounds and emits a call to
    /// kk_{int,long,double,float}_coerceIn. Used by both normal and safe-call member lowering
    /// paths to avoid duplication. Supports all numeric types: Int, Long, Double, Float.
    func emitCoerceInRange(
        prefix: String,
        receiverType: TypeID,
        loweredReceiverID: KIRExprID,
        loweredRangeArgID: KIRExprID,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        // Use non-nullable receiver type for temporaries so Long receivers get
        // Long-typed bounds instead of always Int.
        let boundType = sema.types.makeNonNullable(receiverType)
        let firstExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        let lastExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_first"),
            arguments: [loweredRangeArgID],
            result: firstExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_last"),
            arguments: [loweredRangeArgID],
            result: lastExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(prefix + "_coerceIn"),
            arguments: [loweredReceiverID, firstExpr, lastExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }

    // swiftlint:disable:next cyclomatic_complexity
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
        // SAM constructor calls: `Transformer { ... }` — the single lambda
        // argument is already marked as a SAM conversion.  Lower the lambda
        // directly; the SAM wrapper is produced by LambdaLowerer.
        if args.count == 1,
           sema.bindings.isSamConversion(args[0].expr)
        {
            return driver.lowerExpr(
                args[0].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

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

        if let loweredRepeat = lowerRepeatCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredRepeat
        }

        if let loweredMeasureTime = lowerMeasureTimeMillisCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTime
        }

        if let loweredMeasureNano = lowerMeasureNanoTimeCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureNano
        }

        if let loweredMeasureTimeDuration = lowerMeasureTimeCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTimeDuration
        }

        if let loweredMeasureTimedValue = lowerMeasureTimedValueCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTimedValue
        }

        if let loweredArrayConstructor = lowerArrayConstructorCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredArrayConstructor
        }

        if let loweredEnumValues = lowerEnumValuesCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumValues
        }

        if let loweredEnumEntries = lowerEnumEntriesCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumEntries
        }

        if let loweredEnumValueOf = lowerEnumValueOfCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumValueOf
        }

        // REFL-005: typeOf<T>() — reified inline function returning KType
        if let loweredTypeOf = lowerTypeOfCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredTypeOf
        }

        if let loweredComparison = lowerComparisonSpecialCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredComparison
        }

        // --- Scope function: with(receiver, block) (STDLIB-004) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeWith,
           args.count == 2
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let loweredReceiverID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // Set up implicit receiver for the lambda body.
            let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
            let receiverType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverSymExpr))

            let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
            let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
            driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)

            let loweredLambdaID = driver.lowerExpr(
                args[1].expr,
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
                // Non-lambda-literal argument; restore state and
                // fall through to normal call lowering.
                driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
            }
            return result
        }

        // --- Scope function: top-level run(block) (STDLIB-401) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeTopLevelRun,
           args.count == 1
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
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
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Callable reference or other non-lambda callable: invoke it
                // so that `run(::foo)` calls foo() rather than returning the
                // reference itself.  Use the already-lowered ID to avoid
                // double-lowering the lambda argument expression.
                let invokeName = interner.intern("invoke")
                instructions.append(.call(
                    symbol: nil,
                    callee: invokeName,
                    arguments: [loweredLambdaID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result
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
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let loweredCallable = driver.ctx.callableValueInfo(for: loweredCalleeExprID)
            ?? chosen.flatMap { symbol in
                driver.ctx.localValue(for: symbol).flatMap { driver.ctx.callableValueInfo(for: $0) }
            }
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let sourceCalleeName: InternedString = if let callee = ast.arena.expr(calleeExpr), case let .nameRef(name, _) = callee {
            name
        } else if let loweredCallable {
            loweredCallable.callee
        } else {
            interner.intern("<unknown>")
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
        let knownNames = KnownCompilerNames(interner: interner)
        if sourceCalleeName == interner.intern("generateSequence"),
           loweredArgIDs.count == 2,
           let seedFunctionType = sema.bindings.exprTypes[args[0].expr],
           case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
           functionType.params.isEmpty,
           let seedCallableInfo = driver.ctx.callableValueInfo(for: loweredArgIDs[0])
        {
            let seedResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.makeNonNullable(functionType.returnType)
            )
            instructions.append(.call(
                symbol: seedCallableInfo.symbol,
                callee: seedCallableInfo.callee,
                arguments: seedCallableInfo.captureArguments,
                result: seedResult,
                canThrow: false,
                thrownResult: nil
            ))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: chosen,
                callee: interner.intern("kk_sequence_generate"),
                arguments: [seedResult, loweredArgIDs[1]],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if sema.bindings.builderDSLKind(for: exprID) == .buildString {
            let builderRuntimeCallee: String? = switch (interner.resolve(sourceCalleeName), loweredArgIDs.count) {
            case ("append", 1):
                "kk_string_builder_append"
            case ("appendLine", 0):
                "kk_string_builder_append_line_noarg"
            case ("appendLine", 1):
                "kk_string_builder_append_line"
            case ("appendRange", 3):
                "kk_string_builder_append_range"
            default:
                nil
            }
            if let builderRuntimeCallee {
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType ?? sema.types.anyType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(builderRuntimeCallee),
                    arguments: loweredArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        if let loweredToList = tryLowerCollectionToListCall(
            sourceCalleeName: sourceCalleeName,
            args: args,
            loweredArgIDs: loweredArgIDs,
            boundType: boundType,
            sema: sema,
            arena: arena,
            interner: interner,
            knownNames: knownNames,
            instructions: &instructions
        ) {
            return loweredToList
        }
        if args.count == 1,
           let loweredNumericConversion = lowerTopLevelNumericConversionCall(
               sourceCalleeName: sourceCalleeName,
               argumentExpr: args[0].expr,
               loweredArgumentID: loweredArgIDs[0],
               boundType: boundType ?? sema.types.anyType,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return loweredNumericConversion
        }
        if chosen == nil,
           loweredCallable == nil,
           let implicitStringBuilderCall = implicitReceiverStringBuilderRuntimeCallee(
               sourceCalleeName: sourceCalleeName,
               loweredArguments: loweredArgIDs,
               sema: sema,
               arena: arena,
               interner: interner
           )
        {
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: implicitStringBuilderCall.callee,
                arguments: [implicitStringBuilderCall.receiver] + loweredArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let callNormalized: NormalizedCallResult = if callBinding != nil {
            driver.callSupportLowerer.normalizedCallArguments(
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
            NormalizedCallResult(
                arguments: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableValueCallBinding,
                    sema: sema
                ),
                defaultMask: 0
            )
        }
        var finalArgIDs = callNormalized.arguments
        // Compiler-generated lambdas/local functions use the compiler ABI
        // (including the hidden thrown channel), so route them through their
        // lowered symbol directly instead of Swift closure helpers.
        let callableInvokeCallee: InternedString? = if loweredCallable == nil {
            runtimeCallableInvokeCallee(
                callableValueCallBinding: callableValueCallBinding,
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        if callableInvokeCallee != nil {
            finalArgIDs.insert(loweredCalleeExprID, at: 0)
        }
        if callableInvokeCallee == nil, let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
                  sema.symbols.symbol(chosen)?.kind == .constructor,
                  sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
        {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_array_new(slotCount) and prepend it to the argument list.
            // Derive slot count from NominalLayout.instanceSizeWords of the owning class.
            let allocType = boundType ?? sema.types.anyType
            let intType = sema.types.make(.primitive(.int, .nonNull))
            var slotCount: Int64 = 1
            var ownerNominalSymbol: SymbolID?
            if let parentClassID = sema.symbols.parentSymbol(for: chosen),
               let layout = sema.symbols.nominalLayout(for: parentClassID)
            {
                ownerNominalSymbol = parentClassID
                slotCount = Int64(max(layout.instanceSizeWords, 1))
            }
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
            instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
            let classIDValue: Int64 = if let ownerNominalSymbol {
                RuntimeTypeCheckToken.stableNominalTypeID(symbol: ownerNominalSymbol, sema: sema, interner: interner)
            } else {
                0
            }
            let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
            instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            if let ownerNominalSymbol {
                let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: ownerNominalSymbol,
                    sema: sema,
                    interner: interner
                )
                let childExpr = arena.appendExpr(.intLiteral(childTypeID), type: intType)
                instructions.append(.constValue(result: childExpr, value: .intLiteral(childTypeID)))
                for superSymbol in sema.symbols.directSupertypes(for: ownerNominalSymbol) {
                    let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                        symbol: superSymbol,
                        sema: sema,
                        interner: interner
                    )
                    let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
                    instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
                    let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                    let superKind = sema.symbols.symbol(superSymbol)?.kind
                    let registerCallee: InternedString = if superKind == .interface {
                        interner.intern("kk_type_register_iface")
                    } else {
                        interner.intern("kk_type_register_super")
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: registerCallee,
                        arguments: [childExpr, parentExpr],
                        result: registerResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                if let objectLayout = sema.symbols.nominalLayout(for: ownerNominalSymbol) {
                    for interfaceSymbol in sema.symbols.directSupertypes(for: ownerNominalSymbol) {
                        guard sema.symbols.symbol(interfaceSymbol)?.kind == .interface,
                              let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol)
                        else {
                            continue
                        }
                        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                        for (methodSymbol, methodSlotInt) in interfaceLayout.vtableSlots {
                            let methodSlot = Int64(methodSlotInt)
                            let implementationSymbol: SymbolID = {
                                guard let methodSym = sema.symbols.symbol(methodSymbol),
                                      let ownerSym = sema.symbols.symbol(ownerNominalSymbol)
                                else {
                                    return methodSymbol
                                }
                                let overrideFQName = ownerSym.fqName + [methodSym.name]
                                for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
                                    guard let candidateSym = sema.symbols.symbol(candidate),
                                          candidateSym.kind == .function,
                                          sema.symbols.parentSymbol(for: candidate) == ownerNominalSymbol
                                    else {
                                        continue
                                    }
                                    return candidate
                                }
                                return methodSymbol
                            }()

                            let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                            instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                            let methodFnExpr = arena.appendExpr(.symbolRef(implementationSymbol), type: intType)
                            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementationSymbol)))
                            let registerMethodResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                            instructions.append(.call(
                                symbol: nil,
                                callee: interner.intern("kk_object_register_itable_method"),
                                arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                                result: registerMethodResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                    }
                }
                // REFL-005: Register KClass metadata for this nominal type.
                emitKClassMetadataRegistration(
                    objectSymbol: ownerNominalSymbol,
                    typeID: childTypeID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            finalArgIDs.insert(allocatedObj, at: 0)
        } else if let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen),
                  signature.receiverType != nil,
                  let implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
        {
            finalArgIDs.insert(implicitReceiver, at: 0)
        }
        if loweredCallable == nil, let chosen {
            finalArgIDs = appendClosureArgumentsIfNeeded(
                finalArgIDs,
                originalArgs: args,
                chosenCallee: chosen,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
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
        if loweredCallable == nil {
            let isSyntheticCoroutineLauncher: Bool = if let chosen,
                                                        let chosenInfo = sema.symbols.symbol(chosen)
            {
                chosenInfo.fqName == knownNames.kotlinxCoroutinesRunBlockingFQName
                    || chosenInfo.fqName == knownNames.kotlinxCoroutinesLaunchFQName
                    || chosenInfo.fqName == knownNames.kotlinxCoroutinesAsyncFQName
            } else {
                true
            }
            if isSyntheticCoroutineLauncher,
               sourceCalleeName == knownNames.runBlocking
               || sourceCalleeName == knownNames.launch
               || sourceCalleeName == knownNames.async,
               let firstArg = finalArgIDs.first,
               let callableInfo = driver.ctx.callableValueInfo(for: firstArg),
               !callableInfo.captureArguments.isEmpty
            {
                finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 1)
            }
        }
        if sourceCalleeName == knownNames.withContext,
           finalArgIDs.count >= 2,
           let callableInfo = driver.ctx.callableValueInfo(for: finalArgIDs[1]),
           !callableInfo.captureArguments.isEmpty
        {
            finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        if callNormalized.defaultMask != 0,
           let chosen,
           sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
        {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
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
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let loweredCalleeName: InternedString = if let callableInvokeCallee {
                callableInvokeCallee
            } else if let chosen,
                                                       let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                       !externalLinkName.isEmpty
            {
                interner.intern(externalLinkName)
            } else if let loweredCallable {
                loweredCallable.callee
            } else if chosen == nil {
                driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    argumentTypes: finalArgIDs.map { arena.exprType($0) ?? sema.types.anyType },
                    interner: interner,
                    types: sema.types,
                    knownNames: knownNames
                ) ?? sourceCalleeName
            } else {
                sourceCalleeName
            }
            if loweredCalleeName == interner.intern("kk_channel_create"), finalArgIDs.isEmpty {
                let capacityExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: capacityExpr, value: .intLiteral(0)))
                finalArgIDs.append(capacityExpr)
            }
            let callCanThrow = needsThrownChannel(calleeName: loweredCalleeName, interner: interner)
            let thrownResult = callCanThrow
                ? arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
                )
                : nil
            // When calling a callable value (function-type local/parameter),
            // use its symbol so InlineLoweringPass can match it against lambda
            // parameter symbols and expand the lambda body in place.
            let callSymbol: SymbolID? = chosen ?? loweredCallable?.symbol ?? {
                if let binding = callableValueCallBinding,
                   case let .localValue(sym) = binding.target
                {
                    return sym
                }
                return nil
            }()
            instructions.append(.call(
                symbol: callSymbol,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: callCanThrow,
                thrownResult: thrownResult
            ))
            if let thrownResult,
               shouldRethrowThrownChannelResult(calleeName: loweredCalleeName, interner: interner)
            {
                let continueLabel = driver.ctx.makeLoopLabel()
                let rethrowLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
            }
        }
        return result
    }

    private func runtimeCallableInvokeCallee(
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let callableValueCallBinding else {
            return nil
        }
        let nonNullFunctionType = sema.types.makeNonNullable(callableValueCallBinding.functionType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullFunctionType) else {
            return nil
        }

        if functionType.isSuspend {
            switch functionType.params.count {
            case 0:
                return interner.intern("kk_suspend_function_invoke_0")
            case 1:
                return interner.intern("kk_suspend_function_invoke")
            default:
                return nil
            }
        }

        switch functionType.params.count {
        case 0:
            return interner.intern("kk_function_invoke_0")
        case 1:
            return interner.intern("kk_function_invoke")
        case 2:
            return interner.intern("kk_function_invoke_2")
        case 3:
            return interner.intern("kk_function_invoke_3")
        default:
            return nil
        }
    }

    private func implicitReceiverStringBuilderRuntimeCallee(
        sourceCalleeName: InternedString,
        loweredArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> (receiver: KIRExprID, callee: InternedString)? {
        guard let implicitReceiver = driver.ctx.activeImplicitReceiverExprID(),
              let receiverType = arena.exprType(implicitReceiver),
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        guard knownNames.isStringBuilderSymbol(symbol) else {
            return nil
        }

        let callee: String? = switch (interner.resolve(sourceCalleeName), loweredArguments.count) {
        case ("append", 1):
            "kk_string_builder_append_obj"
        case ("appendLine", 0):
            "kk_string_builder_append_line_noarg_obj"
        case ("appendLine", 1):
            "kk_string_builder_append_line_obj"
        case ("appendRange", 3):
            "kk_string_builder_appendRange_obj"
        case ("toString", 0):
            "kk_string_builder_toString"
        case ("clear", 0):
            "kk_string_builder_clear"
        case ("reverse", 0):
            "kk_string_builder_reverse"
        case ("length", 0):
            "kk_string_builder_length_prop"
        case ("deleteCharAt", 1):
            "kk_string_builder_deleteCharAt"
        case ("insert", 2):
            "kk_string_builder_insert_obj"
        case ("delete", 2):
            "kk_string_builder_delete_obj"
        default:
            nil
        }

        guard let callee else {
            return nil
        }
        return (implicitReceiver, interner.intern(callee))
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    private func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return name == "kk_runCatching" || name == "kk_synchronized"
    }

    private func shouldRethrowThrownChannelResult(calleeName: InternedString, interner: StringInterner) -> Bool {
        interner.resolve(calleeName) == "kk_synchronized"
    }

    private func tryLowerCollectionToListCall(
        sourceCalleeName: InternedString,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        knownNames: KnownCompilerNames,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sourceCalleeName == interner.intern("toList"),
              args.count == 1,
              sema.bindings.isCollectionExpr(args[0].expr)
        else {
            return nil
        }

        let argumentType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
        let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
        let runtimeCallee: InternedString? = if case let .classType(classType) = sema.types.kind(of: nonNullArgumentType),
                                                let symbol = sema.symbols.symbol(classType.classSymbol)
        {
            switch symbol.name {
            case knownNames.list, knownNames.mutableList:
                nil
            case interner.intern("Range"), interner.intern("IntRange"):
                interner.intern("kk_range_toList")
            case interner.intern("LongRange"):
                interner.intern("kk_long_range_toList")
            case interner.intern("ULongRange"):
                interner.intern("kk_ulong_range_toList")
            case interner.intern("CharRange"):
                interner.intern("kk_char_range_toList")
            case knownNames.string:
                interner.intern("kk_string_toList")
            default:
                interner.intern("kk_sequence_to_list")
            }
        } else {
            interner.intern("kk_sequence_to_list")
        }
        guard let runtimeCallee else {
            return loweredArgIDs[0]
        }

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: loweredArgIDs,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    private func appendClosureArgumentsIfNeeded(
        _ loweredArguments: [KIRExprID],
        originalArgs: [CallArgument],
        chosenCallee: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              loweredArguments.count == originalArgs.count
        else {
            return loweredArguments
        }

        let legacyNames: Set = ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy", "kk_sequence_generate"]
        if legacyNames.contains(externalLinkName), loweredArguments.count == 2 {
            var seedArgument = loweredArguments[0]
            if externalLinkName == "kk_sequence_generate",
               let seedCallableInfo = driver.ctx.callableValueInfo(for: loweredArguments[0]),
               let seedFunctionType = sema.bindings.exprTypes[originalArgs[0].expr],
               case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
               functionType.params.isEmpty
            {
                let seedResult = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.makeNonNullable(functionType.returnType)
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

            var finalArgs = [seedArgument, loweredArguments[1]]
            if sema.bindings.isCollectionHOFLambdaExpr(originalArgs[1].expr),
               let callableInfo = driver.ctx.callableValueInfo(for: loweredArguments[1]),
               let closureRaw = callableInfo.captureArguments.first
            {
                finalArgs.append(closureRaw)
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr)
            }
            return finalArgs
        }

        // STDLIB-590: runCatching { block } — expand lambda arg to (fnPtr, closureRaw)
        if externalLinkName == "kk_runCatching", loweredArguments.count == 1 {
            var finalArgs: [KIRExprID] = []
            var lambdaID = loweredArguments[0]
            var resolvedCallableInfo = driver.ctx.callableValueInfo(for: lambdaID)
            if let callableInfo = resolvedCallableInfo,
               !callableInfo.hasClosureParam,
               let adaptedInfo = makeClosureThunkCallableAdapter(
                   callableInfo: callableInfo,
                   loweredArgID: lambdaID,
                   argExprID: originalArgs[0].expr,
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
                lambdaID = adaptedExpr
                resolvedCallableInfo = adaptedInfo
            }
            // Runtime expects a raw function pointer, not a boxed function value.
            if let callableInfo = resolvedCallableInfo {
                let fnPtrExpr = arena.appendExpr(.symbolRef(callableInfo.symbol), type: sema.types.intType)
                instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
                finalArgs.append(fnPtrExpr)
            } else {
                finalArgs.append(lambdaID)
            }
            if let callableInfo = resolvedCallableInfo,
               let closureRaw = callableInfo.captureArguments.first
            {
                finalArgs.append(closureRaw) // closureRaw
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr) // closureRaw = 0 (no captures)
            }
            return finalArgs
        }

        // STDLIB-325: synchronized(lock) { block } — expand block lambda to
        // (lock, fnPtr, closureRaw) while preserving the runtime outThrown slot.
        if externalLinkName == "kk_synchronized", loweredArguments.count == 2 {
            var finalArgs: [KIRExprID] = [loweredArguments[0]]
            var lambdaID = loweredArguments[1]
            var resolvedCallableInfo = driver.ctx.callableValueInfo(for: lambdaID)
            if let callableInfo = resolvedCallableInfo,
               !callableInfo.hasClosureParam,
               let adaptedInfo = makeClosureThunkCallableAdapter(
                   callableInfo: callableInfo,
                   loweredArgID: lambdaID,
                   argExprID: originalArgs[1].expr,
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
                lambdaID = adaptedExpr
                resolvedCallableInfo = adaptedInfo
            }
            if let callableInfo = resolvedCallableInfo {
                let fnPtrExpr = arena.appendExpr(.symbolRef(callableInfo.symbol), type: sema.types.intType)
                instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
                finalArgs.append(fnPtrExpr)
            } else {
                finalArgs.append(lambdaID)
            }
            if let callableInfo = resolvedCallableInfo,
               let closureRaw = callableInfo.captureArguments.first
            {
                finalArgs.append(closureRaw) // closureRaw
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr) // closureRaw = 0 (no captures)
            }
            return finalArgs
        }

        // compareValuesBy: expand selector lambda args to (fnPtr, closureRaw) pairs.
        // kk_compareValuesBy1(a, b, selector) → (a, b, selectorFn, selectorClosureRaw)
        // kk_compareValuesBy(a, b, sel1, sel2) → (a, b, sel1Fn, sel1Closure, sel2Fn, sel2Closure)
        // kk_compareValuesBy3(a, b, sel1, sel2, sel3) → (a, b, sel1Fn, sel1Closure, sel2Fn, sel2Closure, sel3Fn, sel3Closure)
        let compareValuesbyNames: Set = ["kk_compareValuesBy1", "kk_compareValuesBy", "kk_compareValuesBy3"]
        if compareValuesbyNames.contains(externalLinkName), loweredArguments.count >= 3 {
            // First 2 arguments (a, b) pass through unchanged
            var finalArgs = [loweredArguments[0], loweredArguments[1]]
            // Remaining arguments are selector lambdas that need expansion
            for i in 2..<loweredArguments.count {
                let lambdaID = loweredArguments[i]
                var loweredSelectorID = lambdaID
                var selectorCallableInfo = driver.ctx.callableValueInfo(for: lambdaID)
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
                        argExprID: originalArgs[i].expr,
                        sema: sema,
                        arena: arena,
                        interner: interner
                    )
                {
                    let adaptedExpr = arena.appendExpr(.symbolRef(adaptedInfo.symbol), type: arena.exprType(loweredSelectorID) ?? sema.types.anyType)
                    instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
                    loweredSelectorID = adaptedExpr
                    selectorCallableInfo = adaptedInfo
                }
                finalArgs.append(loweredSelectorID) // fnPtr
                if let callableInfo = selectorCallableInfo,
                   let closureRaw = callableInfo.captureArguments.first
                {
                    finalArgs.append(closureRaw) // closureRaw
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    finalArgs.append(zeroExpr) // closureRaw = 0 (no captures)
                }
            }
            return finalArgs
        }

        return loweredArguments
    }

    private func makeCollectionHOFCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType) else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_compare_values_hof_adapter_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = functionType.params.enumerated().map { index, type in
            KIRParameter(
                symbol: SymbolID(rawValue: Int32(clamping: -710_000 - Int64(argExprID.rawValue) * 16 - Int64(index))),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let arrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: captureType)
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

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }

        let callResult = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: functionType.returnType)
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))

        switch sema.types.kind(of: functionType.returnType) {
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
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
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

    private func makeClosureThunkCallableAdapter(
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

        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let arrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)),
                    type: captureType
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

        let lambdaCanThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        let callResult = arena.appendExpr(
            .temporary(Int32(clamping: arena.expressions.count)),
            type: functionType.returnType
        )
        let thrownResult = lambdaCanThrow
            ? arena.appendExpr(
                .temporary(Int32(clamping: arena.expressions.count)),
                type: sema.types.nullableAnyType
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
                    params: [closureParam],
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let adapterCaptureArguments: [KIRExprID]
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
            let closureObj = arena.appendExpr(
                .temporary(Int32(clamping: arena.expressions.count)),
                type: sema.types.intType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: closureObj,
                canThrow: false,
                thrownResult: nil
            ))
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let setResult = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)),
                    type: sema.types.anyType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [closureObj, offsetExpr, captureExpr],
                    result: setResult,
                    canThrow: true,
                    thrownResult: nil
                ))
            }
            adapterCaptureArguments = [closureObj]
        } else {
            adapterCaptureArguments = callableInfo.captureArguments
        }

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: adapterCaptureArguments,
            hasClosureParam: true
        )
    }

    private func callableRequiresThrownChannel(_ lambdaSymbol: SymbolID, arena: KIRArena) -> Bool {
        guard let function = arena.function(for: lambdaSymbol) else {
            return false
        }
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, _, _, canThrow, _, _, _),
                 let .virtualCall(_, _, _, _, _, canThrow, _, _):
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

    func appendReifiedTypeTokens(
        chosenCallee: SymbolID?,
        callBinding: CallBinding?,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let callBinding,
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              !signature.reifiedTypeParameterIndices.isEmpty
        else {
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        for index in signature.reifiedTypeParameterIndices.sorted() {
            let concreteType = index < callBinding.substitutedTypeArguments.count
                ? callBinding.substitutedTypeArguments[index]
                : sema.types.anyType
            let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(
                .intLiteral(encodedToken),
                type: intType
            )
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            arguments.append(tokenExpr)
        }
    }

    func appendDefaultMaskArgument(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskExpr = arena.appendExpr(.intLiteral(Int64(defaultMask)), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(defaultMask))))
        arguments.append(maskExpr)
    }

    func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case let .functionType(functionType) = sema.types.kind(of: callableValueCallBinding.functionType)
        else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty
        else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid
            else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }

    func recoverMemberCallBinding(
        exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        argumentExprs: [ExprID],
        sema: SemaModule
    ) -> CallBinding? {
        let existingBinding = sema.bindings.callBindings[exprID]
        if let existing = existingBinding,
           existing.chosenCallee != .invalid,
           sema.symbols.symbol(existing.chosenCallee) != nil
        {
            return existing
        }
        if case let .symbol(symbol)? = sema.bindings.callableTarget(for: exprID),
           symbol != .invalid,
           let signature = sema.symbols.functionSignature(for: symbol),
           signature.receiverType != nil
        {
            let parameterMapping = normalizedParameterMapping(
                existingBinding?.parameterMapping,
                argumentCount: argumentExprs.count
            )
            return CallBinding(
                chosenCallee: symbol,
                substitutedTypeArguments: [],
                parameterMapping: parameterMapping
            )
        }

        guard let receiverType = sema.bindings.exprTypes[receiverExpr] else {
            return nil
        }
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType) else {
            return nil
        }
        var ownerQueue: [SymbolID] = [classType.classSymbol]
        var visitedOwners: Set<SymbolID> = []
        var candidates: [SymbolID] = []
        while let owner = ownerQueue.first {
            ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner
                else {
                    continue
                }
                candidates.append(candidate)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        candidates.sort(by: { $0.rawValue < $1.rawValue })
        guard !candidates.isEmpty else {
            return nil
        }

        let argumentTypes = argumentExprs.map { exprID in
            sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        }

        let matched = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == argumentTypes.count
            else {
                return false
            }
            return zip(argumentTypes, signature.parameterTypes).allSatisfy { argumentType, parameterType in
                sema.types.isSubtype(argumentType, parameterType)
            }
        }

        guard let chosen = matched else {
            return nil
        }

        let parameterMapping = normalizedParameterMapping(
            existingBinding?.parameterMapping,
            argumentCount: argumentExprs.count
        )
        return CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [],
            parameterMapping: parameterMapping
        )
    }

    private func normalizedParameterMapping(
        _ parameterMapping: [Int: Int]?,
        argumentCount: Int
    ) -> [Int: Int] {
        if let parameterMapping, !parameterMapping.isEmpty {
            return parameterMapping
        }
        var positionalMapping: [Int: Int] = [:]
        for index in 0 ..< argumentCount {
            positionalMapping[index] = index
        }
        return positionalMapping
    }

    private func lowerTopLevelNumericConversionCall(
        sourceCalleeName: InternedString,
        argumentExpr: ExprID,
        loweredArgumentID: KIRExprID,
        boundType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[argumentExpr] ?? sema.types.anyType)
        let calleeStr = interner.resolve(sourceCalleeName)

        let runtimeCallee: InternedString? = switch (calleeStr, receiverType, boundType) {
        case ("toInt", sema.types.uintType, sema.types.intType): interner.intern("kk_uint_to_int")
        case ("toInt", sema.types.ulongType, sema.types.intType): interner.intern("kk_ulong_to_int")
        case ("toInt", sema.types.ubyteType, sema.types.intType): interner.intern("kk_ubyte_to_int")
        case ("toInt", sema.types.ushortType, sema.types.intType): interner.intern("kk_ushort_to_int")
        case ("toInt", sema.types.doubleType, sema.types.intType): interner.intern("kk_double_to_int")
        case ("toInt", sema.types.floatType, sema.types.intType): interner.intern("kk_float_to_int")
        case ("toInt", sema.types.charType, sema.types.intType): interner.intern("kk_char_to_int")
        case ("toInt", sema.types.intType, sema.types.intType), ("toInt", sema.types.longType, sema.types.intType): nil
        case ("toLong", sema.types.intType, sema.types.longType): interner.intern("kk_int_to_long")
        case ("toLong", sema.types.uintType, sema.types.longType): interner.intern("kk_uint_to_long")
        case ("toLong", sema.types.ubyteType, sema.types.longType): interner.intern("kk_ubyte_to_long")
        case ("toLong", sema.types.ushortType, sema.types.longType): interner.intern("kk_ushort_to_long")
        case ("toLong", sema.types.doubleType, sema.types.longType): interner.intern("kk_double_to_long")
        case ("toLong", sema.types.floatType, sema.types.longType): interner.intern("kk_float_to_long")
        case ("toLong", sema.types.charType, sema.types.longType): interner.intern("kk_char_to_long")
        case ("toLong", sema.types.longType, sema.types.longType), ("toLong", sema.types.ulongType, sema.types.longType): nil
        case ("toUInt", sema.types.intType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.longType, sema.types.uintType): interner.intern("kk_long_to_uint")
        case ("toUInt", sema.types.ubyteType, sema.types.uintType): interner.intern("kk_ubyte_to_uint")
        case ("toUInt", sema.types.ushortType, sema.types.uintType): interner.intern("kk_ushort_to_uint")
        case ("toUInt", sema.types.charType, sema.types.uintType): interner.intern("kk_char_to_uint")
        case ("toUInt", sema.types.uintType, sema.types.uintType), ("toUInt", sema.types.ulongType, sema.types.uintType): nil
        case ("toULong", sema.types.intType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.longType, sema.types.ulongType): interner.intern("kk_long_to_ulong")
        case ("toULong", sema.types.ubyteType, sema.types.ulongType): interner.intern("kk_ubyte_to_ulong")
        case ("toULong", sema.types.ushortType, sema.types.ulongType): interner.intern("kk_ushort_to_ulong")
        case ("toULong", sema.types.charType, sema.types.ulongType): interner.intern("kk_char_to_ulong")
        case ("toULong", sema.types.uintType, sema.types.ulongType): interner.intern("kk_uint_to_ulong")
        case ("toULong", sema.types.ulongType, sema.types.ulongType): nil
        case ("toFloat", sema.types.intType, sema.types.floatType): interner.intern("kk_int_to_float")
        case ("toFloat", sema.types.longType, sema.types.floatType): interner.intern("kk_long_to_float")
        case ("toFloat", sema.types.doubleType, sema.types.floatType): interner.intern("kk_double_to_float")
        case ("toFloat", sema.types.floatType, sema.types.floatType): nil
        case ("toDouble", sema.types.intType, sema.types.doubleType): interner.intern("kk_int_to_double_bits")
        case ("toDouble", sema.types.longType, sema.types.doubleType): interner.intern("kk_long_to_double")
        case ("toDouble", sema.types.floatType, sema.types.doubleType): interner.intern("kk_float_to_double_bits")
        case ("toDouble", sema.types.doubleType, sema.types.doubleType): nil
        case ("toByte", sema.types.intType, sema.types.intType): interner.intern("kk_int_to_byte")
        case ("toByte", sema.types.longType, sema.types.intType): interner.intern("kk_long_to_byte")
        case ("toShort", sema.types.intType, sema.types.intType): interner.intern("kk_int_to_short")
        case ("toShort", sema.types.longType, sema.types.intType): interner.intern("kk_long_to_short")
        case ("toUByte", sema.types.intType, sema.types.ubyteType): interner.intern("kk_int_to_ubyte")
        case ("toUByte", sema.types.longType, sema.types.ubyteType): interner.intern("kk_long_to_ubyte")
        case ("toUByte", sema.types.uintType, sema.types.ubyteType): interner.intern("kk_uint_to_ubyte")
        case ("toUByte", sema.types.ulongType, sema.types.ubyteType): interner.intern("kk_ulong_to_ubyte")
        case ("toUByte", sema.types.ubyteType, sema.types.ubyteType): nil
        case ("toUShort", sema.types.intType, sema.types.ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", sema.types.longType, sema.types.ushortType): interner.intern("kk_long_to_ushort")
        case ("toUShort", sema.types.uintType, sema.types.ushortType): interner.intern("kk_uint_to_ushort")
        case ("toUShort", sema.types.ulongType, sema.types.ushortType): interner.intern("kk_ulong_to_ushort")
        case ("toUShort", sema.types.ushortType, sema.types.ushortType): nil
        case ("toChar", sema.types.intType, sema.types.charType): interner.intern("kk_int_to_char")
        case ("toChar", sema.types.longType, sema.types.charType): interner.intern("kk_long_to_char")
        case ("toChar", sema.types.uintType, sema.types.charType): interner.intern("kk_uint_to_char")
        case ("toChar", sema.types.ulongType, sema.types.charType): interner.intern("kk_ulong_to_char")
        case ("toChar", sema.types.ubyteType, sema.types.charType): interner.intern("kk_ubyte_to_char")
        case ("toChar", sema.types.ushortType, sema.types.charType): interner.intern("kk_ushort_to_char")
        case ("toChar", sema.types.charType, sema.types.charType): nil
        default: nil
        }

        if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toChar"].contains(calleeStr),
           runtimeCallee == nil
        {
            return loweredArgumentID
        }
        guard let runtimeCallee else {
            return nil
        }

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [loweredArgumentID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - REFL-005: typeOf<T>() Lowering

    /// Lowers `typeOf<T>()` calls to `kk_typeof(typeToken, nameHint, argsRaw, isNullable)`.
    /// Returns nil if the expression is not a typeOf call.
    private func lowerTypeOfCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .typeOf else {
            return nil
        }

        guard let callee = ast.arena.expr(calleeExpr),
              case let .nameRef(name, _) = callee,
              interner.resolve(name) == "typeOf"
        else {
            return nil
        }

        // Resolve the type argument from the call binding.
        let callBinding = sema.bindings.callBindings[exprID]
        let typeArg: TypeID
        if let binding = callBinding,
           !binding.substitutedTypeArguments.isEmpty
        {
            typeArg = binding.substitutedTypeArguments[0]
        } else {
            // Fallback: typeOf<T>() with no resolved type argument defaults to Any.
            typeArg = sema.types.anyType
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType

        func makeTypeTokenExpr(for type: TypeID) -> KIRExprID {
            if case let .typeParam(typeParam) = sema.types.kind(of: type) {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
                let tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                return tokenExpr
            }
            let encoded = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
            return tokenExpr
        }

        func makeNameHintExpr(for type: TypeID) -> KIRExprID {
            if let name = RuntimeTypeCheckToken.simpleName(of: type, sema: sema, interner: interner) {
                let internedName = interner.intern(name)
                let nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
                instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
                return nameHintExpr
            }
            let nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
            return nameHintExpr
        }

        func makeNullabilityExpr(for type: TypeID) -> KIRExprID {
            let isNullable: Int64 = {
                switch sema.types.kind(of: type) {
                case let .primitive(_, nullability):
                    return nullability == .nullable ? 1 : 0
                case let .classType(ct):
                    return ct.nullability == .nullable ? 1 : 0
                case let .typeParam(tp):
                    return tp.nullability == .nullable ? 1 : 0
                case let .kClassType(kc):
                    return kc.nullability == .nullable ? 1 : 0
                case let .any(nullability):
                    return nullability == .nullable ? 1 : 0
                case let .nothing(nullability):
                    return nullability == .nullable ? 1 : 0
                default:
                    return 0
                }
            }()
            let isNullableExpr = arena.appendExpr(.intLiteral(isNullable), type: intType)
            instructions.append(.constValue(result: isNullableExpr, value: .intLiteral(isNullable)))
            return isNullableExpr
        }

        func lowerKTypeExpr(for type: TypeID) -> KIRExprID {
            func lowerKTypeProjectionExpr(_ argument: TypeArg) -> KIRExprID {
                let varianceOrdinal: Int64
                let typeRawExpr: KIRExprID
                switch argument {
                case .star:
                    varianceOrdinal = -1
                    typeRawExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: typeRawExpr, value: .intLiteral(0)))
                case let .invariant(argumentType):
                    varianceOrdinal = 2
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                case let .out(argumentType):
                    varianceOrdinal = 1
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                case let .in(argumentType):
                    varianceOrdinal = 0
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                }
                let varianceExpr = arena.appendExpr(.intLiteral(varianceOrdinal), type: intType)
                instructions.append(.constValue(result: varianceExpr, value: .intLiteral(varianceOrdinal)))
                let projectionExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_ktypeprojection_create"),
                    arguments: [typeRawExpr, varianceExpr],
                    result: projectionExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                return projectionExpr
            }

            let tokenExpr = makeTypeTokenExpr(for: type)
            let nameHintExpr = makeNameHintExpr(for: type)
            let typeArguments: [TypeArg] = switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
            case let .classType(classType):
                classType.args
            case let .kClassType(kClassType):
                [.invariant(kClassType.argument)]
            default:
                []
            }

            let argsListExpr: KIRExprID
            if typeArguments.isEmpty {
                argsListExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: argsListExpr, value: .intLiteral(0)))
            } else {
                let countExpr = arena.appendExpr(.intLiteral(Int64(typeArguments.count)), type: intType)
                instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(typeArguments.count))))
                let arrayExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_new"),
                    arguments: [countExpr],
                    result: arrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (index, argument) in typeArguments.enumerated() {
                    let projectionExpr = lowerKTypeProjectionExpr(argument)
                    let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
                    instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))
                    let setResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_set"),
                        arguments: [arrayExpr, indexExpr, projectionExpr],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                argsListExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_of"),
                    arguments: [arrayExpr, countExpr],
                    result: argsListExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            let isNullableExpr = makeNullabilityExpr(for: type)
            let ktypeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_typeof"),
                arguments: [tokenExpr, nameHintExpr, argsListExpr, isNullableExpr],
                result: ktypeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            return ktypeExpr
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let lowered = lowerKTypeExpr(for: typeArg)
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.copy(from: lowered, to: result))
        return result
    }

    // MARK: - REFL-005: KClass Metadata Registration for Constructor Calls

    /// Emits a `kk_kclass_register_metadata` call so that `KClass` reflection
    /// queries (`.members`, `.constructors`, etc.) return correct data.
    /// This mirrors `ObjectLiteralLowerer.registerKClassMetadata` but is used
    /// for regular class constructor invocations.
    func emitKClassMetadataRegistration(
        objectSymbol: SymbolID,
        typeID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let symbol = sema.symbols.symbol(objectSymbol) else { return }

        let intType = sema.types.intType

        let typeToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeID
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: intType)
        instructions.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))

        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleName = interner.resolve(symbol.name)
        let simpleNameInterned = interner.intern(simpleName)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        let supertypeNameExpr: KIRExprID
        let supertypes = sema.symbols.directSupertypes(for: objectSymbol)
        let superClassSymbol = supertypes.first(where: { sid in
            sema.symbols.symbol(sid)?.kind == .class
        })
        if let superClassSymbol,
           let superSymbol = sema.symbols.symbol(superClassSymbol)
        {
            let superFqName = superSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            let superInterned = interner.intern(superFqName)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superInterned), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superInterned)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        let fieldCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            fieldCount = Int64(layout.instanceFieldCount)
        } else {
            fieldCount = -1
        }
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        let memberCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            memberCount = Int64(layout.instanceFieldCount + layout.vtableSize)
        } else {
            memberCount = -1
        }
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { child in
            sema.symbols.symbol(child)?.kind == .constructor
        }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: Register annotations for this type.
        emitAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    // MARK: - STDLIB-REFLECT-065: Annotation Registration

    /// Emits calls to register annotation metadata for a nominal type.
    /// Emits one `kk_kclass_register_single_annotation` call per annotation
    /// to avoid requiring runtime list construction at the KIR level.
    func emitAnnotationRegistration(
        objectSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let annotations = sema.symbols.annotations(for: objectSymbol)
        guard !annotations.isEmpty else { return }

        let intType = sema.types.intType
        let stringType = sema.types.stringType

        for annotation in annotations {
            // Annotation FQ name.
            let nameInterned = interner.intern(annotation.annotationFQName)
            let nameExpr = arena.appendExpr(.stringLiteral(nameInterned), type: stringType)
            instructions.append(.constValue(result: nameExpr, value: .stringLiteral(nameInterned)))

            // Encode arguments as a single pipe-delimited string for simplicity.
            let argsEncoded = annotation.arguments.joined(separator: "|")
            let argsInterned = interner.intern(argsEncoded)
            let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
            instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

            // Argument count.
            let argCount = Int64(annotation.arguments.count)
            let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
            instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

            // Call kk_kclass_register_single_annotation(typeToken, fqName, argsEncoded, argCount).
            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_register_single_annotation"),
                arguments: [typeTokenExpr, nameExpr, argsExpr, argCountExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}
