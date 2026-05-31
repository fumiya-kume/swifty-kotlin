import Foundation

extension CollectionLiteralLoweringPass {

    /// Rewrites late-stage runtime call adapters after direct collection/HOF rewrites.
    func rewriteRuntimeAdapterCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // Rewrite println on list/map → kk_list_to_string / kk_map_to_string
        if callee == lookup.kkPrintlnAnyName || callee == lookup.printlnName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.kkAnyToStringName, arguments.count >= 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- sortedWith with Comparator argument (STDLIB-649) ---
        // When kk_list_sortedWith is emitted as a .call (from synthetic stub),
        // the comparator argument needs trampoline/closure expansion.
        // args layout: [receiver, comparatorExpr]
        if callee == lookup.kkListSortedWithName, arguments.count == 2 {
            let receiverID = arguments[0]
            let comparatorExpr = arguments[1]
            let source = isComparatorFromCall(
                exprID: comparatorExpr,
                body: function.body,
                ascendingCallee: lookup.kkComparatorFromSelectorName,
                descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                thenByCallee: lookup.kkComparatorThenByName,
                thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
                reversedCallee: lookup.kkComparatorReversedName
            )
            if case .unknown = source {
                // Not a recognized comparator factory — likely a direct lambda
                // comparator (e.g. sortedWith { a, b -> a - b }).
                // Pass it as fnPtr with closureRaw=0.
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSortedWithName,
                    arguments: [receiverID, comparatorExpr, zeroExpr, zeroExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
            } else {
                let trampolineName: InternedString
                let closureExpr: KIRExprID
                switch source {
                case .descending:
                    trampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                    closureExpr = comparatorExpr
                case .multiSelector:
                    trampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                    closureExpr = comparatorExpr
                case .thenBy:
                    trampolineName = lookup.kkComparatorThenByTrampolineName
                    closureExpr = comparatorExpr
                case .thenByDescending:
                    trampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                    closureExpr = comparatorExpr
                case .thenDescending:
                    trampolineName = lookup.kkComparatorThenDescendingTrampolineName
                    closureExpr = comparatorExpr
                case .thenComparator:
                    trampolineName = lookup.kkComparatorThenComparatorTrampolineName
                    closureExpr = comparatorExpr
                case .nullsFirst:
                    trampolineName = lookup.kkComparatorNullsFirstTrampolineName
                    closureExpr = comparatorExpr
                case .nullsLast:
                    trampolineName = lookup.kkComparatorNullsLastTrampolineName
                    closureExpr = comparatorExpr
                case .naturalOrder:
                    trampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                    closureExpr = zero
                case .reverseOrder:
                    trampolineName = lookup.kkComparatorReverseOrderTrampolineName
                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                    closureExpr = zero
                case let .reversed(innerExpr):
                    trampolineName = lookup.kkComparatorReversedTrampolineName
                    let innerSource = isComparatorFromCall(
                        exprID: innerExpr,
                        body: function.body,
                        ascendingCallee: lookup.kkComparatorFromSelectorName,
                        descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                        multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                        naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                        reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                        thenByCallee: lookup.kkComparatorThenByName,
                        thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                        thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                        thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                        nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                        nullsLastCallee: lookup.kkComparatorNullsLastName,
                        multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                        multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
                        reversedCallee: lookup.kkComparatorReversedName
                    )
                    let innerTrampolineName: InternedString
                    let innerClosureExpr: KIRExprID
                    switch innerSource {
                    case .ascending:
                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                        innerClosureExpr = innerExpr
                    case .descending:
                        innerTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                        innerClosureExpr = innerExpr
                    case .multiSelector:
                        innerTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                        innerClosureExpr = innerExpr
                    case .thenBy:
                        innerTrampolineName = lookup.kkComparatorThenByTrampolineName
                        innerClosureExpr = innerExpr
                    case .thenByDescending:
                        innerTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                        innerClosureExpr = innerExpr
                    case .thenDescending:
                        innerTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
                        innerClosureExpr = innerExpr
                    case .thenComparator:
                        innerTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                        innerClosureExpr = innerExpr
                    case .nullsFirst:
                        innerTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                        innerClosureExpr = innerExpr
                    case .nullsLast:
                        innerTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                        innerClosureExpr = innerExpr
                    case .naturalOrder:
                        innerTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                        innerClosureExpr = zero
                    case .reverseOrder:
                        innerTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                        innerClosureExpr = zero
                    default:
                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                        innerClosureExpr = innerExpr
                    }
                    let innerTrampolineExpr = module.arena.appendExpr(
                        .externSymbolAddress(innerTrampolineName), type: nil)
                    loweredBody.append(.constValue(
                        result: innerTrampolineExpr,
                        value: .externSymbolAddress(innerTrampolineName)))
                    let reversedClosureResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)), type: nil)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkComparatorReversedName,
                        arguments: [innerTrampolineExpr, innerClosureExpr],
                        result: reversedClosureResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    closureExpr = reversedClosureResult
                default:
                    trampolineName = lookup.kkComparatorFromSelectorTrampolineName
                    closureExpr = comparatorExpr
                }
                let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
                loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSortedWithName,
                    arguments: [receiverID, trampolineExpr, closureExpr, zeroExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
            }
            if let result {
                state.listExprIDs.insert(result.rawValue)
            }
            return true
        }

        // --- STDLIB-189: String HOF closureRaw injection ---
        // String higher-order functions (filter, map, count, any, all, none)
        // are called with args = [receiver, lambdaRef] but the runtime
        // expects (strRaw, fnPtr, closureRaw, outThrown).  Insert the
        // missing closureRaw=0 argument so the ABI lowering pass only
        // needs to append the outThrown slot.
        if arguments.count == 2,
           callee == lookup.kkStringFilterName
            || callee == lookup.kkStringMapName
            || callee == lookup.kkStringCountName
            || callee == lookup.kkStringAnyName
            || callee == lookup.kkStringAllName
            || callee == lookup.kkStringNoneName
        {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let isStringResult = callee == lookup.kkStringFilterName
                || callee == lookup.kkStringMapName
            loweredBody.append(.call(
                symbol: nil,
                callee: callee,
                arguments: [receiverID, lambdaID, zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if isStringResult, let result {
                state.stringExprIDs.insert(result.rawValue)
            }
            return true
        }

        return false
    }
}
