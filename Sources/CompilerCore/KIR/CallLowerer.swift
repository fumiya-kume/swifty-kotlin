import Foundation

final class CallLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
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
        if sourceCalleeName == interner.intern("toList"),
           args.count == 1,
           sema.bindings.isCollectionExpr(args[0].expr)
        {
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
                case knownNames.string:
                    interner.intern("kk_string_toList")
                default:
                    interner.intern("kk_sequence_to_list")
                }
            } else {
                interner.intern("kk_sequence_to_list")
            }
            if let runtimeCallee {
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
            return loweredArgIDs[0]
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
                    interner: interner
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

    private func appendClosureArgumentsIfNeeded(
        _ loweredArguments: [KIRExprID],
        originalArgs: [CallArgument],
        chosenCallee: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              ["kk_require_lazy", "kk_check_lazy", "kk_sequence_generate"].contains(externalLinkName),
              loweredArguments.count == originalArgs.count,
              loweredArguments.count == 2
        else {
            return loweredArguments
        }

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
        if let existing = sema.bindings.callBindings[exprID],
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
            var parameterMapping: [Int: Int] = [:]
            for index in argumentExprs.indices {
                parameterMapping[index] = index
            }
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

        var parameterMapping: [Int: Int] = [:]
        for index in argumentExprs.indices {
            parameterMapping[index] = index
        }
        return CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [],
            parameterMapping: parameterMapping
        )
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
        default: nil
        }

        if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort"].contains(calleeStr),
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
}
