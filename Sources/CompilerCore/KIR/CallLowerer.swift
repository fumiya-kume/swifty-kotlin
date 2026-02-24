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
        let sourceCalleeName: InternedString
        if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
            sourceCalleeName = name
        } else if let loweredCallable {
            sourceCalleeName = loweredCallable.callee
        } else {
            sourceCalleeName = interner.intern("<unknown>")
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
        let callNormalized: NormalizedCallResult
        if callBinding != nil {
            callNormalized = driver.callSupportLowerer.normalizedCallArguments(
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
            callNormalized = NormalizedCallResult(
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
                  sema.symbols.symbol(chosen)?.kind == .constructor {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_array_new(slotCount) and prepend it to the argument list.
            // Derive slot count from NominalLayout.instanceSizeWords of the owning class.
            let allocType = boundType ?? sema.types.anyType
            let intType = sema.types.make(.primitive(.int, .nonNull))
            var slotCount: Int64 = 1
            if let parentClassID = sema.symbols.parentSymbol(for: chosen),
               let layout = sema.symbols.nominalLayout(for: parentClassID) {
                slotCount = Int64(max(layout.instanceSizeWords, 1))
            }
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
            instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_new"),
                arguments: [slotCountExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            finalArgIDs.insert(allocatedObj, at: 0)
        } else if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil,
           let implicitReceiver = driver.ctx.currentImplicitReceiverExprID {
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
        if chosen == nil,
           loweredCallable == nil {
            let resolvedSourceCallee = interner.resolve(sourceCalleeName)
            if resolvedSourceCallee == "runBlocking"
                || resolvedSourceCallee == "launch"
                || resolvedSourceCallee == "async",
               let firstArg = finalArgIDs.first,
               let callableInfo = driver.ctx.callableValueInfoByExprID[firstArg],
               !callableInfo.captureArguments.isEmpty {
                finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 1)
            }
        }
        if callNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArgIDs.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(callNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(callNormalized.defaultMask))))
            finalArgIDs.append(maskExpr)
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
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArgIDs.append(tokenExpr)
                }
            }
            let loweredCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredCalleeName = interner.intern(externalLinkName)
            } else if let loweredCallable {
                loweredCalleeName = loweredCallable.callee
            } else if chosen == nil {
                loweredCalleeName = driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    interner: interner
                ) ?? sourceCalleeName
            } else {
                loweredCalleeName = sourceCalleeName
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

    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
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
        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let memberNormalized = driver.callSupportLowerer.normalizedCallArguments(
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
        var finalArguments = memberNormalized.arguments
        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil {
            finalArguments.insert(loweredReceiverID, at: 0)
        } else if chosen == nil {
            // Unresolved member call (e.g. collection stub methods like
            // size, get, contains, isEmpty): always prepend receiver so that
            // the CollectionLiteralLoweringPass can match it.
            finalArguments.insert(loweredReceiverID, at: 0)
        }
        if memberNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(memberNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(memberNormalized.defaultMask))))
            finalArguments.append(maskExpr)
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: isSuperCall
            ))
        } else {
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            if !isSuperCall,
               let chosen,
               let dispatchKind = resolveVirtualDispatch(callee: chosen, sema: sema) {
                // For virtualCall, the receiver is a separate field, so remove it
                // from finalArguments (it was inserted at index 0 above).
                var vcArguments = finalArguments
                if let chosen2 = Optional(chosen),
                   let signature = sema.symbols.functionSignature(for: chosen2),
                   signature.receiverType != nil,
                   !vcArguments.isEmpty {
                    vcArguments.removeFirst()
                }
                instructions.append(.virtualCall(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    receiver: loweredReceiverID,
                    arguments: vcArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatchKind
                ))
            } else {
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: isSuperCall
                ))
            }
        }
        return result
    }

    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
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
        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let safeNormalized = driver.callSupportLowerer.normalizedCallArguments(
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
        var finalArguments = safeNormalized.arguments
        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil {
            finalArguments.insert(loweredReceiverID, at: 0)
        }
        if safeNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(safeNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(safeNormalized.defaultMask))))
            finalArguments.append(maskExpr)
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: isSuperCall
            ))
        } else {
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            if !isSuperCall,
               let chosen,
               let dispatchKind = resolveVirtualDispatch(callee: chosen, sema: sema) {
                // For virtualCall, the receiver is a separate field, so remove it
                // from finalArguments (it was inserted at index 0 above).
                var vcArguments = finalArguments
                if let chosen2 = Optional(chosen),
                   let signature = sema.symbols.functionSignature(for: chosen2),
                   signature.receiverType != nil,
                   !vcArguments.isEmpty {
                    vcArguments.removeFirst()
                }
                instructions.append(.virtualCall(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    receiver: loweredReceiverID,
                    arguments: vcArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatchKind
                ))
            } else {
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: isSuperCall
                ))
            }
        }
        return result
    }

    /// Determine if a callee method requires virtual dispatch.
    /// Returns `.vtable(slot:)` for class methods or `.itable(slot:)` for interface methods,
    /// or `nil` if the call should use direct (static) dispatch.
    private func resolveVirtualDispatch(callee: SymbolID, sema: SemaModule) -> KIRDispatchKind? {
        guard let calleeSymbol = sema.symbols.symbol(callee),
              calleeSymbol.kind == .function else {
            return nil
        }
        guard let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID) else {
            return nil
        }
        guard let layout = sema.symbols.nominalLayout(for: parentID) else {
            return nil
        }
        if parentSymbol.kind == .interface {
            let interfaceSlot = layout.itableSlots[parentID] ?? 0
            if let methodSlot = layout.vtableSlots[callee] {
                return .itable(interfaceSlot: interfaceSlot, methodSlot: methodSlot)
            }
            return nil
        }
        if parentSymbol.kind == .class {
            // Only use virtual dispatch if the class actually has subtypes.
            // In Kotlin, classes are final by default; virtual dispatch is only
            // needed when the class is open/abstract (has known subtypes).
            let subtypes = sema.symbols.directSubtypes(of: parentID)
            guard !subtypes.isEmpty else {
                return nil
            }
            if let vtableSlot = layout.vtableSlots[callee] {
                return .vtable(slot: vtableSlot)
            }
            return nil
        }
        return nil
    }

    private func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case .functionType(let functionType) = sema.types.kind(of: callableValueCallBinding.functionType) else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }

    // MARK: - Binary Operations

    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let lhsID = driver.lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = driver.lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        // Detect whether this is a compareTo-desugared comparison operator.
        // If so, the call binding targets compareTo (returns Int) and we must
        // wrap the result with a comparison against 0 to produce Bool.
        let isCompareToDesugaring: Bool
        switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            isCompareToDesugaring = sema.bindings.callBindings[exprID] != nil
        default:
            isCompareToDesugaring = false
        }
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil {
            // For compareTo desugaring, the call result is Int, not Bool.
            // We allocate a separate temporary for the compareTo call result.
            let callResult: KIRExprID
            if isCompareToDesugaring {
                callResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            } else {
                callResult = result
            }
            let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: [rhsID],
                callBinding: callBinding,
                chosenCallee: callBinding.chosenCallee,
                spreadFlags: [false],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhsID, at: 0)
            if !signature.reifiedTypeParameterIndices.isEmpty {
                for index in signature.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            if normalizedResult.defaultMask != 0 {
                let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(
                    (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                )
                let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: callBinding.chosenCallee)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let loweredCalleeName: InternedString
                if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    loweredCalleeName = symbol.name
                } else {
                    loweredCalleeName = driver.callSupportLowerer.binaryOperatorFunctionName(for: op, interner: interner)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            // compareTo desugaring: emit `compareTo(a,b) <op> 0` to produce Bool
            if isCompareToDesugaring {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan:     cmpOp = .lessThan
                case .lessOrEqual:  cmpOp = .lessOrEqual
                case .greaterThan:  cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: isCompareToDesugaring should only be true for comparison operators")
                }
                instructions.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
            }
            return result
        }
        if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        // String comparison desugaring: route <, <=, >, >= on String operands
        // through kk_string_compareTo (content comparison) instead of the default
        // kk_op_lt/le/gt/ge path which compares raw pointer addresses.
        let lhsType = sema.bindings.exprTypes[lhs]
        let rhsType = sema.bindings.exprTypes[rhs]
        let nullableStringType = sema.types.make(.primitive(.string, .nullable))
        let isStringOperand = (lhsType == stringType || lhsType == nullableStringType)
                           && (rhsType == stringType || rhsType == nullableStringType)
        if isStringOperand {
            switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                let compareResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareTo"),
                    arguments: [lhsID, rhsID],
                    result: compareResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan:      cmpOp = .lessThan
                case .lessOrEqual:   cmpOp = .lessOrEqual
                case .greaterThan:   cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: unexpected comparison operator for string operands")
                }
                instructions.append(.binary(op: cmpOp, lhs: compareResult, rhs: zeroExpr, result: result))
                return result
            default:
                break
            }
        }
        if let runtimeCallee = driver.callSupportLowerer.builtinBinaryRuntimeCallee(for: op, interner: interner) {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .subtract:
            kirOp = .subtract
        case .multiply:
            kirOp = .multiply
        case .divide:
            kirOp = .divide
        case .modulo:
            kirOp = .modulo
        case .equal:
            kirOp = .equal
        case .notEqual:
            kirOp = .notEqual
        case .lessThan:
            kirOp = .lessThan
        case .lessOrEqual:
            kirOp = .lessOrEqual
        case .greaterThan:
            kirOp = .greaterThan
        case .greaterOrEqual:
            kirOp = .greaterOrEqual
        case .logicalAnd:
            kirOp = .logicalAnd
        case .logicalOr:
            kirOp = .logicalOr
        case .elvis:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_elvis"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeUntil:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeUntil"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .downTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_downTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .step:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_step"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }

    // MARK: - Array Operations

    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array get only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerIndexedAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array set only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, valueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIndexedCompoundAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Conceptual desugaring: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // appropriate kk_op_* for the compound operator
        //   3) kk_array_set(a, i, t')
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array compound assign only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Step 1: get current value
        let getResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: getResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 2: apply binary op
        let opResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        guard let expr = ast.arena.expr(exprID),
              case .indexedCompoundAssign(let op, _, _, _, _) = expr else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Determine the runtime op stub.
        // Use kk_string_concat for String += String (matching lowerBinaryExpr pattern),
        // otherwise use the appropriate numeric op stub.
        // Note: exprID's bound type is always unitType for compound assign, so we
        // derive the element type from the receiver's array type instead.
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        // Derive element type from the receiver's array type.
        // Mirrors TypeCheckHelpers.arrayElementType logic but also checks
        // the value expression type as a heuristic for non-IntArray receivers.
        let receiverBoundType = sema.bindings.exprTypes[receiverExpr]
        let isStringElement: Bool = {
            guard let recvType = receiverBoundType,
                  case .classType(let classType) = sema.types.kind(of: recvType) else {
                return false
            }
            // Prefer the explicit element type from type arguments, if present.
            if let firstArg = classType.args.first {
                let elementType: TypeID?
                switch firstArg {
                case .invariant(let t), .out(let t), .in(let t): elementType = t
                case .star: elementType = nil
                }
                if let elementType {
                    return elementType == stringType
                }
            }
            // Fallback: support legacy non-generic StringArray by name only.
            if let symbol = sema.symbols.symbol(classType.classSymbol) {
                let name = interner.resolve(symbol.name)
                return name == "StringArray"
            }
            return false
        }()
        let opName: String
        if op == .plusAssign, isStringElement {
            opName = "kk_string_concat"
        } else {
            switch op {
            case .plusAssign: opName = "kk_op_add"
            case .minusAssign: opName = "kk_op_sub"
            case .timesAssign: opName = "kk_op_mul"
            case .divAssign: opName = "kk_op_div"
            case .modAssign: opName = "kk_op_mod"
            }
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 3: set new value
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, opResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
