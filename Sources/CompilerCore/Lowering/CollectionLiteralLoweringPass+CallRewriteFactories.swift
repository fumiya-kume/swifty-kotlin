import Foundation
import RuntimeABI

extension CollectionLiteralLoweringPass {

    /// Rewrites collection factories, builder DSL calls, and tuple constructor shims.
    func rewriteFactoryAndBuilderCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        builderLambdaKinds: [InternedString: InternedString],
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // --- Rewrite listOf/mutableListOf/emptyList/emptyArray → kk_list_of / kk_emptyList / kk_empty_array ---
        // --- Rewrite arrayOf/intArrayOf/... → kk_array_of ---
        // Only rewrite calls whose symbol resolves to a known
        // kotlin.collections.* factory to avoid accidentally
        // lowering user-defined functions with the same name.
        if lookup.listFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0 && callee != lookup.mutableListOfName && callee != lookup.arrayListOfName {
                if callee == lookup.emptyListName {
                    // emptyList() → kk_emptyList()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyListName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else if callee == lookup.emptyArrayName {
                    // emptyArray() → kk_empty_array()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyArrayName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    // listOf() → kk_emptyList()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyListName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            } else if count == 0 {
                // mutableListOf()/arrayListOf() → fresh instance via kk_list_of(null, 0)
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
                // listOfNotNull(a, b, c) → create array, populate, call kk_list_of_not_null
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
                    let storedArg: KIRExprID
                    if let types = ctx.sema?.types,
                       let argType = module.arena.exprType(arg),
                       let boxCallee = primitiveBoxCalleeName(
                           for: argType,
                           types: types,
                           interner: ctx.interner
                       )
                    {
                        let boxedArg = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: types.anyType
                        )
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: boxCallee,
                            arguments: [arg],
                            result: boxedArg,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        storedArg = boxedArg
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)), type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [arrayExpr, idxExpr, storedArg],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                let runtimeCallee = callee == lookup.listOfNotNullName
                    ? lookup.kkListOfNotNullName
                    : lookup.kkListOfName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // --- Rewrite ArrayList()/HashSet()/LinkedHashSet()/HashMap()/LinkedHashMap() constructors ---
        // 0 args → empty collection; 1 int arg (capacity) → empty collection;
        // 1 collection arg → copy.
        if lookup.mutableListConstructorNames.contains(callee) {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkCollectionToMutableListName,
                    arguments: [arguments[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.listExprIDs.insert(result.rawValue) }
                return true
            }

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
            return true
        }

        if lookup.mutableSetConstructorNames.contains(callee) {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkIterableToMutableSetName,
                    arguments: [arguments[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.setExprIDs.insert(result.rawValue) }
                return true
            }

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
            return true
        }

