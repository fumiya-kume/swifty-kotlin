/// Sequence pipeline rewrites such as asSequence, map/filter, zip, plus, and minus.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteSequencePipelineCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        instruction: KIRInstruction,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // STDLIB-pipeline §5 / KSP-441〜447: If the resolved callee is a bundled
    // Kotlin source declaration and the receiver is a source Sequence object,
    // route through normal function resolution so the source implementation runs.
    // When the receiver is a runtime Sequence handle (RuntimeSequenceBox), keep
    // the call in the lowering pipeline so it can be rewritten to a `kk_*` helper.
    if isSourceBacked(symbol: symbol, ctx: ctx),
       let receiverID = arguments.first,
       !state.sequenceExprIDs.contains(receiverID.rawValue) {
        return false
    }

    // --- Rewrite sequence member calls (STDLIB-003 / STDLIB-471) ---
    // asSequence() on collection → kk_list_asSequence or kk_array_asSequence
    // Guard with state.arrayExprIDs / state.listExprIDs so we only rewrite
    // receivers whose concrete collection kind is known.
    // Since LOWERING-001, non-tracked receivers (e.g., a List<Int>
    // parameter or a function return value) are now seeded into
    // the tracking sets via static type information from KIR.
    // They are rewritten correctly by the checks below.

    // When the callee is already the runtime name (e.g., resolved
    // via the synthetic stub's externalLinkName), track the result as
    // a sequence expression so downstream map/filter/toList rewrites fire.
    if callee == lookup.kkListAsSequenceName || callee == lookup.kkArrayAsSequenceName
        || callee == lookup.kkSequenceMapName || callee == lookup.kkSequenceFilterName
        || callee == lookup.kkSequenceFlatMapName
        || callee == lookup.kkSequenceFlatMapIndexedName
        || callee == lookup.kkSequenceConstrainOnceName
        || callee == lookup.kkSequenceShuffledName || callee == lookup.kkSequenceShuffledRandomName
        || callee == lookup.kkSequencePlusName || callee == lookup.kkSequenceMinusName
    {
        loweredBody.append(instruction)
        if let result { state.sequenceExprIDs.insert(result.rawValue) }
        return true
    }

    if callee == lookup.asSequenceName, arguments.count == 1 {
        let receiverID = arguments[0]
        // Seed tracking from static type so `intArrayOf(...).asSequence()` works even when
        // CallLowerer already rewrote the factory to `kk_array_of` (which PreScan does not
        // always tag as an array factory name).
        classifyTrackedExprByStaticType(
            receiverID,
            module: module,
            sema: ctx.sema,
            interner: ctx.interner,
            state: &state
        )

        // Runtime array/list handles must use kk_*_asSequence. Source-backed
        // Iterable/Sequence.asSequence cannot traverse RuntimeArrayBox/ListBox.
        // Check tracking before the source-backed short-circuit: an unbound
        // asSequence call (symbol == nil) has an empty externalLinkName and would
        // otherwise be misclassified as source-backed, leaving a virtual call that
        // yields an empty sequence (BUG with primitive Array.asSequence pipelines).
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayAsSequenceName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
        if state.listExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListAsSequenceName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // KSP-441〜447: true source-backed Sequence/Iterable.asSequence — keep virtual.
        // Require a real symbol so unbound calls are not treated as source-backed.
        if let symbol,
           let sema = ctx.sema,
           sema.symbols.symbol(symbol) != nil,
           (sema.symbols.externalLinkName(for: symbol) ?? "").isEmpty
        {
            loweredBody.append(instruction)
            return true
        }

        loweredBody.append(instruction)
        return true
    }

    // constrainOnce() on sequence -> kk_sequence_constrainOnce
    if callee == lookup.constrainOnceName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceConstrainOnceName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // requireNoNulls() on sequence -> kk_sequence_requireNoNulls
    // The bundled source iterator cannot propagate an exception thrown from
    // hasNext(), so the runtime pipeline step (which sets outThrown) is kept.
    if callee == lookup.requireNoNullsName, arguments.count == 1,
       let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 0) {
        loweredBody.append(.call(
            symbol: nil,
            callee: kkName,
            arguments: arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        if let result { state.sequenceExprIDs.insert(result.rawValue) }
        return true
    }

    // map/filter on sequence → kk_sequence_map/kk_sequence_filter
    if callee == lookup.mapName || callee == lookup.filterName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 1) ?? callee
            let expanded = expandSequenceLambdaArgument(
                lambdaExpr: arguments[1],
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, expanded.fnPtr, expanded.closureRaw],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // flatMap/flatMapIndexed on a runtime sequence handle
    // → kk_sequence_flatMap/kk_sequence_flatMapIndexed
    if callee == lookup.flatMapName || callee == lookup.flatMapIndexedName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let arity = callee == lookup.flatMapIndexedName ? 2 : 1
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: arity) ?? callee
            let expanded = expandSequenceLambdaArgument(
                lambdaExpr: arguments[1],
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, expanded.fnPtr, expanded.closureRaw],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // flatMap on sequence → kk_sequence_flatMap (STDLIB-095)
    if callee == lookup.flatMapName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFlatMapName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // flatMapIndexed on sequence -> kk_sequence_flatMapIndexed (STDLIB-SEQ-020)
    if callee == lookup.flatMapIndexedName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFlatMapIndexedName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // shuffled([random]) on sequence -> kk_sequence_shuffled(_random)
    if callee == lookup.shuffledName, arguments.count == 1 || arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let kkName = arguments.count == 2
                ? lookup.kkSequenceShuffledRandomName
                : lookup.kkSequenceShuffledName
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    let sequencePlusMinusCallees = SequencePlusMinusRuntimeCallees(
        plus: lookup.kkSequencePlusName,
        minus: lookup.kkSequenceMinusName,
        ofSingle: lookup.kkSequenceOfSingleName
    )

    // plus(other) on sequence → kk_sequence_plus (STDLIB-561)
    if callee == lookup.plusMemberName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            // Only sequence/list/array are supported by
            // kk_sequence_plus at the ABI level (not Set/Map).
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            emitSequencePlusMinusRewrite(
                operation: .plus,
                receiver: receiverID,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // plusElement(element) on sequence -> kk_sequence_plus_element (STDLIB-SEQ-013)
    if callee == lookup.plusElementName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequencePlusElementName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // minus(element)/minusElement(element) on sequence → kk_sequence_minus
    if callee == lookup.minusMemberName || callee == lookup.minusElementName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            // Only sequence/list/array are supported by the
            // ABI (not Set/Map) -- consistent with plus path.
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            let rewriteResult = emitSequencePlusMinusRewrite(
                operation: .minus,
                receiver: receiverID,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            guard case .emitted = rewriteResult else {
                // Fall through: collection-removal not supported
                loweredBody.append(instruction)
                return true
            }
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

        return false
    }

    /// Decomposes a materialized Sequence HOF lambda (a `kk_function_create_N`
    /// function object) back into the `(fnPtr, closureRaw)` pair expected by the
    /// runtime Sequence helpers (`kk_sequence_map`, `kk_sequence_flatMap`, etc.).
    private func expandSequenceLambdaArgument(
        lambdaExpr: KIRExprID,
        module: KIRModule,
        ctx: KIRContext,
        loweredBody: inout [KIRInstruction]
    ) -> (fnPtr: KIRExprID, closureRaw: KIRExprID) {
        if let sema = ctx.sema,
           let info = module.arena.callableValueInfo(for: lambdaExpr) {
            let intType = sema.types.intType
            let fnPtrExpr = module.arena.appendExpr(.symbolRef(info.symbol), type: intType)
            loweredBody.append(.constValue(result: fnPtrExpr, value: .symbolRef(info.symbol)))
            if let closureRaw = info.captureArguments.first {
                return (fnPtrExpr, closureRaw)
            }
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: intType)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return (fnPtrExpr, zeroExpr)
        }

        // Fallback: pass the expression as the function pointer with a zero
        // closure raw. This handles non-materialized callable references; for
        // ordinary lambda literals, `callableValueInfo` is always populated.
        let intType = ctx.sema?.types.intType
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: intType)
        if intType != nil {
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        }
        return (lambdaExpr, zeroExpr)
    }
}
