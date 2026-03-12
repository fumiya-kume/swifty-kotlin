import Foundation

extension CollectionLiteralLoweringPass {
    struct VirtualCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
        let functionBody: [KIRInstruction]
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
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        if rewriteSequenceVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs, sequenceExprIDs: &sequenceExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteListHOFVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteCollectionPropertyVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, lookup: lookup,
            listExprIDs: listExprIDs, setExprIDs: setExprIDs, mapExprIDs: mapExprIDs,
            arrayExprIDs: arrayExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteArrayVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, arrayExprIDs: &arrayExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteRangeVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            rangeExprIDs: &rangeExprIDs, listExprIDs: &listExprIDs,
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

        return false
    }

    // MARK: - Sequence operations

    private func rewriteSequenceVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if callee == lookup.asSequenceName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFromListName,
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

        if callee == lookup.reversedName, arguments.isEmpty, listExprIDs.contains(receiver.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListReversedName,
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

        if rewriteZipUnzipAndIndexedHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, loweredBody: &loweredBody
        ) { return true }

        if rewriteCountFirstLastFoldReduceHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: listExprIDs, loweredBody: &loweredBody
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
        if callee == lookup.filterName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

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
            || callee == lookup.forEachName
            || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
        else { return false }
        guard arguments.count == 1, listExprIDs.contains(receiver.rawValue) else { return false }

        let kkName: InternedString = switch callee {
        case lookup.mapName: lookup.kkListMapName
        case lookup.filterName: lookup.kkListFilterName
        case lookup.mapNotNullName: lookup.kkListMapNotNullName
        case lookup.forEachName: lookup.kkListForEachName
        case lookup.flatMapName: lookup.kkListFlatMapName
        case lookup.anyName: lookup.kkListAnyName
        case lookup.noneName: lookup.kkListNoneName
        case lookup.allName: lookup.kkListAllName
        default: callee
        }
        let needsListTag = callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName || callee == lookup.filterName
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

    private enum ComparatorSource {
        case ascending
        case descending
        case naturalOrder
        case reverseOrder
        case unknown
    }

    private func isComparatorFromCall(
        exprID: KIRExprID,
        body: [KIRInstruction],
        ascendingCallee: InternedString,
        descendingCallee: InternedString,
        naturalOrderCallee: InternedString,
        reverseOrderCallee: InternedString
    ) -> ComparatorSource {
        for inst in body {
            switch inst {
            case let .call(_, callee, _, result, _, _, _):
                if let result, result.rawValue == exprID.rawValue {
                    if callee == ascendingCallee { return .ascending }
                    if callee == descendingCallee { return .descending }
                    if callee == naturalOrderCallee { return .naturalOrder }
                    if callee == reverseOrderCallee { return .reverseOrder }
                    return .unknown
                }
            case let .copy(from: fromID, to: toID):
                if toID.rawValue == exprID.rawValue {
                    return isComparatorFromCall(
                        exprID: fromID,
                        body: body,
                        ascendingCallee: ascendingCallee,
                        descendingCallee: descendingCallee,
                        naturalOrderCallee: naturalOrderCallee,
                        reverseOrderCallee: reverseOrderCallee
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
        else {
            return false
        }
        guard arguments.count == 1 || (callee == lookup.sortedWithName && arguments.count == 2),
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
        default: callee
        }

        var hofArgs: [KIRExprID]
        if callee == lookup.sortedWithName, arguments.count == 1 {
            let comparatorExpr = arguments[0]
            let source = isComparatorFromCall(
                exprID: comparatorExpr,
                body: context.functionBody,
                ascendingCallee: lookup.kkComparatorFromSelectorName,
                descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                reverseOrderCallee: lookup.kkComparatorReverseOrderName
            )
            let trampolineName: InternedString
            let closureExpr: KIRExprID
            switch source {
            case .descending:
                trampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
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
            default:
                trampolineName = lookup.kkComparatorFromSelectorTrampolineName
                closureExpr = comparatorExpr
            }
            let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
            loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
            hofArgs = [trampolineExpr, closureExpr]
        } else {
            hofArgs = arguments
        }

        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: hofArgs + [zeroExpr],
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if callee == lookup.sortedByName || callee == lookup.sortedByDescendingName || callee == lookup.sortedWithName,
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
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            // withIndex returns IndexingIterable, not List — do not add to listExprIDs
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

        if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName, arguments.count == 1 {
            let kkName = callee == lookup.forEachIndexedName
                ? lookup.kkListForEachIndexedName
                : lookup.kkListMapIndexedName
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
            if callee == lookup.mapIndexedName, let result {
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
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
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
        listExprIDs: Set<Int32>,
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
        rangeExprIDs: inout Set<Int32>,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard rangeExprIDs.contains(receiver.rawValue) else { return false }

        // first / last / count — simple property access (STDLIB-092)
        if callee == lookup.firstName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeFirstName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.lastName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeLastName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.countName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeCountName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // contains — delegate to kk_op_contains (STDLIB-090)
        if callee == lookup.containsName, arguments.count == 1 {
            let kkContainsName = lookup.kkOpContainsName
            loweredBody.append(.call(
                symbol: nil, callee: kkContainsName,
                arguments: [receiver, arguments[0]], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toList — returns a List (STDLIB-091)
        if callee == lookup.toListName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeToListName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // forEach — HOF (STDLIB-091)
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkRangeForEachName, receiver: receiver,
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
                kkName: lookup.kkRangeMapName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // reversed — returns a range (STDLIB-093)
        if callee == lookup.reversedName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeReversedName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { rangeExprIDs.insert(result.rawValue) }
            return true
        }

        return false
    }
}
