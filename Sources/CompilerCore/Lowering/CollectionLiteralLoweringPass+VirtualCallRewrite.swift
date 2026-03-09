import Foundation

extension CollectionLiteralLoweringPass {
    func rewriteVirtualCallInstruction(
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
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if rewriteSequenceVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, sequenceExprIDs: &sequenceExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteListHOFVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteCollectionPropertyVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, lookup: lookup,
            listExprIDs: listExprIDs, mapExprIDs: mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

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
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if rewriteCommonListHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, loweredBody: &loweredBody
        ) { return true }

        if rewriteGroupSortFindHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteZipAndUnzipHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, module: module, lookup: lookup,
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
        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: arguments,
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
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName
            || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
        else {
            return false
        }
        guard arguments.count == 1, listExprIDs.contains(receiver.rawValue) else { return false }

        let kkName: InternedString = switch callee {
        case lookup.groupByName: lookup.kkListGroupByName
        case lookup.sortedByName: lookup.kkListSortedByName
        case lookup.findName: lookup.kkListFindName
        case lookup.associateByName: lookup.kkListAssociateByName
        case lookup.associateWithName: lookup.kkListAssociateWithName
        case lookup.associateName: lookup.kkListAssociateName
        default: callee
        }
        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if callee == lookup.sortedByName, let result {
            listExprIDs.insert(result.rawValue)
            listExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.groupByName, let result {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        if (callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName),
           let result
        {
            mapExprIDs.insert(result.rawValue)
            mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    private func rewriteZipAndUnzipHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard listExprIDs.contains(receiver.rawValue) else { return false }

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
        listExprIDs: Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard listExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.countName, arguments.count == 1 {
            _ = emitHOFCall(
                kkName: lookup.kkListCountName, receiver: receiver, arguments: arguments,
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
            if arguments.isEmpty || arguments.count == 1 {
                _ = emitHOFCall(
                    kkName: kkName, receiver: receiver, arguments: arguments,
                    result: result, origCanThrow: origCanThrow,
                    origThrownResult: origThrownResult, module: module,
                    loweredBody: &loweredBody
                )
                return true
            }
        }

        if callee == lookup.foldName, arguments.count == 2 {
            _ = emitHOFCall(
                kkName: lookup.kkListFoldName, receiver: receiver, arguments: arguments,
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.reduceName, arguments.count == 1 {
            _ = emitHOFCall(
                kkName: lookup.kkListReduceName, receiver: receiver, arguments: arguments,
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        return false
    }

    // MARK: - Collection property operations (size, isEmpty)

    private func rewriteCollectionPropertyVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: Set<Int32>,
        mapExprIDs: Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if callee == lookup.sizeName || callee == lookup.countName, arguments.isEmpty {
            if listExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if mapExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.isEmptyName, arguments.isEmpty {
            if listExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if mapExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        return false
    }
}
