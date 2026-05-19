// swiftlint:disable file_length
import Foundation

/// Member-call argument normalization and instruction emission helpers.
extension CallLowerer {
    func tryFoldConstMemberProperty(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        requireNonNullableReceiver: Bool,
        sema: SemaModule,
        arena: KIRArena,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let callBinding = sema.bindings.callBindings[exprID]
        guard let chosen = callBinding?.chosenCallee,
              let symInfo = sema.symbols.symbol(chosen),
              symInfo.flags.contains(.constValue)
        else {
            return nil
        }
        let constant = propertyConstantInitializers[chosen] ?? sema.symbols.constValueExprKind(for: chosen)
        guard let constant else { return nil }
        if requireNonNullableReceiver {
            guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                  receiverType == sema.types.makeNonNullable(receiverType)
            else {
                return nil
            }
        }
        let boundType = sema.bindings.exprTypes[exprID]
        let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
        instructions.append(.constValue(result: id, value: constant))
        return id
    }

    func shouldLowerPrimitiveInv(
        receiverExpr: ExprID,
        sema: SemaModule,
        nullableReceiverAllowed: Bool
    ) -> Bool {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
        let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType || receiverType == uintType || receiverType == ulongType || receiverType == ubyteType || receiverType == ushortType
    }

    func appendReceiverToMemberArguments(
        _ loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        chosenCallee: SymbolID?,
        prependReceiverForUnresolvedCollectionCall: Bool,
        sema: SemaModule,
        interner: StringInterner,
        arguments: inout [KIRExprID]
    ) {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let calleeText = interner.resolve(calleeName)
        if sema.bindings.isRangeExpr(receiverExpr) {
            let rangeMembers: Set<String> = [
                "first", "last", "endExclusive", "step", "contains", "isEmpty", "sum", "count",
                "toList", "forEach", "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot", "reduce", "reduceIndexed",
                "fold", "foldIndexed", "find", "findLast", "firstOrNull",
                "lastOrNull", "any", "all", "none", "chunked", "windowed",
                "reversed",
                "take", "drop", "average", "sorted",
                "random",
            ]
            if rangeMembers.contains(calleeText) {
                arguments.insert(loweredReceiverID, at: 0)
                return
            }
        }
        if let chosenCallee,
           let signature = sema.symbols.functionSignature(for: chosenCallee),
           signature.receiverType != nil
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        guard chosenCallee == nil,
              prependReceiverForUnresolvedCollectionCall
        else {
            return
        }
        if Self.unresolvedCollectionMemberNames.contains(calleeText) {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // String.length: extension needs receiver even when chosenCallee is nil
        // (e.g. mapIndexed { _, v -> v.length } where type inference may not bind).
        // Always prepend receiver for "length" — codegen maps to kk_string_length when
        // receiver is String; other types would be a type error at use site.
        if calleeText == "length" {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let isCoroutineHandleReceiver = isCoroutineHandleReceiverType(
            receiverType,
            sema: sema,
            interner: interner
        )
        if isCoroutineHandleReceiver,
           Self.unresolvedCoroutineHandleMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let isChannelReceiver = isChannelReceiverType(
            receiverType,
            sema: sema,
            interner: interner
        )
        if isChannelReceiver,
           Self.unresolvedChannelMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // removeFirst/removeLast are scoped to ArrayDeque receivers only;
        // they must NOT go through the general unresolvedCollectionMemberNames
        // path because MutableList also has these methods and would get
        // incorrect callee mapping.
        if (calleeText == "removeFirst" || calleeText == "removeLast"),
           isArrayDequeLikeType(receiverType, sema: sema, interner: interner)
        {
            arguments.insert(loweredReceiverID, at: 0)
        }
    }

    func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiver: MemberCallReceiver,
        result: KIRExprID,
        isSuperCall: Bool,
        qualifiedSuperType: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: [KIRExprID],
        sourceArgExprs: [ExprID] = [],
        sourceArgLabels: [InternedString?] = []
    ) {
        var finalArguments = arguments
        let hasHOFLambdaArg = sourceArgExprs.contains { sema.bindings.isCollectionHOFLambdaExpr($0) }
        if normalized.defaultMask != 0,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName == "kk_list_joinToString"
            || externalLinkName == "kk_iterable_joinTo"
            || externalLinkName == "kk_iterable_joinToString"
        {
            materializeJoinToStringDefaultArguments(
                normalized.defaultMask,
                firstDefaultParameterIndex: externalLinkName == "kk_iterable_joinTo" ? 1 : 0,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           let chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true
        {
            appendReifiedTypeTokens(
                chosenCallee: chosenCallee,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            appendDefaultMaskArgument(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosenCallee)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            ))
            return
        }

        appendReifiedTypeTokens(
            chosenCallee: chosenCallee,
            callBinding: callBinding,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions,
            arguments: &finalArguments
        )

        var loweredCallee = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiver.expr,
            argumentCount: finalArguments.count,
            sourceArgumentCount: sourceArgExprs.count,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        )
        if loweredCallee == interner.intern("kk_random_nextLong_until"),
           sourceArgExprs.count == 1,
           sema.bindings.isRangeExpr(sourceArgExprs[0])
        {
            loweredCallee = interner.intern("kk_random_nextLong_rangeObject")
        }
        if loweredCallee == interner.intern("kk_random_nextInt_until"),
           sourceArgExprs.count == 1,
           (sema.bindings.isRangeExpr(sourceArgExprs[0])
            || nominalRangeElementType(
                for: sema.bindings.exprTypes[sourceArgExprs[0]] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            ) == sema.types.intType)
        {
            loweredCallee = interner.intern("kk_random_nextInt_rangeObject")
        }
        if loweredCallee == interner.intern("kk_worker_execute"),
           finalArguments.count == 4,
           sourceArgExprs.count == 3
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[3],
                argExprID: sourceArgExprs[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1]] + producerArgs + jobArgs
        }
        if loweredCallee == interner.intern("kk_list_binarySearch_comparator") {
            materializeBinarySearchDefaultArguments(
                normalized.defaultMask,
                receiverExpr: receiver.expr,
                loweredReceiverID: receiver.loweredID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments,
                sourceArgLabels: sourceArgLabels
            )
        }
        if loweredCallee == interner.intern("kk_list_first"),
           finalArguments.count == 1
        {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            finalArguments.append(zeroExpr)
            finalArguments.append(zeroExpr)
        }
        if let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: sourceArgExprs.first, sema: sema),
           finalArguments.count >= 3
        {
            switch loweredCallee {
            case interner.intern("kk_mutable_list_sortBy"):
                loweredCallee = interner.intern("kk_mutable_list_sortBy_primitive")
            case interner.intern("kk_mutable_list_sortByDescending"):
                loweredCallee = interner.intern("kk_mutable_list_sortByDescending_primitive")
            default:
                break
            }
            if loweredCallee == interner.intern("kk_mutable_list_sortBy_primitive")
                || loweredCallee == interner.intern("kk_mutable_list_sortByDescending_primitive")
            {
                let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                finalArguments.append(kindExpr)
            }
        }
        finalArguments = adaptComparatorBackedCollectionArguments(
            loweredCallee: loweredCallee,
            finalArguments: finalArguments,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if (loweredCallee == interner.intern("kk_comparator_then_by_comparator_selector")
            || loweredCallee == interner.intern("kk_comparator_then_by_descending_comparator_selector")),
           finalArguments.count == 3,
           sourceArgExprs.count == 2,
           let primaryComparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: receiver.expr,
               loweredComparatorID: finalArguments[0],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            let (selectorFnExpr, selectorEnvExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = primaryComparatorArgs + [finalArguments[1], selectorFnExpr, selectorEnvExpr]
        }
        if normalized.defaultMask != 0,
           loweredCallee == interner.intern("kk_array_binarySearch_compare")
        {
            materializeArrayBinarySearchDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           loweredCallee == interner.intern("kk_array_copyInto")
        {
            materializeArrayCopyIntoDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if loweredCallee == interner.intern("kk_list_windowed_transform") {
            let originalArgumentCount = finalArguments.count
            if originalArgumentCount >= 3 {
                let lambdaArgIndex = originalArgumentCount - 1
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    finalArguments[lambdaArgIndex],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArguments[lambdaArgIndex] = fnPtrExpr
                finalArguments.append(envPtrExpr)
            }
            if originalArgumentCount == 3 {
                // `windowed(size, transform)` expands to `windowed(size, 1, false, transform)`.
                let oneExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(oneExpr, at: 2)
                finalArguments.insert(zeroExpr, at: 3)
            } else if originalArgumentCount == 4 {
                // `windowed(size, step, transform)` expands to
                // `windowed(size, step, false, transform)`.
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(zeroExpr, at: 3)
            }
        }
        if loweredCallee == interner.intern("kk_sequence_windowed_transform")
            || (loweredCallee == interner.intern("kk_sequence_windowed") && hasHOFLambdaArg)
        {
            loweredCallee = interner.intern("kk_sequence_windowed_transform")
            let originalArgumentCount = finalArguments.count
            if originalArgumentCount >= 3 {
                let lambdaArgIndex = originalArgumentCount - 1
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    finalArguments[lambdaArgIndex],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArguments[lambdaArgIndex] = fnPtrExpr
                finalArguments.append(envPtrExpr)
            }
            if originalArgumentCount == 3 {
                // `windowed(size, transform)` expands to `windowed(size, 1, false, transform)`.
                let oneExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(oneExpr, at: 2)
                finalArguments.insert(zeroExpr, at: 3)
            } else if originalArgumentCount == 4 {
                // `windowed(size, step, transform)` expands to
                // `windowed(size, step, false, transform)`.
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(zeroExpr, at: 3)
            }
        }
        if loweredCallee == interner.intern("kk_sequence_chunked"),
           hasHOFLambdaArg,
           finalArguments.count == 3
        {
            loweredCallee = interner.intern("kk_sequence_chunked_transform")
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments[2] = fnPtrExpr
            finalArguments.append(envPtrExpr)
        }
        if (loweredCallee == interner.intern("kk_sequence_firstNotNullOf")
            || loweredCallee == interner.intern("kk_sequence_firstNotNullOfOrNull")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if loweredCallee == interner.intern("kk_sequence_filterTo")
            || loweredCallee == interner.intern("kk_sequence_filterNotTo")
            || loweredCallee == interner.intern("kk_sequence_mapNotNullTo")
            || loweredCallee == interner.intern("kk_sequence_mapTo")
        {
            if finalArguments.count == 2 {
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    finalArguments[1],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArguments = [receiver.loweredID, finalArguments[0], fnPtrExpr, envPtrExpr]
            } else if finalArguments.count == 3, finalArguments[0] == receiver.loweredID {
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    finalArguments[2],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArguments = [finalArguments[0], finalArguments[1], fnPtrExpr, envPtrExpr]
            } else if finalArguments.count == 3 {
                finalArguments = [receiver.loweredID] + finalArguments
            }
        }
        if (loweredCallee == interner.intern("kk_iterable_firstNotNullOf")
            || loweredCallee == interner.intern("kk_iterable_firstNotNullOfOrNull")
            || loweredCallee == interner.intern("kk_iterable_any")
            || loweredCallee == interner.intern("kk_iterable_all")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if (loweredCallee == interner.intern("kk_list_sumOf")
            || loweredCallee == interner.intern("kk_list_sumBy")
            || loweredCallee == interner.intern("kk_list_sumByDouble")
            || loweredCallee == interner.intern("kk_sequence_sumBy")
            || loweredCallee == interner.intern("kk_sequence_sumByDouble")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if (loweredCallee == interner.intern("kk_sequence_associateTo")
            || loweredCallee == interner.intern("kk_sequence_associateByTo")
            || loweredCallee == interner.intern("kk_sequence_associateWithTo")
            || loweredCallee == interner.intern("kk_sequence_groupByTo")),
           finalArguments.count == 3
        {
            let firstArg = finalArguments[1]
            let secondArg = finalArguments[2]
            let lambdaArg: KIRExprID
            let destinationArg: KIRExprID
            if driver.ctx.callableValueInfo(for: firstArg) != nil {
                lambdaArg = firstArg
                destinationArg = secondArg
            } else {
                destinationArg = firstArg
                lambdaArg = secondArg
            }
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                lambdaArg,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], destinationArg, fnPtrExpr, envPtrExpr]
        }
        if loweredCallee == interner.intern("kk_array_copyOf_newSize_init"),
           finalArguments.count == 3
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1], fnPtrExpr, envPtrExpr]
        }
        if let primitiveKind = collectionElementPrimitiveCompareKind(
            of: sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType,
            sema: sema
        ) {
            let primitiveSortCallees: Set<InternedString> = [
                interner.intern("kk_list_sorted_primitive"),
                interner.intern("kk_list_sortedDescending_primitive"),
                interner.intern("kk_mutable_list_sort_primitive"),
                interner.intern("kk_mutable_list_sortDescending_primitive"),
            ]
            if primitiveSortCallees.contains(loweredCallee),
               finalArguments.count == 1
            {
                let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveKind.rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveKind.rawValue))))
                finalArguments.append(kindExpr)
            }
        }
        if isArrayBinarySearchRuntimeCallee(loweredCallee, interner: interner) {
            let receiverType = sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
            let sizeRuntimeCallee = arraySizeRuntimeCallee(
                for: receiverType,
                sema: sema,
                interner: interner
            )
            let memberArgumentCount = finalArguments.count - 1
            if memberArgumentCount == 1 || memberArgumentCount == 2 {
                let sizeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: sizeRuntimeCallee,
                    arguments: [receiver.loweredID],
                    result: sizeExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                if memberArgumentCount == 1 {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    finalArguments.append(zeroExpr)
                }
                finalArguments.append(sizeExpr)
            }
        }
        let comparatorOnlyCallees: Set<InternedString> = [
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_maxWithOrNull"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_minWithOrNull"),
            interner.intern("kk_list_sortedWith"),
            interner.intern("kk_array_sortedArrayWith"),
        ]
        if comparatorOnlyCallees.contains(loweredCallee),
           finalArguments.count == 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: nil,
               loweredComparatorID: finalArguments[1],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            finalArguments = [finalArguments[0]] + comparatorArgs
        }
        if loweredCallee == interner.intern("kk_channel_send")
            || loweredCallee == interner.intern("kk_channel_receive")
            || loweredCallee == interner.intern("kk_mutex_lock")
            || loweredCallee == interner.intern("kk_semaphore_acquire")
        {
            let continuationExpr = arena.appendExpr(
                .intLiteral(0),
                type: sema.types.intType
            )
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments.append(continuationExpr)
        }
        // kk_mutex_withLock(handle, actionFnPtr, actionEnvPtr, continuation): split the lambda
        // argument at index 1 into a function pointer and environment pointer,
        // following the standard closure-conversion ABI used by collection HOFs.
        // A zero continuation placeholder is appended as the 4th argument because the
        // current runtime path blocks on contention and keeps the ABI shape aligned
        // with the suspend-aware mutex entry point.
        if loweredCallee == interner.intern("kk_mutex_withLock"),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let continuationExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr, continuationExpr]
        }
        // kk_lock_withLock(handle, actionFnPtr, actionEnvPtr),
        // kk_read_write_lock_read(handle, actionFnPtr, actionEnvPtr), and
        // kk_read_write_lock_write(handle, actionFnPtr, actionEnvPtr): split the
        // lambda argument at index 1 into a function pointer and environment pointer.
        if loweredCallee == interner.intern("kk_lock_withLock")
            || loweredCallee == interner.intern("kk_read_write_lock_read")
            || loweredCallee == interner.intern("kk_read_write_lock_write"),
           finalArguments.count == 2
        {
            let lambdaID = finalArguments[1]
            let fnPtrExpr: KIRExprID
            let envPtrExpr: KIRExprID
            if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID) {
                fnPtrExpr = arena.appendExpr(
                    .symbolRef(callableInfo.symbol),
                    type: sema.types.anyType
                )
                instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
                if callableInfo.captureArguments.count >= 2 {
                    // Multi-capture: pack captures into a closure object.
                    // The lambda has been generated to unpack them via kk_array_get_inbounds.
                    let intType = sema.types.intType
                    let anyType = sema.types.anyType
                    let kkObjectNew = interner.intern("kk_object_new")
                    let kkArraySet = interner.intern("kk_array_set")
                    let slotCount = Int64(2 + callableInfo.captureArguments.count)
                    let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                    instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
                    let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
                    let closureObjExpr = arena.appendExpr(
                        .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkObjectNew,
                        arguments: [slotCountExpr, classIDExpr],
                        result: closureObjExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                        let fieldOffset = Int64(captureIndex + 2)
                        let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                        let unusedResult = arena.appendExpr(
                            .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: kkArraySet,
                            arguments: [closureObjExpr, offsetExpr, captureArg],
                            result: unusedResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    envPtrExpr = closureObjExpr
                } else if let closureRaw = callableInfo.captureArguments.first {
                    envPtrExpr = closureRaw
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    envPtrExpr = zeroExpr
                }
            } else {
                // Fallback when callableValueInfo is unavailable (e.g. stored lambda /
                // function reference): treat lambdaID as the function pointer and pass
                // zero as the environment pointer so the argument count always matches
                // the 3-parameter ABI (handle, actionFnPtr, actionEnvPtr).
                fnPtrExpr = lambdaID
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                envPtrExpr = zeroExpr
            }
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        // ReentrantReadWriteLock.read(handle, actionFnPtr, actionEnvPtr): split the lambda in
        // the same way as kk_mutex_withLock, but leave the continuation out because the call
        // is synchronous and throw-only.
        if loweredCallee == interner.intern("kk_reentrant_read_write_lock_read"),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        // Skip virtual dispatch when loweredMemberCalleeName remapped the callee
        // to a concrete runtime function (e.g. iterator → kk_list_iterator).
        // Virtual dispatch is only correct when no remapping occurred.
        if loweredCallee == calleeName,
           let inst = tryEmitVirtualDispatch(
               chosenCallee: chosenCallee, calleeName: loweredCallee,
               receiverExpr: receiver.expr, loweredReceiverID: receiver.loweredID,
               isSuperCall: isSuperCall, finalArguments: finalArguments,
               result: result, sema: sema
           )
        {
            instructions.append(inst)
            return
        }
        var callArguments = finalArguments
        if loweredCallee == interner.intern("kk_system_currentTimeMillis")
            || loweredCallee == interner.intern("kk_system_nanoTime")
            || loweredCallee == interner.intern("kk_system_process_start_nanos")
            || loweredCallee == interner.intern("kk_system_gc")
            || loweredCallee == interner.intern("kk_runtime_getRuntime")
            || loweredCallee == interner.intern("kk_runtime_totalMemory")
            || loweredCallee == interner.intern("kk_runtime_freeMemory")
            || loweredCallee == interner.intern("kk_runtime_maxMemory")
            || loweredCallee == interner.intern("kk_instant_now")
            || loweredCallee == interner.intern("kk_clock_system_now") {
            callArguments = []
        }
        // Result HOF functions accept an outThrown parameter but we don't need
        // the codegen to generate conditional thrown-check branches. Instead,
        // append a zero (null) pointer argument so the runtime receives the
        // expected parameter count, and keep canThrow=false to avoid control-
        // flow complexity.
        let resultHOFCallees: Set = [
            interner.intern("kk_result_onSuccess"),
            interner.intern("kk_result_onFailure"),
            interner.intern("kk_result_getOrElse"),
            interner.intern("kk_result_map"),
            interner.intern("kk_result_fold"),
            interner.intern("kk_result_recover"),
            interner.intern("kk_result_recoverCatching"),
            interner.intern("kk_result_mapCatching"),
            interner.intern("kk_result_flatMap"),
            interner.intern("kk_result_flatMapCatching"),
        ]
        if resultHOFCallees.contains(loweredCallee) {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            callArguments.append(zeroExpr)
        }
        let throwingCallees = Self.throwingMemberCalleeNames(interner: interner)
        let canThrow = throwingCallees.contains(loweredCallee)
        instructions.append(.call(
            symbol: chosenCallee,
            callee: loweredCallee,
            arguments: callArguments,
            result: result,
            canThrow: canThrow,
            thrownResult: nil,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType
        ))
    }

    /// Cached set of runtime callee names whose `.call` should be emitted
    /// with `canThrow: true`. Hoisted from per-call `interner.intern()`
    /// invocations to avoid repeated interning in the hot lowering path.
    private static func throwingMemberCalleeNames(interner: StringInterner) -> Set<InternedString> {
        Set([
            interner.intern("kk_base64_decode_default"),
            interner.intern("kk_base64_decode_urlsafe"),
            interner.intern("kk_base64_decode_mime"),
            interner.intern("kk_base64_decodeFromByteArray_default"),
            interner.intern("kk_base64_decodeFromByteArray_urlsafe"),
            interner.intern("kk_base64_decodeFromByteArray_mime"),
            interner.intern("kk_base64_decode_instance"),
            interner.intern("kk_base64_decodeFromByteArray_instance"),
            interner.intern("kk_list_random"),
            interner.intern("kk_list_elementAt"),
            interner.intern("kk_list_take"),
            interner.intern("kk_list_takeLast"),
            interner.intern("kk_sequence_takeLast"),
            interner.intern("kk_list_drop"),
            interner.intern("kk_list_max"),
            interner.intern("kk_list_minBy"),
            interner.intern("kk_list_min"),
            interner.intern("kk_list_maxOf"),
            interner.intern("kk_list_minOf"),
            interner.intern("kk_list_maxBy"),
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_maxOfWith"),
            interner.intern("kk_list_minOfWith"),
            interner.intern("kk_list_fold"),
            interner.intern("kk_list_foldRight"),
            interner.intern("kk_list_reduce"),
            interner.intern("kk_list_reduceRight"),
            interner.intern("kk_list_reduceRightIndexed"),
            interner.intern("kk_list_reduceRightIndexedOrNull"),
            interner.intern("kk_list_reduceRightOrNull"),
            interner.intern("kk_list_reduceOrNull"),
            interner.intern("kk_list_scan"),
            interner.intern("kk_list_runningFold"),
            interner.intern("kk_list_runningReduce"),
            interner.intern("kk_list_scanReduce"),
            interner.intern("kk_list_filterIndexed"),
            interner.intern("kk_list_foldIndexed"),
            interner.intern("kk_list_foldRightIndexed"),
            interner.intern("kk_list_reduceIndexed"),
            interner.intern("kk_list_reduceIndexedOrNull"),
            interner.intern("kk_list_runningFoldIndexed"),
            interner.intern("kk_list_runningReduceIndexed"),
            interner.intern("kk_list_scanIndexed"),
            interner.intern("kk_list_sumOf"),
            interner.intern("kk_list_sumBy"),
            interner.intern("kk_list_sumByDouble"),
            interner.intern("kk_list_distinctBy"),
            interner.intern("kk_list_takeWhile"),
            interner.intern("kk_list_dropLastWhile"),
            interner.intern("kk_iterable_firstNotNullOf"),
            interner.intern("kk_iterable_firstNotNullOfOrNull"),
            interner.intern("kk_iterable_any"),
            interner.intern("kk_iterable_all"),
            interner.intern("kk_iterable_requireNoNulls"),
            interner.intern("kk_kclass_cast"),
            interner.intern("kk_range_first_predicate"),
            interner.intern("kk_range_last_predicate"),
            interner.intern("kk_range_random"),
            interner.intern("kk_range_random_random"),
            interner.intern("kk_random_nextInt_rangeObject"),
            interner.intern("kk_range_reduce"),
            interner.intern("kk_range_reduceIndexed"),
            interner.intern("kk_long_range_random"),
            interner.intern("kk_long_range_random_random"),
            interner.intern("kk_uint_range_random"),
            interner.intern("kk_uint_range_random_random"),
            interner.intern("kk_ulong_range_random"),
            interner.intern("kk_ulong_range_random_random"),
            interner.intern("kk_int_progression_fromClosedRange"),
            interner.intern("kk_long_progression_fromClosedRange"),
            interner.intern("kk_uint_progression_fromClosedRange"),
            interner.intern("kk_ulong_progression_fromClosedRange"),
            interner.intern("kk_sequence_foldIndexed"),
            interner.intern("kk_sequence_reduceIndexed"),
            interner.intern("kk_sequence_reduceIndexedOrNull"),
            interner.intern("kk_long_range_random"),
            interner.intern("kk_random_nextLong_rangeObject"),
            interner.intern("kk_uint_range_random"),
            interner.intern("kk_ulong_range_random"),
            interner.intern("kk_sequence_runningReduceIndexed"),
            interner.intern("kk_sequence_sortedBy"),
            interner.intern("kk_sequence_sumOf"),
            interner.intern("kk_sequence_sumBy"),
            interner.intern("kk_sequence_sumByDouble"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_associate"),
            interner.intern("kk_sequence_associateBy"),
            interner.intern("kk_sequence_associateTo"),
            interner.intern("kk_sequence_associateByTo"),
            interner.intern("kk_map_getValue"),
            interner.intern("kk_map_mapKeysTo"),
            interner.intern("kk_map_mapValuesTo"),
            interner.intern("kk_sequence_mapNotNull"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_mapIndexed"),
            interner.intern("kk_sequence_filterIndexed"),
            interner.intern("kk_sequence_findLast"),
            interner.intern("kk_sequence_elementAt"),
            interner.intern("kk_sequence_minByOrNull"),
            interner.intern("kk_sequence_maxByOrNull"),
            interner.intern("kk_sequence_minOf"),
            interner.intern("kk_sequence_maxOfOrNull"),
            interner.intern("kk_sequence_maxOf"),
            interner.intern("kk_sequence_partition"),
            interner.intern("kk_sequence_associateWith"),
            interner.intern("kk_sequence_associateWithTo"),
            interner.intern("kk_sequence_groupByTo"),
            interner.intern("kk_sequence_ifEmpty"),
            interner.intern("kk_string_ifBlank"),
            interner.intern("kk_string_ifEmpty"),
            interner.intern("kk_string_chunked_sequence_transform"),
            interner.intern("kk_sequence_first"),
            interner.intern("kk_sequence_last"),
            interner.intern("kk_sequence_firstOrNull"),
            interner.intern("kk_sequence_singleOrNull"),
            interner.intern("kk_sequence_randomOrNull"),
            interner.intern("kk_sequence_count"),
            interner.intern("kk_string_firstNotNullOf"),
            interner.intern("kk_string_firstNotNullOfOrNull"),
            interner.intern("kk_string_reduceRightIndexed"),
            interner.intern("kk_string_reduceRightIndexedOrNull"),
            interner.intern("kk_string_reduceRightOrNull"),
            interner.intern("kk_string_sumBy"),
            interner.intern("kk_string_sumByDouble"),
            interner.intern("kk_string_zipWithNextTransform"),
            interner.intern("kk_string_chunked_sequence_transform"),
            interner.intern("kk_string_windowedSequence_transform"),
            interner.intern("kk_sequence_to_list"),
            interner.intern("kk_list_windowed_transform"),
            interner.intern("kk_sequence_chunked_transform"),
            interner.intern("kk_sequence_runningFoldIndexed"),
            interner.intern("kk_sequence_scanIndexed"),
            interner.intern("kk_array_copyOf_newSize_init"),
            interner.intern("kk_mutable_list_replaceAll"),
            interner.intern("kk_mutable_list_removeIf"),
            interner.intern("kk_list_binarySearch_compare"),
            interner.intern("kk_list_binarySearch_comparator"),
            interner.intern("kk_array_binarySearch_compare"),
            interner.intern("kk_array_sortedArrayWith"),
            interner.intern("kk_list_binarySearchBy"),
            interner.intern("kk_list_binarySearchBy_fromIndex"),
            interner.intern("kk_list_binarySearchBy_range"),
            interner.intern("kk_result_getOrThrow"),
            interner.intern("kk_reentrant_read_write_lock_read"),
        ])
    }

    func splitCallableLambdaArgument(
        _ lambdaID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (fnPtrExpr: KIRExprID, envPtrExpr: KIRExprID) {
        let fnPtrExpr: KIRExprID
        let envPtrExpr: KIRExprID
        if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID) {
            fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            if callableInfo.captureArguments.count >= 2 {
                // Multi-capture: pack captures into a closure object.
                let intType = sema.types.intType
                let anyType = sema.types.anyType
                let kkObjectNew = interner.intern("kk_object_new")
                let kkArraySet = interner.intern("kk_array_set")
                let slotCount = Int64(2 + callableInfo.captureArguments.count)
                let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
                let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
                let closureObjExpr = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: kkObjectNew,
                    arguments: [slotCountExpr, classIDExpr],
                    result: closureObjExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                    let fieldOffset = Int64(captureIndex + 2)
                    let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                    let unusedResult = arena.appendExpr(
                        .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkArraySet,
                        arguments: [closureObjExpr, offsetExpr, captureArg],
                        result: unusedResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                envPtrExpr = closureObjExpr
            } else if let closureRaw = callableInfo.captureArguments.first {
                envPtrExpr = closureRaw
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                envPtrExpr = zeroExpr
            }
        } else {
            // Fallback when callableValueInfo is unavailable (e.g. stored lambda /
            // function reference): treat lambdaID as the function pointer and pass
            // zero as the environment pointer so the argument count always matches
            // the closure-conversion ABI.
            fnPtrExpr = lambdaID
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            envPtrExpr = zeroExpr
        }
        return (fnPtrExpr, envPtrExpr)
    }
}
