import Foundation
import RuntimeABI

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
           listExprIDs.contains(receiver.rawValue) || setExprIDs.contains(receiver.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListIteratorName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        if rewriteRangeVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            sema: context.sema, interner: context.interner,
            rangeExprIDs: &rangeExprIDs, charRangeExprIDs: &charRangeExprIDs,
            ulongRangeExprIDs: &ulongRangeExprIDs,
            setExprIDs: &setExprIDs,
            listExprIDs: &listExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if (callee == lookup.foldIndexedName || callee == lookup.kkListFoldIndexedName),
           arguments.count == 2,
           setExprIDs.contains(receiver.rawValue)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListFoldIndexedName,
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

        // toTypedArray()/toTypeArray() on list -> kk_list_toTypedArray (result is Array)
        if callee == lookup.toTypedArrayName || callee == lookup.toTypeArrayName,
           arguments.isEmpty,
           listExprIDs.contains(receiver.rawValue)
        {
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

        // toTypedArray() on array → kk_array_copyOf (result is Array)
        if callee == lookup.toTypedArrayName, arguments.isEmpty, arrayExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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

        // toIntArray() on list → kk_list_toIntArray (STDLIB-LIST-PRIM-ARRAY)
        if callee == lookup.toIntArrayName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListToIntArrayName,
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

        // toLongArray() on list → kk_list_toLongArray (STDLIB-LIST-PRIM-ARRAY)
        if callee == lookup.toLongArrayName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListToLongArrayName,
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

        // toByteArray() on list → kk_list_toByteArray (STDLIB-LIST-PRIM-ARRAY)
        if callee == lookup.toByteArrayName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListToByteArrayName,
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

        let unsignedArrayCallee: InternedString? = switch callee {
        case lookup.toCharArrayName: lookup.kkListToCharArrayName
        case lookup.toBooleanArrayName: lookup.kkListToBooleanArrayName
        case lookup.toShortArrayName: lookup.kkListToShortArrayName
        case lookup.toDoubleArrayName: lookup.kkListToDoubleArrayName
        case lookup.toFloatArrayName: lookup.kkListToFloatArrayName
        case lookup.toUByteArrayName: lookup.kkListToUByteArrayName
        case lookup.toUShortArrayName: lookup.kkListToUShortArrayName
        case lookup.toUIntArrayName: lookup.kkListToUIntArrayName
        case lookup.toULongArrayName: lookup.kkListToULongArrayName
        default: nil
        }
        if let unsignedArrayCallee, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let toArrayResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: unsignedArrayCallee,
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
        case lookup.printWriterName:
            kkCallee = arguments.isEmpty ? lookup.kkFilePrintWriterName : nil
        case lookup.walkName:
            kkCallee = switch arguments.count {
            case 0:
                lookup.kkFileWalkName
            case 1:
                lookup.kkFileWalkDirectionName
            default:
                nil
            }
        case lookup.walkTopDownName:
            kkCallee = arguments.isEmpty ? lookup.kkFileWalkTopDownName : nil
        case lookup.walkBottomUpName:
            kkCallee = arguments.isEmpty ? lookup.kkFileWalkBottomUpName : nil
        case lookup.listFilesName:
            kkCallee = lookup.kkFileListFilesName
        case lookup.deleteName:
            kkCallee = lookup.kkFileDeleteName
        case lookup.deleteRecursivelyName:
            kkCallee = lookup.kkFileDeleteRecursivelyName
        case lookup.mkdirsName:
            kkCallee = lookup.kkFileMkdirsName
        case lookup.readBytesName:
            kkCallee = lookup.kkFileReadBytesName
        case lookup.appendTextName:
            kkCallee = lookup.kkFileAppendTextName
        case lookup.copyToName:
            kkCallee = switch arguments.count {
            case 1:
                lookup.kkFileCopyToDefaultName
            case 2:
                lookup.kkFileCopyToOverwriteName
            case 3:
                lookup.kkFileCopyToName
            default:
                nil
            }
        case lookup.copyRecursivelyName:
            kkCallee = switch arguments.count {
            case 1:
                lookup.kkFileCopyRecursivelyDefaultName
            case 2:
                lookup.kkFileCopyRecursivelyOverwriteName
            default:
                nil
            }
        default:
            kkCallee = nil
        }

        guard let target = kkCallee else { return false }

        // Methods that pass extra arguments beyond the receiver
        let needsExtraArgs = callee == lookup.forEachLineName
            || callee == lookup.useLinesName
            || callee == lookup.writeTextName
            || callee == lookup.appendTextName
            || callee == lookup.copyToName
            || callee == lookup.copyRecursivelyName
            || callee == lookup.walkName
            || callee == lookup.walkTopDownName
            || callee == lookup.walkBottomUpName
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
        if (callee == lookup.readLinesName
            || callee == lookup.readBytesName
            || callee == lookup.walkName
            || callee == lookup.walkTopDownName
            || callee == lookup.walkBottomUpName
        ), let result {
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
            context: context,
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
        context: VirtualCallRewriteContext,
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
            || callee == lookup.filterNotName
            || callee == lookup.forEachName || callee == lookup.onEachName
            || callee == lookup.flatMapName || callee == lookup.flatMapIndexedName
            || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        else { return false }
        guard arguments.count == 1, listExprIDs.contains(receiver.rawValue) else { return false }

        let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1) ?? callee
        let needsListTag = callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName || callee == lookup.filterName
            || callee == lookup.filterNotName
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
        case thenDescending(inner: KIRExprID)
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
        thenDescendingCallee: InternedString? = nil,
        thenComparatorCallee: InternedString? = nil,
        nullsFirstCallee: InternedString? = nil,
        nullsLastCallee: InternedString? = nil,
        multiSelector3Callee: InternedString? = nil,
        multiSelectorVarargCallee: InternedString? = nil,
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
                    if let msVararg = multiSelectorVarargCallee, callee == msVararg { return .multiSelector }
                    if callee == naturalOrderCallee { return .naturalOrder }
                    if callee == reverseOrderCallee { return .reverseOrder }
                    if let thenBy = thenByCallee, callee == thenBy, let innerExpr = arguments.first {
                        return .thenBy(inner: innerExpr)
                    }
                    if let thenByDescending = thenByDescendingCallee, callee == thenByDescending, let innerExpr = arguments.first {
                        return .thenByDescending(inner: innerExpr)
                    }
                    if let thenDescending = thenDescendingCallee, callee == thenDescending, let innerExpr = arguments.first {
                        return .thenDescending(inner: innerExpr)
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
                        thenDescendingCallee: thenDescendingCallee,
                        thenComparatorCallee: thenComparatorCallee,
                        nullsFirstCallee: nullsFirstCallee,
                        nullsLastCallee: nullsLastCallee,
                        multiSelector3Callee: multiSelector3Callee,
                        multiSelectorVarargCallee: multiSelectorVarargCallee,
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
        guard callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName || callee == lookup.findLastName
            || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
            || callee == lookup.sortedByDescendingName || callee == lookup.sortedWithName
            || callee == lookup.maxByName || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
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
        case lookup.findLastName: lookup.kkListFindLastName
        case lookup.associateByName: lookup.kkListAssociateByName
        case lookup.associateWithName: lookup.kkListAssociateWithName
        case lookup.associateName: lookup.kkListAssociateName
        case lookup.maxByName: lookup.kkListMaxByName
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
                thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
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
                thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
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
            case .thenDescending:
                cmpTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
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
        let needsClosureRaw = callee != lookup.maxByName
            && callee != lookup.maxByOrNullName && callee != lookup.minByOrNullName
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

        guard callee == lookup.filterToName || callee == lookup.filterNotToName
            || callee == lookup.mapToName || callee == lookup.flatMapToName
            || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName
            || callee == lookup.mapIndexedNotNullToName
            || callee == lookup.flatMapIndexedToName || callee == lookup.associateToName
        else {
            return false
        }

        guard (arguments.count == 2 || arguments.count == 3),
              listExprIDs.contains(receiver.rawValue) || sequenceExprIDs.contains(receiver.rawValue)
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

        let isSequenceReceiver = sequenceExprIDs.contains(receiver.rawValue)
        let kkName: InternedString = switch callee {
        case lookup.filterToName: lookup.kkListFilterToName
        case lookup.filterNotToName: lookup.kkListFilterNotToName
        case lookup.mapToName: lookup.kkListMapToName
        case lookup.flatMapToName: lookup.kkListFlatMapToName
        case lookup.mapNotNullToName: lookup.kkListMapNotNullToName
        case lookup.mapIndexedToName: lookup.kkListMapIndexedToName
        case lookup.mapIndexedNotNullToName: lookup.kkListMapIndexedNotNullToName
        case lookup.flatMapIndexedToName: lookup.kkListFlatMapIndexedToName
        case lookup.filterIndexedToName:
            isSequenceReceiver ? lookup.kkSequenceFilterIndexedToName : lookup.kkListFilterIndexedToName
        case lookup.associateToName:
            isSequenceReceiver ? lookup.kkSequenceAssociateToName : lookup.kkListAssociateToName
        default: callee
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
        guard (arguments.count == 2 || arguments.count == 3),
              listExprIDs.contains(receiver.rawValue) || sequenceExprIDs.contains(receiver.rawValue)
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

        let isSequenceReceiver = sequenceExprIDs.contains(receiver.rawValue)
        let kkName: InternedString = switch callee {
        case lookup.associateByToName:
            isSequenceReceiver ? lookup.kkSequenceAssociateByToName : lookup.kkListAssociateByToName
        case lookup.associateWithToName:
            isSequenceReceiver ? lookup.kkSequenceAssociateWithToName : lookup.kkListAssociateWithToName
        case lookup.groupByToName:
            isSequenceReceiver ? lookup.kkSequenceGroupByToName : lookup.kkListGroupByToName
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

        if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName
            || callee == lookup.mapIndexedNotNullName || callee == lookup.onEachIndexedName
            || callee == lookup.flatMapIndexedName,
            arguments.count == 1 {
            let kkName: InternedString
            if callee == lookup.forEachIndexedName {
                kkName = lookup.kkListForEachIndexedName
            } else if callee == lookup.onEachIndexedName {
                kkName = lookup.kkListOnEachIndexedName
            } else if callee == lookup.mapIndexedNotNullName {
                kkName = lookup.kkListMapIndexedNotNullName
            } else if callee == lookup.flatMapIndexedName {
                kkName = lookup.kkListFlatMapIndexedName
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
            if callee == lookup.mapIndexedName || callee == lookup.mapIndexedNotNullName
                || callee == lookup.onEachIndexedName || callee == lookup.flatMapIndexedName,
                let result {
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
        if setExprIDs.contains(receiver.rawValue), callee == lookup.foldName, arguments.count == 2 {
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
        // foldRight: args = [initial, lambda]
        if callee == lookup.foldRightName || callee == lookup.kkListFoldRightName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListFoldRightName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // foldRightIndexed: args = [initial, lambda]
        if callee == lookup.foldRightIndexedName || callee == lookup.kkListFoldRightIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListFoldRightIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceRight: args = [lambda]
        if callee == lookup.reduceRightName || callee == lookup.kkListReduceRightName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceRightName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceRightIndexed: args = [lambda]
        if callee == lookup.reduceRightIndexedName || callee == lookup.kkListReduceRightIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceRightIndexedName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceRightIndexedOrNull: args = [lambda]
        if callee == lookup.reduceRightIndexedOrNullName || callee == lookup.kkListReduceRightIndexedOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceRightIndexedOrNullName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
            return true
        }
        // reduceRightOrNull: args = [lambda]
        if callee == lookup.reduceRightOrNullName || callee == lookup.kkListReduceRightOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(kkName: lookup.kkListReduceRightOrNullName, receiver: receiver, arguments: arguments + [zeroExpr], result: result, origCanThrow: origCanThrow, origThrownResult: origThrownResult, module: module, loweredBody: &loweredBody)
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
             "ByteArray", "ShortArray", "UByteArray", "UShortArray", "UIntArray", "ULongArray":
            arrayExprIDs.insert(raw)
        case "Sequence":
            sequenceExprIDs.insert(raw)
        default:
            break
        }
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
        let nonNullType = sema.types.makeNonNullable(typeID)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
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
}
