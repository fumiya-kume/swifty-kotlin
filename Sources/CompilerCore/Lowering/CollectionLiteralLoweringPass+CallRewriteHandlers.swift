extension CollectionLiteralLoweringPass {
    struct CollectionCallRewrite {
        let callee: InternedString
        let arguments: [KIRExprID]
        let result: KIRExprID?
        let canThrow: Bool
        let thrownResult: KIRExprID?
    }

    struct CollectionCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
    }

    struct CollectionCallRewriteResult {
        let instructions: [KIRInstruction]
    }

    func rewriteCollectionHOFCall(
        call: CollectionCallRewrite,
        state: inout CollectionRewriteState,
        ctx: CollectionCallRewriteContext
    ) -> CollectionCallRewriteResult? {
        let lookup = ctx.lookup
        guard isCollectionHOFMemberName(call.callee, lookup: lookup) else {
            return nil
        }

        var instructions: [KIRInstruction] = []

        if call.callee == lookup.toListName, call.arguments.count == 1 {
            let receiverID = call.arguments[0]
            if state.mapExprIDs.contains(receiverID.rawValue) {
                let toListResult = ctx.module.arena.appendExpr(
                    .temporary(Int32(ctx.module.arena.expressions.count)), type: nil
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToListName,
                    arguments: [receiverID],
                    result: toListResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                state.tagListResult(call.result, temporary: toListResult)
                if let result = call.result {
                    instructions.append(.copy(from: toListResult, to: result))
                }
                return CollectionCallRewriteResult(instructions: instructions)
            }
            if state.setExprIDs.contains(receiverID.rawValue) {
                let toListResult = ctx.module.arena.appendExpr(
                    .temporary(Int32(ctx.module.arena.expressions.count)), type: nil
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToListName,
                    arguments: [receiverID],
                    result: toListResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                state.tagListResult(call.result, temporary: toListResult)
                if let result = call.result {
                    instructions.append(.copy(from: toListResult, to: result))
                }
                return CollectionCallRewriteResult(instructions: instructions)
            }
        }

        guard call.arguments.count == 2 || call.arguments.count == 3 else {
            return nil
        }
        let receiverID = call.arguments[0]
        let lambdaID = call.arguments[1]

        if state.listExprIDs.contains(receiverID.rawValue), call.callee != lookup.countName {
            let closureRawID = closureRawArgument(for: call.arguments, module: ctx.module, instructions: &instructions)
            let kkName = listHOFRuntimeName(for: call.callee, lookup: lookup)
            let hofResult = ctx.module.arena.appendExpr(
                .temporary(Int32(ctx.module.arena.expressions.count)), type: nil
            )
            instructions.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ))
            if listHOFReturnsList(call.callee, lookup: lookup) {
                state.tagListResult(call.result, temporary: hofResult)
            }
            if let result = call.result {
                instructions.append(.copy(from: hofResult, to: result))
            }
            return CollectionCallRewriteResult(instructions: instructions)
        }

        if state.mapExprIDs.contains(receiverID.rawValue),
           let kkName = mapHOFRuntimeName(for: call.callee, lookup: lookup)
        {
            let closureRawID = closureRawArgument(for: call.arguments, module: ctx.module, instructions: &instructions)
            let hofResult = ctx.module.arena.appendExpr(
                .temporary(Int32(ctx.module.arena.expressions.count)), type: nil
            )
            instructions.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ))
            if mapHOFReturnsList(call.callee, lookup: lookup) {
                state.tagListResult(call.result, temporary: hofResult)
            }
            if mapHOFReturnsMap(call.callee, lookup: lookup) {
                state.tagMapResult(call.result, temporary: hofResult)
            }
            if let result = call.result {
                instructions.append(.copy(from: hofResult, to: result))
            }
            return CollectionCallRewriteResult(instructions: instructions)
        }

        return nil
    }

    private func isCollectionHOFMemberName(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapName
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.mapNotNullName
            || callee == lookup.forEachName
            || callee == lookup.onEachName
            || callee == lookup.flatMapName
            || callee == lookup.anyName
            || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.mapValuesName
            || callee == lookup.mapKeysName
            || callee == lookup.toListName
            || callee == lookup.countName
    }

    private func closureRawArgument(
        for arguments: [KIRExprID],
        module: KIRModule,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if arguments.count == 3 {
            return arguments[2]
        }
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    private func listHOFRuntimeName(
        for callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> InternedString {
        switch callee {
        case lookup.mapName: lookup.kkListMapName
        case lookup.filterName: lookup.kkListFilterName
        case lookup.filterNotName: lookup.kkListFilterNotName
        case lookup.mapNotNullName: lookup.kkListMapNotNullName
        case lookup.forEachName: lookup.kkListForEachName
        case lookup.onEachName: lookup.kkListOnEachName
        case lookup.flatMapName: lookup.kkListFlatMapName
        case lookup.flatMapIndexedName: lookup.kkListFlatMapIndexedName
        case lookup.anyName: lookup.kkListAnyName
        case lookup.noneName: lookup.kkListNoneName
        case lookup.allName: lookup.kkListAllName
        default: callee
        }
    }

    private func mapHOFRuntimeName(
        for callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> InternedString? {
        switch callee {
        case lookup.mapName: lookup.kkMapMapName
        case lookup.filterName: lookup.kkMapFilterName
        case lookup.forEachName: lookup.kkMapForEachName
        case lookup.mapValuesName: lookup.kkMapMapValuesName
        case lookup.mapKeysName: lookup.kkMapMapKeysName
        case lookup.filterKeysName: lookup.kkMapFilterKeysName
        case lookup.filterValuesName: lookup.kkMapFilterValuesName
        case lookup.flatMapName: lookup.kkMapFlatMapName
        case lookup.maxByOrNullName: lookup.kkMapMaxByOrNullName
        case lookup.minByOrNullName: lookup.kkMapMinByOrNullName
        case lookup.anyName: lookup.kkMapAnyName
        case lookup.allName: lookup.kkMapAllName
        case lookup.noneName: lookup.kkMapNoneName
        default: nil
        }
    }

    private func listHOFReturnsList(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName
            || callee == lookup.flatMapIndexedName
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.onEachName
    }

    private func mapHOFReturnsList(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapName || callee == lookup.flatMapName || callee == lookup.mapNotNullName
    }

    private func mapHOFReturnsMap(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapValuesName
            || callee == lookup.mapKeysName
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.filterKeysName
            || callee == lookup.filterValuesName
    }
}
