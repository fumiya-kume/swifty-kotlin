/// Core one-lambda higher-order collection rewrites.
extension CollectionLiteralLoweringPass {
    func rewriteCoreHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // --- Rewrite higher-order collection member calls (FUNC-003) ---
    if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.mapNotNullName || callee == lookup.forEachName || callee == lookup.onEachName
        || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
        || callee == lookup.allName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
        || callee == lookup.toListName || callee == lookup.countName
    {
        if let rewrite = rewriteCollectionHOFCall(
            call: .init(
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ),
            state: &state,
            ctx: .init(module: module, lookup: lookup)
        ) {
            loweredBody.append(contentsOf: rewrite.instructions)
            return true
        }

        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            // countName with a List receiver is handled by the dedicated count/first/last
            // handler below, which correctly rewrites it to kk_list_count.
            // Entering this generic list-HOF path for countName would emit a call with
            // the un-rewritten "count" callee and mark the call handled, skipping that handler.
            if state.listExprIDs.contains(receiverID.rawValue) && callee != lookup.countName {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1) ?? callee
                let needsListTag = callee == lookup.mapName
                    || callee == lookup.mapNotNullName
                    || callee == lookup.flatMapName
                    || callee == lookup.flatMapIndexedName
                    || callee == lookup.filterName
                    || callee == lookup.filterNotName
                    || callee == lookup.onEachName
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if needsListTag, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
            if state.mapExprIDs.contains(receiverID.rawValue),
               callee == lookup.mapName || callee == lookup.filterName || callee == lookup.forEachName
               || callee == lookup.mapValuesName || callee == lookup.mapKeysName
               || callee == lookup.filterKeysName || callee == lookup.filterValuesName
               || callee == lookup.flatMapName || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
               || callee == lookup.anyName || callee == lookup.allName
               || callee == lookup.noneName
               || callee == lookup.flatMapName || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let kkName = lookup.collectionHOFRuntimeName(ownerKind: .map, callee: callee, arity: 1) ?? callee
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if callee == lookup.mapName || callee == lookup.flatMapName || callee == lookup.mapNotNullName, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if callee == lookup.mapValuesName || callee == lookup.mapKeysName, let result {
                    state.mapExprIDs.insert(result.rawValue)
                    state.mapExprIDs.insert(hofResult.rawValue)
                }
                if callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.filterKeysName || callee == lookup.filterValuesName, let result {
                    state.mapExprIDs.insert(result.rawValue)
                    state.mapExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
            if state.rangeExprIDs.contains(receiverID.rawValue),
               callee == lookup.mapName || callee == lookup.forEachName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let isCharRange = state.charRangeExprIDs.contains(receiverID.rawValue)
                let isULongRange = state.ulongRangeExprIDs.contains(receiverID.rawValue)
                let kkName: InternedString
                if callee == lookup.mapName {
                    // STDLIB-RANGE-037: use ULong-specific map for unsigned ranges
                    kkName = isULongRange ? lookup.kkULongRangeMapName : lookup.kkRangeMapName
                } else {
                    // forEach: use ULong, char, or default range variant
                    if isULongRange {
                        kkName = lookup.kkULongRangeForEachName
                    } else {
                        kkName = isCharRange ? lookup.kkCharRangeForEachName : lookup.kkRangeForEachName
                    }
                }
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if callee == lookup.mapName, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
            if state.arrayExprIDs.contains(receiverID.rawValue),
               callee == lookup.mapName || callee == lookup.filterName
               || callee == lookup.forEachName || callee == lookup.anyName
               || callee == lookup.allName
               || callee == lookup.noneName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let kkName: InternedString = switch callee {
                case lookup.mapName: lookup.kkArrayMapName
                case lookup.filterName: lookup.kkArrayFilterName
                case lookup.forEachName: lookup.kkArrayForEachName
                case lookup.anyName: lookup.kkArrayAnyName
                case lookup.allName: lookup.kkArrayAllName
                case lookup.noneName: lookup.kkArrayNoneName
                default: callee
                }
                let needsListTag = callee == lookup.mapName || callee == lookup.filterName
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if needsListTag, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
            if state.setExprIDs.contains(receiverID.rawValue),
               callee == lookup.mapName || callee == lookup.filterName
               || callee == lookup.forEachName
               || callee == lookup.filterNotName
               || callee == lookup.mapNotNullName
               || callee == lookup.flatMapName
               || callee == lookup.anyName
               || callee == lookup.noneName
               || callee == lookup.allName
               || callee == lookup.countName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let kkName = lookup.collectionHOFRuntimeName(ownerKind: .set, callee: callee, arity: 1) ?? callee
                let needsListTag = callee == lookup.mapName || callee == lookup.filterName
                    || callee == lookup.filterNotName || callee == lookup.mapNotNullName
                    || callee == lookup.flatMapName
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if needsListTag, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

        return false
    }
}
