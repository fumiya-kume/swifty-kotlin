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

    /// Shared helper for coerceIn(range) lowering (STDLIB-525).
    /// Decomposes a range argument into first/last bounds and emits a call to
    /// kk_{int,long}_coerceIn. Used by both normal and safe-call member lowering
    /// paths to avoid duplication.
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
        let loweredCallable = driver.ctx.callableValueInfo(for: loweredCalleeExprID)
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
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let callBinding = sema.bindings.callBindings[exprID]
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let chosen = callBinding?.chosenCallee
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
        if let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
            if loweredCallable.hasClosureParam {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgIDs.insert(zeroExpr, at: loweredCallable.captureArguments.count)
            }
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
            let loweredCalleeName: InternedString = if let chosen,
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
            instructions.append(.call(
                symbol: chosen ?? loweredCallable?.symbol,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: callCanThrow,
                thrownResult: nil
            ))
        }
        return result
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    private func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return name == "kk_runCatching"
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
            case interner.intern("Range"), interner.intern("IntRange"), interner.intern("LongRange"):
                interner.intern("kk_range_toList")
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
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              loweredArguments.count == originalArgs.count
        else {
            return loweredArguments
        }

        let legacyNames: Set = ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy", "kk_sequence_generate"]
        if legacyNames.contains(externalLinkName), loweredArguments.count == 2 {
            var finalArgs = [loweredArguments[0], loweredArguments[1]]
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
            let lambdaID = loweredArguments[0]
            // The lowered lambda is a function pointer; its callableValueInfo
            // holds (callee=fnPtr, captureArguments=[closureRaw]).
            finalArgs.append(lambdaID) // fnPtr
            if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID),
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

        return loweredArguments
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
        } ?? candidates.first

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
        case ("toInt", sema.types.doubleType, sema.types.intType): interner.intern("kk_double_to_int")
        case ("toInt", sema.types.floatType, sema.types.intType): interner.intern("kk_float_to_int")
        case ("toInt", sema.types.charType, sema.types.intType): nil
        case ("toInt", sema.types.intType, sema.types.intType), ("toInt", sema.types.longType, sema.types.intType): nil
        case ("toLong", sema.types.intType, sema.types.longType): interner.intern("kk_int_to_long")
        case ("toLong", sema.types.uintType, sema.types.longType): interner.intern("kk_uint_to_long")
        case ("toLong", sema.types.doubleType, sema.types.longType): interner.intern("kk_double_to_long")
        case ("toLong", sema.types.floatType, sema.types.longType): interner.intern("kk_float_to_long")
        case ("toLong", sema.types.longType, sema.types.longType), ("toLong", sema.types.ulongType, sema.types.longType): nil
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
        case ("toChar", sema.types.intType, sema.types.charType): nil
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
    private func emitKClassMetadataRegistration(
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
    }
}
