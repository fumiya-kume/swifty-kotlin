// swiftlint:disable file_length
import Foundation

extension CollectionLiteralLoweringPass {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func rewriteCalls(module: KIRModule, ctx: KIRContext) throws {
        let lookup = CollectionLiteralLookupTables(interner: ctx.interner)
        let builderLambdaKinds = collectBuilderLambdaKinds(
            module: module,
            lookup: lookup,
            interner: ctx.interner
        )

        module.arena.transformFunctions { function in
            var updated = function

            // Phase 1: Identify collection-typed expression IDs
            var listExprIDs: Set<Int32> = []
            var setExprIDs: Set<Int32> = []
            var mapExprIDs: Set<Int32> = []
            var arrayExprIDs: Set<Int32> = []
            var sequenceExprIDs: Set<Int32> = []
            var rangeExprIDs: Set<Int32> = []
            var stringExprIDs: Set<Int32> = []

            collectInitialCollectionExprIDs(
                function: function,
                lookup: lookup,
                listExprIDs: &listExprIDs,
                setExprIDs: &setExprIDs,
                mapExprIDs: &mapExprIDs,
                arrayExprIDs: &arrayExprIDs,
                sequenceExprIDs: &sequenceExprIDs,
                rangeExprIDs: &rangeExprIDs,
                stringExprIDs: &stringExprIDs
            )

            // Phase 2: Rewrite instructions
            var listIteratorExprIDs: Set<Int32> = []
            var mapIteratorExprIDs: Set<Int32> = []
            var stringIteratorExprIDs: Set<Int32> = []
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _):
                    // --- Rewrite listOf/mutableListOf/emptyList → kk_list_of ---
                    if lookup.listFactoryNames.contains(callee) {
                        let count = arguments.count
                        if count == 0 {
                            // emptyList() / listOf() → kk_list_of(0, 0)
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListOfName,
                                arguments: [nullExpr, zeroExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        } else {
                            // listOf(a, b, c) → create array, populate, call kk_list_of
                            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                            let arrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [countExpr],
                                result: arrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            for (i, arg) in arguments.enumerated() {
                                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                                let setResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySetName,
                                    arguments: [arrayExpr, idxExpr, arg],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListOfName,
                                arguments: [arrayExpr, countExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // --- Rewrite setOf/mutableSetOf/emptySet → kk_set_of ---
                    if lookup.setFactoryNames.contains(callee) {
                        let count = arguments.count
                        if count == 0 {
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSetOfName,
                                arguments: [nullExpr, zeroExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        } else {
                            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                            let arrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [countExpr],
                                result: arrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            for (i, arg) in arguments.enumerated() {
                                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                                let setResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySetName,
                                    arguments: [arrayExpr, idxExpr, arg],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSetOfName,
                                arguments: [arrayExpr, countExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // --- Rewrite mapOf/mutableMapOf/emptyMap → kk_map_of ---
                    if lookup.mapFactoryNames.contains(callee) {
                        let count = arguments.count
                        if count == 0 {
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                            let nullExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: nullExpr2, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapOfName,
                                arguments: [nullExpr, nullExpr2, zeroExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        } else {
                            // mapOf(pair1, pair2, ...) → kk_map_of(keysArray, valuesArray, count)
                            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                            let keysArrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [countExpr],
                                result: keysArrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            let valuesArrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [countExpr],
                                result: valuesArrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            for (i, arg) in arguments.enumerated() {
                                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                                let keyExpr = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkPairFirstName,
                                    arguments: [arg],
                                    result: keyExpr,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                let valueExpr = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkPairSecondName,
                                    arguments: [arg],
                                    result: valueExpr,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                let setResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySetName,
                                    arguments: [keysArrayExpr, idxExpr, keyExpr],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                let setResult2 = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySetName,
                                    arguments: [valuesArrayExpr, idxExpr, valueExpr],
                                    result: setResult2,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapOfName,
                                arguments: [keysArrayExpr, valuesArrayExpr, countExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // --- Rewrite sequenceOf → kk_sequence_of (STDLIB-097) ---
                    if callee == lookup.sequenceOfName {
                        let count = arguments.count
                        if count == 0 {
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            let emptyArrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [zeroExpr],
                                result: emptyArrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceOfName,
                                arguments: [emptyArrayExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        } else {
                            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                            let arrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayNewName,
                                arguments: [countExpr],
                                result: arrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            for (i, arg) in arguments.enumerated() {
                                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                                let setResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySetName,
                                    arguments: [arrayExpr, idxExpr, arg],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceOfName,
                                arguments: [arrayExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // --- Rewrite generateSequence → kk_sequence_generate (STDLIB-097) ---
                    if callee == lookup.generateSequenceName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkSequenceGenerateName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // --- Rewrite buildString/buildList/buildMap → kk_build_* (STDLIB-002) ---
                    if symbol == nil, lookup.builderDSLNames.contains(callee) {
                        let kkCallee: InternedString = switch callee {
                        case lookup.buildStringName: lookup.kkBuildStringName
                        case lookup.buildListName:
                            arguments.count == 2 ? lookup.kkBuildListWithCapacityName : lookup.kkBuildListName
                        case lookup.buildMapName: lookup.kkBuildMapName
                        default: callee
                        }
                        let builderResult = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)), type: nil
                        )
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkCallee,
                            arguments: arguments,
                            result: builderResult,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        if callee == lookup.buildListName, let result {
                            listExprIDs.insert(result.rawValue)
                            listExprIDs.insert(builderResult.rawValue)
                        }
                        if callee == lookup.buildMapName, let result {
                            mapExprIDs.insert(result.rawValue)
                            mapExprIDs.insert(builderResult.rawValue)
                        }
                        if let result {
                            loweredBody.append(.copy(from: builderResult, to: result))
                        }
                        continue
                    }

                    // --- Rewrite builder member functions (STDLIB-002) ---
                    // Only rewrite append/add/put inside builder lambda functions
                    // matching the correct builder kind to avoid cross-kind rewrites.
                    if let builderCallee = builderLambdaKinds[function.name] {
                        var rewrittenCallee: InternedString?
                        if builderCallee == lookup.buildStringName, callee == lookup.appendName, arguments.count == 1 {
                            rewrittenCallee = lookup.kkStringBuilderAppendName
                        } else if builderCallee == lookup.buildListName, callee == lookup.addName, arguments.count == 1 {
                            rewrittenCallee = lookup.kkBuilderListAddName
                        } else if builderCallee == lookup.buildMapName, callee == lookup.putName, arguments.count == 2 {
                            rewrittenCallee = lookup.kkBuilderMapPutName
                        }
                        if let target = rewrittenCallee {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: target,
                                arguments: arguments,
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                            continue
                        }
                    }

                    // --- Rewrite `to` infix → kk_pair_new (FUNC-002) ---
                    if callee == lookup.toName, arguments.count == 2 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkPairNewName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }

                    // --- Rewrite Triple(a, b, c) → kk_triple_new (STDLIB-120) ---
                    if callee == lookup.tripleName, arguments.count == 3 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkTripleNewName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }

                    // --- Rewrite arrayOf → kk_array_of ---
                    if lookup.arrayOfFactoryNames.contains(callee) {
                        let count = arguments.count
                        let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                        loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                        let arrayExpr = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)), type: nil
                        )
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkArrayNewName,
                            arguments: [countExpr],
                            result: arrayExpr,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        for (i, arg) in arguments.enumerated() {
                            let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                            loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                            let setResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArraySetName,
                                arguments: [arrayExpr, idxExpr, arg],
                                result: setResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        if result != nil {
                            loweredBody.append(.copy(from: arrayExpr, to: result!))
                        }
                        continue
                    }

                    // --- Rewrite kk_range_iterator on list → kk_list_iterator ---
                    if callee == lookup.kkRangeIteratorName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            if let result { listIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapExprIDs.contains(argID.rawValue) {
                            if let result { mapIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        // STDLIB-189: Rewrite kk_range_iterator on String → kk_string_iterator
                        if stringExprIDs.contains(argID.rawValue) {
                            if let result { stringIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkStringIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_hasNext on list iterator → kk_list_iterator_hasNext ---
                    if callee == lookup.kkRangeHasNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListIteratorHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapIteratorHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        // STDLIB-189: Rewrite kk_range_hasNext on string iterator → kk_string_iterator_hasNext
                        if stringIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkStringIteratorHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_next on list iterator → kk_list_iterator_next ---
                    if callee == lookup.kkRangeNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListIteratorNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapIteratorNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        // STDLIB-189: Rewrite kk_range_next on string iterator → kk_string_iterator_next
                        if stringIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkStringIteratorNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite collection member calls ---
                    // Member calls are lowered as call(callee=memberName, args=[receiver, ...])
                    // any()/none()/first()/last() with no predicate: args=[receiver], pass fnPtr=0, closure=0
                    if callee == lookup.anyName || callee == lookup.noneName || callee == lookup.firstName || callee == lookup.lastName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                                let kkName: InternedString = switch callee {
                                case lookup.anyName: lookup.kkListAnyName
                                case lookup.noneName: lookup.kkListNoneName
                                case lookup.firstName: lookup.kkListFirstName
                                case lookup.lastName: lookup.kkListLastName
                                default: callee
                                }
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: [receiverID, zeroExpr, zeroExpr],
                                    result: result,
                                    canThrow: callee == lookup.firstName || callee == lookup.lastName,
                                    thrownResult: thrownResult
                                ))
                                continue
                            }
                            if rangeExprIDs.contains(receiverID.rawValue),
                               callee == lookup.firstName || callee == lookup.lastName
                            {
                                let kkName = callee == lookup.firstName
                                    ? lookup.kkRangeFirstName : lookup.kkRangeLastName
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.sizeName || callee == lookup.countName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListSizeName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapSizeName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if setExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSetSizeName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if arrayExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkArraySizeName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if rangeExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkRangeCountName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.getName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListGetName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult
                                ))
                                continue
                            }
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapGetName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.containsName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListContainsName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if setExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSetContainsName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.containsKeyName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapContainsKeyName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.addName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if setExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMutableSetAddName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.removeName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if setExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMutableSetRemoveName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == lookup.isEmptyName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListIsEmptyName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if setExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSetIsEmptyName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapIsEmptyName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    // --- Rewrite sequence member calls (STDLIB-003) ---
                    // asSequence() on collection → kk_sequence_from_list
                    // Sema already restricts asSequence to collection expressions,
                    // so we rewrite unconditionally (no listExprIDs guard needed).
                    if callee == lookup.asSequenceName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkSequenceFromListName,
                            arguments: [receiverID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // map/filter on sequence → kk_sequence_map/kk_sequence_filter
                    if callee == lookup.mapName || callee == lookup.filterName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue),
                           !arrayExprIDs.contains(receiverID.rawValue)
                        {
                            let kkName = callee == lookup.mapName ? lookup.kkSequenceMapName : lookup.kkSequenceFilterName
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // take(n) on sequence → kk_sequence_take
                    if callee == lookup.takeName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceTakeName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListTakeName,
                                arguments: arguments,
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    // forEach on sequence → kk_sequence_forEach (STDLIB-095)
                    if callee == lookup.forEachName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceForEachName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // flatMap on sequence → kk_sequence_flatMap (STDLIB-095)
                    if callee == lookup.flatMapName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceFlatMapName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // drop(n) on sequence → kk_sequence_drop (STDLIB-096)
                    if callee == lookup.dropName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceDropName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // distinct() on sequence → kk_sequence_distinct (STDLIB-096)
                    if callee == lookup.distinctName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceDistinctName,
                                arguments: [receiverID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // zip(other) on sequence → kk_sequence_zip (STDLIB-096)
                    if callee == lookup.zipName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceZipName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    if callee == lookup.dropName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListDropName,
                                arguments: arguments,
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.reversedName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListReversedName,
                                arguments: [receiverID],
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                        if rangeExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkRangeReversedName,
                                arguments: [receiverID],
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                rangeExprIDs.insert(result.rawValue)
                                rangeExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.sortedName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListSortedName,
                                arguments: [receiverID],
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.distinctName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListDistinctName,
                                arguments: [receiverID],
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    // toList() on sequence → kk_sequence_to_list
                    if callee == lookup.toListName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue),
                           !arrayExprIDs.contains(receiverID.rawValue)
                        {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceToListName,
                                arguments: [receiverID],
                                result: toListResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(toListResult.rawValue)
                                loweredBody.append(.copy(from: toListResult, to: result))
                            }
                            continue
                        }
                        if mapExprIDs.contains(receiverID.rawValue) {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapToListName,
                                arguments: [receiverID],
                                result: toListResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(toListResult.rawValue)
                                loweredBody.append(.copy(from: toListResult, to: result))
                            }
                            continue
                        }
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayToListName,
                                arguments: [receiverID],
                                result: toListResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(toListResult.rawValue)
                                loweredBody.append(.copy(from: toListResult, to: result))
                            }
                            continue
                        }
                        if rangeExprIDs.contains(receiverID.rawValue) {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkRangeToListName,
                                arguments: [receiverID],
                                result: toListResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(toListResult.rawValue)
                                loweredBody.append(.copy(from: toListResult, to: result))
                            }
                            continue
                        }
                    }

                    // toMutableList() on array → kk_array_toMutableList (STDLIB-087)
                    if callee == lookup.toMutableListName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            let toMutableListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayToMutableListName,
                                arguments: [receiverID],
                                result: toMutableListResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(toMutableListResult.rawValue)
                                loweredBody.append(.copy(from: toMutableListResult, to: result))
                            }
                            continue
                        }
                    }

                    // toTypedArray() on list → kk_list_toTypedArray (STDLIB-087)
                    if callee == lookup.toTypedArrayName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let toArrayResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToTypedArrayName,
                                arguments: [receiverID],
                                result: toArrayResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                arrayExprIDs.insert(result.rawValue)
                                arrayExprIDs.insert(toArrayResult.rawValue)
                                loweredBody.append(.copy(from: toArrayResult, to: result))
                            }
                            continue
                        }
                    }

                    // copyOf / copyOfRange / fill on array (STDLIB-089)
                    if callee == lookup.copyOfName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            let copyResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayCopyOfName,
                                arguments: [receiverID],
                                result: copyResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                arrayExprIDs.insert(result.rawValue)
                                arrayExprIDs.insert(copyResult.rawValue)
                                loweredBody.append(.copy(from: copyResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.copyOfRangeName, arguments.count == 3 {
                        let receiverID = arguments[0]
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            let copyResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayCopyOfRangeName,
                                arguments: arguments,
                                result: copyResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                arrayExprIDs.insert(result.rawValue)
                                arrayExprIDs.insert(copyResult.rawValue)
                                loweredBody.append(.copy(from: copyResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.fillName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayFillName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // sequence { ... } builder → kk_sequence_builder_build
                    if callee == lookup.sequenceName, arguments.count == 1 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkSequenceBuilderBuildName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // yield(value) inside sequence builder → kk_sequence_builder_yield
                    if callee == lookup.yieldName, arguments.count == 2 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkSequenceBuilderYieldName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }

                    // --- Rewrite higher-order collection member calls (FUNC-003) ---
                    if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.mapNotNullName || callee == lookup.forEachName
                        || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
                        || callee == lookup.allName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
                        || callee == lookup.toListName
                    {
                        if callee == lookup.toListName, arguments.count == 1 {
                            let receiverID = arguments[0]
                            if mapExprIDs.contains(receiverID.rawValue) {
                                let toListResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapToListName,
                                    arguments: [receiverID],
                                    result: toListResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                if let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(toListResult.rawValue)
                                    loweredBody.append(.copy(from: toListResult, to: result))
                                }
                                continue
                            }
                        }
                        // args = [receiver, lambda, closureRaw?]; Runtime expects (listRaw, fnPtr, closureRaw, outThrown)
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let closureRawID: KIRExprID
                                if arguments.count == 3 {
                                    closureRawID = arguments[2]
                                } else {
                                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                                    closureRawID = zeroExpr
                                }
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
                                    || callee == lookup.flatMapName
                                    || callee == lookup.filterName
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
                                if needsListTag, let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                }
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                            if mapExprIDs.contains(receiverID.rawValue),
                               callee == lookup.mapName || callee == lookup.filterName || callee == lookup.forEachName
                               || callee == lookup.mapValuesName || callee == lookup.mapKeysName
                               || callee == lookup.countName || callee == lookup.anyName
                               || callee == lookup.allName || callee == lookup.noneName
                            {
                                let closureRawID: KIRExprID
                                if arguments.count == 3 {
                                    closureRawID = arguments[2]
                                } else {
                                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                                    closureRawID = zeroExpr
                                }
                                let kkName: InternedString = switch callee {
                                case lookup.mapName: lookup.kkMapMapName
                                case lookup.filterName: lookup.kkMapFilterName
                                case lookup.forEachName: lookup.kkMapForEachName
                                case lookup.mapValuesName: lookup.kkMapMapValuesName
                                case lookup.mapKeysName: lookup.kkMapMapKeysName
                                case lookup.countName: lookup.kkMapCountName
                                case lookup.anyName: lookup.kkMapAnyName
                                case lookup.allName: lookup.kkMapAllName
                                case lookup.noneName: lookup.kkMapNoneName
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
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                            if rangeExprIDs.contains(receiverID.rawValue),
                               callee == lookup.mapName || callee == lookup.forEachName
                            {
                                let closureRawID: KIRExprID
                                if arguments.count == 3 {
                                    closureRawID = arguments[2]
                                } else {
                                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                                    closureRawID = zeroExpr
                                }
                                let kkName = callee == lookup.mapName
                                    ? lookup.kkRangeMapName : lookup.kkRangeForEachName
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
                                if callee == lookup.mapName, let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                }
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                            if arrayExprIDs.contains(receiverID.rawValue),
                               callee == lookup.mapName || callee == lookup.filterName
                               || callee == lookup.forEachName || callee == lookup.anyName
                               || callee == lookup.noneName
                            {
                                let closureRawID: KIRExprID
                                if arguments.count == 3 {
                                    closureRawID = arguments[2]
                                } else {
                                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                                    closureRawID = zeroExpr
                                }
                                let kkName: InternedString = switch callee {
                                case lookup.mapName: lookup.kkArrayMapName
                                case lookup.filterName: lookup.kkArrayFilterName
                                case lookup.forEachName: lookup.kkArrayForEachName
                                case lookup.anyName: lookup.kkArrayAnyName
                                case lookup.noneName: lookup.kkArrayNoneName
                                default: callee
                                }
                                let needsListTag = callee == lookup.mapName || callee == lookup.filterName
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
                                if needsListTag, let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                }
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                        }
                    }

                    if callee == lookup.filterNotNullName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    // --- Rewrite additional HOF collection member calls (STDLIB-005) ---
                    // 1-param lambda HOFs with [receiver, lambda, closureRaw?]
                    if callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName
                        || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
                    {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
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
                                case lookup.associateByName: lookup.kkListAssociateByName
                                case lookup.associateWithName: lookup.kkListAssociateWithName
                                case lookup.associateName: lookup.kkListAssociateName
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
                                if callee == lookup.sortedByName, let result {
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
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                        }
                    }

                    if callee == lookup.zipName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.unzipName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                            continue
                        }
                    }

                    if callee == lookup.withIndexName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString = callee == lookup.forEachIndexedName
                                    ? lookup.kkListForEachIndexedName
                                    : lookup.kkListMapIndexedName
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
                                if callee == lookup.mapIndexedName, let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                }
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                        }
                    }

