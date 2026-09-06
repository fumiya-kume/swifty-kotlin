
extension CollectionLiteralConstructionLoweringPass {

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
        // A source-backed primitive array factory with a normalized spread
        // argument already has the complete array value. Preserve that value
        // directly instead of treating it as one nested element or passing it
        // through the source body's List-shaped vararg representation.
        if arguments.count == 1,
           isSourceBackedPrimitiveArrayFactory(symbol, sema: ctx.sema, interner: ctx.interner),
           let sema = ctx.sema,
           let argumentType = module.arena.exprType(arguments[0]),
           isPrimitiveArrayType(argumentType, sema: sema, interner: ctx.interner)
        {
            let copiedArray = module.arena.appendTemporary(type: argumentType)
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfName,
                arguments: [arguments[0]],
                result: copiedArray,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                loweredBody.append(.copy(from: copiedArray, to: result))
            }
            return true
        }

        // --- Rewrite arrayOf → kk_array_of ---
        if isStdlibArrayFactoryCall(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
            let arrayExpr = module.arena.appendTemporary(type: nil
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
                let setResult = module.arena.appendTemporary(type: nil
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

        // Source-backed collection iterator bindings may already carry the
        // specialized runtime link instead of the source member name. Record
        // that result so subsequent generic Iterator.hasNext()/next() calls
        // can retain the list-specific ABI path.
        if callee == lookup.kkListIteratorName, arguments.count == 1 {
            if let result { state.listIteratorExprIDs.insert(result.rawValue) }
            loweredBody.append(.call(
                symbol: nil,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
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

        // --- Rewrite list-iterator hasNext calls → kk_list_iterator_hasNext ---
        // Source-backed collection shells can bind Iterator.hasNext directly,
        // which emits the generic kk_iterator_hasNext callee. The iterator
        // result is still recognized as a concrete list iterator above, so
        // preserve the specialized runtime path for both spellings.
        if (callee == lookup.kkRangeHasNextName || callee == ctx.interner.intern("kk_iterator_hasNext")), arguments.count == 1 {
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
            // STDLIB-331/564: Rewrite kk_range_hasNext on iterator builder → __kk_iterator_builder_hasNext
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

        // --- Rewrite list-iterator next calls → kk_list_iterator_next ---
        if (callee == lookup.kkRangeNextName || callee == ctx.interner.intern("kk_iterator_next")), arguments.count == 1 {
            let argID = arguments[0]
            if state.listIteratorExprIDs.contains(argID.rawValue) {
                appendListIteratorNextWithUnboxing(
                    callee: lookup.kkListIteratorNextName,
                    arguments: arguments,
                    result: result,
                    module: module,
                    ctx: ctx,
                    loweredBody: &loweredBody
                )
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
            // STDLIB-331/564: Rewrite kk_range_next on iterator builder → __kk_iterator_builder_next
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
           callee == lookup.hasPreviousName || callee == lookup.previousName
                || callee == lookup.nextIndexName || callee == lookup.previousIndexName {
            let runtimeCallee: InternedString = switch callee {
            case lookup.hasPreviousName:
                lookup.kkListIteratorHasPreviousName
            case lookup.previousName:
                lookup.kkListIteratorPreviousName
            case lookup.nextIndexName:
                lookup.kkListIteratorNextIndexName
            default:
                lookup.kkListIteratorPreviousIndexName
            }
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

    /// Emits a `kk_list_iterator_next`-style call and, when the result expression
    /// has a non-null primitive type, appends an unboxing call so that the loop
    /// variable holds a raw primitive value rather than a boxed heap pointer.
    private func appendListIteratorNextWithUnboxing(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        loweredBody: inout [KIRInstruction]
    ) {
        if let result,
           let resultTypeID = module.arena.exprType(result),
           let types = ctx.sema?.types,
           let unboxCallee = BoxingCalleeTable(interner: ctx.interner).unboxCallee(
               for: resultTypeID,
               types: types,
               requireNonNull: true
           )
        {
            let tempBoxed = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: callee,
                arguments: arguments,
                result: tempBoxed,
                canThrow: false,
                thrownResult: nil
            ))
            emitNonThrowingCall(
                callee: unboxCallee,
                arg: tempBoxed,
                result: result,
                into: &loweredBody
            )
        } else {
            loweredBody.append(.call(
                symbol: nil,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}
