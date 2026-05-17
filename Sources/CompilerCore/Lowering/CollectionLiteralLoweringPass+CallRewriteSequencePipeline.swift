/// Sequence pipeline rewrites such as asSequence, map/filter, zip, plus, and minus.
extension CollectionLiteralLoweringPass {
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
        || callee == lookup.kkSequenceTakeName || callee == lookup.kkSequenceFlatMapName
        || callee == lookup.kkSequenceDropName || callee == lookup.kkSequenceDistinctName
        || callee == lookup.kkSequenceZipName
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
        } else if state.listExprIDs.contains(receiverID.rawValue) {
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
        } else {
            // Receiver is not a tracked list/array literal — skip
            // the rewrite and let virtual-call rewrite or the
            // original symbol linkage handle it. Still mark the
            // result as a sequence so downstream map/filter/take
            // rewrites fire correctly for chained calls.
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
        }
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

    // map/filter on sequence → kk_sequence_map/kk_sequence_filter
    if callee == lookup.mapName || callee == lookup.filterName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 1) ?? callee
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

    // take(n) on sequence → kk_sequence_take
    if callee == lookup.takeName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceTakeName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListTakeName,
                arguments: arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
    }

    // forEach on sequence → kk_sequence_forEach (STDLIB-095)
    if callee == lookup.forEachName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceForEachName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }
    }

    // forEachIndexed on sequence → kk_sequence_forEachIndexed
    if callee == lookup.forEachIndexedName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceForEachIndexedName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }
    }

    // zipWithNext on sequence → kk_sequence_zipWithNext / kk_sequence_zipWithNextTransform
    if callee == lookup.zipWithNextName,
       arguments.count == 1 || arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            if arguments.count == 1 {
                // zipWithNext() — no transform
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSequenceZipWithNextName,
                    arguments: [receiverID],
                    result: hofResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            } else {
                // zipWithNext { a, b -> ... } — with transform
                let lambdaID = arguments[1]
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSequenceZipWithNextTransformName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
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

    // drop(n) on sequence → kk_sequence_drop (STDLIB-096)
    if callee == lookup.dropName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceDropName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // distinct() on sequence → kk_sequence_distinct (STDLIB-096)
    if callee == lookup.distinctName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceDistinctName,
                arguments: [receiverID],
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

    // zip(other) on sequence → kk_sequence_zip (STDLIB-096)
    if callee == lookup.zipName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceZipName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // plus(other) on sequence → kk_sequence_plus (STDLIB-561)
    // If the argument is not a collection, wrap it in a
    // single-element sequence first so the runtime ABI always
    // receives a collection handle.
    if callee == lookup.plusMemberName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            // Only sequence/list/array are supported by
            // kk_sequence_plus at the ABI level (not Set/Map).
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            let effectiveArg: KIRExprID
            if isArgCollection {
                effectiveArg = argID
            } else {
                let wrappedExpr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSequenceOfSingleName,
                    arguments: [argID],
                    result: wrappedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                effectiveArg = wrappedExpr
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequencePlusName,
                arguments: [receiverID, effectiveArg],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
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

    // Iterable.minusElement(element) returns a List, even when
    // the receiver's static type is the Iterable interface.
    if callee == lookup.minusElementName, arguments.count == 2 {
        let receiverID = arguments[0]
        let isIterableMinusElementSymbol = symbol.flatMap { symbolID in
            ctx.sema?.symbols.externalLinkName(for: symbolID)
        } == "kk_list_minus_element"
        let returnsList = result.flatMap { module.arena.exprType($0) }.map { resultType in
            guard let sema = ctx.sema,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(resultType)),
                  let resultSymbol = sema.symbols.symbol(classType.classSymbol)
            else { return false }
            return ctx.interner.resolve(resultSymbol.name) == "List"
        } ?? false
        if isIterableMinusElementSymbol
            || returnsList
            || state.listExprIDs.contains(receiverID.rawValue)
            || state.setExprIDs.contains(receiverID.rawValue)
            || state.arrayExprIDs.contains(receiverID.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListMinusElementName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // minus(element)/minusElement(element) on sequence → kk_sequence_minus
    // Only rewrite when the argument is a single element (not a
    // collection).  Collection-removal is not yet supported at the
    // ABI level and falls through to the generic member-call path.
    if (callee == lookup.minusMemberName || callee == lookup.minusElementName), arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            // Only sequence/list/array are supported by the
            // ABI (not Set/Map) -- consistent with plus path.
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            guard !isArgCollection else {
                // Fall through: collection-removal not supported
                loweredBody.append(instruction)
                return true
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceMinusName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

        return false
    }
}
