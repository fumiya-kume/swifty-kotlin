import Foundation

extension CollectionLiteralLoweringPass {
    /// Returns true when the virtual call was rewritten and appended.
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

        if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.forEachName
            || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
        {
            if arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.mapName: lookup.kkListMapName
                case lookup.filterName: lookup.kkListFilterName
                case lookup.forEachName: lookup.kkListForEachName
                case lookup.flatMapName: lookup.kkListFlatMapName
                case lookup.anyName: lookup.kkListAnyName
                case lookup.noneName: lookup.kkListNoneName
                case lookup.allName: lookup.kkListAllName
                default: callee
                }
                let needsListTag = callee == lookup.mapName
                    || callee == lookup.flatMapName || callee == lookup.filterName
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: hofResult,
                    canThrow: origCanThrow,
                    thrownResult: origThrownResult
                ))
                if needsListTag, let result {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }

        if callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName {
            if arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.groupByName: lookup.kkListGroupByName
                case lookup.sortedByName: lookup.kkListSortedByName
                case lookup.findName: lookup.kkListFindName
                default: callee
                }
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
                if callee == lookup.sortedByName, let result {
                    listExprIDs.insert(result.rawValue)
                    listExprIDs.insert(hofResult.rawValue)
                }
                if callee == lookup.groupByName, let result {
                    mapExprIDs.insert(result.rawValue)
                    mapExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }

        // TODO: Support zero-arg first()/last() by lowering to kk_list_get equivalents
        if callee == lookup.countName || callee == lookup.firstName || callee == lookup.lastName {
            if arguments.count == 1, listExprIDs.contains(receiver.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.countName: lookup.kkListCountName
                case lookup.firstName: lookup.kkListFirstName
                case lookup.lastName: lookup.kkListLastName
                default: callee
                }
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
                return true
            }
        }

        if callee == lookup.foldName, arguments.count == 2 {
            if listExprIDs.contains(receiver.rawValue) {
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListFoldName,
                    arguments: [receiver] + arguments,
                    result: hofResult,
                    canThrow: origCanThrow,
                    thrownResult: origThrownResult
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }

        if callee == lookup.reduceName, arguments.count == 1 {
            if listExprIDs.contains(receiver.rawValue) {
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListReduceName,
                    arguments: [receiver] + arguments,
                    result: hofResult,
                    canThrow: origCanThrow,
                    thrownResult: origThrownResult
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }

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
