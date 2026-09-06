import RuntimeABI

extension CollectionVirtualCallRewriteLoweringPass {
    struct VirtualCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
        let functionBody: [KIRInstruction]
        let sema: SemaModule?
        let interner: StringInterner
    }

    /// Returns true when the callee resolves to a bundled Kotlin source declaration
    /// that should not be rewritten to a runtime `kk_*` entry point.
    private func shouldPreserveSourceBackedVirtualCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        receiver: KIRExprID,
        context: VirtualCallRewriteContext
    ) -> Bool {
        // KSP-1513: array `size` is a bundled Kotlin declaration, so do not
        // replace it with the generic runtime bridge when the receiver is an
        // Array<T> or primitive array.
        if callee == lookup.sizeName,
           let symbol,
           let sema = context.sema,
           sema.symbols.isSourceBackedSymbol(symbol),
           let receiverType = context.module.arena.exprType(receiver),
           let (_, receiverSymbol) = resolveClassTypeSymbol(
               receiverType,
               sema: sema
           )
        {
            let sourceBackedArrayNames: Set<String> = [
                "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
                "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
            ]
            return sourceBackedArrayNames.contains(context.interner.resolve(receiverSymbol.name))
        }

        // KSP-1516: array conversion members are bundled Kotlin source. Keep
        // the selected declaration so its source body is emitted instead of
        // the removed synthetic runtime shortcuts.
        if callee == lookup.sliceArrayName
            || callee == lookup.reversedArrayName
            || callee == lookup.asListName
            || callee == lookup.toTypedArrayName,
           let symbol,
           let sema = context.sema,
           sema.symbols.isSourceBackedSymbol(symbol),
           let receiverType = context.module.arena.exprType(receiver),
           let (_, receiverSymbol) = resolveClassTypeSymbol(
               receiverType,
               sema: sema
           )
        {
            let sourceBackedArrayNames: Set<String> = [
                "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
                "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
            ]
            return sourceBackedArrayNames.contains(context.interner.resolve(receiverSymbol.name))
        }

        guard callee == lookup.foldName
            || callee == lookup.foldRightName
            || callee == lookup.reduceName
            || callee == lookup.reduceOrNullName
            || callee == lookup.scanName
            || callee == lookup.scanIndexedName
            || callee == lookup.scanReduceName
            || callee == lookup.runningFoldName
            || callee == lookup.runningFoldIndexedName
            || callee == lookup.runningReduceName
            || callee == lookup.runningReduceIndexedName
            || callee == lookup.foldIndexedName
            || callee == lookup.foldRightIndexedName
            || callee == lookup.reduceRightName
            || callee == lookup.reduceRightOrNullName
            || callee == lookup.reduceRightIndexedName
            || callee == lookup.reduceRightIndexedOrNullName
            || callee == lookup.reduceIndexedName
            || callee == lookup.reduceIndexedOrNullName
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.filterNotNullName
            || callee == lookup.filterIndexedName
            || callee == lookup.associateName
            || callee == lookup.associateByName
            || callee == lookup.associateWithName
            || callee == lookup.associateToName
            || callee == lookup.associateByToName
            || callee == lookup.associateWithToName
            || callee == lookup.groupByName
            || callee == lookup.groupByToName
            || callee == lookup.partitionName
            || callee == lookup.unzipName
            || callee == lookup.withIndexName
            || callee == lookup.onEachName
            || callee == lookup.onEachIndexedName
            || callee == lookup.sumOfName
            || callee == lookup.maxByOrNullName
            || callee == lookup.minByOrNullName
            // KSP-426: List sorting/extrema are bundled Kotlin source.
            || callee == lookup.sortedName
            || callee == lookup.sortedByName
            || callee == lookup.sortedByDescendingName
            || callee == lookup.sortedDescendingName
            || callee == lookup.sortedWithName
            || callee == lookup.maxName
            || callee == lookup.maxByName
            || callee == lookup.maxOfName
            || callee == lookup.maxOfOrNullName
            || callee == lookup.maxOfWithName
            || callee == lookup.maxOfWithOrNullName
            || callee == lookup.maxOrNullName
            || callee == lookup.maxWithName
            || callee == lookup.maxWithOrNullName
            || callee == lookup.minName
            || callee == lookup.minByName
            || callee == lookup.minByOrNullName
            || callee == lookup.minOfName
            || callee == lookup.minOfOrNullName
            || callee == lookup.minOfWithName
            || callee == lookup.minOfWithOrNullName
            || callee == lookup.minOrNullName
            || callee == lookup.minWithName
            || callee == lookup.minWithOrNullName
            || callee == lookup.mapName
            || callee == lookup.mapIndexedName
            || callee == lookup.mapNotNullName
            || callee == lookup.mapValuesName
            || callee == lookup.mapValuesToName
            || callee == lookup.mapKeysName
            || callee == lookup.mapKeysToName
            || callee == lookup.filterKeysName
            || callee == lookup.filterValuesName
            || callee == lookup.forEachName
            || callee == lookup.mapToName
            || callee == lookup.mapIndexedToName
            || callee == lookup.mapNotNullToName
            || callee == lookup.mapIndexedNotNullName
            || callee == lookup.mapIndexedNotNullToName
            || callee == lookup.flatMapName
            || callee == lookup.flatMapIndexedName
            || callee == lookup.flatMapToName
            || callee == lookup.flatMapIndexedToName
            || callee == lookup.flattenName
            || callee == lookup.takeName
            || callee == lookup.dropName
            // KSP-423: List search and predicate HOFs have Kotlin source implementations.
            || callee == lookup.findName
            || callee == lookup.findLastName
            || callee == lookup.indexOfName
            || callee == lookup.lastIndexOfName
            || callee == lookup.indexOfFirstName
            || callee == lookup.indexOfLastName
            || callee == lookup.containsName
            || callee == lookup.containsAllName
            || callee == lookup.countName
            || callee == lookup.anyName
            || callee == lookup.allName
            || callee == lookup.noneName
            || callee == lookup.firstOrNullName
            || callee == lookup.lastOrNullName
            // KSP-658: generic Array<T>.copyOf / copyOfRange have Kotlin source implementations.
            || callee == lookup.copyOfName
            || callee == lookup.copyOfRangeName
            // KSP-312: Range/progression contains/isEmpty/iterator are now source-backed.
            || callee == lookup.isEmptyName
            || callee == lookup.iteratorName
            // KSP-453/454: Range/progression HOFs are now implemented in bundled Kotlin source.
            || callee == lookup.toListName
            || callee == lookup.toIntArrayName
            || callee == lookup.averageName
            || callee == lookup.sortedName
            || callee == lookup.chunkedName
            || callee == lookup.windowedName
            || callee == lookup.firstName
            || callee == lookup.lastName
            || callee == context.interner.intern("random")
            || callee == context.interner.intern("randomOrNull"),
            let symbol,
            let sema = context.sema,
            sema.symbols.symbol(symbol) != nil
        else {
            return false
        }
        return sema.symbols.isSourceBackedSymbol(symbol)
    }

    func rewriteVirtualCallInstruction(
        symbol: SymbolID?,
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
        pathExprIDs: inout Set<Int32>,
        indexingIterableExprIDs: inout Set<Int32>,
        listIteratorExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        // Handle runtime-backed collection iterators before the generic
        // source-backed preservation rule. A source-backed Iterable shell can
        // make the iterator member look like ordinary Kotlin source, while
        // the concrete list value still requires the shared list iterator ABI.
        if callee == lookup.iteratorName,
           arguments.isEmpty,
           listExprIDs.contains(receiver.rawValue) || setExprIDs.contains(receiver.rawValue) || indexingIterableExprIDs.contains(receiver.rawValue)
        {
            let iterCallee = indexingIterableExprIDs.contains(receiver.rawValue)
                ? lookup.kkIndexingIterableIteratorName
                : lookup.kkListIteratorName
            loweredBody.append(.call(
                symbol: nil,
                callee: iterCallee,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if iterCallee == lookup.kkListIteratorName, let result {
                listIteratorExprIDs.insert(result.rawValue)
            }
            return true
        }

        if shouldPreserveSourceBackedVirtualCall(
            symbol: symbol,
            callee: callee,
            lookup: lookup,
            receiver: receiver,
            context: context
        ) {
            return false
        }

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
            symbol: symbol,
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            context: context,
            listExprIDs: &listExprIDs, setExprIDs: &setExprIDs, mapExprIDs: &mapExprIDs, sequenceExprIDs: &sequenceExprIDs,
            arrayExprIDs: arrayExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteListHOFVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            setExprIDs: &setExprIDs, sequenceExprIDs: &sequenceExprIDs,
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

        // Runtime collection boxes do not carry generated itables, so route
        // stdlib list/set iterator calls directly to the shared iterator helper.
        if callee == lookup.iteratorName,
           arguments.isEmpty,
           listExprIDs.contains(receiver.rawValue) || setExprIDs.contains(receiver.rawValue) || indexingIterableExprIDs.contains(receiver.rawValue)
        {
            let iterCallee = indexingIterableExprIDs.contains(receiver.rawValue)
                ? lookup.kkIndexingIterableIteratorName
                : lookup.kkListIteratorName
            loweredBody.append(.call(
                symbol: nil,
                callee: iterCallee,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if iterCallee == lookup.kkListIteratorName, let result {
                listIteratorExprIDs.insert(result.rawValue)
            }
            return true
        }

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

        // KSP-628 + KSP-629: the List receivers of toTypedArray /
        // to{Char,Boolean,Short,Double,Float,Int,Long,Byte,UByte,UShort,UInt,ULong}Array
        // are source-backed (ArrayConversions.kt) and lower through normal function resolution.

        // toTypedArray() on array → __kk_array_copyOf (result is Array)
        if callee == lookup.toTypedArrayName, arguments.isEmpty, arrayExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfName,
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
        case lookup.existsName:
            kkCallee = lookup.kkFileExistsName
        case lookup.isFileName:
            kkCallee = lookup.kkFileIsFileName
        case lookup.isDirectoryName:
            kkCallee = lookup.kkFileIsDirectoryName
        // STDLIB-IO-FN-016: forEachBlock — arity-based dispatch (virtual call path, args excludes receiver)
        case lookup.forEachBlockName:
            kkCallee = arguments.isEmpty
                ? lookup.kkFileForEachBlockName
                : lookup.kkFileForEachBlockBlockSizeName
        case lookup.bufferedReaderName:
            // Only rewrite argument-less bufferedReader(); the runtime function
            // __kk_file_bufferedReader does not accept charset/bufferSize args.
            kkCallee = arguments.isEmpty ? lookup.kkFileBufferedReaderName : nil
        case lookup.bufferedWriterName:
            // Only rewrite argument-less bufferedWriter(); the runtime function
            // __kk_file_bufferedWriter does not accept charset/bufferSize args.
            kkCallee = arguments.isEmpty ? lookup.kkFileBufferedWriterName : nil
        case lookup.printWriterName:
            // Only rewrite argument-less printWriter(); the runtime function
            // __kk_file_printWriter does not accept charset/bufferSize args.
            kkCallee = arguments.isEmpty ? lookup.kkFilePrintWriterName : nil
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
        let needsExtraArgs = callee == lookup.forEachBlockName
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
        if callee == lookup.readBytesName, let result {
            listExprIDs.insert(result.rawValue)
        }

        return true
    }

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
        setExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
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

        if rewriteDestinationCollectionHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            sequenceExprIDs: &sequenceExprIDs, loweredBody: &loweredBody
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
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs, sequenceExprIDs: &sequenceExprIDs,
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
            listExprIDs: &listExprIDs, setExprIDs: &setExprIDs, loweredBody: &loweredBody
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
            || callee == lookup.mapValuesName || callee == lookup.mapKeysName
            || callee == lookup.filterKeysName || callee == lookup.filterValuesName
        else {
            return false
        }
        guard mapExprIDs.contains(receiver.rawValue) else { return false }

        guard arguments.count == 1 else { return false }

        let kkName = lookup.collectionHOFRuntimeName(ownerKind: .map, callee: callee, arity: 1) ?? callee
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
        if callee == lookup.mapName || callee == lookup.mapNotNullName, let result {
            listExprIDs.insert(result.rawValue)
            listExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.mapValuesName || callee == lookup.mapKeysName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.filterKeysName || callee == lookup.filterValuesName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    @discardableResult
    func emitHOFCall(
        kkName: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        loweredBody: inout [KIRInstruction]
    ) -> KIRExprID {
        let hofResult = module.arena.appendTemporary(type: nil
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
        guard callee == lookup.mapName || callee == lookup.mapNotNullName
            || callee == lookup.forEachName || callee == lookup.onEachName
            || callee == lookup.flatMapName || callee == lookup.flatMapIndexedName
            || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        else { return false }
        guard arguments.count == 1, listExprIDs.contains(receiver.rawValue),
              let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1)
        else { return false }
        let needsListTag = callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName
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
        guard callee == lookup.groupByName
            || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
        else {
            return false
        }
        guard arguments.count == 1,
              listExprIDs.contains(receiver.rawValue)
        else { return false }

        let kkName: InternedString = switch callee {
        case lookup.groupByName: lookup.kkListGroupByName
        case lookup.associateByName: lookup.kkListAssociateByName
        case lookup.associateWithName: lookup.kkListAssociateWithName
        case lookup.associateName: lookup.kkListAssociateName
        default: callee
        }

        var hofArgs = arguments
        if callee != lookup.groupByName {
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

    // STDLIB-021: toCollection and destination collection HOFs
    private func rewriteDestinationCollectionHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        if callee == lookup.toCollectionName {
            guard arguments.count == 1 else {
                return false
            }

            let destID = arguments[0]
            let kkName: InternedString
            if listExprIDs.contains(receiver.rawValue) {
                kkName = lookup.kkCollectionToCollectionName
            } else if sequenceExprIDs.contains(receiver.rawValue) {
                kkName = lookup.kkSequenceToCollectionName
            } else {
                return false
            }
            let hofResult = emitHOFCall(
                kkName: kkName,
                receiver: receiver,
                arguments: [destID],
                result: result,
                origCanThrow: false,
                origThrownResult: nil,
                module: module,
                loweredBody: &loweredBody
            )
            if let result, listExprIDs.contains(destID.rawValue) {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        guard callee == lookup.mapToName || callee == lookup.flatMapToName
            || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName
            || callee == lookup.mapIndexedNotNullToName
            || callee == lookup.flatMapIndexedToName || callee == lookup.associateToName
        else {
            return false
        }

        guard arguments.count == 2 || arguments.count == 3,
              listExprIDs.contains(receiver.rawValue)
        else {
            return false
        }

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

        guard let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 2) else {
            return false
        }

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
            } else if mapExprIDs.contains(destID.rawValue) {
                mapExprIDs.insert(result.rawValue)
                mapExprIDs.insert(hofResult.rawValue)
            }
        }
        return true
    }

    // STDLIB-SEQ-023 / STDLIB-535/536/537: associateByTo / associateWithTo / groupByTo
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
        sequenceExprIDs: inout Set<Int32>,
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
        guard arguments.count == 2 || arguments.count == 3,
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

        if callee == lookup.zipName, arguments.count == 1 {
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipBridgeName,
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

        if callee == lookup.zipName, arguments.count == 2 || arguments.count == 3 {
            let otherID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipTransformBridgeName,
                arguments: [receiver, otherID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: origCanThrow,
                thrownResult: origThrownResult
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
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipWithNextBridgeName,
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
                kkName: lookup.kkListZipWithNextTransformBridgeName,
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

        // KSP-626: withIndex / forEachIndexed are bundled Kotlin source, not bridges.
        if callee == lookup.mapIndexedName
            || callee == lookup.mapIndexedNotNullName || callee == lookup.onEachIndexedName
            || callee == lookup.flatMapIndexedName,
            arguments.count == 1,
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1) {
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
            if callee == lookup.mapIndexedName || callee == lookup.mapIndexedNotNullName
                || callee == lookup.onEachIndexedName || callee == lookup.flatMapIndexedName,
                let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        if callee == lookup.unzipName, arguments.isEmpty {
            let hofResult = module.arena.appendTemporary(type: nil
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
        setExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard listExprIDs.contains(receiver.rawValue) else { return false }

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

    func supportsIterableWindowedTransformReceiver(
        receiver: KIRExprID,
        context: VirtualCallRewriteContext,
        listExprIDs: Set<Int32>,
        setExprIDs: Set<Int32>,
        arrayExprIDs: Set<Int32>
    ) -> Bool {
        let raw = receiver.rawValue
        if listExprIDs.contains(raw) || setExprIDs.contains(raw) || arrayExprIDs.contains(raw) {
            return true
        }
        guard let sema = context.sema,
              let typeID = context.module.arena.exprType(receiver)
        else {
            return false
        }
        guard let (_, symbol) = resolveClassTypeSymbol(typeID, sema: sema),
              let simpleName = symbol.fqName.last
        else {
            return false
        }
        switch context.interner.resolve(simpleName) {
        case "Iterable", "Collection", "MutableCollection":
            return true
        default:
            return false
        }
    }

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

        switch trackedStaticTypeKind(of: symInfo, interner: interner) {
        case .list:
            listExprIDs.insert(raw)
        case .set:
            setExprIDs.insert(raw)
        case .map:
            mapExprIDs.insert(raw)
        case .array:
            arrayExprIDs.insert(raw)
        case .sequence:
            sequenceExprIDs.insert(raw)
        default:
            break
        }
    }

}
