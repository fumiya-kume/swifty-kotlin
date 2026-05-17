/// Sequence terminal conversions plus list/range transform rewrites.
extension CollectionLiteralLoweringPass {
    func rewriteSequenceTerminalCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let uintType = ctx.sema?.types.uintType

        func isUIntRangeExpr(_ expr: KIRExprID) -> Bool {
            guard let uintType else { return false }
            return module.arena.exprType(expr) == uintType
        }

    // toSet() on sequence → kk_sequence_toSet (STDLIB-470)
    if callee == lookup.toSetName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let toSetResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToSetName,
                arguments: [receiverID],
                result: toSetResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.setExprIDs.insert(result.rawValue)
                state.setExprIDs.insert(toSetResult.rawValue)
                loweredBody.append(.copy(from: toSetResult, to: result))
            }
            return true
        }
    }

    // toMap() on sequence → kk_sequence_toMap (STDLIB-470)
    if callee == lookup.toMapName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let toMapResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToMapName,
                arguments: [receiverID],
                result: toMapResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.mapExprIDs.insert(result.rawValue)
                state.mapExprIDs.insert(toMapResult.rawValue)
                loweredBody.append(.copy(from: toMapResult, to: result))
            }
            return true
        }
    }

    // groupBy on sequence → kk_sequence_groupBy (STDLIB-470)
    if callee == lookup.groupByName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
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
                callee: lookup.kkSequenceGroupByName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                state.mapExprIDs.insert(result.rawValue)
                state.mapExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    // maxOrNull / minOrNull on sequence (STDLIB-470)
    if callee == lookup.maxOrNullName || callee == lookup.minOrNullName {
        if arguments.count == 1 {
            let receiverID = arguments[0]
            if state.sequenceExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = callee == lookup.maxOrNullName
                    ? lookup.kkSequenceMaxOrNullName
                    : lookup.kkSequenceMinOrNullName
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID],
                    result: hofResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

    // flatten on sequence → kk_sequence_flatten (STDLIB-470)
    if callee == lookup.flattenName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFlattenName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.dropName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListDropName,
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

    if callee == lookup.reversedName || callee == lookup.asReversedName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: callee == lookup.asReversedName ? lookup.kkListAsReversedName : lookup.kkListReversedName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
        if callee == lookup.reversedName, state.rangeExprIDs.contains(receiverID.rawValue) {
            let isUIntRange = isUIntRangeExpr(receiverID)
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let reversedName = state.ulongRangeExprIDs.contains(receiverID.rawValue)
                ? lookup.kkULongRangeReversedName
                : (isUIntRange ? ctx.interner.intern("kk_uint_range_reversed") : lookup.kkRangeReversedName)
            loweredBody.append(.call(
                symbol: nil,
                callee: reversedName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.rangeExprIDs.insert(result.rawValue)
                state.rangeExprIDs.insert(transformResult.rawValue)
                if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                    state.ulongRangeExprIDs.insert(transformResult.rawValue)
                    state.ulongRangeExprIDs.insert(result.rawValue)
                }
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.sortedName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListSortedName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
        if state.setExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSetSortedName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
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

    if callee == lookup.distinctName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListDistinctName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
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

    // toList() on sequence → kk_sequence_to_list
    if callee == lookup.toListName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let toListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToListName,
                arguments: [receiverID],
                result: toListResult,
                canThrow: true,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }
        if state.mapExprIDs.contains(receiverID.rawValue) {
            let toListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkMapToListName,
                arguments: [receiverID],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let toListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToListName,
                arguments: [receiverID],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }
        if state.rangeExprIDs.contains(receiverID.rawValue) {
            let toListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            // Use char/ULong range variant if applicable (STDLIB-290, STDLIB-524)
            let rangeToListCallee: InternedString
            if state.charRangeExprIDs.contains(receiverID.rawValue) {
                rangeToListCallee = lookup.kkCharRangeToListName
            } else if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                rangeToListCallee = lookup.kkULongRangeToListName
            } else if isUIntRangeExpr(receiverID) {
                rangeToListCallee = ctx.interner.intern("kk_uint_range_toList")
            } else {
                rangeToListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: rangeToListCallee,
                arguments: [receiverID],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }
    }

        return false
    }
}
