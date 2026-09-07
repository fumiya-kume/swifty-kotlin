// swiftlint:disable file_length

/// Default-argument materialization and runtime callee resolution helpers.
extension CallLowerer {
    /// Returns the default mask for the three string parameters of the
    /// source-backed Iterable.joinToString overload.
    ///
    /// Safe-call collection fallback can lose the declaration's default-value
    /// metadata, so the generic argument normalizer may leave raw null
    /// sentinels in the call. Recover the omitted parameters from the source
    /// labels before emitting the source-backed call.
    func joinToStringDefaultMask(
        sourceArguments: [CallArgument],
        interner: StringInterner
    ) -> Int64 {
        let parameterNames = ["separator", "prefix", "postfix"]
        var suppliedParameters = Set<Int>()
        var nextPositionalParameter = 0

        for argument in sourceArguments {
            if let label = argument.label,
               let parameterIndex = parameterNames.firstIndex(of: interner.resolve(label))
            {
                suppliedParameters.insert(parameterIndex)
                continue
            }

            while suppliedParameters.contains(nextPositionalParameter) {
                nextPositionalParameter += 1
            }
            guard nextPositionalParameter < parameterNames.count else {
                continue
            }
            suppliedParameters.insert(nextPositionalParameter)
            nextPositionalParameter += 1
        }

        var defaultMask: Int64 = 0
        for parameterIndex in parameterNames.indices where !suppliedParameters.contains(parameterIndex) {
            defaultMask |= Int64(1) << parameterIndex
        }
        return defaultMask
    }

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


