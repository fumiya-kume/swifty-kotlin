// swiftlint:disable file_length

/// Virtual-call rewrite for `Sequence`-typed receivers.
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`
/// to keep each rewrite source scoped to a single receiver kind.
extension CollectionLiteralLoweringPass {
    // MARK: - Sequence operations

    func rewriteSequenceVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        arrayExprIDs: Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // asSequence() → kk_list_asSequence only when receiver is a tracked list.
        // Array receivers are handled by rewriteArrayVirtualCall (guarded by arrayExprIDs).
        // Non-tracked receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        if callee == lookup.asSequenceName, arguments.isEmpty,
           listExprIDs.contains(receiver.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        if callee == lookup.mapName || callee == lookup.filterName, arguments.count == 1 {
            if sequenceExprIDs.contains(receiver.rawValue) {
                let kkName = callee == lookup.mapName
                    ? lookup.kkSequenceMapName : lookup.kkSequenceFilterName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { sequenceExprIDs.insert(result.rawValue) }
                return true
            }
        }

        if callee == lookup.flatMapName || callee == lookup.flatMapIndexedName, arguments.count == 1 {
            if sequenceExprIDs.contains(receiver.rawValue) {
                let kkName = callee == lookup.flatMapName
                    ? lookup.kkSequenceFlatMapName : lookup.kkSequenceFlatMapIndexedName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { sequenceExprIDs.insert(result.rawValue) }
                return true
            }
        }

        if callee == lookup.takeName, arguments.count == 1 {
            if sequenceExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSequenceTakeName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { sequenceExprIDs.insert(result.rawValue) }
                return true
            }
        }

        if callee == lookup.takeName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListTakeName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.dropName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListDropName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if (callee == lookup.reversedName || callee == lookup.asReversedName), arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: callee == lookup.asReversedName ? lookup.kkListAsReversedName : lookup.kkListReversedName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.sortedName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListSortedName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.sortedName, arguments.isEmpty, setExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSetSortedName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.distinctName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListDistinctName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.shuffledName,
           (arguments.isEmpty || arguments.count == 1),
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let kkName = arguments.isEmpty
                ? lookup.kkSequenceShuffledName
                : lookup.kkSequenceShuffledRandomName
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        if callee == lookup.shuffledName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListShuffledName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // shuffled(random: Random) overload (STDLIB-531)
        if callee == lookup.shuffledName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListShuffledRandomName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.flattenName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListFlattenName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.chunkedName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListChunkedName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // chunked(size, transform) HOF overload — 3 args after closure expansion [size, fnPtr, closureRaw]
        if callee == lookup.chunkedName, arguments.count == 3, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let thrownExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListChunkedTransformName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedDefaultName,
                arguments: [receiver, arguments[0]],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 2, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 3, listExprIDs.contains(receiver.rawValue) {
            let thirdArgType = module.arena.exprType(arguments[2])
            let thirdArgIsBoolean = context.sema.map { thirdArgType == $0.types.booleanType } ?? false
            if thirdArgIsBoolean {
                let transformResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListWindowedPartialName,
                    arguments: [receiver] + arguments,
                    result: transformResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(transformResult.rawValue)
                    loweredBody.append(.copy(from: transformResult, to: result))
                }
                return true
            }
        }

        // windowed(size, transform) HOF overload — 3 args after closure expansion [size, fnPtr, closureRaw]
        if callee == lookup.windowedName, arguments.count == 3,
           supportsIterableWindowedTransformReceiver(
               receiver: receiver,
               context: context,
               listExprIDs: listExprIDs,
               setExprIDs: setExprIDs,
               arrayExprIDs: arrayExprIDs
           )
        {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let oneExpr = module.arena.appendExpr(.intLiteral(1), type: nil)
            loweredBody.append(.constValue(result: oneExpr, value: .intLiteral(1)))
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let thrownExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedTransformName,
                arguments: [receiver, arguments[0], oneExpr, zeroExpr, arguments[1], arguments[2]],
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // windowed(size, step, transform) HOF overload — 4 args after closure expansion [size, step, fnPtr, closureRaw]
        if callee == lookup.windowedName, arguments.count == 4,
           supportsIterableWindowedTransformReceiver(
               receiver: receiver,
               context: context,
               listExprIDs: listExprIDs,
               setExprIDs: setExprIDs,
               arrayExprIDs: arrayExprIDs
           )
        {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let thrownExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedTransformName,
                arguments: [receiver, arguments[0], arguments[1], zeroExpr, arguments[2], arguments[3]],
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // windowed(size, step, partialWindows, transform) HOF overload — 5 args after closure expansion [size, step, partialWindows, fnPtr, closureRaw]
        if callee == lookup.windowedName, arguments.count == 5,
           supportsIterableWindowedTransformReceiver(
               receiver: receiver,
               context: context,
               listExprIDs: listExprIDs,
               setExprIDs: setExprIDs,
               arrayExprIDs: arrayExprIDs
           )
        {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let thrownExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedTransformName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.sortedDescendingName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListSortedDescendingName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.toListName, arguments.isEmpty {
            if sequenceExprIDs.contains(receiver.rawValue) {
                if let result {
                    let toListResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)), type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: toListResult,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(toListResult.rawValue)
                    loweredBody.append(.copy(from: toListResult, to: result))
                } else {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: nil,
                        canThrow: true,
                        thrownResult: nil
                    ))
                }
                return true
            }
            if mapExprIDs.contains(receiver.rawValue) {
                if let result {
                    let toListResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)), type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapToListName,
                        arguments: [receiver],
                        result: toListResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(toListResult.rawValue)
                    loweredBody.append(.copy(from: toListResult, to: result))
                } else {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapToListName,
                        arguments: [receiver],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return true
            }
        }

        // constrainOnce() on sequence -> kk_sequence_constrainOnce
        if callee == lookup.constrainOnceName, arguments.isEmpty, sequenceExprIDs.contains(receiver.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceConstrainOnceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                sequenceExprIDs.insert(result.rawValue)
            }
            return true
        }

        // toSet() on sequence → kk_sequence_toSet (STDLIB-470)
        if callee == lookup.toSetName, arguments.isEmpty, sequenceExprIDs.contains(receiver.rawValue) {
            let toSetResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToSetName,
                arguments: [receiver],
                result: toSetResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                setExprIDs.insert(result.rawValue)
                setExprIDs.insert(toSetResult.rawValue)
                loweredBody.append(.copy(from: toSetResult, to: result))
            }
            return true
        }

        // toMap() on sequence → kk_sequence_toMap (STDLIB-470)
        if callee == lookup.toMapName, arguments.isEmpty, sequenceExprIDs.contains(receiver.rawValue) {
            let toMapResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToMapName,
                arguments: [receiver],
                result: toMapResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                mapExprIDs.insert(result.rawValue)
                mapExprIDs.insert(toMapResult.rawValue)
                loweredBody.append(.copy(from: toMapResult, to: result))
            }
            return true
        }

        // maxOrNull / minOrNull on sequence (STDLIB-470)
        if (callee == lookup.maxOrNullName || callee == lookup.minOrNullName),
           arguments.isEmpty, sequenceExprIDs.contains(receiver.rawValue)
        {
            let kkName = callee == lookup.maxOrNullName
                ? lookup.kkSequenceMaxOrNullName : lookup.kkSequenceMinOrNullName
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // flatten on sequence → kk_sequence_flatten (STDLIB-470)
        if callee == lookup.flattenName, arguments.isEmpty, sequenceExprIDs.contains(receiver.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFlattenName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // foldIndexed on sequence → kk_sequence_foldIndexed (STDLIB-557)
        // Args: initial, lambda (2 from Kotlin: initial + operation)
        if callee == lookup.foldIndexedName, arguments.count == 2,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequenceFoldIndexedName,
                receiver: receiver,
                arguments: [arguments[0]] + [arguments[1]] + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // runningFoldIndexed on sequence → kk_sequence_runningFoldIndexed (STDLIB-SEQ-016)
        // Args: initial, lambda (2 from Kotlin: initial + operation)
        if callee == lookup.runningFoldIndexedName, arguments.count == 2,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceRunningFoldIndexedName,
                receiver: receiver,
                arguments: [arguments[0]] + [arguments[1]] + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result { sequenceExprIDs.insert(result.rawValue); sequenceExprIDs.insert(hofResult.rawValue) }
            return true
        }

        // scanIndexed on sequence -> kk_sequence_scanIndexed (STDLIB-SEQ-FN-105)
        // Args: initial, lambda (2 from Kotlin: initial + operation)
        if callee == lookup.scanIndexedName, arguments.count == 2,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceScanIndexedName,
                receiver: receiver,
                arguments: [arguments[0]] + [arguments[1]] + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result { sequenceExprIDs.insert(result.rawValue); sequenceExprIDs.insert(hofResult.rawValue) }
            return true
        }

        // reduceIndexed on sequence → kk_sequence_reduceIndexed (STDLIB-556)
        // Args: lambda (1 from Kotlin: operation)
        if callee == lookup.reduceIndexedName, arguments.count == 1,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequenceReduceIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // reduceIndexedOrNull on sequence → kk_sequence_reduceIndexedOrNull (STDLIB-SEQ-015)
        // Args: lambda (1 from Kotlin: operation)
        if callee == lookup.reduceIndexedOrNullName, arguments.count == 1,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequenceReduceIndexedOrNullName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // plus(other) on sequence → kk_sequence_plus (STDLIB-561)
        // Wrap single-element arguments in a one-element sequence so the
        // runtime ABI always receives a collection handle.
        // TODO: Extract shared helper (e.g., emitSequencePlusMinusRewrite) to
        // deduplicate logic across VirtualCallRewrite, CallRewrite, and
        // CallLowerer+Operators (see PR #460 review).
        if callee == lookup.plusMemberName, arguments.count == 1, sequenceExprIDs.contains(receiver.rawValue) {
            let argID = arguments[0]
            // Only sequence/list/array are supported by kk_sequence_plus
            // at the ABI level (not Set/Map).
            let isArgCollection = listExprIDs.contains(argID.rawValue)
                || sequenceExprIDs.contains(argID.rawValue)
                || arrayExprIDs.contains(argID.rawValue)
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
                arguments: [receiver, effectiveArg],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // plusElement(element) on sequence -> kk_sequence_plus_element (STDLIB-SEQ-013)
        if callee == lookup.plusElementName, arguments.count == 1, sequenceExprIDs.contains(receiver.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequencePlusElementName,
                arguments: [receiver, arguments[0]],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // partition(predicate) on sequence → kk_sequence_partition (STDLIB-SEQ-012)
        if callee == lookup.partitionName, arguments.count == 1, sequenceExprIDs.contains(receiver.rawValue) {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequencePartitionName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // Iterable.minusElement(element) returns a List, even when the receiver
        // is tracked through the generic Iterable interface.
        let minusElementReturnsList = result.flatMap { module.arena.exprType($0) }.map { resultType in
            guard let sema = context.sema,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(resultType)),
                  let resultSymbol = sema.symbols.symbol(classType.classSymbol)
            else { return false }
            return context.interner.resolve(resultSymbol.name) == "List"
        } ?? false
        if callee == lookup.minusElementName,
           arguments.count == 1,
           minusElementReturnsList
            || listExprIDs.contains(receiver.rawValue)
            || setExprIDs.contains(receiver.rawValue)
            || arrayExprIDs.contains(receiver.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListMinusElementName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // minus(element)/minusElement(element) on sequence → kk_sequence_minus
        // Only rewrite when the argument is a single element (not a collection).
        // Collection-removal is not yet supported at the ABI level.
        if (callee == lookup.minusMemberName || callee == lookup.minusElementName),
           arguments.count == 1,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let argID = arguments[0]
            // Only sequence/list/array are supported by the ABI (not
            // Set/Map) -- consistent with plus path.
            let isArgCollection = listExprIDs.contains(argID.rawValue)
                || sequenceExprIDs.contains(argID.rawValue)
                || arrayExprIDs.contains(argID.rawValue)
            guard !isArgCollection else {
                // Fall through: collection-removal not supported
                return false
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceMinusName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // STDLIB-SEQ-021: Sequence destination-collection filter operations
        // filterTo / filterNotTo on sequence (2 args: destination, lambda)
        if (callee == lookup.filterToName || callee == lookup.filterNotToName),
           (2 ... 4).contains(arguments.count),
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let normalizedArguments = arguments.first == receiver ? Array(arguments.dropFirst()) : arguments
            guard normalizedArguments.count == 2 || normalizedArguments.count == 3 else {
                return false
            }
            let destID = normalizedArguments[0]
            let lambdaID = normalizedArguments[1]
            let closureRawExpr: KIRExprID
            if normalizedArguments.count == 3 {
                closureRawExpr = normalizedArguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawExpr = zeroExpr
            }
            let kkName = callee == lookup.filterToName
                ? lookup.kkSequenceFilterToName : lookup.kkSequenceFilterNotToName
            let hofResult = emitHOFCall(
                kkName: kkName,
                receiver: receiver,
                arguments: [destID, lambdaID, closureRawExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                if listExprIDs.contains(destID.rawValue) {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                } else if setExprIDs.contains(destID.rawValue) {
                    setExprIDs.insert(result.rawValue)
                    setExprIDs.insert(hofResult.rawValue)
                }
            }
            return true
        }

        if callee == lookup.mapToName,
           arguments.count == 2 || arguments.count == 3,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawExpr: KIRExprID
            if arguments.count == 3 {
                closureRawExpr = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawExpr = zeroExpr
            }
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceMapToName,
                receiver: receiver,
                arguments: [destID, lambdaID, closureRawExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                if listExprIDs.contains(destID.rawValue) {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                } else if setExprIDs.contains(destID.rawValue) {
                    setExprIDs.insert(result.rawValue)
                    setExprIDs.insert(hofResult.rawValue)
                }
            }
            return true
        }

        if callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName,
           arguments.count == 2 || arguments.count == 3,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawExpr: KIRExprID
            if arguments.count == 3 {
                closureRawExpr = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawExpr = zeroExpr
            }
            let hofResult = emitHOFCall(
                kkName: callee == lookup.mapIndexedToName
                    ? lookup.kkSequenceMapIndexedToName
                    : lookup.kkSequenceMapNotNullToName,
                receiver: receiver,
                arguments: [destID, lambdaID, closureRawExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                if listExprIDs.contains(destID.rawValue) {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                } else if setExprIDs.contains(destID.rawValue) {
                    setExprIDs.insert(result.rawValue)
                    setExprIDs.insert(hofResult.rawValue)
                }
            }
            return true
        }

        // filterIndexedTo on sequence (2 args: destination, indexed-lambda)
        if callee == lookup.filterIndexedToName,
           arguments.count == 2 || arguments.count == 3,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawExpr: KIRExprID
            if arguments.count == 3 {
                closureRawExpr = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawExpr = zeroExpr
            }
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceFilterIndexedToName,
                receiver: receiver,
                arguments: [destID, lambdaID, closureRawExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                if listExprIDs.contains(destID.rawValue) {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                } else if setExprIDs.contains(destID.rawValue) {
                    setExprIDs.insert(result.rawValue)
                    setExprIDs.insert(hofResult.rawValue)
                }
            }
            return true
        }

        if callee == lookup.mapIndexedNotNullToName,
           arguments.count == 2 || arguments.count == 3,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawExpr: KIRExprID
            if arguments.count == 3 {
                closureRawExpr = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawExpr = zeroExpr
            }
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceMapIndexedNotNullToName,
                receiver: receiver,
                arguments: [destID, lambdaID, closureRawExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                if listExprIDs.contains(destID.rawValue) {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                } else if setExprIDs.contains(destID.rawValue) {
                    setExprIDs.insert(result.rawValue)
                    setExprIDs.insert(hofResult.rawValue)
                }
            }
            return true
        }

        // filterNotNullTo on list (1 arg: destination)
        if callee == lookup.filterNotNullToName,
           arguments.count == 1,
           listExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListFilterNotNullToName,
                arguments: [receiver, destID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result, listExprIDs.contains(destID.rawValue) {
                listExprIDs.insert(result.rawValue)
            }
            return true
        }

        // filterNotNullTo on sequence (1 arg: destination)
        if callee == lookup.filterNotNullToName,
           arguments.count == 1,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFilterNotNullToName,
                arguments: [receiver, destID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result, listExprIDs.contains(destID.rawValue) {
                listExprIDs.insert(result.rawValue)
            }
            return true
        }

        // filterIsInstanceTo on sequence (1 arg: destination, type token handled at call site)
        if callee == lookup.filterIsInstanceToName,
           arguments.count == 1 || arguments.count == 2,
           sequenceExprIDs.contains(receiver.rawValue)
        {
            let destID = arguments[0]
            let typeToken: KIRExprID
            if arguments.count == 2 {
                typeToken = arguments[1]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                typeToken = zeroExpr
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFilterIsInstanceToName,
                arguments: [receiver, destID, typeToken],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result, listExprIDs.contains(destID.rawValue) {
                listExprIDs.insert(result.rawValue)
            }
            return true
        }

        return false
    }

    // MARK: - List higher-order function operations
}
