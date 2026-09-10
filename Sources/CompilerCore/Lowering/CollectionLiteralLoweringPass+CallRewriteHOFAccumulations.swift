/// Predicate and accumulation higher-order collection rewrites.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteAccumulationHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // count with predicate: [receiver, lambda, closureRaw?]
    if callee == lookup.countName {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = callee
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
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

    // reduceIndexed: args = [receiver, lambda, closureRaw?]
    if callee == lookup.reduceIndexedName || callee == lookup.kkSequenceReduceIndexedName, arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] } else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = lookup.kkSequenceReduceIndexedName
            let callResult = result ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceIndexedOrNull: args = [receiver, lambda, closureRaw?]
    if callee == lookup.reduceIndexedOrNullName
        || callee == lookup.kkSequenceReduceIndexedOrNullName,
       arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]; let lambdaID = arguments[1]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] } else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = lookup.kkSequenceReduceIndexedOrNullName
            let callResult = result ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // runningFoldIndexed / scanIndexed: args = [receiver, initial, lambda, closureRaw?]
    if callee == lookup.runningFoldIndexedName
        || callee == lookup.scanIndexedName
        || callee == lookup.kkSequenceRunningFoldIndexedName
        || callee == lookup.kkSequenceScanIndexedName,
       (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]; let initialID = arguments[1]; let lambdaID = arguments[2]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 4 { closureRawID = arguments[3] } else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = (callee == lookup.scanIndexedName || callee == lookup.kkSequenceScanIndexedName) ? lookup.kkSequenceScanIndexedName : lookup.kkSequenceRunningFoldIndexedName
            let hofResult = module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
            if let result { loweredBody.append(.copy(from: hofResult, to: result)); state.sequenceExprIDs.insert(result.rawValue) }
            state.sequenceExprIDs.insert(hofResult.rawValue); return true
        }
    }


    // scan / runningFold on sequence → kk_sequence_scan / kk_sequence_runningFold (STDLIB-558, 560)
    if callee == lookup.scanName || callee == lookup.runningFoldName, (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]
        let initialID = arguments[1]
        let lambdaID = arguments[2]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let kkName = callee == lookup.scanName
                ? lookup.kkSequenceScanName : lookup.kkSequenceRunningFoldName
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, initialID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            state.listExprIDs.insert(hofResult.rawValue)
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }
    }
    // runningReduce on sequence → kk_sequence_runningReduce (STDLIB-559)
    if callee == lookup.runningReduceName, (2 ... 3).contains(arguments.count) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
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
                callee: lookup.kkSequenceRunningReduceName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            state.listExprIDs.insert(hofResult.rawValue)
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }
    }
    // runningReduceIndexed on sequence → kk_sequence_runningReduceIndexed (STDLIB-SEQ-017)
    if callee == lookup.runningReduceIndexedName, (2 ... 3).contains(arguments.count) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
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
                callee: lookup.kkSequenceRunningReduceIndexedName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            state.listExprIDs.insert(hofResult.rawValue)
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }
    }

        return false
    }
}
