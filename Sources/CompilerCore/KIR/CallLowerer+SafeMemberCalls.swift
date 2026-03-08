import Foundation

extension CallLowerer {
    private static let coroutineHandleMemberNames: Set<String> = ["await", "join", "cancel"]

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

        // Primitive member function: Int/Long/UInt/ULong.inv() → kk_op_inv (P5-103, TYPE-005)
        if interner.resolve(effectiveCalleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType {
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

        // Primitive infix member functions: Int/Long/UInt/ULong.and|or|xor|shl|shr|ushr (EXPR-003, TYPE-005)
        if args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType {
                let rhsType = sema.types.makeNonNullable(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType)
                let isIntegerRhs = rhsType == intType || rhsType == longType || rhsType == uintType || rhsType == ulongType
                let primitiveCallee: InternedString? = switch interner.resolve(effectiveCalleeName) {
                case "and":
                    isIntegerRhs ? interner.intern("kk_bitwise_and") : nil
                case "or":
                    isIntegerRhs ? interner.intern("kk_bitwise_or") : nil
                case "xor":
                    isIntegerRhs ? interner.intern("kk_bitwise_xor") : nil
                case "shl":
                    rhsType == intType ? interner.intern("kk_op_shl") : nil
                case "shr":
                    rhsType == intType ? interner.intern("kk_op_shr") : nil
                case "ushr":
                    rhsType == intType ? interner.intern("kk_op_ushr") : nil
                default:
                    nil
                }
                if let primitiveCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: primitiveCallee,
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Primitive member function: Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if interner.resolve(effectiveCalleeName) == "toString",
           args.count == 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_int_toString_radix"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let calleeStr = interner.resolve(effectiveCalleeName)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", intType, intType), ("toInt", longType, intType): nil
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ulongType, ulongType): nil
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if ["toInt", "toUInt", "toLong", "toULong"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType,
               nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
            {
                instructions.append(.copy(from: loweredReceiverID, to: result))
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
        if safeNormalized.defaultMask != 0,
           let chosen,
           sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
        {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
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
                interner: interner,
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
        else { return nil }
        guard let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID)
        else { return nil }
        guard let layout = sema.symbols.nominalLayout(for: parentID) else { return nil }
        if parentSymbol.kind == .interface {
            return resolveItableDispatch(
                callee: callee, parentID: parentID, layout: layout,
                receiverTypeID: receiverTypeID, sema: sema
            )
        }
        if parentSymbol.kind == .class {
            return resolveVtableDispatch(callee: callee, parentID: parentID, layout: layout, sema: sema)
        }
        return nil
    }

    private func resolveItableDispatch(
        callee: SymbolID,
        parentID: SymbolID,
        layout: NominalLayout,
        receiverTypeID: TypeID?,
        sema: SemaModule
    ) -> KIRDispatchKind? {
        // The itable slot must be derived from the concrete receiver's layout
        // (which records where each interface is stored), not the interface's
        // own layout.  Without a concrete class receiver we cannot form an
        // itable dispatch.
        guard let receiverTypeID,
              case let .classType(classType) = sema.types.kind(of: receiverTypeID)
        else { return nil }
        let receiverClassSymID = classType.classSymbol
        // If the receiver is a concrete class with no subtypes, use direct
        // dispatch.  Kotlin classes are final by default, so this is safe and
        // avoids the itable path which requires runtime typeInfo support.
        if let receiverClassSym = sema.symbols.symbol(receiverClassSymID),
           receiverClassSym.kind == .class
        {
            if sema.symbols.directSubtypes(of: receiverClassSymID).isEmpty { return nil }
        }
        guard let receiverLayout = sema.symbols.nominalLayout(for: receiverClassSymID) else { return nil }
        let interfaceSlot = receiverLayout.itableSlots[parentID] ?? 0
        if let methodSlot = layout.vtableSlots[callee] {
            return .itable(interfaceSlot: interfaceSlot, methodSlot: methodSlot)
        }
        return nil
    }

    private func resolveVtableDispatch(
        callee: SymbolID,
        parentID: SymbolID,
        layout: NominalLayout,
        sema: SemaModule
    ) -> KIRDispatchKind? {
        // Only use virtual dispatch if the class actually has subtypes.
        // In Kotlin, classes are final by default; virtual dispatch is only
        // needed when the class is open/abstract (has known subtypes).
        let subtypes = sema.symbols.directSubtypes(of: parentID)
        guard !subtypes.isEmpty else { return nil }
        if let vtableSlot = layout.vtableSlots[callee] {
            return .vtable(slot: vtableSlot)
        }
        return nil
    }
}