        if lookup.mutableMapConstructorNames.contains(callee) {
            // Create an empty mutable map first
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            let nullExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr2, value: .intLiteral(0)))

            if arguments.count == 1, state.mapExprIDs.contains(arguments[0].rawValue) {
                // Copy constructor: HashMap(otherMap) — only when arg is map-typed
                // 1. Create empty map into the result
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapOfName,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                // 2. putAll from source map (result is Unit, discarded)
                let putAllResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)), type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMutableMapPutAllName,
                    arguments: result.map { [$0, arguments[0]] } ?? [arguments[0]],
                    result: putAllResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // 0 args, capacity arg (Int), or unknown arg type → empty map
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapOfName,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // map.count(predicate) on map literals
        if callee == lookup.countName && (arguments.count == 2 || arguments.count == 3) {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.mapExprIDs.contains(receiverID.rawValue) {
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
                    callee: lookup.kkMapCountName,
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

        // --- Rewrite setOf/mutableSetOf/hashSetOf/linkedSetOf/emptySet -> kk_set_of / kk_emptySet ---
        if lookup.setFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableSetOfName
                && callee != lookup.hashSetOfName
                && callee != lookup.linkedSetOfName {
                // emptySet() / setOf() → kk_emptySet()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptySetName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // Mutable set factories produce a fresh instance via kk_set_of(null, 0).
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
                    let storedArg: KIRExprID
                    if let types = ctx.sema?.types,
                       let argType = module.arena.exprType(arg),
                       let boxCallee = primitiveBoxCalleeName(
                           for: argType,
                           types: types,
                           interner: ctx.interner
                       )
                    {
                        let boxedArg = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: types.anyType
                        )
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: boxCallee,
                            arguments: [arg],
                            result: boxedArg,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        storedArg = boxedArg
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)), type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [arrayExpr, idxExpr, storedArg],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                let runtimeCallee = callee == lookup.setOfNotNullName
                    ? lookup.kkSetOfNotNullName
                    : lookup.kkSetOfName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            if let result { state.setExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite mapOf/mutableMapOf/hashMapOf/linkedMapOf/emptyMap → kk_map_of / kk_emptyMap ---
        if lookup.mapFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableMapOfName
                && callee != lookup.hashMapOfName
                && callee != lookup.linkedMapOfName {
                // emptyMap() / mapOf() → kk_emptyMap()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptyMapName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // mutableMapOf()/hashMapOf()/linkedMapOf() → fresh instance via kk_map_of(null, null, 0)
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullKeysExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullKeysExpr, value: .intLiteral(0)))
                let nullValsExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullValsExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapOfName,
                    arguments: [nullKeysExpr, nullValsExpr, zeroExpr],
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
            return true
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
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
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
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // --- STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction) → kk_sequence_generate_noarg ---
        // arguments.count == 1: just the function value; the ABILoweringPass will expand to (fnPtr, closureRaw).
        if callee == lookup.generateSequenceName,
           arguments.count == 1
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceGenerateNoArgName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite buildString/buildList/buildMap → kk_build_* (STDLIB-002) ---
        if symbol == nil, lookup.builderDSLNames.contains(callee) {
            let kkCallee: InternedString = switch callee {
            case lookup.buildStringName:
                arguments.count == 2 ? lookup.kkBuildStringWithCapacityName : lookup.kkBuildStringName
            case lookup.buildListName:
                arguments.count == 2 ? lookup.kkBuildListWithCapacityName : lookup.kkBuildListName
            case lookup.buildSetName: lookup.kkBuildSetName
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
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(builderResult.rawValue)
            }
            if callee == lookup.buildSetName, let result {
                state.setExprIDs.insert(result.rawValue)
                state.setExprIDs.insert(builderResult.rawValue)
            }
            if callee == lookup.buildMapName, let result {
                state.mapExprIDs.insert(result.rawValue)
                state.mapExprIDs.insert(builderResult.rawValue)
            }
            if let result {
                loweredBody.append(.copy(from: builderResult, to: result))
            }
            return true
        }

        // --- Rewrite builder member functions (STDLIB-002) ---
        // Only rewrite append/add/put inside builder lambda functions
        // matching the correct builder kind to avoid cross-kind rewrites.
        if let builderCallee = builderLambdaKinds[function.name] {
            var rewrittenCallee: InternedString?
            if builderCallee == lookup.buildStringName, callee == lookup.appendName, arguments.count == 1 {
                rewrittenCallee = lookup.kkStringBuilderAppendName
            } else if builderCallee == lookup.buildStringName, callee == lookup.appendLineName, arguments.count == 1 {
                rewrittenCallee = lookup.kkStringBuilderAppendLineName
            } else if builderCallee == lookup.buildStringName, callee == lookup.appendLineName, arguments.count == 0 {
                rewrittenCallee = lookup.kkStringBuilderAppendLineNoargName
            } else if builderCallee == lookup.buildStringName, callee == lookup.insertName, arguments.count == 2 {
                rewrittenCallee = lookup.kkStringBuilderInsertName
            } else if builderCallee == lookup.buildStringName, callee == lookup.deleteName, arguments.count == 2 {
                rewrittenCallee = lookup.kkStringBuilderDeleteName
            } else if builderCallee == lookup.buildStringName, callee == lookup.lengthName, arguments.count == 0 {
                rewrittenCallee = lookup.kkStringBuilderLengthName
            } else if builderCallee == lookup.buildStringName, callee == lookup.appendRangeName, arguments.count == 3 {
                rewrittenCallee = lookup.kkStringBuilderAppendRangeName
            } else if builderCallee == lookup.buildListName, callee == lookup.addName, arguments.count == 1 {
                rewrittenCallee = lookup.kkBuilderListAddName
            } else if builderCallee == lookup.buildListName, callee == lookup.addAllName, arguments.count == 1 {
                rewrittenCallee = lookup.kkBuilderListAddAllName
            } else if builderCallee == lookup.buildSetName, callee == lookup.addName, arguments.count == 1 {
                rewrittenCallee = lookup.kkBuilderSetAddName
            } else if builderCallee == lookup.buildSetName, callee == lookup.addAllName, arguments.count == 1 {
                rewrittenCallee = lookup.kkBuilderSetAddAllName
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
                return true
            }
        }

        // --- Rewrite `to` infix → Pair constructor (STDLIB-120) ---
        if callee == lookup.toName, arguments.count == 2 {
            let initFQName: [InternedString] = [
                lookup.kotlinName, lookup.pairName, lookup.initName
            ]
            let initSymbol = ctx.sema?.symbols.lookup(fqName: initFQName)
            loweredBody.append(.call(
                symbol: initSymbol,
                callee: lookup.kkPairNewName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // --- Rewrite Triple(a, b, c) → Triple constructor (STDLIB-120) ---
        if callee == lookup.tripleName, arguments.count == 3 {
            let initFQName: [InternedString] = [
                lookup.kotlinName, lookup.tripleName, lookup.initName
            ]
            let initSymbol = ctx.sema?.symbols.lookup(fqName: initFQName)
            loweredBody.append(.call(
                symbol: initSymbol,
                callee: lookup.kkTripleNewName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        return false
    }
}
