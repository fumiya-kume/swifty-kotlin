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

            let savedReceiverExprID = driver.ctx.currentImplicitReceiverExprID
            let savedReceiverSymbol = driver.ctx.currentImplicitReceiverSymbol
            driver.ctx.localValuesBySymbol[receiverSymbol] = receiverSymExpr
            driver.ctx.currentImplicitReceiverExprID = receiverSymExpr
            driver.ctx.currentImplicitReceiverSymbol = receiverSymbol

            let loweredLambdaID = driver.lowerExpr(
                args[1].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            driver.ctx.currentImplicitReceiverExprID = savedReceiverExprID
            driver.ctx.currentImplicitReceiverSymbol = savedReceiverSymbol

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            if let info = driver.ctx.callableValueInfoByExprID[loweredLambdaID] {
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
                driver.ctx.currentImplicitReceiverExprID = savedReceiverExprID
                driver.ctx.currentImplicitReceiverSymbol = savedReceiverSymbol
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
        let loweredCallable = driver.ctx.callableValueInfoByExprID[loweredCalleeExprID]
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
                  let implicitReceiver = driver.ctx.currentImplicitReceiverExprID
        {
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
        if loweredCallable == nil {
            let runBlockingID = interner.intern("runBlocking")
            let launchID = interner.intern("launch")
            let asyncID = interner.intern("async")
            let isSyntheticCoroutineLauncher: Bool
            if let chosen,
               let chosenInfo = sema.symbols.symbol(chosen)
            {
                let fqName = chosenInfo.fqName.map(interner.resolve)
                isSyntheticCoroutineLauncher = fqName == ["kotlinx", "coroutines", "runBlocking"]
                    || fqName == ["kotlinx", "coroutines", "launch"]
                    || fqName == ["kotlinx", "coroutines", "async"]
            } else {
                isSyntheticCoroutineLauncher = true
            }
            if isSyntheticCoroutineLauncher,
               (sourceCalleeName == runBlockingID
                   || sourceCalleeName == launchID
                   || sourceCalleeName == asyncID),
               let firstArg = finalArgIDs.first,
               let callableInfo = driver.ctx.callableValueInfoByExprID[firstArg],
               !callableInfo.captureArguments.isEmpty
            {
                finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 1)
            }
        }
        let withContextID = interner.intern("withContext")
        if sourceCalleeName == withContextID,
           finalArgIDs.count >= 2,
           let callableInfo = driver.ctx.callableValueInfoByExprID[finalArgIDs[1]],
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
            for (argumentType, parameterType) in zip(argumentTypes, signature.parameterTypes) {
                if !sema.types.isSubtype(argumentType, parameterType) {
                    return false
                }
            }
            return true
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
}
