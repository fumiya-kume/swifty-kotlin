/// Destination, association, zip, and indexed higher-order collection rewrites.
extension CollectionLiteralLoweringPass {
    func rewriteTransformHigherOrderCollectionCall(
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
    if callee == lookup.filterNotNullName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListFilterNotNullName,
                arguments: arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.associateByName,
       arguments.count == 4 || arguments.count == 5,
       state.listExprIDs.contains(arguments[0].rawValue)
    {
        let receiverID = arguments[0]
        let keyLambdaID = arguments[1]
        let keyClosureRawID = arguments[2]
        let valueLambdaID = arguments[3]
        let valueClosureRawID: KIRExprID
        if arguments.count == 5 {
            valueClosureRawID = arguments[4]
        } else {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            valueClosureRawID = zeroExpr
        }
        let hofResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: nil
        )
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkListAssociateByTransformName,
            arguments: [receiverID, keyLambdaID, keyClosureRawID, valueLambdaID, valueClosureRawID],
            result: hofResult,
            canThrow: canThrow,
            thrownResult: thrownResult
        ))
        if let result {
            state.mapExprIDs.insert(result.rawValue)
            state.mapExprIDs.insert(hofResult.rawValue)
            loweredBody.append(.copy(from: hofResult, to: result))
        }
        return true
    }

    // --- STDLIB-631: groupBy with value transform (two-lambda variant) ---
    // Arguments: [receiver, keyLambda, keyClosureRaw, valueLambda] (4 args)
    // or [receiver, keyLambda, keyClosureRaw, valueLambda, valueClosureRaw] (5 args)
    if callee == lookup.groupByName,
       arguments.count == 4 || arguments.count == 5,
       state.listExprIDs.contains(arguments[0].rawValue)
    {
        let receiverID = arguments[0]
        let keyLambdaID = arguments[1]
        let keyClosureRawID = arguments[2]
        let valueLambdaID = arguments[3]
        let valueClosureRawID: KIRExprID
        if arguments.count == 5 {
            valueClosureRawID = arguments[4]
        } else {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            valueClosureRawID = zeroExpr
        }
        let hofResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: nil
        )
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkListGroupByTransformName,
            arguments: [receiverID, keyLambdaID, keyClosureRawID, valueLambdaID, valueClosureRawID],
            result: hofResult,
            canThrow: canThrow,
            thrownResult: thrownResult
        ))
        if let result {
            state.mapExprIDs.insert(result.rawValue)
            state.mapExprIDs.insert(hofResult.rawValue)
            loweredBody.append(.copy(from: hofResult, to: result))
        }
        return true
    }

    // --- Rewrite additional HOF collection member calls (STDLIB-005) ---
    // 1-param lambda HOFs with [receiver, lambda, closureRaw?]
    if callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName || callee == lookup.findLastName
        || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
        || callee == lookup.distinctByName
    {
        if arguments.count == 2 || arguments.count == 3 {
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
                let kkName: InternedString = switch callee {
                case lookup.groupByName: lookup.kkListGroupByName
                case lookup.sortedByName: lookup.kkListSortedByName
                case lookup.findName: lookup.kkListFindName
                case lookup.findLastName: lookup.kkListFindLastName
                case lookup.associateByName: lookup.kkListAssociateByName
                case lookup.associateWithName: lookup.kkListAssociateWithName
                case lookup.associateName: lookup.kkListAssociateName
                case lookup.distinctByName: lookup.kkListDistinctByName
                default: callee
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
                if callee == lookup.sortedByName || callee == lookup.distinctByName, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if callee == lookup.groupByName, let result {
                    state.mapExprIDs.insert(result.rawValue)
                    state.mapExprIDs.insert(hofResult.rawValue)
                }
                if callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName,
                   let result
                {
                    state.mapExprIDs.insert(result.rawValue)
                    state.mapExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

    // --- STDLIB-SEQ-022: sequence destination-collection mapping variants ---
    if (callee == lookup.mapToName || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedNotNullToName),
       (arguments.count == 3 || arguments.count == 4),
       state.sequenceExprIDs.contains(arguments[0].rawValue)
    {
        let receiverID = arguments[0]
        let destID = arguments[1]
        let lambdaID = arguments[2]
        let closureRawID: KIRExprID
        if arguments.count == 4 {
            closureRawID = arguments[3]
        } else {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            closureRawID = zeroExpr
        }
        let kkName: InternedString = if callee == lookup.mapToName {
            lookup.kkSequenceMapToName
        } else if callee == lookup.mapNotNullToName {
            lookup.kkSequenceMapNotNullToName
        } else {
            lookup.kkSequenceMapIndexedNotNullToName
        }
        let hofResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: nil
        )
        loweredBody.append(.call(
            symbol: nil,
            callee: kkName,
            arguments: [receiverID, destID, lambdaID, closureRawID],
            result: hofResult,
            canThrow: canThrow,
            thrownResult: thrownResult
        ))
        if let result {
            if state.listExprIDs.contains(destID.rawValue) {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
            } else if state.setExprIDs.contains(destID.rawValue) {
                state.setExprIDs.insert(result.rawValue)
                state.setExprIDs.insert(hofResult.rawValue)
            }
            loweredBody.append(.copy(from: hofResult, to: result))
        }
        return true
    }

    // --- STDLIB-021: destination collection variants with [receiver, dest, lambda, closureRaw?] ---
    if callee == lookup.filterToName || callee == lookup.filterNotToName
        || callee == lookup.mapToName || callee == lookup.flatMapToName
        || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName
        || callee == lookup.mapIndexedNotNullToName
        || callee == lookup.flatMapIndexedToName || callee == lookup.associateToName
    {
        if (arguments.count == 3 || arguments.count == 4),
           (state.listExprIDs.contains(arguments[0].rawValue)
            || state.setExprIDs.contains(arguments[0].rawValue)
            || state.sequenceExprIDs.contains(arguments[0].rawValue)
            || state.arrayExprIDs.contains(arguments[0].rawValue))
        {
            let receiverID = arguments[0]
            let destID = arguments[1]
            let lambdaID = arguments[2]
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let isSequenceReceiver = state.sequenceExprIDs.contains(receiverID.rawValue)
            let kkName: InternedString = switch callee {
            case lookup.filterToName: lookup.kkListFilterToName
            case lookup.filterNotToName: lookup.kkListFilterNotToName
            case lookup.mapToName: lookup.kkListMapToName
            case lookup.flatMapToName: lookup.kkListFlatMapToName
            case lookup.mapNotNullToName: lookup.kkListMapNotNullToName
            case lookup.mapIndexedToName: lookup.kkListMapIndexedToName
            case lookup.mapIndexedNotNullToName: lookup.kkListMapIndexedNotNullToName
            case lookup.flatMapIndexedToName: lookup.kkListFlatMapIndexedToName
            case lookup.associateToName:
                isSequenceReceiver ? lookup.kkSequenceAssociateToName : lookup.kkListAssociateToName
            default: callee
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, destID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                if state.listExprIDs.contains(destID.rawValue) {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                } else if state.setExprIDs.contains(destID.rawValue) {
                    state.setExprIDs.insert(result.rawValue)
                    state.setExprIDs.insert(hofResult.rawValue)
                } else if state.mapExprIDs.contains(destID.rawValue) {
                    state.mapExprIDs.insert(result.rawValue)
                    state.mapExprIDs.insert(hofResult.rawValue)
                }
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.toCollectionName, arguments.count == 2 {
        let receiverID = arguments[0]
        let destID = arguments[1]
        let runtimeCallee: InternedString?
        if state.listExprIDs.contains(receiverID.rawValue)
            || state.setExprIDs.contains(receiverID.rawValue)
            || state.arrayExprIDs.contains(receiverID.rawValue)
        {
            runtimeCallee = lookup.kkCollectionToCollectionName
        } else if state.sequenceExprIDs.contains(receiverID.rawValue) {
            runtimeCallee = lookup.kkSequenceToCollectionName
        } else {
            runtimeCallee = nil
        }
        if let runtimeCallee {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [receiverID, destID],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                if state.listExprIDs.contains(destID.rawValue) {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                } else if state.setExprIDs.contains(destID.rawValue) {
                    state.setExprIDs.insert(result.rawValue)
                    state.setExprIDs.insert(hofResult.rawValue)
                }
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    // --- STDLIB-SEQ-023 / STDLIB-535/536/537: sequence/list *To variants with [receiver, dest, lambda, closureRaw?] ---
    if callee == lookup.associateByToName || callee == lookup.associateWithToName
        || callee == lookup.groupByToName
    {
        if (arguments.count == 3 || arguments.count == 4),
           (state.listExprIDs.contains(arguments[0].rawValue)
            || state.sequenceExprIDs.contains(arguments[0].rawValue))
        {
            let receiverID = arguments[0]
            let destID = arguments[1]
            let lambdaID = arguments[2]
            let closureRawID: KIRExprID
            if arguments.count == 4 {
                closureRawID = arguments[3]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let isSequenceReceiver = state.sequenceExprIDs.contains(receiverID.rawValue)
            let kkName: InternedString = switch callee {
            case lookup.associateByToName:
                isSequenceReceiver ? lookup.kkSequenceAssociateByToName : lookup.kkListAssociateByToName
            case lookup.associateWithToName:
                isSequenceReceiver ? lookup.kkSequenceAssociateWithToName : lookup.kkListAssociateWithToName
            case lookup.groupByToName:
                isSequenceReceiver ? lookup.kkSequenceGroupByToName : lookup.kkListGroupByToName
            default: callee
            }
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiverID, destID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                state.mapExprIDs.insert(result.rawValue)
                state.mapExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.zipName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipName,
                arguments: arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.unzipName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListUnzipName,
                arguments: arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    // zipWithNext(): List<Pair<T, T>> — 0-arg (receiver only)
    if callee == lookup.zipWithNextName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let hofResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipWithNextName,
                arguments: arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    // zipWithNext(transform): List<R> — 1-arg HOF (receiver + lambda + closure)
    if callee == lookup.zipWithNextName, arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
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
                callee: lookup.kkListZipWithNextTransformName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.withIndexName || callee == lookup.kkListWithIndexName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.listExprIDs.contains(receiverID.rawValue) {
            let transformResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWithIndexName,
                arguments: [receiverID],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.indexingIterableExprIDs.insert(result.rawValue)
                state.indexingIterableExprIDs.insert(transformResult.rawValue)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName || callee == lookup.mapIndexedNotNullName || callee == lookup.onEachIndexedName {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString
                if callee == lookup.forEachIndexedName {
                    kkName = lookup.kkListForEachIndexedName
                } else if callee == lookup.onEachIndexedName {
                    kkName = lookup.kkListOnEachIndexedName
                } else if callee == lookup.mapIndexedNotNullName {
                    kkName = lookup.kkListMapIndexedNotNullName
                } else {
                    kkName = lookup.kkListMapIndexedName
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
                if callee == lookup.mapIndexedName || callee == lookup.mapIndexedNotNullName || callee == lookup.onEachIndexedName, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

        return false
    }
}
