
extension CollectionLiteralConstructionLoweringPass {

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
        // --- Rewrite list factories to runtime helpers. ---
        // Keep the Kotlin-source declarations visible to sema, but preserve the
        // runtime lowering path for primitive boxing and tracked collection IDs.
        if lookup.listFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0 && callee != lookup.mutableListOfName && callee != lookup.arrayListOfName {
                if callee == lookup.emptyArrayName {
                    // emptyArray() -> kk_empty_array()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyArrayName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    // emptyList(), listOf() -> kk_emptyList()
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
                // mutableListOf()/arrayListOf() -> fresh instance via kk_list_of(null, 0)
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
                // listOf(a, b, c), mutableListOf(a, b, c), arrayListOf(a, b, c) -> kk_list_of
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let arrayExpr = module.arena.appendTemporary(type: nil
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
                           symbols: ctx.sema?.symbols,
                           interner: ctx.interner
                       )
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: arg,
                            rawSourceKind: types.kind(of: argType),
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: ctx.sema?.symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            into: &loweredBody
                        )
                        storedArg = boxedResult
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendTemporary(type: nil
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
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListOfName,
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

        let isHashSetConstructor = isHashSetConstructor(
            callee: callee,
            symbol: symbol,
            result: result,
            module: module,
            lookup: lookup,
            ctx: ctx
        )
        if lookup.mutableSetConstructorNames.contains(callee) || isHashSetConstructor {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: isHashSetConstructor
                        ? lookup.kkIterableToHashSetName
                        : lookup.kkIterableToMutableSetName,
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
                callee: isHashSetConstructor
                    ? lookup.kkHashSetOfName
                    : lookup.kkSetOfName,
                arguments: [nullExpr, zeroExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        if lookup.mutableMapConstructorNames.contains(callee) {
            let constructorCallee = callee == lookup.hashMapName
                ? lookup.kkHashMapOfName
                : lookup.kkMapOfName
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
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                // 2. putAll from source map (result is Unit, discarded)
                let putAllResult = module.arena.appendTemporary(type: nil
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
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // map.count(predicate) on map literals (skip when Map.count is source-backed)
        if callee == lookup.countName && (arguments.count == 2 || arguments.count == 3),
           !isSourceBackedBundledFunction(symbol: symbol, ctx: ctx) {
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
                let hofResult = module.arena.appendTemporary(type: nil
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

        // --- Rewrite set factories to runtime helpers. ---
        if lookup.setFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableSetOfName
                && callee != lookup.hashSetOfName
                && callee != lookup.linkedSetOfName {
                // emptySet(), setOf(), setOfNotNull() -> __kk_emptySet()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptySetName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // Mutable/hash/linked set factories produce a fresh instance via
                // the shared set storage, with HashSet retaining its nominal tag.
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: callee == lookup.hashSetOfName
                        ? lookup.kkHashSetOfName
                        : lookup.kkSetOfName,
                    arguments: [nullExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let arrayExpr = module.arena.appendTemporary(type: nil
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
                           symbols: ctx.sema?.symbols,
                           interner: ctx.interner
                       )
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: arg,
                            rawSourceKind: types.kind(of: argType),
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: ctx.sema?.symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            into: &loweredBody
                        )
                        storedArg = boxedResult
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendTemporary(type: nil
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
                let runtimeCallee = callee == lookup.hashSetOfName
                    ? lookup.kkHashSetOfName
                    : callee == lookup.setOfNotNullName
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

        // --- Rewrite map factories to runtime helpers. ---
        if lookup.mapFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableMapOfName
                && callee != lookup.hashMapOfName
                && callee != lookup.linkedMapOfName {
                // emptyMap(), mapOf() -> kk_emptyMap()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptyMapName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // mutableMapOf()/hashMapOf()/linkedMapOf() -> fresh instance via kk_map_of(null, null, 0)
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
                // mapOf(pair1, pair2, ...), mutableMapOf(...), hashMapOf(...), linkedMapOf(...) -> kk_map_of
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let keysArrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: keysArrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                let valuesArrayExpr = module.arena.appendTemporary(type: nil
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
                    let keyExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkPairFirstName,
                        arguments: [arg],
                        result: keyExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let valueExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkPairSecondName,
                        arguments: [arg],
                        result: valueExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let setResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [keysArrayExpr, idxExpr, keyExpr],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let setResult2 = module.arena.appendTemporary(type: nil
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

        // Sequence factories are lowered through their bundled Kotlin source.

        // --- Rewrite builder DSL calls to kk_build_* runtime helpers (STDLIB-002) ---
        if isStdlibBuilderDSLCall(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let kkCallee: InternedString = switch callee {
            case lookup.buildListName:
                arguments.count == 2 ? lookup.kkBuildListWithCapacityName : lookup.kkBuildListName
            case lookup.buildSetName:
                arguments.count == 2 ? lookup.kkBuildSetWithCapacityName : lookup.kkBuildSetName
            case lookup.buildMapName:
                arguments.count == 2 ? lookup.kkBuildMapWithCapacityName : lookup.kkBuildMapName
            default: callee
            }
            let builderResult = module.arena.appendTemporary(type: nil
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


        return false
    }

    private func isSourceBackedBundledFunction(symbol: SymbolID?, ctx: KIRContext) -> Bool {
        guard let symbol, let sema = ctx.sema, sema.symbols.symbol(symbol) != nil else {
            return false
        }
        return sema.symbols.isSourceBackedSymbol(symbol)
    }
}
