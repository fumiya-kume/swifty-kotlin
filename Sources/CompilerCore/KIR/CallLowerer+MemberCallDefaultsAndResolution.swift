// swiftlint:disable file_length
import Foundation

/// Default-argument materialization and runtime callee resolution helpers.
extension CallLowerer {
    func materializeJoinToStringDefaultArguments(
        _ defaultMask: Int64,
        firstDefaultParameterIndex: Int = 0,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let defaults = [", ", "", ""]
        let stringType = sema.types.stringType
        for (offset, defaultValue) in defaults.enumerated() {
            let paramIndex = firstDefaultParameterIndex + offset
            let maskBit = Int64(1) << paramIndex
            guard (defaultMask & maskBit) != 0 else { continue }
            let argumentIndex = paramIndex + 1
            guard argumentIndex < arguments.count else { continue }
            let interned = interner.intern(defaultValue)
            let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
            instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
            arguments[argumentIndex] = exprID
        }
    }

    func materializeBinarySearchDefaultArguments(
        _ defaultMask: Int64,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID],
        sourceArgLabels: [InternedString?]
    ) {
        let intType = sema.types.intType
        var cachedZeroExpr: KIRExprID?
        var cachedSizeExpr: KIRExprID?

        func makeZeroExpr() -> KIRExprID {
            if let cachedZeroExpr {
                return cachedZeroExpr
            }
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            cachedZeroExpr = zeroExpr
            return zeroExpr
        }

        func makeSizeExpr() -> KIRExprID {
            if let cachedSizeExpr {
                return cachedSizeExpr
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let sizeCallee = unresolvedCollectionMemberCallee(
                memberName: "size",
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) ?? interner.intern("kk_list_size")
            let sizeExpr = arena.appendExpr(
                .temporary(Int32(clamping: arena.expressions.count)),
                type: intType
            )
            instructions.append(.call(
                symbol: nil,
                callee: sizeCallee,
                arguments: [loweredReceiverID],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            cachedSizeExpr = sizeExpr
            return sizeExpr
        }

        if defaultMask == 0 {
            if arguments.count <= 3 {
                arguments.append(makeZeroExpr())
                arguments.append(makeSizeExpr())
            } else if arguments.count == 4 {
                let explicitLabel = sourceArgLabels.last ?? nil
                if let explicitLabel, interner.resolve(explicitLabel) == "toIndex" {
                    arguments.insert(makeZeroExpr(), at: 3)
                } else {
                    arguments.append(makeSizeExpr())
                }
            }
            return
        }

        if (defaultMask & (Int64(1) << 2)) != 0,
           arguments.count > 3
        {
            arguments[3] = makeZeroExpr()
        }

        if (defaultMask & (Int64(1) << 3)) != 0,
           arguments.count > 4
        {
            arguments[4] = makeSizeExpr()
        }
    }

    func materializeArrayBinarySearchDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard arguments.count >= 6 else {
            return
        }

        let intType = sema.types.intType
        let fromIndexMaskBit = Int64(1) << 2
        let toIndexMaskBit = Int64(1) << 3
        if (defaultMask & fromIndexMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[4] = zeroExpr
        }

        if (defaultMask & toIndexMaskBit) != 0 {
            let sizeExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_size"),
                arguments: [arguments[0]],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            arguments[5] = sizeExpr
        }
    }

    func materializeArrayCopyIntoDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard arguments.count >= 5 else {
            return
        }

        let intType = sema.types.intType
        let destinationOffsetMaskBit = Int64(1) << 1
        let startIndexMaskBit = Int64(1) << 2
        let endIndexMaskBit = Int64(1) << 3
        if (defaultMask & destinationOffsetMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[2] = zeroExpr
        }

        if (defaultMask & startIndexMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[3] = zeroExpr
        }

        if (defaultMask & endIndexMaskBit) != 0 {
            let sizeExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_size"),
                arguments: [arguments[0]],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            arguments[4] = sizeExpr
        }
    }

    /// Callees with an externalLinkName (C runtime functions such as
    /// kk_array_get) are never dispatched virtually.
    func tryEmitVirtualDispatch(
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        isSuperCall: Bool,
        finalArguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule
    ) -> KIRInstruction? {
        guard !isSuperCall, let chosenCallee else { return nil }
        let hasExternalLink = sema.symbols.externalLinkName(for: chosenCallee)
            .map { !$0.isEmpty } ?? false
        guard !hasExternalLink else { return nil }
        let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
        guard let dispatchKind = resolveVirtualDispatch(
            callee: chosenCallee, receiverTypeID: receiverTypeForDispatch, sema: sema
        ) else { return nil }
        var vcArguments = finalArguments
        if let sig = sema.symbols.functionSignature(for: chosenCallee),
           sig.receiverType != nil, !vcArguments.isEmpty
        {
            vcArguments.removeFirst()
        }
        return .virtualCall(
            symbol: chosenCallee,
            callee: calleeName,
            receiver: loweredReceiverID,
            arguments: vcArguments,
            result: result,
            canThrow: false,
            thrownResult: nil,
            dispatch: dispatchKind
        )
    }

    func loweredMemberCalleeName(
        chosenCallee: SymbolID?,
        fallback: InternedString,
        receiverExpr: ExprID,
        argumentCount: Int,
        sourceArgumentCount: Int? = nil,
        hasHOFLambdaArg: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        let callArgumentCount = sourceArgumentCount ?? argumentCount
        let fallbackName = interner.resolve(fallback)
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let rangeDispatchKey = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).map {
            MemberDispatchKey(
                receiverKind: $0,
                memberName: fallbackName,
                arity: callArgumentCount,
                lambdaShape: hasHOFLambdaArg ? .hofLambda : .none
            )
        }

        if let rangeDispatchKey,
           fallbackName == "step",
           callArgumentCount <= 1,
           let runtimeLinkName = MemberRuntimeDispatch.rangeRuntimeLinkName(for: rangeDispatchKey)
        {
            return interner.intern(runtimeLinkName)
        }

        if let rangeDispatchKey,
           !hasHOFLambdaArg,
           let runtimeLinkName = MemberRuntimeDispatch.rangeRuntimeLinkName(for: rangeDispatchKey),
           ["random", "firstOrNull", "lastOrNull", "randomOrNull"].contains(fallbackName)
        {
            return interner.intern(runtimeLinkName)
        }

        if let chosenCallee {
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               !externalLinkName.isEmpty
            {
                if let closedRangeRuntimeName = closedRangeInterfaceRuntimeName(
                    memberName: fallbackName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ) {
                    return closedRangeRuntimeName
                }
                if fallbackName == "iterator",
                   let collectionIterator = unresolvedCollectionMemberCallee(
                       memberName: fallbackName,
                       receiverType: receiverType,
                       sema: sema,
                       interner: interner
                   )
                {
                    return collectionIterator
                }
                if callArgumentCount == 1,
                   (externalLinkName == "kk_op_step"
                    || externalLinkName == "kk_uint_step"
                    || externalLinkName == "kk_ulong_step")
                {
                    if externalLinkName == "kk_ulong_step"
                        || sema.bindings.isULongRangeExpr(receiverExpr)
                        || nonNullReceiverType == sema.types.ulongType
                    {
                        return interner.intern("kk_ulong_range_step")
                    }
                    if nonNullReceiverType == sema.types.longType {
                        return interner.intern("kk_long_range_step")
                    }
                    return interner.intern("kk_range_step")
                }
                if externalLinkName == "kk_list_binarySearch" {
                    // STDLIB-547: When the element-based binarySearch overload was
                    // recovered but the call actually has a HOF lambda argument,
                    // redirect to the comparison-based runtime function.
                    if hasHOFLambdaArg && argumentCount == 2 {
                        return interner.intern("kk_list_binarySearch_compare")
                    }
                    if argumentCount > 2 {
                        return interner.intern("kk_list_binarySearch_comparator")
                    }
                }
                if (externalLinkName == "kk_list_binarySearch" || externalLinkName == "kk_array_binarySearch"),
                   isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
                   argumentCount == 5
                {
                    return interner.intern("kk_array_binarySearch_compare")
                }
                if (externalLinkName == "kk_list_binarySearch" || externalLinkName == "kk_array_binarySearch"),
                   isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
                   argumentCount == 5
                {
                    return interner.intern("kk_array_binarySearch_compare")
                }
                return interner.intern(externalLinkName)
            }
            if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
                memberName: fallbackName,
                receiverExpr: receiverExpr,
                receiverType: receiverType,
                argumentCount: callArgumentCount,
                hasHOFLambdaArg: hasHOFLambdaArg,
                sema: sema,
                interner: interner
            ) {
                return unresolvedSynthetic
            }
            // Collection interface members (size property, isEmpty function)
            // resolved on a concrete receiver (List, Array, Map, Set) must be
            // lowered to the matching runtime function instead of virtual dispatch.
            if let collectionProperty = unresolvedCollectionMemberCallee(
                memberName: fallbackName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) {
                return collectionProperty
            }
            return fallback
        }

        if isCoroutineHandleReceiverType(receiverType, sema: sema, interner: interner) {
            switch fallbackName {
            case "await":
                return interner.intern("kk_kxmini_async_await")
            case "join":
                return interner.intern("kk_job_join")
            case "awaitCompletion":
                return interner.intern("kk_job_await_completion")
            case "cancel":
                return argumentCount > 1
                    ? interner.intern("kk_job_cancel_with_cause")
                    : interner.intern("kk_job_cancel")
            case "complete":
                return interner.intern("kk_job_complete")
            case "completeExceptionally":
                return interner.intern("kk_job_complete_exceptionally")
            case "isActive":
                return interner.intern("kk_job_is_active")
            case "isCompleted":
                return interner.intern("kk_job_is_completed")
            case "isCancelled":
                return interner.intern("kk_job_is_cancelled")
            default:
                break
            }
        }
        if isChannelReceiverType(receiverType, sema: sema, interner: interner) {
            switch fallbackName {
            case "send":
                return interner.intern("kk_channel_send")
            case "receive":
                return interner.intern("kk_channel_receive")
            case "close":
                return interner.intern("kk_channel_close")
            case "isClosedForReceive":
                return interner.intern("kk_channel_is_closed_for_receive")
            case "isClosedForSend":
                return interner.intern("kk_channel_is_closed_for_send")
            default:
                break
            }
        }
        if let collectionProperty = unresolvedCollectionMemberCallee(
            memberName: fallbackName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) {
            return collectionProperty
        }
        if let mapMember = unresolvedMapMemberCallee(
            memberName: fallbackName,
            receiverType: receiverType,
            argumentCount: argumentCount,
            sema: sema,
            interner: interner
        ) {
            return mapMember
        }
        if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
            memberName: fallbackName,
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            argumentCount: argumentCount,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        ) {
            return unresolvedSynthetic
        }
        return fallback
    }

    func closedRangeInterfaceRuntimeName(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let closedRangeSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("ranges"),
                  interner.intern("ClosedRange"),
              ]),
              let liftedArgs = sema.types.liftedNominalSupertypeArgs(
                  from: classType.classSymbol,
                  childArgs: classType.args,
                  to: closedRangeSymbol
              ),
              let typeArg = liftedArgs.first
        else {
            return nil
        }
        let elementType: TypeID
        switch typeArg {
        case let .invariant(type), let .out(type), let .in(type):
            elementType = type
        case .star:
            return nil
        }
        switch memberName {
        case "contains":
            if elementType == sema.types.longType {
                return interner.intern("kk_long_range_contains")
            }
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_contains")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_contains")
            }
            return nil
        case "isEmpty":
            if elementType == sema.types.longType {
                return interner.intern("kk_long_range_isEmpty")
            }
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_isEmpty")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_isEmpty")
            }
            return nil
        default:
            return nil
        }
    }
}
