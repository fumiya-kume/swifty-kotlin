/// Predicate and accumulation higher-order collection rewrites.
extension CollectionLiteralLoweringPass {
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
    // count/first/last with predicate: [receiver, lambda, closureRaw?]
    if callee == lookup.countName || callee == lookup.firstName || callee == lookup.lastName {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.countName: lookup.kkListCountName
                case lookup.firstName: lookup.kkListFirstName
                case lookup.lastName: lookup.kkListLastName
                default: callee
                }
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let hofResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
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
    // fold: args = [receiver, initial, lambda, closureRaw?]
    // Runtime expects (collectionRaw, initial, fnPtr, closureRaw, outThrown)
    if callee == lookup.foldName, (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]
        let initialID = arguments[1]
        let lambdaID = arguments[2]
        if state.listExprIDs.contains(receiverID.rawValue)
            || state.setExprIDs.contains(receiverID.rawValue)
            || state.sequenceExprIDs.contains(receiverID.rawValue)
        {
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            let foldCallee = state.sequenceExprIDs.contains(receiverID.rawValue)
                ? lookup.kkSequenceFoldName
                : lookup.kkListFoldName
            loweredBody.append(.call(
                symbol: nil,
                callee: foldCallee,
                arguments: [receiverID, initialID, lambdaID, closureRawID],
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
    // reduce: args = [receiver, lambda, closureRaw?]
    if callee == lookup.reduceName, (2 ... 3).contains(arguments.count) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListReduceName,
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
    // reduceOrNull: args = [receiver, lambda, closureRaw?]
    if callee == lookup.reduceOrNullName, arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListReduceOrNullName,
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

    // foldIndexed: args = [receiver, initial, lambda, closureRaw?]
    if (callee == lookup.foldIndexedName || callee == lookup.kkListFoldIndexedName || callee == lookup.kkSequenceFoldIndexedName), (arguments.count == 3 || arguments.count == 4) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue)
            || state.setExprIDs.contains(receiverID.rawValue)
            || state.sequenceExprIDs.contains(receiverID.rawValue)
        {
            let initialID = arguments[1]
            let lambdaID = arguments[2]
            let closureRawID: KIRExprID
            if arguments.count == 4 { closureRawID = arguments[3] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = state.sequenceExprIDs.contains(receiverID.rawValue) ? lookup.kkSequenceFoldIndexedName : lookup.kkListFoldIndexedName
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceIndexed: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceIndexedName || callee == lookup.kkListReduceIndexedName || callee == lookup.kkSequenceReduceIndexedName), (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) || state.sequenceExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = state.sequenceExprIDs.contains(receiverID.rawValue) ? lookup.kkSequenceReduceIndexedName : lookup.kkListReduceIndexedName
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // runningFoldIndexed on sequence: args = [receiver, initial, lambda, closureRaw?]
    if (callee == lookup.runningFoldIndexedName
        || callee == lookup.kkListRunningFoldIndexedName
        || callee == lookup.kkSequenceRunningFoldIndexedName),
       (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]
        let initialID = arguments[1]
        let lambdaID = arguments[2]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                closureRawID = z
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceRunningFoldIndexedName,
                arguments: [receiverID, initialID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            state.sequenceExprIDs.insert(hofResult.rawValue)
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }
    // foldRight: args = [receiver, initial, lambda, closureRaw?]
    if (callee == lookup.foldRightName || callee == lookup.kkListFoldRightName), (arguments.count == 3 || arguments.count == 4) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let initialID = arguments[1]
            let lambdaID = arguments[2]
            let closureRawID: KIRExprID
            if arguments.count == 4 { closureRawID = arguments[3] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFoldRightName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // foldRightIndexed: args = [receiver, initial, lambda, closureRaw?]
    if (callee == lookup.foldRightIndexedName || callee == lookup.kkListFoldRightIndexedName), (arguments.count == 3 || arguments.count == 4) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let initialID = arguments[1]
            let lambdaID = arguments[2]
            let closureRawID: KIRExprID
            if arguments.count == 4 { closureRawID = arguments[3] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFoldRightIndexedName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceRight: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceRightName || callee == lookup.kkListReduceRightName), (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListReduceRightName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceRightIndexed: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceRightIndexedName || callee == lookup.kkListReduceRightIndexedName), (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListReduceRightIndexedName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceRightIndexedOrNull: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceRightIndexedOrNullName || callee == lookup.kkListReduceRightIndexedOrNullName), (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListReduceRightIndexedOrNullName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // reduceRightOrNull: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceRightOrNullName || callee == lookup.kkListReduceRightOrNullName), (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListReduceRightOrNullName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // filterIndexed: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.filterIndexedName || callee == lookup.kkListFilterIndexedName),
       (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]; let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFilterIndexedName, arguments: [receiverID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
            if let result { loweredBody.append(.copy(from: hofResult, to: result)); state.listExprIDs.insert(result.rawValue) }
            state.listExprIDs.insert(hofResult.rawValue); return true
        }
    }
    // takeWhile: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.takeWhileName || callee == lookup.kkListTakeWhileName),
       (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                closureRawID = z
            }
            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListTakeWhileName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
                state.listExprIDs.insert(result.rawValue)
            }
            state.listExprIDs.insert(hofResult.rawValue)
            return true
        }
    }
    // reduceIndexedOrNull: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.reduceIndexedOrNullName
        || callee == lookup.kkListReduceIndexedOrNullName
        || callee == lookup.kkSequenceReduceIndexedOrNullName),
       (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]; let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) || state.sequenceExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = state.sequenceExprIDs.contains(receiverID.rawValue)
                ? lookup.kkSequenceReduceIndexedOrNullName
                : lookup.kkListReduceIndexedOrNullName
            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    // runningFoldIndexed / scanIndexed: args = [receiver, initial, lambda, closureRaw?]
    if (callee == lookup.runningFoldIndexedName
        || callee == lookup.scanIndexedName
        || callee == lookup.kkListRunningFoldIndexedName
        || callee == lookup.kkListScanIndexedName
        || callee == lookup.kkSequenceRunningFoldIndexedName),
       (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]; let initialID = arguments[1]; let lambdaID = arguments[2]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 4 { closureRawID = arguments[3] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = (callee == lookup.scanIndexedName || callee == lookup.kkListScanIndexedName) ? lookup.kkListScanIndexedName : lookup.kkListRunningFoldIndexedName
            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
            if let result { loweredBody.append(.copy(from: hofResult, to: result)); state.listExprIDs.insert(result.rawValue) }
            state.listExprIDs.insert(hofResult.rawValue); return true
        }
    }
    // runningReduceIndexed: args = [receiver, lambda, closureRaw?]
    if (callee == lookup.runningReduceIndexedName || callee == lookup.kkListRunningReduceIndexedName),
       (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]; let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] }
            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
            loweredBody.append(.call(symbol: nil, callee: lookup.kkListRunningReduceIndexedName, arguments: [receiverID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
            if let result { loweredBody.append(.copy(from: hofResult, to: result)); state.listExprIDs.insert(result.rawValue) }
            state.listExprIDs.insert(hofResult.rawValue); return true
        }
    }

    // scan / runningFold: args = [receiver, initial, lambda, closureRaw?]
    // Runtime expects (listRaw, initial, fnPtr, closureRaw, outThrown)
    // NOTE: The rewrite blocks below intentionally duplicate the "allocate temp +
    // emit .call + copy to result" pattern used by emitHOFCall in VirtualCallRewrite.
    // emitHOFCall is a private method on the VirtualCallRewrite extension and not
    // visible from this file-scope rewrite path.  Kept inline to avoid coupling
    // the two rewrite paths; extracting a shared helper is a future cleanup.
    if (callee == lookup.scanName || callee == lookup.runningFoldName),
       (3 ... 4).contains(arguments.count) {
        let receiverID = arguments[0]
        let initialID = arguments[1]
        let lambdaID = arguments[2]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let kkName = callee == lookup.scanName ? lookup.kkListScanName : lookup.kkListRunningFoldName
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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
    // runningReduce: args = [receiver, lambda, closureRaw?]
    if callee == lookup.runningReduceName,
       (2 ... 3).contains(arguments.count) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let kkName = callee == lookup.scanReduceName ? lookup.kkListScanReduceName : lookup.kkListRunningReduceName
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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
            state.listExprIDs.insert(hofResult.rawValue)
            if let result { state.listExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // scan / runningFold on sequence → kk_sequence_scan / kk_sequence_runningFold (STDLIB-558, 560)
    if (callee == lookup.scanName || callee == lookup.runningFoldName), (3 ... 4).contains(arguments.count) {
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
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
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
    // scanReduce: args = [receiver, lambda, closureRaw?] — alias for runningReduce
    if callee == lookup.scanReduceName, (arguments.count == 2 || arguments.count == 3) {
        let receiverID = arguments[0]
        let lambdaID = arguments[1]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListScanReduceName,
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