    // KSP-423: preserve the Kotlin defaults when a named range argument skips fromIndex.
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
            ) ?? interner.intern("__kk_list_size")
            let sizeExpr = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: sizeCallee,
                arg: loweredReceiverID,
                result: sizeExpr,
                into: &instructions
            )
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

    /// STDLIB-CINTEROP-FN-029: ByteArray.toKString(startIndex = 0, endIndex = size,
    /// throwOnInvalidSequence = false). The generic default-argument filler
    /// (`CallSupportLowerer.normalizedCallArguments`) substitutes an `0` sentinel
    /// for every omitted parameter, which is only correct for `startIndex` and
    /// `throwOnInvalidSequence` here — `endIndex` must default to the receiver's
    /// size, not `0`.
    func materializeByteArrayToKStringDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard arguments.count >= 4 else {
            return
        }

        let endIndexMaskBit = Int64(1) << 1
        guard (defaultMask & endIndexMaskBit) != 0 else {
            return
        }
        let intType = sema.types.intType
        let sizeExpr = arena.appendTemporary(type: intType)
        emitNonThrowingCall(
            callee: interner.intern("__kk_array_size"),
            arg: arguments[0],
            result: sizeExpr,
            into: &instructions
        )
        arguments[2] = sizeExpr
    }

    /// Resolve inherited Iterator methods through their real interface owner when
    /// the receiver is statically typed as a source-backed ListIterator.
    func listIteratorInheritedDispatchCallee(
        receiverType: TypeID?,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let receiverType,
              isExactListIteratorReceiverType(receiverType, sema: sema, interner: interner),
              calleeName == interner.intern("hasNext") || calleeName == interner.intern("next")
        else {
            return nil
        }
        return sema.symbols.lookup(
            fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterator"),
                calleeName,
            ]
        )
    }

    /// KSP-611: a member of an interface imported from a compiled library carries the
    /// link name of the body emitted for it in that library. For an abstract member that
    /// body is an empty stub, so honouring the link name would silently call nothing;
    /// interface members must dispatch through the receiver's itable instead. A
    /// source-backed interface declaration may instead carry a private runtime bridge
    /// such as `__kk_string_builder_append_obj`; that link is the actual implementation
    /// and must stay on direct dispatch, just like a synthetic runtime bridge.
    func isImportedInterfaceMember(_ callee: SymbolID, sema: SemaModule) -> Bool {
        guard let calleeSymbol = sema.symbols.symbol(callee),
              calleeSymbol.flags.contains(.importedLibrary),
              let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID)
        else { return false }
        return parentSymbol.kind == .interface
            && Self.isSourceBackedLinkName(sema.symbols.externalLinkName(for: callee))
    }

    /// Callees bridged to a C runtime function (such as kk_array_get) are
    /// normally not dispatched virtually; see `kirIsRuntimeBridgedCallee`.
    func tryEmitVirtualDispatch(
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiverExpr: ExprID?,
        loweredReceiverID: KIRExprID,
        isSuperCall: Bool,
        finalArguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> KIRInstruction? {
        guard !isSuperCall, let chosenCallee else { return nil }
        let receiverTypeForDispatch: TypeID? = {
            if let receiverExpr {
                return sema.bindings.exprTypes[receiverExpr]
            }
            return arena.exprType(loweredReceiverID)
        }()
        let listIteratorInheritedDispatch = listIteratorInheritedDispatchCallee(
            receiverType: receiverTypeForDispatch,
            calleeName: calleeName,
            sema: sema,
            interner: interner
        )
        let dispatchCallee = listIteratorInheritedDispatch ?? chosenCallee
        // Runtime ABI bridges are receiver-type-agnostic entry points even
        // when their declarations are imported interface members. Dispatching
        // those symbols through an itable is invalid for the built-in runtime
        // collection boxes; only source-backed/internal links may use virtual
        // dispatch here. A source-backed ListIterator's inherited Iterator
        // methods are the deliberate exception because they must use the
        // implementation's inherited itable slots. Clock bridges are another
        // deliberate exception: their receiver is represented by a
        // runtime-backed virtual object.
        guard listIteratorInheritedDispatch != nil
            || !kirIsRuntimeBridgedCallee(chosenCallee, sema: sema)
            || isClockRuntimeVirtualBridge(chosenCallee, sema: sema)
        else { return nil }
        guard let dispatchKind = resolveVirtualDispatch(
            callee: dispatchCallee, receiverTypeID: receiverTypeForDispatch, sema: sema, interner: interner
        ) else { return nil }
        var vcArguments = finalArguments
        if let sig = sema.symbols.functionSignature(for: dispatchCallee),
           sig.receiverType != nil, !vcArguments.isEmpty
        {
            vcArguments.removeFirst()
        }
        return .virtualCall(
            symbol: dispatchCallee,
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
            if let setMember = runtimeBackedSetMemberCallee(
                memberName: fallbackName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) {
                return setMember
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               !externalLinkName.isEmpty
            {
                // A source-backed ListIterator can be implemented by user code.
                // Its inherited synthetic Iterator members must therefore use
                // the same dynamic itable path as the four source-backed members
                // instead of calling the runtime list-iterator bridge directly.
                if isExactListIteratorReceiverType(receiverType, sema: sema, interner: interner),
                   let parentSymbol = sema.symbols.parentSymbol(for: chosenCallee)
                       .flatMap(sema.symbols.symbol),
                   (parentSymbol.fqName.map(interner.resolve) == ["kotlin", "collections", "Iterator"]
                       || parentSymbol.fqName.map(interner.resolve) == ["kotlin", "collections", "ListIterator"]),
                   fallbackName == "hasNext" || fallbackName == "next"
                {
                    return fallback
                }
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
                // Collection.size is source-declared but runtime-backed. When
                // it is inherited by a concrete List/Set/EnumEntries receiver,
                // retain the receiver-specific bridge instead of letting the
                // Collection declaration's generic link erase the nominal kind.
                if fallbackName == "size",
                   let ownerID = sema.symbols.parentSymbol(for: chosenCallee),
                   let owner = sema.symbols.symbol(ownerID),
                   owner.fqName == [
                       interner.intern("kotlin"),
                       interner.intern("collections"),
                       interner.intern("Collection"),
                   ],
                   let collectionSize = unresolvedCollectionMemberCallee(
                       memberName: fallbackName,
                       receiverType: receiverType,
                       sema: sema,
                       interner: interner
                   )
                {
                    return collectionSize
                }
                if let collectionProperty = unresolvedCollectionMemberCallee(
                    memberName: fallbackName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ) {
                    return collectionProperty
                }
                return interner.intern(externalLinkName)
            }
            if sema.symbols.isSourceBackedSymbol(chosenCallee) {
                // Source-backed stdlib migrations lower through the chosen symbol's internal function.
                return fallback
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
            // KSP-678: close / isClosedForReceive / isClosedForSend are resolved
            // through bundled Kotlin source, not this synthetic fallback.
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
            sourceArgumentCount: callArgumentCount,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        ) {
            return unresolvedSynthetic
        }
        return fallback
    }

    private func isExactListIteratorReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.kind == .interface
            && symbol.fqName.map(interner.resolve) == ["kotlin", "collections", "ListIterator"]
    }

    func resultRuntimeHOFMemberCalleeName(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        guard isKotlinResultType(receiverType, sema: sema, interner: interner) else {
            return nil
        }
        switch memberName {
        case "getOrElse":
            return "kk_result_getOrElse"
        case "map":
            return "kk_result_map"
        case "fold":
            return "kk_result_fold"
        case "onSuccess":
            return "kk_result_onSuccess"
        case "onFailure":
            return "kk_result_onFailure"
        case "recover":
            return "kk_result_recover"
        case "recoverCatching":
            return "kk_result_recoverCatching"
        default:
            return nil
        }
    }

    func isKotlinResultType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName.map(interner.resolve) == ["kotlin", "Result"]
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
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_contains")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_contains")
            }
            return interner.intern("__kk_range_contains")
        case "isEmpty":
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_isEmpty")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_isEmpty")
            }
            return interner.intern("__kk_range_isEmpty")
        default:
            return nil
        }
    }
}
