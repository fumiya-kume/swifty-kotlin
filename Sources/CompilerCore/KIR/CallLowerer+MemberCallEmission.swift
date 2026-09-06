// swiftlint:disable file_length

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
        let byteType = sema.types.byteType
        let shortType = sema.types.shortType
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType || receiverType == uintType || receiverType == ulongType || receiverType == ubyteType || receiverType == ushortType || receiverType == byteType || receiverType == shortType
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
        // Always prepend receiver for "length"; codegen extracts the aggregate length
        // field when the receiver is String. Other types would be a type error at use site.
        if calleeText == "length" {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // Enum.name / Enum.ordinal are source-backed properties whose values are
        // still materialized by compiler-owned per-enum helpers. When an older or
        // source-less stdlib surface leaves the property unresolved, prepend the
        // receiver so EnumNameAccessLoweringPass's generic (arguments.count == 1)
        // rewrite can recover the same residual path. Gate on the receiver being
        // enum-typed so unrelated "name"/"ordinal" members remain unaffected.
        if calleeText == "name" || calleeText == "ordinal",
           let (_, classSym) = resolveClassTypeSymbol(receiverType, sema: sema),
           classSym.kind == .enumClass
        {
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
        if Self.unresolvedFlowMemberNames.contains(calleeText),
           isFlowReceiverType(receiverType, sema: sema, interner: interner)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
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
        // Enum values are raw ordinals while they remain statically enum-typed.
        // Enum.equals(Any?) is an Any-boundary call, so box the receiver with
        // its nominal class ID before reaching the shared Any bridge. Without
        // this, Direction.NORTH.equals(Color.RED) compares two bare ordinals
        // and incorrectly reports equality for matching entry positions.
        if finalArguments.first == receiver.loweredID,
           let chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_any_member_equals",
           let receiverType = sema.bindings.exprTypes[receiver.expr],
           let (receiverClassType, receiverClassSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
           receiverClassType.nullability == .nonNull,
           receiverClassSymbol.kind == .enumClass,
           !receiverClassSymbol.flags.contains(.synthetic)
        {
            let boxedReceiver = arena.appendTemporary(type: sema.types.anyType)
            emitEnumOrdinalBoxCall(
                ordinal: receiver.loweredID,
                classSymbol: receiverClassType.classSymbol,
                result: boxedReceiver,
                resultType: sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                into: &instructions
            )
            finalArguments[0] = boxedReceiver
        }
        let hasHOFLambdaArg = sourceArgExprs.contains { sema.bindings.isCollectionHOFLambdaExpr($0) }
        // Must run before the "$default" stub dispatch below (which returns
        // early): the stub forwards its own `transform`-shaped parameter
        // straight to the real source-backed function (e.g.
        // `Sequence.windowed(size, step = 1, partialWindows = false,
        // transform)`), which expects the normal wrapped function-value
        // convention. Without materializing here, a call like
        // `windowed(3) { it.sum() + bonus }` (defaults skipped, so this path
        // is taken) forwarded the lambda as a bare, unwrapped symbol
        // reference -- fine for a non-capturing lambda (closureRaw is unused
        // either way), but silently dropping any captured values (`bonus`)
        // for one that does capture, since nothing ever threaded the actual
        // closure environment through.
        materializeSourceBackedFunctionValueArguments(
            chosenCallee: chosenCallee,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: &finalArguments
        )
        if normalized.defaultMask != 0,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName.hasSuffix("_joinToString")
        {
            materializeJoinToStringDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           let chosenCallee,
           (sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true ||
            sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: chosenCallee)) != nil)
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

        let loweredCallee = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiver.expr,
            argumentCount: finalArguments.count,
            sourceArgumentCount: sourceArgExprs.count,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        )
        // BUG-049: `CoroutineScope.launch { block }` where `block` captures outer
        // variables. The receiver scope is finalArguments[0] and the suspend lambda
        // reference is finalArguments[1]; inject the lambda's captures after it so the
        // coroutine lowering can thread them through the continuation (mirrors the free
        // launch/withContext capture injection in CallLowerer).
        if loweredCallee == interner.intern("kk_coroutine_scope_launch"),
           finalArguments.count >= 2,
           let callableInfo = driver.ctx.callableValueInfo(for: finalArguments[1]),
           !callableInfo.captureArguments.isEmpty
        {
            finalArguments.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        // A source-backed HashSet declaration is only the semantic target. Its
        // runtime representation is a RuntimeSetBox, so a remapped set
        // operation must not retain the source symbol for NativeEmitter's
        // internal-function lookup; that would bypass the runtime ABI callee.
        let runtimeSetMemberCallee = runtimeBackedSetMemberCallee(
            memberName: interner.resolve(calleeName),
            receiverType: sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )
        let receiverType = sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
        let callSymbol: SymbolID? = runtimeSetMemberCallee.map { $0 == loweredCallee } == true
            && isSourceBackedHashSetType(receiverType, sema: sema, interner: interner)
            ? nil
            : chosenCallee
        // KSP-641: ClosedFloatingPointRange members are still compiler residuals,
        // so lower the concrete Double/Float overload directly to the range ABI.
        // The source-backed generic declaration remains available for overload
        // resolution, while this path preserves the stdlib's empty-range and NaN
        // behavior without dispatching synthetic range accessors through an
        // unpopulated itable.
        if interner.resolve(calleeName) == "coerceIn",
           sourceArgExprs.count == 1,
           sema.bindings.isFloatingPointRangeExpr(sourceArgExprs[0])
        {
            let receiverType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
            )
            let floatingRangeCallee: InternedString? = if receiverType == sema.types.floatType {
                interner.intern("__kk_float_coerceIn_range")
            } else if receiverType == sema.types.doubleType {
                interner.intern("__kk_double_coerceIn_range")
            } else {
                nil
            }
            if let floatingRangeCallee {
                var rangeArguments = finalArguments
                if rangeArguments.count == 1 {
                    rangeArguments.insert(receiver.loweredID, at: 0)
                }
                guard rangeArguments.count == 2 else {
                    preconditionFailure("KSP-641 range coerceIn must lower to receiver and range arguments")
                }
                let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: floatingRangeCallee,
                    arguments: rangeArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                let continueLabel = driver.ctx.makeLoopLabel()
                let rethrowLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
                return
            }
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
        let isComparatorBinarySearch: Bool = {
            guard loweredCallee == interner.intern("binarySearch"),
                  let chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                return false
            }
            return signature.parameterTypes.contains { parameterType in
                guard let (_, symbol) = resolveClassTypeSymbol(parameterType, sema: sema)
                else {
                    return false
                }
                return interner.resolve(symbol.name) == "Comparator"
            }
        }()
        if isComparatorBinarySearch {
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
        finalArguments = adaptComparatorBackedCollectionArguments(
            loweredCallee: loweredCallee,
            finalArguments: finalArguments,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if normalized.defaultMask != 0,
           loweredCallee == interner.intern("__kk_byteArray_toKString")
        {
            materializeByteArrayToKStringDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if loweredCallee == interner.intern("kk_list_zip_transform"),
           finalArguments.count == 3
        {
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
        let isStringRuntimeHOFCallee = switch interner.resolve(loweredCallee) {
        case "kk_string_indexOfFirst",
             "kk_string_indexOfLast":
            true
        default:
            false
        }
        if isStringRuntimeHOFCallee,
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
        if loweredCallee == interner.intern("kk_sequence_firstNotNullOf")
            || loweredCallee == interner.intern("kk_sequence_firstNotNullOfOrNull")
            || loweredCallee == interner.intern("kk_sequence_indexOfFirst")
            || loweredCallee == interner.intern("kk_sequence_takeLastWhile")
            || loweredCallee == interner.intern("kk_sequence_indexOfLast"),
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
        if loweredCallee == interner.intern("kk_sequence_elementAtOrElse"),
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
        if loweredCallee == interner.intern("__kk_iterable_firstNotNullOf")
            || loweredCallee == interner.intern("__kk_iterable_firstNotNullOfOrNull")
            || loweredCallee == interner.intern("__kk_iterable_any")
            || loweredCallee == interner.intern("__kk_iterable_all"),
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
        let resultFunction1Callees: Set<InternedString> = [
            interner.intern("kk_runtime_result_get_or_else"),
            interner.intern("kk_runtime_result_map"),
            interner.intern("kk_runtime_result_on_success"),
            interner.intern("kk_runtime_result_on_failure"),
            interner.intern("kk_runtime_result_recover"),
            interner.intern("kk_runtime_result_recover_catching"),
        ]
        if resultFunction1Callees.contains(loweredCallee),
           finalArguments.count == 2,
           sourceArgExprs.count == 1
        {
            let callbackArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[1],
                argExprID: sourceArgExprs[0],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0]] + callbackArgs
        }
        if loweredCallee == interner.intern("kk_runtime_result_fold"),
           finalArguments.count == 3,
           sourceArgExprs.count == 2
        {
            let successArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[1],
                argExprID: sourceArgExprs[0],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let failureArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0]] + successArgs + failureArgs
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
        // KSP-677: Mutex.withLock / Semaphore.withPermit / Lock.withLock are Kotlin
        // source (Stdlib/kotlinx/coroutines/sync/Sync.kt, Stdlib/kotlin/concurrent/Lock.kt).
        // The Mutex/Semaphore helpers compose lock()/unlock() and acquire()/release();
        // Lock.withLock delegates to the demoted __kk_lock_withLock bridge via the general
        // closure-taking ABI, so none of them need a dedicated closure-conversion branch.
        // Skip virtual dispatch when loweredMemberCalleeName remapped the callee
        // to a concrete runtime function (e.g. iterator → kk_list_iterator).
        // Virtual dispatch is only correct when no remapping occurred; a
        // declaration imported from a precompiled library is always named by
        // its own mangled link name, which is not such a remapping. KSP-611: for
        // an abstract imported interface member that link name is an empty stub,
        // so itable dispatch must be attempted there as well;
        // tryEmitVirtualDispatch falls back to the link name when the receiver
        // has no resolvable itable entry.
        // Source-backed ListIterator inherits hasNext/next from Iterator, but
        // loweredMemberCalleeName intentionally retains those names so the
        // implementation can be selected through its dynamic itable.
        let listIteratorInheritedDispatch = listIteratorInheritedDispatchCallee(
            receiverType: sema.bindings.exprTypes[receiver.expr],
            calleeName: loweredCallee,
            sema: sema,
            interner: interner
        ) != nil
        let isImportedLibraryLink = chosenCallee.map { symbol in
            // Imported source-backed interface members (kk_fn_* links) still
            // need itable dispatch, but runtime-bridged interface members must
            // call their ABI entry point directly. The latter can now be
            // source-declared and serialized into a stdlib artifact (for
            // example Collection.isEmpty), so treating every imported
            // interface link as virtual dispatch breaks runtime collection
            // boxes that intentionally have no Kotlin itable entry.
            let linkMatches = sema.symbols.externalLinkName(for: symbol)
                .map { interner.intern($0) == loweredCallee } == true
            return linkMatches && !kirIsRuntimeBridgedCallee(symbol, sema: sema)
        } ?? false
        let isRuntimeBridgedCallee = chosenCallee.map {
            kirIsRuntimeBridgedCallee($0, sema: sema)
        } ?? false
        if (loweredCallee == calleeName && !isRuntimeBridgedCallee)
            || listIteratorInheritedDispatch
            || isImportedLibraryLink
            || chosenCallee.map({ isClockRuntimeVirtualBridge($0, sema: sema) }) == true,
           let inst = tryEmitVirtualDispatch(
               chosenCallee: chosenCallee, calleeName: loweredCallee,
               receiverExpr: receiver.expr, loweredReceiverID: receiver.loweredID,
               isSuperCall: isSuperCall, finalArguments: finalArguments,
               result: result, sema: sema, arena: arena, interner: interner
           )
        {
            instructions.append(inst)
            return
        }
        var callArguments = finalArguments
        if loweredCallee == interner.intern("__kk_system_currentTimeMillis")
            || loweredCallee == interner.intern("__kk_system_nanoTime")
            || loweredCallee == interner.intern("__kk_system_process_start_nanos")
            || loweredCallee == interner.intern("kk_system_gc")
            || loweredCallee == interner.intern("kk_runtime_getRuntime")
            || loweredCallee == interner.intern("kk_runtime_totalMemory")
            || loweredCallee == interner.intern("kk_runtime_freeMemory")
            || loweredCallee == interner.intern("kk_runtime_maxMemory")
            || loweredCallee == interner.intern("kk_instant_now")
            || loweredCallee == interner.intern("kk_clock_system_now") {
            callArguments = []
        }
        if let bridgeCall = listWindowChunkMemberSourceBridgeCall(
            calleeName: loweredCallee,
            receiverExpr: receiver.expr,
            argumentCount: callArguments.count,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            interner: interner
        ) {
            instructions.append(.call(
                symbol: nil,
                callee: bridgeCall.callee,
                arguments: callArguments,
                result: result,
                canThrow: bridgeCall.canThrow,
                thrownResult: bridgeCall.canThrow ? arena.appendTemporary(type: sema.types.nullableAnyType) : nil,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            ))
            return
        }
        let throwingCallees = Self.throwingMemberCalleeNames(interner: interner)
        let needsOutThrown = needsThrownChannel(calleeName: loweredCallee, interner: interner)
        let thrownResult: KIRExprID? = needsOutThrown
            ? arena.appendTemporary(type: sema.types.nullableAnyType)
            : nil
        let canThrow = throwingCallees.contains(loweredCallee) || thrownResult != nil
        instructions.append(.call(
            symbol: callSymbol,
            callee: loweredCallee,
            arguments: callArguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType
        ))
        if let thrownResult,
           shouldRethrowThrownChannelResult(calleeName: loweredCallee, interner: interner)
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

    /// Cached set of runtime callee names whose `.call` should be emitted
    /// with `canThrow: true`. Hoisted from per-call `interner.intern()`
    /// invocations to avoid repeated interning in the hot lowering path.
    private static func throwingMemberCalleeNames(interner: StringInterner) -> Set<InternedString> {
        Set([
            interner.intern("kk_list_random"),
            interner.intern("kk_iterable_iterator"),
            interner.intern("kk_sequence_takeLast"),
            interner.intern("__kk_iterable_firstNotNullOf"),
            interner.intern("__kk_iterable_firstNotNullOfOrNull"),
            interner.intern("__kk_iterable_any"),
            interner.intern("__kk_iterable_all"),
            interner.intern("__kk_iterable_requireNoNulls"),
            interner.intern("__kk_string_codePointCount_from"),
            interner.intern("__kk_string_codePointCount_range"),
            interner.intern("__kk_kclass_cast"),
            interner.intern("kk_range_first_predicate"),
            interner.intern("kk_range_last_predicate"),
            interner.intern("__kk_range_random"),
            interner.intern("__kk_range_random_random"),
            interner.intern("__kk_char_range_random"),
            interner.intern("__kk_char_range_random_random"),
            interner.intern("__kk_random_nextInt_rangeObject"),
            interner.intern("__kk_random_nextLong_rangeObject"),
            interner.intern("kk_range_reduce"),
            interner.intern("kk_range_reduceIndexed"),
            interner.intern("__kk_long_range_random"),
            interner.intern("__kk_long_range_random_random"),
            interner.intern("__kk_uint_range_random"),
            interner.intern("__kk_uint_range_random_random"),
            interner.intern("__kk_ulong_range_random"),
            interner.intern("__kk_ulong_range_random_random"),
            interner.intern("__kk_int_progression_fromClosedRange"),
            interner.intern("__kk_long_progression_fromClosedRange"),
            interner.intern("__kk_uint_progression_fromClosedRange"),
            interner.intern("__kk_ulong_progression_fromClosedRange"),
            interner.intern("__kk_char_progression_fromClosedRange"),
            interner.intern("__kk_op_step"),
            interner.intern("__kk_char_range_step"),
            interner.intern("kk_sequence_foldIndexed"),
            interner.intern("kk_sequence_reduceOrNull"),
            interner.intern("kk_sequence_reduceRight"),
            interner.intern("kk_sequence_reduce"),
            interner.intern("kk_sequence_scan"),
            interner.intern("kk_sequence_reduceIndexed"),
            interner.intern("kk_sequence_reduceIndexedOrNull"),
            interner.intern("kk_sequence_reduceRightIndexed"),
            interner.intern("kk_sequence_reduceRightOrNull"),
            interner.intern("kk_sequence_reduceRightIndexedOrNull"),
            interner.intern("kk_sequence_runningFold"),
            interner.intern("kk_sequence_runningReduceIndexed"),
            interner.intern("kk_sequence_sortedBy"),
            interner.intern("kk_sequence_sortedByDescending"),
            interner.intern("kk_sequence_takeLastWhile"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_indexOfFirst"),
            interner.intern("kk_sequence_indexOfLast"),
            interner.intern("kk_map_mapKeysTo"),
            interner.intern("kk_map_mapValuesTo"),
            interner.intern("kk_sequence_mapNotNull"),
            interner.intern("kk_sequence_mapIndexedNotNull"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_mapIndexed"),
            interner.intern("kk_sequence_filterIndexed"),
            interner.intern("kk_sequence_elementAt"),
            interner.intern("kk_sequence_min"),
            interner.intern("kk_sequence_ifEmpty"),
            interner.intern("kk_sequence_first"),
            interner.intern("kk_sequence_random"),
            interner.intern("kk_sequence_last"),
            interner.intern("kk_sequence_max"),
            interner.intern("kk_sequence_firstOrNull"),
            interner.intern("kk_sequence_single"),
            interner.intern("kk_sequence_singleOrNull"),
            interner.intern("kk_sequence_randomOrNull"),
            interner.intern("kk_sequence_count"),
            interner.intern("kk_sequence_to_list"),
            interner.intern("kk_sequence_runningFoldIndexed"),
            interner.intern("kk_sequence_scanIndexed"),
        ])
    }

    private func listWindowChunkMemberSourceBridgeCall(
        calleeName: InternedString,
        receiverExpr: ExprID,
        argumentCount: Int,
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        interner: StringInterner
    ) -> (callee: InternedString, canThrow: Bool)? {
        let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType)
        let isListWindowChunkReceiver = isConcreteListLikeType(receiverType, sema: sema, interner: interner)
            || isSetLikeType(receiverType, sema: sema, interner: interner)
            || isIterableOrCollectionInterfaceType(receiverType, sema: sema, interner: interner)
            || isConcreteArrayLikeType(receiverType, sema: sema, interner: interner)
        guard isListWindowChunkReceiver else {
            return nil
        }

        if interner.resolve(calleeName) == "zip",
           let firstArgument = sourceArgExprs.first,
           let firstArgumentType = sema.bindings.exprTypes[firstArgument],
           isGenericKotlinArrayType(
               sema.types.makeNonNullable(firstArgumentType),
               sema: sema,
               interner: interner
           )
        {
            // KSP-999: Array overloads execute the bundled Kotlin source body;
            // the materializing Iterable bridge is retained for Iterable inputs.
            return nil
        }

        let callee: String
        let canThrow: Bool
        switch (interner.resolve(calleeName), argumentCount) {
        case ("chunked", 2):
            callee = "__kk_list_chunked"
            canThrow = false
        case ("chunked", 4):
            callee = "__kk_list_chunked_transform"
            canThrow = true
        case ("windowed", 4):
            callee = "__kk_list_windowed"
            canThrow = false
        case ("windowed", 6):
            callee = "__kk_list_windowed_transform"
            canThrow = true
        case ("zip", 2):
            callee = "__kk_list_zip"
            canThrow = false
        case ("zip", 4):
            callee = "__kk_list_zip_transform"
            canThrow = true
        case ("zipWithNext", 1):
            callee = "__kk_list_zipWithNext"
            canThrow = false
        case ("zipWithNext", 3):
            callee = "__kk_list_zipWithNextTransform"
            canThrow = true
        default:
            return nil
        }
        return (interner.intern(callee), canThrow)
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
                let closureObjExpr = arena.appendTemporary(type: anyType)
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
                    let unusedResult = arena.appendTemporary(type: anyType)
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
            // function reference forwarded as an ordinary argument to a bundled
            // Kotlin-source HOF, which boxes it via kk_function_create_1 rather
            // than lowering it with the raw closure-trampoline shape). lambdaID
            // may be a boxed Function1 object or an already-raw function
            // reference; kk_function_value_fn_ptr/closure_raw resolve either
            // shape at runtime (naively treating a boxed value as a raw fnPtr
            // and invoking it directly crashes — see BUG-... Sequence
            // chunked/windowed transform).
            let intType = sema.types.intType
            let fnPtrResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_fn_ptr"),
                arguments: [lambdaID],
                result: fnPtrResult,
                canThrow: false,
                thrownResult: nil
            ))
            fnPtrExpr = fnPtrResult
            let closureRawResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_closure_raw"),
                arguments: [lambdaID],
                result: closureRawResult,
                canThrow: false,
                thrownResult: nil
            ))
            envPtrExpr = closureRawResult
        }
        return (fnPtrExpr, envPtrExpr)
    }
}
