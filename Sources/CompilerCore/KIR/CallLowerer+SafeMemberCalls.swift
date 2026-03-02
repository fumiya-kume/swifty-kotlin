import Foundation

extension CallLowerer {
    private static let coroutineHandleMemberNames: Set<String> = ["await", "join", "cancel"]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let boundType = sema.bindings.exprTypes[exprID]

        // const val member property folding (P5-109): check before lowering
        // receiver so no dead instructions are emitted.
        // Only fold actual const val properties (constValue flag); regular
        // immutable class members must not be folded because the receiver
        // expression may have side effects that would be silently dropped.
        // Only fold when the receiver is statically non-nullable.
        // For nullable receivers, safe-call semantics (`receiver?.const`)
        // require the result to be null if the receiver is null, so we
        // must not replace the whole expression with the constant value.
        if args.isEmpty {
            let callBinding = sema.bindings.callBindings[exprID]
            if let chosen = callBinding?.chosenCallee,
               let constant = propertyConstantInitializers[chosen],
               let symInfo = sema.symbols.symbol(chosen),
               symInfo.flags.contains(.constValue)
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr]
                if let receiverType,
                   receiverType == sema.types.makeNonNullable(receiverType)
                {
                    let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
            }
        }

        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            shared: shared, emit: &instructions
        )
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                shared: shared, emit: &instructions
            )
        }
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let safeReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullSafeReceiverType = sema.types.makeNonNullable(safeReceiverType)
        let isCoroutineReceiver = if case .primitive = sema.types.kind(of: nonNullSafeReceiverType) {
            false
        } else {
            true
        }
        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }

        // Primitive member function: Int/Long.inv() → kk_op_inv (P5-103)
        if interner.resolve(effectiveCalleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_inv"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let safeNormalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            shared: shared, emit: &instructions
        )
        var finalArguments = safeNormalized.arguments
        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil
        {
            finalArguments.insert(loweredReceiverID, at: 0)
        } else if chosen == nil {
            let calleeStr = interner.resolve(effectiveCalleeName)
            if Self.coroutineHandleMemberNames.contains(calleeStr), isCoroutineReceiver, args.isEmpty {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
        }
        if safeNormalized.defaultMask != 0, let chosen {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            appendDefaultMaskArgument(
                safeNormalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            let stubName = interner.intern(interner.resolve(effectiveCalleeName) + "$default")
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
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            let loweredMemberCalleeName: InternedString = if let chosen,
                                                             let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                             !externalLinkName.isEmpty
            {
                interner.intern(externalLinkName)
            } else if chosen == nil, isCoroutineReceiver, args.isEmpty {
                switch interner.resolve(effectiveCalleeName) {
                case "await":
                    interner.intern("kk_kxmini_async_await")
                case "join":
                    interner.intern("kk_job_join")
                case "cancel":
                    interner.intern("kk_job_cancel")
                default:
                    effectiveCalleeName
                }
            } else {
                effectiveCalleeName
            }
            let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
            if !isSuperCall,
               let chosen,
               let dispatchKind = resolveVirtualDispatch(callee: chosen, receiverTypeID: receiverTypeForDispatch, sema: sema)
            {
                // For virtualCall, the receiver is a separate field, so remove it
                // from finalArguments (it was inserted at index 0 above).
                var vcArguments = finalArguments
                if let signature = sema.symbols.functionSignature(for: chosen),
                   signature.receiverType != nil,
                   !vcArguments.isEmpty
                {
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
    func resolveVirtualDispatch(callee: SymbolID, receiverTypeID: TypeID?, sema: SemaModule) -> KIRDispatchKind? {
        guard let calleeSymbol = sema.symbols.symbol(callee),
              calleeSymbol.kind == .function
        else {
            return nil
        }
        guard let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID)
        else {
            return nil
        }
        guard let layout = sema.symbols.nominalLayout(for: parentID) else {
            return nil
        }
        if parentSymbol.kind == .interface {
            // The itable slot must be derived from the concrete receiver's layout
            // (which records where each interface is stored), not the interface's
            // own layout.  Without a concrete class receiver we cannot form an
            // itable dispatch.
            guard let receiverTypeID,
                  case let .classType(classType) = sema.types.kind(of: receiverTypeID)
            else {
                return nil
            }
            let receiverClassSymID = classType.classSymbol
            // If the receiver is a concrete class with no subtypes, use direct
            // dispatch.  Kotlin classes are final by default, so this is safe and
            // avoids the itable path which requires runtime typeInfo support.
            if let receiverClassSym = sema.symbols.symbol(receiverClassSymID),
               receiverClassSym.kind == .class
            {
                let subtypes = sema.symbols.directSubtypes(of: receiverClassSymID)
                if subtypes.isEmpty {
                    return nil
                }
            }
            guard let receiverLayout = sema.symbols.nominalLayout(for: receiverClassSymID) else {
                return nil
            }
            let interfaceSlot = receiverLayout.itableSlots[parentID] ?? 0
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
}
