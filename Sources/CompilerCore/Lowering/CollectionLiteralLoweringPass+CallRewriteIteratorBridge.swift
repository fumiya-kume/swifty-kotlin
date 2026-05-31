import Foundation

extension CollectionLiteralLoweringPass {

    /// Rewrites array factory calls and bridges range-style iterator intrinsics to runtime iterators.
    func rewriteArrayAndIteratorBridgeCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // --- Rewrite arrayOf → kk_array_of ---
        if isStdlibArrayFactoryCall(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
            let arrayExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayNewName,
                arguments: [countExpr],
                result: arrayExpr,
                canThrow: false,
                thrownResult: nil
            ))
            for (i, arg) in arguments.enumerated() {
                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                let setResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArraySetName,
                    arguments: [arrayExpr, idxExpr, arg],
                    result: setResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            if result != nil {
                loweredBody.append(.copy(from: arrayExpr, to: result!))
            }
            return true
        }

        // --- Rewrite kk_range_iterator on ULong range → kk_ulong_range_iterator (STDLIB-RANGE-037) ---
        if callee == lookup.kkRangeIteratorName, arguments.count == 1 {
            let argID = arguments[0]
            if state.ulongRangeExprIDs.contains(argID.rawValue) {
                if let result { state.ulongRangeIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkULongRangeIteratorName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if module.arena.exprType(argID) == ctx.sema?.types.uintType {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: ctx.interner.intern("kk_uint_range_iterator"),
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite kk_range_iterator on list/set → kk_list_iterator ---
        if callee == lookup.kkRangeIteratorName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) || state.setExprIDs.contains(argID.rawValue) {
                if let result { state.listIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIteratorName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                if let result { state.mapIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIteratorName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-189: Rewrite kk_range_iterator on String → kk_string_iterator
            if state.stringExprIDs.contains(argID.rawValue) {
                if let result { state.stringIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkStringIteratorName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-331/564: iterator {} result is already an iterator; pass through
            if state.iteratorBuilderExprIDs.contains(argID.rawValue) {
                if let result {
                    state.iteratorBuilderExprIDs.insert(result.rawValue)
                    loweredBody.append(.copy(from: argID, to: result))
                }
                return true
            }
            // Rewrite kk_range_iterator on IndexingIterable → kk_indexing_iterable_iterator
            if state.indexingIterableExprIDs.contains(argID.rawValue) {
                if let result { state.indexingIterableIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIndexingIterableIteratorName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite kk_range_hasNext on ULong range iterator → kk_ulong_range_hasNext (STDLIB-RANGE-037) ---
        if callee == lookup.kkRangeHasNextName, arguments.count == 1 {
            let argID = arguments[0]
            if state.ulongRangeIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkULongRangeHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite kk_range_hasNext on list iterator → kk_list_iterator_hasNext ---
        if callee == lookup.kkRangeHasNextName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIteratorHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIteratorHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-189: Rewrite kk_range_hasNext on string iterator → kk_string_iterator_hasNext
            if state.stringIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkStringIteratorHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-331/564: Rewrite kk_range_hasNext on iterator builder → kk_iterator_builder_hasNext
            if state.iteratorBuilderExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIteratorBuilderHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // Rewrite kk_range_hasNext on IndexingIterable iterator → kk_indexing_iterable_hasNext
            if state.indexingIterableIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIndexingIterableHasNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite kk_range_next on ULong range iterator → kk_ulong_range_next (STDLIB-RANGE-037) ---
        if callee == lookup.kkRangeNextName, arguments.count == 1 {
            let argID = arguments[0]
            if state.ulongRangeIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkULongRangeNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite kk_range_next on list iterator → kk_list_iterator_next ---
        if callee == lookup.kkRangeNextName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIteratorNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIteratorNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-189: Rewrite kk_range_next on string iterator → kk_string_iterator_next
            if state.stringIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkStringIteratorNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // STDLIB-331/564: Rewrite kk_range_next on iterator builder → kk_iterator_builder_next
            if state.iteratorBuilderExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIteratorBuilderNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            // Rewrite kk_range_next on IndexingIterable iterator → kk_indexing_iterable_next
            if state.indexingIterableIteratorExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIndexingIterableNextName,
                    arguments: arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- STDLIB-538: Rewrite explicit listIterator() on list → kk_list_iterator ---
        if callee == lookup.listIteratorMemberName, arguments.count == 1 {
            let receiverID = arguments[0]
            if state.listExprIDs.contains(receiverID.rawValue) {
                if let result { state.listIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIteratorName,
                    arguments: [receiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- Rewrite explicit iterator() on list/set → kk_list_iterator ---
        if callee == lookup.iteratorName, arguments.count == 1 {
            let receiverID = arguments[0]
            if state.listExprIDs.contains(receiverID.rawValue) || state.setExprIDs.contains(receiverID.rawValue) {
                if let result { state.listIteratorExprIDs.insert(result.rawValue) }
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIteratorName,
                    arguments: [receiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- STDLIB-538: Rewrite hasPrevious()/previous() on list iterator ---
        let isListIteratorReceiverCall = arguments.count == 1
            && state.listIteratorExprIDs.contains(arguments[0].rawValue)
        if isListIteratorReceiverCall,
           callee == lookup.hasPreviousName || callee == lookup.previousName {
            let runtimeCallee = callee == lookup.hasPreviousName
                ? lookup.kkListIteratorHasPreviousName
                : lookup.kkListIteratorPreviousName
            loweredBody.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        return false
    }
}