                    if callee == lookup.sumOfName {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
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
                                    callee: lookup.kkListSumOfName,
                                    arguments: [receiverID, lambdaID, closureRawID],
                                    result: hofResult,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult
                                ))
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                        }
                    }

                    if callee == lookup.maxOrNullName || callee == lookup.minOrNullName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString = callee == lookup.maxOrNullName
                                    ? lookup.kkListMaxOrNullName
                                    : lookup.kkListMinOrNullName
                                let hofResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: [receiverID],
                                    result: hofResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                if let result {
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
                        }
                    }
                    // count/first/last with predicate: [receiver, lambda, closureRaw?]
                    if callee == lookup.countName || callee == lookup.firstName || callee == lookup.lastName {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
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
                                continue
                            }
                        }
                    }
                    // fold: args = [receiver, initial, lambda, closureRaw?]
                    // Runtime expects (listRaw, initial, fnPtr, closureRaw, outThrown)
                    if callee == lookup.foldName, arguments.count == 3 || arguments.count == 4 {
                        let receiverID = arguments[0]
                        let initialID = arguments[1]
                        let lambdaID = arguments[2]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListFoldName,
                                arguments: [receiverID, initialID, lambdaID, closureRawID],
                                result: hofResult,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                            if let result {
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }
                    // reduce: args = [receiver, lambda, closureRaw?]
                    if callee == lookup.reduceName, arguments.count == 2 || arguments.count == 3 {
                        let receiverID = arguments[0]
                        let lambdaID = arguments[1]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                            continue
                        }
                    }

                    // Rewrite println on list/map → kk_list_to_string / kk_map_to_string
                    if callee == lookup.kkPrintlnAnyName || callee == lookup.printlnName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            let strResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToStringName,
                                arguments: [argID],
                                result: strResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkPrintlnAnyName,
                                arguments: [strResult],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if setExprIDs.contains(argID.rawValue) {
                            let strResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSetToStringName,
                                arguments: [argID],
                                result: strResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkPrintlnAnyName,
                                arguments: [strResult],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapExprIDs.contains(argID.rawValue) {
                            let strResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapToStringName,
                                arguments: [argID],
                                result: strResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkPrintlnAnyName,
                                arguments: [strResult],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    if callee == lookup.kkAnyToStringName, arguments.count >= 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToStringName,
                                arguments: [argID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if setExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSetToStringName,
                                arguments: [argID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapToStringName,
                                arguments: [argID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // Default: keep instruction as-is
                    loweredBody.append(instruction)

                case let .virtualCall(_, callee, receiver, arguments, result, origCanThrow, origThrownResult, _):
                    if rewriteVirtualCallInstruction(
                        callee: callee,
                        receiver: receiver,
                        arguments: arguments,
                        result: result,
                        origCanThrow: origCanThrow,
                        origThrownResult: origThrownResult,
                        context: .init(module: module, lookup: lookup, functionBody: function.body),
                        listExprIDs: &listExprIDs,
                        setExprIDs: &setExprIDs,
                        mapExprIDs: &mapExprIDs,
                        arrayExprIDs: &arrayExprIDs,
                        sequenceExprIDs: &sequenceExprIDs,
                        rangeExprIDs: &rangeExprIDs,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }
                    loweredBody.append(instruction)

                case let .copy(from, to):
                    // Track copies of collection expressions
                    if listExprIDs.contains(from.rawValue) {
                        listExprIDs.insert(to.rawValue)
                    }
                    if setExprIDs.contains(from.rawValue) {
                        setExprIDs.insert(to.rawValue)
                    }
                    if mapExprIDs.contains(from.rawValue) {
                        mapExprIDs.insert(to.rawValue)
                    }
                    if arrayExprIDs.contains(from.rawValue) {
                        arrayExprIDs.insert(to.rawValue)
                    }
                    if sequenceExprIDs.contains(from.rawValue) {
                        sequenceExprIDs.insert(to.rawValue)
                    }
                    if rangeExprIDs.contains(from.rawValue) {
                        rangeExprIDs.insert(to.rawValue)
                    }
                    if stringExprIDs.contains(from.rawValue) {
                        stringExprIDs.insert(to.rawValue)
                    }
                    if listIteratorExprIDs.contains(from.rawValue) {
                        listIteratorExprIDs.insert(to.rawValue)
                    }
                    if mapIteratorExprIDs.contains(from.rawValue) {
                        mapIteratorExprIDs.insert(to.rawValue)
                    }
                    if stringIteratorExprIDs.contains(from.rawValue) {
                        stringIteratorExprIDs.insert(to.rawValue)
                    }
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.replaceBody(loweredBody)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
