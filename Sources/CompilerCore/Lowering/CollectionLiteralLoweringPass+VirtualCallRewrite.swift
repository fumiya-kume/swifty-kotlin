import Foundation

extension CollectionLiteralLoweringPass {
    struct VirtualCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
        let functionBody: [KIRInstruction]
        let sema: SemaModule?
        let interner: StringInterner
    }

    func rewriteVirtualCallInstruction(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        fileExprIDs: inout Set<Int32>,
        indexingIterableExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        // LOWERING-001: If the receiver is not in any tracking set yet,
        // attempt to classify it from its static type in the KIR arena.
        // This handles non-tracked receivers such as function parameters,
        // function return values, and field loads whose concrete collection
        // kind was not determined by the factory-call pre-scan.
        classifyReceiverByStaticType(
            receiver: receiver,
            context: context,
            listExprIDs: &listExprIDs,
            setExprIDs: &setExprIDs,
            mapExprIDs: &mapExprIDs,
            arrayExprIDs: &arrayExprIDs,
            sequenceExprIDs: &sequenceExprIDs
        )

        if rewriteArrayVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, arrayExprIDs: &arrayExprIDs,
            sequenceExprIDs: &sequenceExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteSequenceVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, setExprIDs: &setExprIDs, mapExprIDs: &mapExprIDs, sequenceExprIDs: &sequenceExprIDs,
            arrayExprIDs: arrayExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteListHOFVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            indexingIterableExprIDs: &indexingIterableExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteCollectionPropertyVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, lookup: lookup,
            listExprIDs: listExprIDs, setExprIDs: setExprIDs, mapExprIDs: mapExprIDs,
            arrayExprIDs: arrayExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteRangeVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            sema: context.sema, interner: context.interner,
            rangeExprIDs: &rangeExprIDs, charRangeExprIDs: &charRangeExprIDs,
            ulongRangeExprIDs: &ulongRangeExprIDs,
            listExprIDs: &listExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        // toTypedArray() on list → kk_list_toTypedArray (result is Array)
        if callee == lookup.toTypedArrayName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListToTypedArrayName,
                arguments: [receiver],
                result: toArrayResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(toArrayResult.rawValue)
                loweredBody.append(.copy(from: toArrayResult, to: result))
            }
            return true
        }

        // --- Rewrite File member virtual calls (STDLIB-320) ---
        if fileExprIDs.contains(receiver.rawValue) {
            if rewriteFileMemberVirtualCall(
                callee: callee, receiver: receiver, arguments: arguments,
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, lookup: lookup,
                listExprIDs: &listExprIDs,
                loweredBody: &loweredBody
            ) { return true }
        }

        return false
    }

    // MARK: - File member operations (STDLIB-320)

    private func rewriteFileMemberVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let kkCallee: InternedString?

        switch callee {
        case lookup.readTextName:
            kkCallee = lookup.kkFileReadTextName
        case lookup.writeTextName:
            kkCallee = lookup.kkFileWriteTextName
        case lookup.readLinesName:
            kkCallee = lookup.kkFileReadLinesName
        case lookup.existsName:
            kkCallee = lookup.kkFileExistsName
        case lookup.isFileName:
            kkCallee = lookup.kkFileIsFileName
        case lookup.isDirectoryName:
            kkCallee = lookup.kkFileIsDirectoryName
        case lookup.namePropertyName:
            kkCallee = lookup.kkFileNameName
        case lookup.pathPropertyName:
            kkCallee = lookup.kkFilePathName
        case lookup.forEachLineName:
            kkCallee = lookup.kkFileForEachLineName
        case lookup.useLinesName:
            kkCallee = lookup.kkFileUseLinesName
        case lookup.bufferedReaderName:
            // Only rewrite argument-less bufferedReader(); the runtime function
            // kk_file_bufferedReader does not accept charset/bufferSize args.
            kkCallee = arguments.isEmpty ? lookup.kkFileBufferedReaderName : nil
        case lookup.bufferedWriterName:
            // Only rewrite argument-less bufferedWriter(); the runtime function
            // kk_file_bufferedWriter does not accept charset/bufferSize args.
            kkCallee = arguments.isEmpty ? lookup.kkFileBufferedWriterName : nil
        case lookup.walkName:
            kkCallee = lookup.kkFileWalkName
        case lookup.listFilesName:
            kkCallee = lookup.kkFileListFilesName
        case lookup.deleteName:
            kkCallee = lookup.kkFileDeleteName
        case lookup.mkdirsName:
            kkCallee = lookup.kkFileMkdirsName
        case lookup.readBytesName:
            kkCallee = lookup.kkFileReadBytesName
        case lookup.appendTextName:
            kkCallee = lookup.kkFileAppendTextName
        default:
            kkCallee = nil
        }

        guard let target = kkCallee else { return false }

        // Methods that pass extra arguments beyond the receiver
        let needsExtraArgs = callee == lookup.forEachLineName
            || callee == lookup.useLinesName
            || callee == lookup.writeTextName
            || callee == lookup.appendTextName
        let memberArgs = needsExtraArgs ?
            [receiver] + arguments :
            [receiver]

        loweredBody.append(.call(
            symbol: nil,
            callee: target,
            arguments: memberArgs,
            result: result,
            canThrow: origCanThrow,
            thrownResult: origThrownResult
        ))

        // Track results that produce lists (readLines/readBytes return List)
        if (callee == lookup.readLinesName || callee == lookup.readBytesName), let result {
            listExprIDs.insert(result.rawValue)
        }

        return true
    }

    // MARK: - Sequence operations

    private func rewriteSequenceVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
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

        if callee == lookup.dropName, arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListDropName,
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
                        canThrow: false,
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
                        canThrow: false,
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

        // minus(element) on sequence → kk_sequence_minus (STDLIB-562)
        // Only rewrite when the argument is a single element (not a collection).
        // Collection-removal is not yet supported at the ABI level.
        if callee == lookup.minusMemberName, arguments.count == 1, sequenceExprIDs.contains(receiver.rawValue) {
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

        return false
    }

    // MARK: - List higher-order function operations

    private func rewriteListHOFVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        indexingIterableExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        if rewriteCommonListHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, loweredBody: &loweredBody
        ) { return true }

        if rewriteMapHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteGroupSortFindHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteAssociateToHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteZipUnzipAndIndexedHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, indexingIterableExprIDs: &indexingIterableExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteCountFirstLastFoldReduceHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, loweredBody: &loweredBody
        ) { return true }

        return false
    }

    private func rewriteMapHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard callee == lookup.mapName || callee == lookup.filterName || callee == lookup.forEachName
            || callee == lookup.mapValuesName || callee == lookup.mapKeysName || callee == lookup.toListName
            || callee == lookup.filterKeysName || callee == lookup.filterValuesName
        else {
            return false
        }
        guard mapExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.toListName {
            guard arguments.isEmpty else { return false }
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
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }

        guard arguments.count == 1 else { return false }

        let kkName: InternedString = switch callee {
        case lookup.mapName: lookup.kkMapMapName
        case lookup.filterName: lookup.kkMapFilterName
        case lookup.filterKeysName: lookup.kkMapFilterKeysName
        case lookup.filterValuesName: lookup.kkMapFilterValuesName
        case lookup.forEachName: lookup.kkMapForEachName
        case lookup.mapValuesName: lookup.kkMapMapValuesName
        case lookup.mapKeysName: lookup.kkMapMapKeysName
        default: callee
        }
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let hofResult = emitHOFCall(
            kkName: kkName,
            receiver: receiver,
            arguments: arguments + [zeroExpr],
            result: result,
            origCanThrow: origCanThrow,
            origThrownResult: origThrownResult,
            module: module,
            loweredBody: &loweredBody
        )
        if callee == lookup.mapName, let result {
            listExprIDs.insert(result.rawValue)
            listExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.mapValuesName || callee == lookup.mapKeysName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.filterName || callee == lookup.filterKeysName || callee == lookup.filterValuesName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    @discardableResult
    private func emitHOFCall(
        kkName: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        loweredBody: inout [KIRInstruction]
    ) -> KIRExprID {
        let hofResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: nil
        )
        loweredBody.append(.call(
            symbol: nil,
            callee: kkName,
            arguments: [receiver] + arguments,
            result: hofResult,
            canThrow: origCanThrow,
            thrownResult: origThrownResult
        ))
        if let result {
            loweredBody.append(.copy(from: hofResult, to: result))
        }
        return hofResult
    }

    private func rewriteCommonListHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if callee == lookup.filterNotNullName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListFilterNotNullName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        guard callee == lookup.mapName || callee == lookup.filterName || callee == lookup.mapNotNullName
            || callee == lookup.forEachName || callee == lookup.onEachName
            || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        else { return false }
        guard arguments.count == 1, listExprIDs.contains(receiver.rawValue) else { return false }

        let kkName: InternedString = switch callee {
        case lookup.mapName: lookup.kkListMapName
        case lookup.filterName: lookup.kkListFilterName
        case lookup.mapNotNullName: lookup.kkListMapNotNullName
        case lookup.forEachName: lookup.kkListForEachName
        case lookup.onEachName: lookup.kkListOnEachName
        case lookup.flatMapName: lookup.kkListFlatMapName
        case lookup.anyName: lookup.kkListAnyName
        case lookup.noneName: lookup.kkListNoneName
        case lookup.allName: lookup.kkListAllName
        case lookup.takeWhileName: lookup.kkListTakeWhileName
        case lookup.dropWhileName: lookup.kkListDropWhileName
        case lookup.takeLastWhileName: lookup.kkListTakeLastWhileName
        case lookup.dropLastWhileName: lookup.kkListDropLastWhileName
        default: callee
        }
        let needsListTag = callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName || callee == lookup.filterName
            || callee == lookup.onEachName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if needsListTag, let result {
            listExprIDs.insert(result.rawValue)
            listExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    enum ComparatorSource {
        case ascending
        case descending
        case multiSelector
        case naturalOrder
        case reverseOrder
        case thenBy(inner: KIRExprID)
        case thenByDescending(inner: KIRExprID)
        case thenComparator(inner: KIRExprID)
        case nullsFirst(inner: KIRExprID)
        case nullsLast(inner: KIRExprID)
        /// The comparator was produced by `Comparator.reversed()`.
        /// The associated KIRExprID is the inner comparator expression.
        case reversed(inner: KIRExprID)
        case unknown
    }

    func isComparatorFromCall(
        exprID: KIRExprID,
        body: [KIRInstruction],
        ascendingCallee: InternedString,
        descendingCallee: InternedString,
        multiSelectorCallee: InternedString,
        naturalOrderCallee: InternedString,
        reverseOrderCallee: InternedString,
        thenByCallee: InternedString? = nil,
        thenByDescendingCallee: InternedString? = nil,
        thenComparatorCallee: InternedString? = nil,
        nullsFirstCallee: InternedString? = nil,
        nullsLastCallee: InternedString? = nil,
        multiSelector3Callee: InternedString? = nil,
        reversedCallee: InternedString? = nil
    ) -> ComparatorSource {
        for inst in body {
            switch inst {
            case let .call(_, callee, arguments, result, _, _, _, _):
                if let result, result.rawValue == exprID.rawValue {
                    if callee == ascendingCallee { return .ascending }
                    if callee == descendingCallee { return .descending }
                    if callee == multiSelectorCallee { return .multiSelector }
                    if let ms3 = multiSelector3Callee, callee == ms3 { return .multiSelector }
                    if callee == naturalOrderCallee { return .naturalOrder }
                    if callee == reverseOrderCallee { return .reverseOrder }
                    if let thenBy = thenByCallee, callee == thenBy, let innerExpr = arguments.first {
                        return .thenBy(inner: innerExpr)
                    }
                    if let thenByDescending = thenByDescendingCallee, callee == thenByDescending, let innerExpr = arguments.first {
                        return .thenByDescending(inner: innerExpr)
                    }
                    if let thenComparator = thenComparatorCallee, callee == thenComparator, let innerExpr = arguments.first {
                        return .thenComparator(inner: innerExpr)
                    }
                    if let nullsFirst = nullsFirstCallee, callee == nullsFirst, let innerExpr = arguments.first {
                        return .nullsFirst(inner: innerExpr)
                    }
                    if let nullsLast = nullsLastCallee, callee == nullsLast, let innerExpr = arguments.first {
                        return .nullsLast(inner: innerExpr)
                    }
                    if let rc = reversedCallee, callee == rc, let innerExpr = arguments.first {
                        return .reversed(inner: innerExpr)
                    }
                    return .unknown
                }
            case let .copy(from: fromID, to: toID):
                if toID.rawValue == exprID.rawValue {
                    return isComparatorFromCall(
                        exprID: fromID,
                        body: body,
                        ascendingCallee: ascendingCallee,
                        descendingCallee: descendingCallee,
                        multiSelectorCallee: multiSelectorCallee,
                        naturalOrderCallee: naturalOrderCallee,
                        reverseOrderCallee: reverseOrderCallee,
                        thenByCallee: thenByCallee,
                        thenByDescendingCallee: thenByDescendingCallee,
                        thenComparatorCallee: thenComparatorCallee,
                        nullsFirstCallee: nullsFirstCallee,
                        nullsLastCallee: nullsLastCallee,
                        multiSelector3Callee: multiSelector3Callee,
                        reversedCallee: reversedCallee
                    )
            }
            default:
                break
            }
        }
        return .unknown
    }

    private func rewriteGroupSortFindHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        guard callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName
            || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
            || callee == lookup.sortedByDescendingName || callee == lookup.sortedWithName
            || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
            || callee == lookup.maxOfOrNullName || callee == lookup.minOfOrNullName
            || callee == lookup.maxOfName || callee == lookup.minOfName
            || callee == lookup.maxWithName || callee == lookup.maxWithOrNullName
            || callee == lookup.minWithName || callee == lookup.minWithOrNullName
            || callee == lookup.maxOfWithName || callee == lookup.maxOfWithOrNullName
            || callee == lookup.minOfWithName || callee == lookup.minOfWithOrNullName
            || callee == lookup.distinctByName
        else {
            return false
        }
        let acceptsTwoArguments = callee == lookup.sortedWithName
            || callee == lookup.maxOfWithName || callee == lookup.maxOfWithOrNullName
            || callee == lookup.minOfWithName || callee == lookup.minOfWithOrNullName
        guard arguments.count == 1 || (acceptsTwoArguments && arguments.count == 2),
              listExprIDs.contains(receiver.rawValue)
        else { return false }

        let kkName: InternedString = switch callee {
        case lookup.groupByName: lookup.kkListGroupByName
        case lookup.sortedByName: lookup.kkListSortedByName
        case lookup.sortedByDescendingName: lookup.kkListSortedByDescendingName
        case lookup.sortedWithName: lookup.kkListSortedWithName
        case lookup.findName: lookup.kkListFindName
        case lookup.associateByName: lookup.kkListAssociateByName
        case lookup.associateWithName: lookup.kkListAssociateWithName
        case lookup.associateName: lookup.kkListAssociateName
        case lookup.maxByOrNullName: lookup.kkListMaxByOrNullName
        case lookup.minByOrNullName: lookup.kkListMinByOrNullName
        case lookup.maxOfOrNullName: lookup.kkListMaxOfOrNullName
        case lookup.minOfOrNullName: lookup.kkListMinOfOrNullName
        case lookup.maxOfName: lookup.kkListMaxOfName
        case lookup.minOfName: lookup.kkListMinOfName
        case lookup.maxWithName: lookup.kkListMaxWithName
        case lookup.maxWithOrNullName: lookup.kkListMaxWithOrNullName
        case lookup.minWithName: lookup.kkListMinWithName
        case lookup.minWithOrNullName: lookup.kkListMinWithOrNullName
        case lookup.maxOfWithName: lookup.kkListMaxOfWithName
        case lookup.maxOfWithOrNullName: lookup.kkListMaxOfWithOrNullName
        case lookup.minOfWithName: lookup.kkListMinOfWithName
        case lookup.minOfWithOrNullName: lookup.kkListMinOfWithOrNullName
        case lookup.distinctByName: lookup.kkListDistinctByName
        default: callee
        }

        var hofArgs: [KIRExprID]
        if (callee == lookup.sortedWithName || callee == lookup.maxWithName || callee == lookup.maxWithOrNullName
            || callee == lookup.minWithName || callee == lookup.minWithOrNullName), arguments.count == 1 {
            let comparatorExpr = arguments[0]
            let source = isComparatorFromCall(
                exprID: comparatorExpr,
                body: context.functionBody,
                ascendingCallee: lookup.kkComparatorFromSelectorName,
                descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                thenByCallee: lookup.kkComparatorThenByName,
                thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                reversedCallee: lookup.kkComparatorReversedName
            )
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
                // Determine the inner comparator's trampoline and closure so we
                // can build the (fnPtr, closureRaw) pair that
                // kk_comparator_reversed_trampoline expects.
                let innerSource = isComparatorFromCall(
                    exprID: innerExpr,
                    body: context.functionBody,
                    ascendingCallee: lookup.kkComparatorFromSelectorName,
                    descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                    naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                    reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                    thenByCallee: lookup.kkComparatorThenByName,
                    thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                    thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
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
                case .thenBy:
                    innerTrampolineName = lookup.kkComparatorThenByTrampolineName
                    innerClosureExpr = innerExpr
                case .thenByDescending:
                    innerTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
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
                default:
                    // Unknown inner comparator -- use selector trampoline as fallback
                    innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                    innerClosureExpr = innerExpr
                }
                // Emit the inner trampoline function pointer
                let innerTrampolineExpr = module.arena.appendExpr(
                    .externSymbolAddress(innerTrampolineName), type: nil)
                loweredBody.append(.constValue(
                    result: innerTrampolineExpr,
                    value: .externSymbolAddress(innerTrampolineName)))
                // Call kk_comparator_reversed(innerTrampoline, innerClosure)
                // to produce a PairBox that kk_comparator_reversed_trampoline
                // can unpack.
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
            hofArgs = [trampolineExpr, closureExpr]
        } else if (callee == lookup.maxOfWithName || callee == lookup.maxOfWithOrNullName
            || callee == lookup.minOfWithName || callee == lookup.minOfWithOrNullName), arguments.count == 2 {
            let comparatorExpr = arguments[0]
            let selectorExpr = arguments[1]
            let cmpTrampolineName: InternedString
            let cmpClosureExpr: KIRExprID
            switch isComparatorFromCall(
                exprID: comparatorExpr,
                body: context.functionBody,
                ascendingCallee: lookup.kkComparatorFromSelectorName,
                descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                thenByCallee: lookup.kkComparatorThenByName,
                thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                reversedCallee: lookup.kkComparatorReversedName
            ) {
            case .descending:
                cmpTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                cmpClosureExpr = comparatorExpr
            case .multiSelector:
                cmpTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                cmpClosureExpr = comparatorExpr
            case .thenBy:
                cmpTrampolineName = lookup.kkComparatorThenByTrampolineName
                cmpClosureExpr = comparatorExpr
            case .thenByDescending:
                cmpTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                cmpClosureExpr = comparatorExpr
            case .thenComparator:
                cmpTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                cmpClosureExpr = comparatorExpr
            case .nullsFirst:
                cmpTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                cmpClosureExpr = comparatorExpr
            case .nullsLast:
                cmpTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                cmpClosureExpr = comparatorExpr
            case .naturalOrder:
                cmpTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                cmpClosureExpr = zero
            case .reverseOrder:
                cmpTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                cmpClosureExpr = zero
            default:
                cmpTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                cmpClosureExpr = comparatorExpr
            }
            let cmpTrampolineExpr = module.arena.appendExpr(.externSymbolAddress(cmpTrampolineName), type: nil)
            loweredBody.append(.constValue(result: cmpTrampolineExpr, value: .externSymbolAddress(cmpTrampolineName)))
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            hofArgs = [cmpTrampolineExpr, cmpClosureExpr, selectorExpr, zeroExpr]
        } else {
            hofArgs = arguments
        }
        let needsClosureRaw = callee != lookup.maxByOrNullName && callee != lookup.minByOrNullName
            && callee != lookup.maxOfOrNullName && callee != lookup.minOfOrNullName
            && callee != lookup.maxOfWithName && callee != lookup.maxOfWithOrNullName
            && callee != lookup.minOfWithName && callee != lookup.minOfWithOrNullName
        if needsClosureRaw {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            hofArgs.append(zeroExpr)
        }

        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: hofArgs,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if callee == lookup.sortedByName || callee == lookup.sortedByDescendingName || callee == lookup.sortedWithName
            || callee == lookup.distinctByName,
           let result
        {
            listExprIDs.insert(result.rawValue)
            listExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.groupByName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName,
           let result
        {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    // STDLIB-535/536/537: associateByTo / associateWithTo / groupByTo
    private func rewriteAssociateToHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        guard callee == lookup.associateByToName || callee == lookup.associateWithToName
            || callee == lookup.groupByToName
        else {
            return false
        }
        // arguments: [destination, lambda] or [destination, lambda, closureRaw]
        guard (arguments.count == 2 || arguments.count == 3),
              listExprIDs.contains(receiver.rawValue)
        else { return false }

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

        let kkName: InternedString = switch callee {
        case lookup.associateByToName: lookup.kkListAssociateByToName
        case lookup.associateWithToName: lookup.kkListAssociateWithToName
        case lookup.groupByToName: lookup.kkListGroupByToName
        default: callee
        }

        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver,
            arguments: [destID, lambdaID, closureRawExpr],
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    private func rewriteZipUnzipAndIndexedHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        indexingIterableExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard listExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.withIndexName, arguments.isEmpty {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWithIndexName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                indexingIterableExprIDs.insert(result.rawValue)
                indexingIterableExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        if callee == lookup.zipName, arguments.count == 1 {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipName,
                arguments: [receiver] + arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // zipWithNext() — no-arg
        if callee == lookup.zipWithNextName, arguments.isEmpty {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipWithNextName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // zipWithNext(transform) — HOF
        if callee == lookup.zipWithNextName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkListZipWithNextTransformName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName || callee == lookup.onEachIndexedName, arguments.count == 1 {
            let kkName: InternedString
            if callee == lookup.forEachIndexedName {
                kkName = lookup.kkListForEachIndexedName
            } else if callee == lookup.onEachIndexedName {
                kkName = lookup.kkListOnEachIndexedName
            } else {
                kkName = lookup.kkListMapIndexedName
            }
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if callee == lookup.mapIndexedName || callee == lookup.onEachIndexedName, let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        if callee == lookup.unzipName, arguments.isEmpty {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListUnzipName,
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

        return false
    }

    // MARK: - Array virtual call operations (STDLIB-087/088/089)

    private func rewriteArrayVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // Non-tracked array receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        guard arrayExprIDs.contains(receiver.rawValue) else { return false }

        // toList on array → kk_array_toList (result is List)
        if callee == lookup.toListName, arguments.isEmpty {
            let toListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToListName,
                arguments: [receiver],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }

        // toMutableList on array → kk_array_toMutableList (result is MutableList)
        if callee == lookup.toMutableListName, arguments.isEmpty {
            let toMutableListResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToMutableListName,
                arguments: [receiver],
                result: toMutableListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toMutableListResult.rawValue)
                loweredBody.append(.copy(from: toMutableListResult, to: result))
            }
            return true
        }

        // map/filter on array → kk_array_map/kk_array_filter (result is List)
        if callee == lookup.mapName || callee == lookup.filterName, arguments.count == 1 {
            let kkName = callee == lookup.mapName
                ? lookup.kkArrayMapName : lookup.kkArrayFilterName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // forEach on array → kk_array_forEach
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkArrayForEachName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // any/none on array → kk_array_any/kk_array_none
        if callee == lookup.anyName || callee == lookup.noneName, arguments.count == 1 {
            let kkName = callee == lookup.anyName
                ? lookup.kkArrayAnyName : lookup.kkArrayNoneName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // copyOf on array → kk_array_copyOf (result is Array)
        if callee == lookup.copyOfName, arguments.isEmpty {
            let copyResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfName,
                arguments: [receiver],
                result: copyResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // copyOfRange on array → kk_array_copyOfRange (result is Array)
        if callee == lookup.copyOfRangeName, arguments.count == 2 {
            let copyResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfRangeName,
                arguments: [receiver] + arguments,
                result: copyResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // fill on array → kk_array_fill
        if callee == lookup.fillName, arguments.count == 1 {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFillName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // asSequence on array → kk_array_asSequence (STDLIB-471)
        if callee == lookup.asSequenceName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        return false
    }

    private func rewriteCountFirstLastFoldReduceHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard listExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.countName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListCountName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.firstName || callee == lookup.lastName {
            let kkName: InternedString = callee == lookup.firstName
                ? lookup.kkListFirstName
                : lookup.kkListLastName
            if arguments.isEmpty {
                // No-arg first()/last(): Runtime expects (listRaw, fnPtr=0, closureRaw=0, outThrown)
                let zeroExpr1 = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr1, value: .intLiteral(0)))
                let zeroExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr2, value: .intLiteral(0)))
                _ = emitHOFCall(
                    kkName: kkName, receiver: receiver, arguments: [zeroExpr1, zeroExpr2],
                    result: result, origCanThrow: origCanThrow,
                    origThrownResult: origThrownResult, module: module,
                    loweredBody: &loweredBody
                )
                return true
            }
            if arguments.count == 1 {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                _ = emitHOFCall(
                    kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                    result: result, origCanThrow: origCanThrow,
                    origThrownResult: origThrownResult, module: module,
                    loweredBody: &loweredBody
                )
                return true
            }
        }

        if callee == lookup.foldName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListFoldName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.reduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListReduceName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if (callee == lookup.scanName || callee == lookup.runningFoldName), arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let kkName = callee == lookup.scanName ? lookup.kkListScanName : lookup.kkListRunningFoldName
            let hofResult = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        if callee == lookup.runningReduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkListRunningReduceName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // reduceOrNull: args = [lambda]
        if callee == lookup.reduceOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListReduceOrNullName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // scanReduce: args = [lambda] — alias for runningReduce
        if callee == lookup.scanReduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkListScanReduceName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // filterIndexed: args = [lambda]
        if callee == lookup.filterIndexedName || callee == lookup.kkListFilterIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(kkName: lookup.kkListFilterIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            if let result { listExprIDs.insert(result.rawValue); listExprIDs.insert(hofResult.rawValue) }
            return true
        }
        // foldIndexed: args = [initial, lambda]
        if (callee == lookup.foldIndexedName || callee == lookup.kkListFoldIndexedName), arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListFoldIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceIndexed: args = [lambda]
        if (callee == lookup.reduceIndexedName || callee == lookup.kkListReduceIndexedName), arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceIndexedOrNull: args = [lambda]
        if callee == lookup.reduceIndexedOrNullName || callee == lookup.kkListReduceIndexedOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceIndexedOrNullName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // runningFoldIndexed: args = [initial, lambda]
        if callee == lookup.runningFoldIndexedName || callee == lookup.kkListRunningFoldIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(kkName: lookup.kkListRunningFoldIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            if let result { listExprIDs.insert(result.rawValue); listExprIDs.insert(hofResult.rawValue) }
            return true
        }
        // runningReduceIndexed: args = [lambda]
        if callee == lookup.runningReduceIndexedName || callee == lookup.kkListRunningReduceIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(kkName: lookup.kkListRunningReduceIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            if let result { listExprIDs.insert(result.rawValue); listExprIDs.insert(hofResult.rawValue) }
            return true
        }
        // scanIndexed: args = [initial, lambda]
        if callee == lookup.scanIndexedName || callee == lookup.kkListScanIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(kkName: lookup.kkListScanIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            if let result { listExprIDs.insert(result.rawValue); listExprIDs.insert(hofResult.rawValue) }
            return true
        }

        if callee == lookup.indexOfFirstName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListIndexOfFirstName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.indexOfLastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListIndexOfLastName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.partitionName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListPartitionName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        return false
    }

    // MARK: - IntRange operations (STDLIB-090/091/092/093)

    private func rewriteRangeVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        sema: SemaModule?,
        interner: StringInterner,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard rangeExprIDs.contains(receiver.rawValue) else { return false }
        let isCharRange = charRangeExprIDs.contains(receiver.rawValue)
        let isULongRange = ulongRangeExprIDs.contains(receiver.rawValue)
        let isUIntRange = sema.map { module.arena.exprType(receiver) == $0.types.uintType } ?? false

        // step — simple property access (STDLIB-RANGE-037)
        if callee == lookup.stepName, arguments.isEmpty {
            let stepName = isULongRange ? lookup.kkULongRangeStepName : (isUIntRange ? interner.intern("kk_uint_range_step") : lookup.kkRangeStepName)
            loweredBody.append(.call(
                symbol: nil, callee: stepName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // first / last / start / endInclusive / count — simple property access (STDLIB-092 / STDLIB-RANGE-034)
        if (callee == lookup.firstName || callee == lookup.startName), arguments.isEmpty {
            let firstName = isULongRange ? lookup.kkULongRangeFirstName : (isUIntRange ? interner.intern("kk_uint_range_first") : lookup.kkRangeFirstName)
            loweredBody.append(.call(
                symbol: nil, callee: firstName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if (callee == lookup.lastName || callee == lookup.endInclusiveName), arguments.isEmpty {
            let lastName = isULongRange ? lookup.kkULongRangeLastName : (isUIntRange ? interner.intern("kk_uint_range_last") : lookup.kkRangeLastName)
            loweredBody.append(.call(
                symbol: nil, callee: lastName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.countName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: isUIntRange ? interner.intern("kk_uint_range_count") : lookup.kkRangeCountName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        // STDLIB-637: isEmpty / sum
        if callee == lookup.isEmptyName, arguments.isEmpty {
            let isEmptyName = isULongRange ? lookup.kkULongRangeIsEmptyName : (isUIntRange ? interner.intern("kk_uint_range_isEmpty") : lookup.kkRangeIsEmptyName)
            loweredBody.append(.call(
                symbol: nil, callee: isEmptyName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.sumName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: isUIntRange ? interner.intern("kk_uint_range_sum") : lookup.kkRangeSumName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // contains — delegate to kk_op_contains (STDLIB-090) or kk_ulong_range_contains (STDLIB-RANGE-037)
        if callee == lookup.containsName, arguments.count == 1 {
            let containsName = isULongRange ? lookup.kkULongRangeContainsName : (isUIntRange ? interner.intern("kk_uint_range_contains") : lookup.kkOpContainsName)
            loweredBody.append(.call(
                symbol: nil, callee: containsName,
                arguments: [receiver, arguments[0]], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toList — returns a List (STDLIB-091 / STDLIB-290 / STDLIB-524)
        if callee == lookup.toListName, arguments.isEmpty {
            let toListCallee: InternedString
            if isCharRange {
                toListCallee = lookup.kkCharRangeToListName
            } else if isULongRange {
                toListCallee = lookup.kkULongRangeToListName
            } else if isUIntRange {
                toListCallee = interner.intern("kk_uint_range_toList")
            } else {
                toListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(
                symbol: nil, callee: toListCallee,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        if callee == interner.intern("toUIntArray"), arguments.isEmpty, isUIntRange {
            loweredBody.append(.call(
                symbol: nil, callee: interner.intern("kk_uint_range_toUIntArray"),
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toULongArray — returns a ULongArray (STDLIB-RANGE-037)
        if callee == lookup.toULongArrayName, arguments.isEmpty, isULongRange {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkULongRangeToULongArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toLongArray — returns a LongArray (STDLIB-RANGE-035)
        if callee == lookup.toLongArrayName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkLongRangeToLongArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toIntArray — returns an IntArray (STDLIB-RANGE-034)
        if callee == lookup.toIntArrayName, arguments.isEmpty, !isCharRange, !isULongRange {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeToIntArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        if callee == lookup.iteratorName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeIteratorName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // forEach — HOF (STDLIB-091 / STDLIB-290)
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let forEachCallee = isCharRange ? lookup.kkCharRangeForEachName : (isUIntRange ? interner.intern("kk_uint_range_forEach") : lookup.kkRangeForEachName)
            _ = emitHOFCall(
                kkName: forEachCallee, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // map — HOF returning List (STDLIB-091)
        if callee == lookup.mapName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isUIntRange ? interner.intern("kk_uint_range_map") : lookup.kkRangeMapName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // Additional range HOFs.
        if callee == lookup.mapIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeMapIndexedName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.mapNotNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeMapNotNullName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterIndexedName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterNotName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterNotName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.reduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeReduceName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.reduceIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeReduceIndexedName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFoldName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFoldIndexedName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFindName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findLastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFindLastName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFirstPredicateName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeFirstOrNullPredicateName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeLastPredicateName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeLastOrNullPredicateName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if (callee == lookup.anyName || callee == lookup.allName || callee == lookup.noneName), arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let kkName: InternedString =
                callee == lookup.anyName ? lookup.kkRangeAnyName
                    : callee == lookup.allName ? lookup.kkRangeAllName
                    : lookup.kkRangeNoneName
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.chunkedName, arguments.count == 1 {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeChunkedName,
                arguments: [receiver] + arguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.windowedName, arguments.count == 3 {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeWindowedName,
                arguments: [receiver] + arguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // reversed — returns a range (STDLIB-093)
        if callee == lookup.reversedName, arguments.isEmpty {
            let reversedName = isULongRange ? lookup.kkULongRangeReversedName : (isUIntRange ? interner.intern("kk_uint_range_reversed") : lookup.kkRangeReversedName)
            loweredBody.append(.call(
                symbol: nil, callee: reversedName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result {
                rangeExprIDs.insert(result.rawValue)
                // Propagate char range through reversed() (STDLIB-290)
                if isCharRange { charRangeExprIDs.insert(result.rawValue) }
                // Propagate ULong range through reversed() (STDLIB-524)
                if isULongRange { ulongRangeExprIDs.insert(result.rawValue) }
            }
            return true
        }

        return false
    }

    // MARK: - Static type fallback classification (LOWERING-001)

    /// Classify a receiver expression by its static type in the KIR arena.
    /// If the receiver is already in one of the tracking sets, this is a no-op.
    /// Otherwise, look up the expression's TypeID, resolve its class symbol,
    /// and insert it into the appropriate tracking set so that downstream
    /// rewrite logic can match on it.
    private func classifyReceiverByStaticType(
        receiver: KIRExprID,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        let raw = receiver.rawValue
        // Already classified -- skip.
        if listExprIDs.contains(raw) || setExprIDs.contains(raw)
            || mapExprIDs.contains(raw) || arrayExprIDs.contains(raw)
            || sequenceExprIDs.contains(raw)
        {
            return
        }
        guard let sema = context.sema else { return }
        guard let typeID = context.module.arena.exprType(receiver) else { return }

        let types = sema.types
        let symbols = sema.symbols
        let interner = context.interner

        let kind = types.kind(of: typeID)
        guard case let .classType(classType) = kind else { return }
        let classSymbol = classType.classSymbol
        guard let symInfo = symbols.symbol(classSymbol) else { return }
        guard let simpleName = symInfo.fqName.last else { return }

        let resolved = interner.resolve(simpleName)
        switch resolved {
        case "List", "MutableList", "ArrayList",
             "AbstractList", "AbstractMutableList":
            listExprIDs.insert(raw)
        case "Set", "MutableSet", "HashSet", "LinkedHashSet",
             "AbstractSet", "AbstractMutableSet":
            setExprIDs.insert(raw)
        case "Map", "MutableMap", "HashMap", "LinkedHashMap",
             "AbstractMap", "AbstractMutableMap":
            mapExprIDs.insert(raw)
        case "Array", "IntArray", "LongArray", "DoubleArray",
             "FloatArray", "BooleanArray", "CharArray",
             "ByteArray", "ShortArray", "UIntArray", "ULongArray":
            arrayExprIDs.insert(raw)
        case "Sequence":
            sequenceExprIDs.insert(raw)
        default:
            break
        }
    }
}
