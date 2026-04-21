// swiftlint:disable file_length
import Foundation

extension CollectionLiteralLoweringPass {

    private func primitiveBoxCalleeName(
        for type: TypeID,
        types: TypeSystem,
        interner: StringInterner
    ) -> InternedString? {
        switch types.kind(of: type) {
        case .primitive(.int, _), .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return interner.intern("kk_box_int")
        case .primitive(.boolean, _):
            return interner.intern("kk_box_bool")
        case .primitive(.long, _), .primitive(.ulong, _):
            return interner.intern("kk_box_long")
        case .primitive(.float, _):
            return interner.intern("kk_box_float")
        case .primitive(.double, _):
            return interner.intern("kk_box_double")
        case .primitive(.char, _):
            return interner.intern("kk_box_char")
        default:
            return nil
        }
    }

    /// Returns true when the resolved symbol's FQN matches one of the known
    /// `kotlin.collections.*` factory FQNs.  When the symbol is nil (unresolved)
    /// we conservatively allow the rewrite – the name check already passed and
    /// unresolved symbols are common for synthetic stubs that have no KIR-level
    /// symbol entry.
    private func isStdlibCollectionFactory(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard let sym = symbol,
              let resolved = ctx.sema?.symbols.symbol(sym)
        else {
            // No symbol info available – fall through to name-only rewrite
            // (backwards compatible with pre-symbol resolution passes).
            return true
        }
        let fqName = resolved.fqName
        // Match against known stdlib collection factory FQNs
        return fqName == lookup.emptyListFQName
            || fqName == lookup.emptyArrayFQName
            || fqName == lookup.listOfFQName
            || fqName == lookup.mutableListOfFQName
            || fqName == lookup.listOfNotNullFQName
            || fqName == lookup.emptySetFQName
            || fqName == lookup.setOfFQName
            || fqName == lookup.mutableSetOfFQName
            || fqName == lookup.emptyMapFQName
            || fqName == lookup.mapOfFQName
            || fqName == lookup.mutableMapOfFQName
    }

    private func isStdlibArrayFactoryCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard lookup.arrayOfFactoryNames.contains(callee) else {
            return false
        }
        return isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx)
    }

    private func isJavaIOFileMember(
        symbol: SymbolID?,
        ctx: KIRContext,
        interner: StringInterner
    ) -> Bool {
        guard let symbol,
              let resolved = ctx.sema?.symbols.symbol(symbol)
        else {
            return false
        }

        let javaIOFilePrefix: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]
        return resolved.fqName.starts(with: javaIOFilePrefix)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func rewriteCalls(module: KIRModule, ctx: KIRContext) throws {
        let lookup = CollectionLiteralLookupTables(interner: ctx.interner)
        let builderLambdaKinds = collectBuilderLambdaKinds(
            module: module,
            lookup: lookup,
            interner: ctx.interner
        )

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function
            let uintType = ctx.sema?.types.uintType

            func isUIntRangeExpr(_ expr: KIRExprID) -> Bool {
                guard let uintType else { return false }
                return module.arena.exprType(expr) == uintType
            }

            // Phase 1: Identify collection-typed expression IDs
            var listExprIDs: Set<Int32> = []
            var setExprIDs: Set<Int32> = []
            var mapExprIDs: Set<Int32> = []
            var arrayExprIDs: Set<Int32> = []
            var sequenceExprIDs: Set<Int32> = []
            var rangeExprIDs: Set<Int32> = []
            var charRangeExprIDs: Set<Int32> = []
            var ulongRangeExprIDs: Set<Int32> = []
            var stringExprIDs: Set<Int32> = []
            var fileExprIDs: Set<Int32> = []

            collectInitialCollectionExprIDs(
                function: function,
                lookup: lookup,
                arena: module.arena,
                sema: ctx.sema,
                interner: ctx.interner,
                listExprIDs: &listExprIDs,
                setExprIDs: &setExprIDs,
                mapExprIDs: &mapExprIDs,
                arrayExprIDs: &arrayExprIDs,
                sequenceExprIDs: &sequenceExprIDs,
                rangeExprIDs: &rangeExprIDs,
                charRangeExprIDs: &charRangeExprIDs,
                ulongRangeExprIDs: &ulongRangeExprIDs,
                stringExprIDs: &stringExprIDs,
                fileExprIDs: &fileExprIDs
            )

            // Phase 2: Rewrite instructions
            var listIteratorExprIDs: Set<Int32> = []
            var mapIteratorExprIDs: Set<Int32> = []
            var stringIteratorExprIDs: Set<Int32> = []
            var iteratorBuilderExprIDs: Set<Int32> = []
            var indexingIterableExprIDs: Set<Int32> = []
            var indexingIterableIteratorExprIDs: Set<Int32> = []
            var ulongRangeIteratorExprIDs: Set<Int32> = []
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _):
                    // --- Rewrite listOf/mutableListOf/emptyList/emptyArray → kk_list_of / kk_emptyList / kk_empty_array ---
                    // --- Rewrite arrayOf/intArrayOf/... → kk_array_of ---
                    // Only rewrite calls whose symbol resolves to a known
                    // kotlin.collections.* factory to avoid accidentally
                    // lowering user-defined functions with the same name.
                    if lookup.listFactoryNames.contains(callee),
                       isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
                        let count = arguments.count
                        if count == 0 && callee != lookup.mutableListOfName {
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
                            // mutableListOf() → fresh instance via kk_list_of(null, 0)
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
                        continue
                    }

                    // --- Rewrite ArrayList()/HashSet()/LinkedHashSet()/HashMap()/LinkedHashMap() constructors ---
                    // 0 args → empty collection; 1 int arg (capacity) → empty collection;
                    // 1 collection arg → copy (treated as empty for now since runtime uses Swift collections)
                    if lookup.mutableListConstructorNames.contains(callee) {
                        // All forms produce an empty mutable list
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
                        continue
                    }

                    if lookup.mutableSetConstructorNames.contains(callee) {
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
                        continue
                    }

                    if lookup.mutableMapConstructorNames.contains(callee) {
                        // Create an empty mutable map first
                        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                        let nullExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: nullExpr2, value: .intLiteral(0)))

                        if arguments.count == 1 {
                            // Copy constructor: HashMap(otherMap)
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
                            // 0 args or capacity arg → empty map
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkMapOfName,
                                arguments: [nullExpr, nullExpr2, zeroExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // map.count(predicate) on map literals
                    if callee == lookup.countName && (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]
                        let lambdaID = arguments[1]
                        if mapExprIDs.contains(receiverID.rawValue) {
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
                            continue
                        }
                    }

                    // --- Rewrite setOf/mutableSetOf/emptySet → kk_set_of / kk_emptySet ---
                    if lookup.setFactoryNames.contains(callee),
                       isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
                        let count = arguments.count
                        if count == 0 && callee != lookup.mutableSetOfName {
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
                            // mutableSetOf() → fresh instance via kk_set_of(null, 0)
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

                    // --- Rewrite mapOf/mutableMapOf/emptyMap → kk_map_of / kk_emptyMap ---
                    if lookup.mapFactoryNames.contains(callee),
                       isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
                        let count = arguments.count
                        if count == 0 && callee != lookup.mutableMapOfName {
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
                            // mutableMapOf() → fresh instance via kk_map_of(null, null, 0)
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
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
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
                            listExprIDs.insert(result.rawValue)
                            listExprIDs.insert(builderResult.rawValue)
                        }
                        if callee == lookup.buildSetName, let result {
                            setExprIDs.insert(result.rawValue)
                            setExprIDs.insert(builderResult.rawValue)
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
                            continue
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
                        continue
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
                        continue
                    }

                    // --- Rewrite File(path) → kk_file_new(path) (STDLIB-565)
                    //     Rewrite File(parent, child) → kk_file_new_parent_child(parent, child) (STDLIB-IO-087) ---
                    if callee == lookup.fileConstructorName {
                        let fileCallee = arguments.count == 2
                            ? lookup.kkFileNewParentChildName
                            : lookup.kkFileNewName
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: fileCallee,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { fileExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // --- Rewrite File member calls: readText/writeText/readLines (STDLIB-320) ---
                    if callee == lookup.readTextName,
                       arguments.count == 1,
                       fileExprIDs.contains(arguments[0].rawValue),
                       isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkFileReadTextName,
                            arguments: arguments,
                            result: result,
                            canThrow: true,
                            thrownResult: thrownResult
                        ))
                        continue
                    }

                    if callee == lookup.writeTextName,
                       arguments.count == 2,
                       fileExprIDs.contains(arguments[0].rawValue),
                       isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkFileWriteTextName,
                            arguments: arguments,
                            result: result,
                            canThrow: true,
                            thrownResult: thrownResult
                        ))
                        continue
                    }

                    if callee == lookup.appendTextName,
                       arguments.count == 2,
                       fileExprIDs.contains(arguments[0].rawValue),
                       isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkFileAppendTextName,
                            arguments: arguments,
                            result: result,
                            canThrow: true,
                            thrownResult: thrownResult
                        ))
                        continue
                    }

                    if callee == lookup.readLinesName,
                       arguments.count == 1,
                       fileExprIDs.contains(arguments[0].rawValue),
                       isJavaIOFileMember(symbol: symbol, ctx: ctx, interner: ctx.interner)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkFileReadLinesName,
                            arguments: arguments,
                            result: result,
                            canThrow: true,
                            thrownResult: thrownResult
                        ))
                        if let result { listExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // --- Rewrite File member calls (STDLIB-321) ---
                    // Only rewrite calls on File expressions (tracked in fileExprIDs)
                    if arguments.count >= 1, fileExprIDs.contains(arguments[0].rawValue) {
                        let receiverID = arguments[0]
                        let kkCallee: InternedString?
                        
                        switch callee {
                        case lookup.readTextName:
                            kkCallee = lookup.kkFileReadTextName
                        case lookup.writeTextName:
                            kkCallee = lookup.kkFileWriteTextName
                        case lookup.appendTextName:
                            kkCallee = lookup.kkFileAppendTextName
                        case lookup.readLinesName:
                            kkCallee = lookup.kkFileReadLinesName
                        case lookup.existsName:
                            kkCallee = lookup.kkFileExistsName
                        case lookup.isFileName:
                            kkCallee = lookup.kkFileIsFileName
                        case lookup.isDirectoryName:
                            kkCallee = lookup.kkFileIsDirectoryName
                        case lookup.namePropertyName:
                            kkCallee = lookup.kkFileNameName
                        case lookup.pathPropertyName:
                            kkCallee = lookup.kkFilePathName
                        case lookup.forEachLineName:
                            kkCallee = lookup.kkFileForEachLineName
                        case lookup.useLinesName:
                            kkCallee = lookup.kkFileUseLinesName
                        case lookup.bufferedReaderName:
                            // Only rewrite argument-less bufferedReader(); the runtime
                            // function kk_file_bufferedReader does not accept charset/bufferSize.
                            kkCallee = arguments.count == 1 ? lookup.kkFileBufferedReaderName : nil
                        case lookup.bufferedWriterName:
                            // Only rewrite argument-less bufferedWriter()
                            kkCallee = arguments.count == 1 ? lookup.kkFileBufferedWriterName : nil
                        case lookup.walkName:
                            kkCallee = lookup.kkFileWalkName
                        case lookup.listFilesName:
                            kkCallee = lookup.kkFileListFilesName
                        case lookup.deleteName:
                            kkCallee = lookup.kkFileDeleteName
                        case lookup.mkdirsName:
                            kkCallee = lookup.kkFileMkdirsName
                        case lookup.readBytesName:
                            kkCallee = lookup.kkFileReadBytesName
                        case lookup.appendTextName:
                            kkCallee = lookup.kkFileAppendTextName
                        // STDLIB-IO-087: Additional File operations
                        case lookup.absolutePathName:
                            kkCallee = lookup.kkFileAbsolutePathName
                        case lookup.canonicalPathName:
                            kkCallee = lookup.kkFileCanonicalPathName
                        case lookup.parentName:
                            kkCallee = lookup.kkFileParentName
                        case lookup.lengthName:
                            kkCallee = lookup.kkFileLengthName
                        case lookup.lastModifiedName:
                            kkCallee = lookup.kkFileLastModifiedName
                        case lookup.createNewFileName:
                            kkCallee = lookup.kkFileCreateNewFileName
                        case lookup.canReadName:
                            kkCallee = lookup.kkFileCanReadName
                        case lookup.canWriteName:
                            kkCallee = lookup.kkFileCanWriteName
                        case lookup.canExecuteName:
                            kkCallee = lookup.kkFileCanExecuteName
                        default:
                            kkCallee = nil
                        }
                        
                        if let target = kkCallee {
                            let memberArgs = (
                                callee == lookup.forEachLineName
                                    || callee == lookup.useLinesName
                                    || callee == lookup.writeTextName
                                    || callee == lookup.appendTextName
                            ) ? [receiverID] + arguments.dropFirst() : [receiverID]
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: target,
                                arguments: memberArgs,
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                            // Track walk()/listFiles()/readLines() results as lists
                            // so chained operations (forEach, sortedBy, etc.) are rewritten correctly
                            if let result,
                               callee == lookup.walkName || callee == lookup.listFilesName || callee == lookup.readLinesName || callee == lookup.readBytesName
                            {
                                listExprIDs.insert(result.rawValue)
                            }
                            // Track bufferedReader()/bufferedWriter() results as file-like exprs for chained member calls
                            if let result,
                               callee == lookup.bufferedReaderName || callee == lookup.bufferedWriterName
                            {
                                fileExprIDs.insert(result.rawValue)
                            }
                            continue
                        }
                    }

                    // --- Append closureRaw argument for File lambda-accepting methods (STDLIB-322) ---
                    // When the KIR callee is already rewritten via externalLinkName,
                    // the lambda argument must be supplemented with closureRaw (0)
                    // so the runtime receives (fileRaw, fnPtr, closureRaw, outThrown).
                    if callee == lookup.kkFileForEachLineName || callee == lookup.kkFileUseLinesName {
                        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        loweredBody.append(.call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments + [zeroExpr],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        continue
                    }

                    // --- Rewrite arrayOf → kk_array_of ---
                    if isStdlibArrayFactoryCall(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
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

                    // --- Rewrite kk_range_iterator on ULong range → kk_ulong_range_iterator (STDLIB-RANGE-037) ---
                    if callee == lookup.kkRangeIteratorName, arguments.count == 1 {
                        let argID = arguments[0]
                        if ulongRangeExprIDs.contains(argID.rawValue) {
                            if let result { ulongRangeIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkULongRangeIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if module.arena.exprType(argID) == ctx.sema?.types.uintType {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: ctx.interner.intern("kk_uint_range_iterator"),
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
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
                        // STDLIB-331/564: iterator {} result is already an iterator; pass through
                        if iteratorBuilderExprIDs.contains(argID.rawValue) {
                            if let result {
                                iteratorBuilderExprIDs.insert(result.rawValue)
                                loweredBody.append(.copy(from: argID, to: result))
                            }
                            continue
                        }
                        // Rewrite kk_range_iterator on IndexingIterable → kk_indexing_iterable_iterator
                        if indexingIterableExprIDs.contains(argID.rawValue) {
                            if let result { indexingIterableIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkIndexingIterableIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_hasNext on ULong range iterator → kk_ulong_range_hasNext (STDLIB-RANGE-037) ---
                    if callee == lookup.kkRangeHasNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if ulongRangeIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkULongRangeHasNextName,
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
                        // STDLIB-331/564: Rewrite kk_range_hasNext on iterator builder → kk_iterator_builder_hasNext
                        if iteratorBuilderExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkIteratorBuilderHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        // Rewrite kk_range_hasNext on IndexingIterable iterator → kk_indexing_iterable_hasNext
                        if indexingIterableIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkIndexingIterableHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_next on ULong range iterator → kk_ulong_range_next (STDLIB-RANGE-037) ---
                    if callee == lookup.kkRangeNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if ulongRangeIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkULongRangeNextName,
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
                        // STDLIB-331/564: Rewrite kk_range_next on iterator builder → kk_iterator_builder_next
                        if iteratorBuilderExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkIteratorBuilderNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        // Rewrite kk_range_next on IndexingIterable iterator → kk_indexing_iterable_next
                        if indexingIterableIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkIndexingIterableNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- STDLIB-538: Rewrite explicit listIterator() on list → kk_list_iterator ---
                    if callee == lookup.listIteratorMemberName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            if let result { listIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListIteratorName,
                                arguments: [receiverID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- STDLIB-538: Rewrite hasPrevious()/previous() on list iterator ---
                    let isListIteratorReceiverCall = arguments.count == 1
                        && listIteratorExprIDs.contains(arguments[0].rawValue)
                    if isListIteratorReceiverCall,
                       callee == lookup.hasPreviousName || callee == lookup.previousName {
                        let runtimeCallee = callee == lookup.hasPreviousName
                            ? lookup.kkListIteratorHasPreviousName
                            : lookup.kkListIteratorPreviousName
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: runtimeCallee,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
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
                               callee == lookup.firstName || callee == lookup.lastName || callee == lookup.endExclusiveName
                            {
                                let kkName: InternedString = switch callee {
                                case lookup.firstName: lookup.kkRangeFirstName
                                case lookup.lastName: lookup.kkRangeLastName
                                case lookup.endExclusiveName: lookup.kkRangeEndExclusiveName
                                default: callee
                                }
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
                                let countCallee: InternedString
                                if ulongRangeExprIDs.contains(receiverID.rawValue) {
                                    countCallee = lookup.kkULongRangeCountName
                                } else if isUIntRangeExpr(receiverID) {
                                    countCallee = ctx.interner.intern("kk_uint_range_count")
                                } else {
                                    countCallee = lookup.kkRangeCountName
                                }
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: countCallee,
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

                    if callee == lookup.containsAllName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListContainsAllName,
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
                                    callee: lookup.kkSetContainsAllName,
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

                    if callee == lookup.containsValueName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkMapContainsValueName,
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
                            // STDLIB-637: UIntRange/ULongRange isEmpty
                            if rangeExprIDs.contains(receiverID.rawValue) {
                                let isUIntRange = isUIntRangeExpr(receiverID)
                                let isEmptyName = ulongRangeExprIDs.contains(receiverID.rawValue)
                                    ? lookup.kkULongRangeIsEmptyName
                                    : (isUIntRange ? ctx.interner.intern("kk_uint_range_isEmpty") : lookup.kkRangeIsEmptyName)
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: isEmptyName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    // STDLIB-637: range/list sum()
                    if callee == lookup.sumName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if rangeExprIDs.contains(receiverID.rawValue) {
                                let isUIntRange = isUIntRangeExpr(receiverID)
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: isUIntRange ? ctx.interner.intern("kk_uint_range_sum") : lookup.kkRangeSumName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                            if listExprIDs.contains(receiverID.rawValue) || arrayExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkListSumName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    // --- Rewrite sequence member calls (STDLIB-003 / STDLIB-471) ---
                    // asSequence() on collection → kk_list_asSequence or kk_array_asSequence
                    // Guard with arrayExprIDs / listExprIDs so we only rewrite
                    // receivers whose concrete collection kind is known.
                    // Since LOWERING-001, non-tracked receivers (e.g., a List<Int>
                    // parameter or a function return value) are now seeded into
                    // the tracking sets via static type information from KIR.
                    // They are rewritten correctly by the checks below.

                    // When the callee is already the runtime name (e.g., resolved
                    // via the synthetic stub's externalLinkName), track the result as
                    // a sequence expression so downstream map/filter/toList rewrites fire.
                    if callee == lookup.kkListAsSequenceName || callee == lookup.kkArrayAsSequenceName
                        || callee == lookup.kkSequenceMapName || callee == lookup.kkSequenceFilterName
                        || callee == lookup.kkSequenceTakeName || callee == lookup.kkSequenceFlatMapName
                        || callee == lookup.kkSequenceDropName || callee == lookup.kkSequenceDistinctName
                        || callee == lookup.kkSequenceZipName
                        || callee == lookup.kkSequencePlusName || callee == lookup.kkSequenceMinusName
                    {
                        loweredBody.append(instruction)
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    if callee == lookup.asSequenceName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if arrayExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkArrayAsSequenceName,
                                arguments: [receiverID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        } else if listExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListAsSequenceName,
                                arguments: [receiverID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        } else {
                            // Receiver is not a tracked list/array literal — skip
                            // the rewrite and let virtual-call rewrite or the
                            // original symbol linkage handle it. Still mark the
                            // result as a sequence so downstream map/filter/take
                            // rewrites fire correctly for chained calls.
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                        }
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

                    // forEachIndexed on sequence → kk_sequence_forEachIndexed
                    if callee == lookup.forEachIndexedName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceForEachIndexedName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // zipWithNext on sequence → kk_sequence_zipWithNext / kk_sequence_zipWithNextTransform
                    if callee == lookup.zipWithNextName,
                       arguments.count == 1 || arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            if arguments.count == 1 {
                                // zipWithNext() — no transform
                                let hofResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSequenceZipWithNextName,
                                    arguments: [receiverID],
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
                            } else {
                                // zipWithNext { a, b -> ... } — with transform
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
                                    callee: lookup.kkSequenceZipWithNextTransformName,
                                    arguments: [receiverID, lambdaID, closureRawID],
                                    result: hofResult,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult
                                ))
                                if let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                    loweredBody.append(.copy(from: hofResult, to: result))
                                }
                                continue
                            }
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

                    // plus(other) on sequence → kk_sequence_plus (STDLIB-561)
                    // If the argument is not a collection, wrap it in a
                    // single-element sequence first so the runtime ABI always
                    // receives a collection handle.
                    if callee == lookup.plusMemberName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let argID = arguments[1]
                            // Only sequence/list/array are supported by
                            // kk_sequence_plus at the ABI level (not Set/Map).
                            let isArgCollection = listExprIDs.contains(argID.rawValue)
                                || sequenceExprIDs.contains(argID.rawValue)
                                || arrayExprIDs.contains(argID.rawValue)
                            let effectiveArg: KIRExprID
                            if isArgCollection {
                                effectiveArg = argID
                            } else {
                                let wrappedExpr = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSequenceOfSingleName,
                                    arguments: [argID],
                                    result: wrappedExpr,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                effectiveArg = wrappedExpr
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequencePlusName,
                                arguments: [receiverID, effectiveArg],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // plusElement(element) on sequence -> kk_sequence_plus_element (STDLIB-SEQ-013)
                    if callee == lookup.plusElementName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequencePlusElementName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // minus(element) on sequence → kk_sequence_minus (STDLIB-562)
                    // Only rewrite when the argument is a single element (not a
                    // collection).  Collection-removal is not yet supported at the
                    // ABI level and falls through to the generic member-call path.
                    if callee == lookup.minusMemberName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let argID = arguments[1]
                            // Only sequence/list/array are supported by the
                            // ABI (not Set/Map) -- consistent with plus path.
                            let isArgCollection = listExprIDs.contains(argID.rawValue)
                                || sequenceExprIDs.contains(argID.rawValue)
                                || arrayExprIDs.contains(argID.rawValue)
                            guard !isArgCollection else {
                                // Fall through: collection-removal not supported
                                loweredBody.append(instruction)
                                continue
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceMinusName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // toSet() on sequence → kk_sequence_toSet (STDLIB-470)
                    if callee == lookup.toSetName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let toSetResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceToSetName,
                                arguments: [receiverID],
                                result: toSetResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                setExprIDs.insert(result.rawValue)
                                setExprIDs.insert(toSetResult.rawValue)
                                loweredBody.append(.copy(from: toSetResult, to: result))
                            }
                            continue
                        }
                    }

                    // toMap() on sequence → kk_sequence_toMap (STDLIB-470)
                    if callee == lookup.toMapName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let toMapResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceToMapName,
                                arguments: [receiverID],
                                result: toMapResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                mapExprIDs.insert(result.rawValue)
                                mapExprIDs.insert(toMapResult.rawValue)
                                loweredBody.append(.copy(from: toMapResult, to: result))
                            }
                            continue
                        }
                    }

                    // groupBy on sequence → kk_sequence_groupBy (STDLIB-470)
                    if callee == lookup.groupByName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
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
                                callee: lookup.kkSequenceGroupByName,
                                arguments: [receiverID, lambdaID, closureRawID],
                                result: hofResult,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                            if let result {
                                mapExprIDs.insert(result.rawValue)
                                mapExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    // maxOrNull / minOrNull on sequence (STDLIB-470)
                    if callee == lookup.maxOrNullName || callee == lookup.minOrNullName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if sequenceExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString = callee == lookup.maxOrNullName
                                    ? lookup.kkSequenceMaxOrNullName
                                    : lookup.kkSequenceMinOrNullName
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

                    // flatten on sequence → kk_sequence_flatten (STDLIB-470)
                    if callee == lookup.flattenName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSequenceFlattenName,
                                arguments: [receiverID],
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

                    if callee == lookup.reversedName || callee == lookup.asReversedName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: callee == lookup.asReversedName ? lookup.kkListAsReversedName : lookup.kkListReversedName,
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
                        if callee == lookup.reversedName, rangeExprIDs.contains(receiverID.rawValue) {
                            let isUIntRange = isUIntRangeExpr(receiverID)
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            let reversedName = ulongRangeExprIDs.contains(receiverID.rawValue)
                                ? lookup.kkULongRangeReversedName
                                : (isUIntRange ? ctx.interner.intern("kk_uint_range_reversed") : lookup.kkRangeReversedName)
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: reversedName,
                                arguments: [receiverID],
                                result: transformResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result {
                                rangeExprIDs.insert(result.rawValue)
                                rangeExprIDs.insert(transformResult.rawValue)
                                if ulongRangeExprIDs.contains(receiverID.rawValue) {
                                    ulongRangeExprIDs.insert(transformResult.rawValue)
                                    ulongRangeExprIDs.insert(result.rawValue)
                                }
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
                        if setExprIDs.contains(receiverID.rawValue) {
                            let transformResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkSetSortedName,
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
                            // Use char/ULong range variant if applicable (STDLIB-290, STDLIB-524)
                            let rangeToListCallee: InternedString
                            if charRangeExprIDs.contains(receiverID.rawValue) {
                                rangeToListCallee = lookup.kkCharRangeToListName
                            } else if ulongRangeExprIDs.contains(receiverID.rawValue) {
                                rangeToListCallee = lookup.kkULongRangeToListName
                            } else if isUIntRangeExpr(receiverID) {
                                rangeToListCallee = ctx.interner.intern("kk_uint_range_toList")
                            } else {
                                rangeToListCallee = lookup.kkRangeToListName
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: rangeToListCallee,
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

                    // toIntArray() on list → kk_list_toIntArray (STDLIB-LIST-PRIM-ARRAY)
                    if callee == lookup.toIntArrayName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let toArrayResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToIntArrayName,
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

                    // toLongArray() on list → kk_list_toLongArray (STDLIB-LIST-PRIM-ARRAY)
                    if callee == lookup.toLongArrayName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let toArrayResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToLongArrayName,
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

                    // toByteArray() on list → kk_list_toByteArray (STDLIB-LIST-PRIM-ARRAY)
                    if callee == lookup.toByteArrayName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let toArrayResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListToByteArrayName,
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

                    // iterator { ... } builder → kk_iterator_builder_build (STDLIB-331)
                    // Mirror the sequence {} builder rewrite. The sema layer
                    // already special-cases the synthetic stdlib builder, so
                    // by this point plain `iterator { ... }` should refer to
                    // kotlin.sequences.iterator rather than a user-defined
                    // overload. Keep the runtime call non-throwing.
                    if callee == lookup.iteratorBuilderName, arguments.count == 1, symbol == nil {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkIteratorBuilderBuildName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { iteratorBuilderExprIDs.insert(result.rawValue) }
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

                    // yieldAll(iterable) inside sequence builder → kk_sequence_builder_yieldAll (STDLIB-553)
                    if callee == lookup.yieldAllName, arguments.count == 2 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: lookup.kkSequenceBuilderYieldAllName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }

                    // --- Rewrite higher-order collection member calls (FUNC-003) ---
                    if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.mapNotNullName || callee == lookup.forEachName || callee == lookup.onEachName
                        || callee == lookup.flatMapName || callee == lookup.anyName || callee == lookup.noneName
                        || callee == lookup.allName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
                        || callee == lookup.toListName || callee == lookup.countName
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
                            if setExprIDs.contains(receiverID.rawValue) {
                                let toListResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkSetToListName,
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
                            // countName with a List receiver is handled by the dedicated count/first/last
                            // handler below, which correctly rewrites it to kk_list_count.
                            // Entering this generic list-HOF path for countName would emit a call with
                            // the un-rewritten "count" callee and then `continue`, skipping that handler.
                            if listExprIDs.contains(receiverID.rawValue) && callee != lookup.countName {
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
                                case lookup.filterNotName: lookup.kkListFilterNotName
                                case lookup.mapNotNullName: lookup.kkListMapNotNullName
                                case lookup.forEachName: lookup.kkListForEachName
                                case lookup.onEachName: lookup.kkListOnEachName
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
                                    || callee == lookup.filterNotName
                                    || callee == lookup.onEachName
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
                               || callee == lookup.filterKeysName || callee == lookup.filterValuesName
                               || callee == lookup.flatMapName || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
                               || callee == lookup.anyName || callee == lookup.allName
                               || callee == lookup.noneName
                               || callee == lookup.flatMapName || callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
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
                                case lookup.filterNotName: lookup.kkMapFilterNotName
                                case lookup.filterKeysName: lookup.kkMapFilterKeysName
                                case lookup.filterValuesName: lookup.kkMapFilterValuesName
                                case lookup.forEachName: lookup.kkMapForEachName
                                case lookup.mapValuesName: lookup.kkMapMapValuesName
                                case lookup.mapKeysName: lookup.kkMapMapKeysName
                                case lookup.mapNotNullName: lookup.kkMapMapNotNullName
                                case lookup.flatMapName: lookup.kkMapFlatMapName
                                case lookup.maxByOrNullName: lookup.kkMapMaxByOrNullName
                                case lookup.minByOrNullName: lookup.kkMapMinByOrNullName
                                case lookup.anyName: lookup.kkMapAnyName
                                case lookup.allName: lookup.kkMapAllName
                                case lookup.noneName: lookup.kkMapNoneName
                                case lookup.flatMapName: lookup.kkMapFlatMapName
                                case lookup.maxByOrNullName: lookup.kkMapMaxByOrNullName
                                case lookup.minByOrNullName: lookup.kkMapMinByOrNullName
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
                                if callee == lookup.mapName || callee == lookup.flatMapName || callee == lookup.mapNotNullName, let result {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                }
                                if callee == lookup.mapValuesName || callee == lookup.mapKeysName, let result {
                                    mapExprIDs.insert(result.rawValue)
                                    mapExprIDs.insert(hofResult.rawValue)
                                }
                                if callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.filterKeysName || callee == lookup.filterValuesName, let result {
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
                                let isCharRange = charRangeExprIDs.contains(receiverID.rawValue)
                                let isULongRange = ulongRangeExprIDs.contains(receiverID.rawValue)
                                let kkName: InternedString
                                if callee == lookup.mapName {
                                    // STDLIB-RANGE-037: use ULong-specific map for unsigned ranges
                                    kkName = isULongRange ? lookup.kkULongRangeMapName : lookup.kkRangeMapName
                                } else {
                                    // forEach: use ULong, char, or default range variant
                                    if isULongRange {
                                        kkName = lookup.kkULongRangeForEachName
                                    } else {
                                        kkName = isCharRange ? lookup.kkCharRangeForEachName : lookup.kkRangeForEachName
                                    }
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
                            if setExprIDs.contains(receiverID.rawValue),
                               callee == lookup.mapName || callee == lookup.filterName
                               || callee == lookup.forEachName
                               || callee == lookup.filterNotName
                               || callee == lookup.mapNotNullName
                               || callee == lookup.flatMapName
                               || callee == lookup.anyName
                               || callee == lookup.noneName
                               || callee == lookup.allName
                               || callee == lookup.countName
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
                                case lookup.mapName: lookup.kkSetMapName
                                case lookup.filterName: lookup.kkSetFilterName
                                case lookup.forEachName: lookup.kkSetForEachName
                                case lookup.filterNotName: lookup.kkSetFilterNotName
                                case lookup.mapNotNullName: lookup.kkSetMapNotNullName
                                case lookup.flatMapName: lookup.kkSetFlatMapName
                                case lookup.anyName: lookup.kkSetAnyName
                                case lookup.noneName: lookup.kkSetNoneName
                                case lookup.allName: lookup.kkSetAllName
                                case lookup.countName: lookup.kkSetCountPredicateName
                                default: callee
                                }
                                let needsListTag = callee == lookup.mapName || callee == lookup.filterName
                                    || callee == lookup.filterNotName || callee == lookup.mapNotNullName
                                    || callee == lookup.flatMapName
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

                    // --- STDLIB-631: groupBy with value transform (two-lambda variant) ---
                    // Arguments: [receiver, keyLambda, keyClosureRaw, valueLambda] (4 args)
                    // or [receiver, keyLambda, keyClosureRaw, valueLambda, valueClosureRaw] (5 args)
                    if callee == lookup.groupByName,
                       arguments.count == 4 || arguments.count == 5,
                       listExprIDs.contains(arguments[0].rawValue)
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
                            mapExprIDs.insert(result.rawValue)
                            mapExprIDs.insert(hofResult.rawValue)
                            loweredBody.append(.copy(from: hofResult, to: result))
                        }
                        continue
                    }

                    // --- Rewrite additional HOF collection member calls (STDLIB-005) ---
                    // 1-param lambda HOFs with [receiver, lambda, closureRaw?]
                    if callee == lookup.groupByName || callee == lookup.sortedByName || callee == lookup.findName
                        || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
                        || callee == lookup.distinctByName
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

                    // --- STDLIB-SEQ-022: sequence destination-collection mapping variants ---
                    if (callee == lookup.mapToName || callee == lookup.mapIndexedNotNullToName),
                       (arguments.count == 3 || arguments.count == 4),
                       sequenceExprIDs.contains(arguments[0].rawValue)
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
                        let kkName = callee == lookup.mapToName
                            ? lookup.kkSequenceMapToName
                            : lookup.kkSequenceMapIndexedNotNullToName
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
                            if listExprIDs.contains(destID.rawValue) {
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(hofResult.rawValue)
                            } else if setExprIDs.contains(destID.rawValue) {
                                setExprIDs.insert(result.rawValue)
                                setExprIDs.insert(hofResult.rawValue)
                            }
                            loweredBody.append(.copy(from: hofResult, to: result))
                        }
                        continue
                    }

                    // --- STDLIB-021: destination collection variants with [receiver, dest, lambda, closureRaw?] ---
                    if callee == lookup.filterToName || callee == lookup.filterNotToName
                        || callee == lookup.mapToName || callee == lookup.flatMapToName
                        || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName
                        || callee == lookup.flatMapIndexedToName || callee == lookup.associateToName
                    {
                        if (arguments.count == 3 || arguments.count == 4),
                           (listExprIDs.contains(arguments[0].rawValue)
                            || setExprIDs.contains(arguments[0].rawValue)
                            || sequenceExprIDs.contains(arguments[0].rawValue)
                            || arrayExprIDs.contains(arguments[0].rawValue))
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
                            let isSequenceReceiver = sequenceExprIDs.contains(receiverID.rawValue)
                            let kkName: InternedString = switch callee {
                            case lookup.filterToName: lookup.kkListFilterToName
                            case lookup.filterNotToName: lookup.kkListFilterNotToName
                            case lookup.mapToName: lookup.kkListMapToName
                            case lookup.flatMapToName: lookup.kkListFlatMapToName
                            case lookup.mapNotNullToName: lookup.kkListMapNotNullToName
                            case lookup.mapIndexedToName: lookup.kkListMapIndexedToName
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
                                if listExprIDs.contains(destID.rawValue) {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                } else if setExprIDs.contains(destID.rawValue) {
                                    setExprIDs.insert(result.rawValue)
                                    setExprIDs.insert(hofResult.rawValue)
                                } else if mapExprIDs.contains(destID.rawValue) {
                                    mapExprIDs.insert(result.rawValue)
                                    mapExprIDs.insert(hofResult.rawValue)
                                }
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.toCollectionName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        let destID = arguments[1]
                        let runtimeCallee: InternedString?
                        if listExprIDs.contains(receiverID.rawValue)
                            || setExprIDs.contains(receiverID.rawValue)
                            || arrayExprIDs.contains(receiverID.rawValue)
                        {
                            runtimeCallee = lookup.kkCollectionToCollectionName
                        } else if sequenceExprIDs.contains(receiverID.rawValue) {
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
                                if listExprIDs.contains(destID.rawValue) {
                                    listExprIDs.insert(result.rawValue)
                                    listExprIDs.insert(hofResult.rawValue)
                                } else if setExprIDs.contains(destID.rawValue) {
                                    setExprIDs.insert(result.rawValue)
                                    setExprIDs.insert(hofResult.rawValue)
                                }
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    // --- STDLIB-SEQ-023 / STDLIB-535/536/537: sequence/list *To variants with [receiver, dest, lambda, closureRaw?] ---
                    if callee == lookup.associateByToName || callee == lookup.associateWithToName
                        || callee == lookup.groupByToName
                    {
                        if (arguments.count == 3 || arguments.count == 4),
                           (listExprIDs.contains(arguments[0].rawValue)
                            || sequenceExprIDs.contains(arguments[0].rawValue))
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
                            let isSequenceReceiver = sequenceExprIDs.contains(receiverID.rawValue)
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
                                mapExprIDs.insert(result.rawValue)
                                mapExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
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

                    // zipWithNext(): List<Pair<T, T>> — 0-arg (receiver only)
                    if callee == lookup.zipWithNextName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    // zipWithNext(transform): List<R> — 1-arg HOF (receiver + lambda + closure)
                    if callee == lookup.zipWithNextName, arguments.count == 2 || arguments.count == 3 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
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
                                listExprIDs.insert(result.rawValue)
                                listExprIDs.insert(hofResult.rawValue)
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.withIndexName || callee == lookup.kkListWithIndexName, arguments.count == 1 {
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
                                indexingIterableExprIDs.insert(result.rawValue)
                                indexingIterableExprIDs.insert(transformResult.rawValue)
                                loweredBody.append(.copy(from: transformResult, to: result))
                            }
                            continue
                        }
                    }

                    if callee == lookup.forEachIndexedName || callee == lookup.mapIndexedName || callee == lookup.onEachIndexedName {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let lambdaID = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString
                                if callee == lookup.forEachIndexedName {
                                    kkName = lookup.kkListForEachIndexedName
                                } else if callee == lookup.onEachIndexedName {
                                    kkName = lookup.kkListOnEachIndexedName
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
                                if callee == lookup.mapIndexedName || callee == lookup.onEachIndexedName, let result {
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
                    // maxByOrNull / minByOrNull / maxOfOrNull / minOfOrNull / maxOf / minOf (STDLIB-301)
                    if callee == lookup.maxByOrNullName || callee == lookup.minByOrNullName
                        || callee == lookup.maxOfOrNullName || callee == lookup.minOfOrNullName
                        || callee == lookup.maxOfName || callee == lookup.minOfName
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
                                case lookup.maxByOrNullName: lookup.kkListMaxByOrNullName
                                case lookup.minByOrNullName: lookup.kkListMinByOrNullName
                                case lookup.maxOfOrNullName: lookup.kkListMaxOfOrNullName
                                case lookup.minOfOrNullName: lookup.kkListMinOfOrNullName
                                case lookup.maxOfName: lookup.kkListMaxOfName
                                default: lookup.kkListMinOfName
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

                    // maxWith / maxWithOrNull / minWith / minWithOrNull (comparator-based) (STDLIB-301c)
                    if callee == lookup.maxWithName || callee == lookup.maxWithOrNullName
                        || callee == lookup.minWithName || callee == lookup.minWithOrNullName
                    {
                        if arguments.count == 2 || arguments.count == 3 {
                            let receiverID = arguments[0]
                            let comparatorExpr = arguments[1]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString = switch callee {
                                case lookup.maxWithName: lookup.kkListMaxWithName
                                case lookup.maxWithOrNullName: lookup.kkListMaxWithOrNullName
                                case lookup.minWithName: lookup.kkListMinWithName
                                default: lookup.kkListMinWithOrNullName
                                }
                                let source = isComparatorFromCall(
                                    exprID: comparatorExpr,
                                    body: function.body,
                                    ascendingCallee: lookup.kkComparatorFromSelectorName,
                                    descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                                    naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                                    reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                                    thenByCallee: lookup.kkComparatorThenByName,
                                    thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                                    thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                                    thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                                    reversedCallee: lookup.kkComparatorReversedName
                                )
                                let trampolineName: InternedString
                                let closureExpr: KIRExprID
                                if case .unknown = source {
                                    // Direct lambda comparator — pass as fnPtr with closureRaw
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
                                        arguments: [receiverID, comparatorExpr, closureRawID],
                                        result: hofResult,
                                        canThrow: canThrow,
                                        thrownResult: thrownResult
                                    ))
                                    if let result {
                                        loweredBody.append(.copy(from: hofResult, to: result))
                                    }
                                    continue
                                }
                                switch source {
                                case .descending:
                                    trampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                    closureExpr = comparatorExpr
                                case .multiSelector:
                                    trampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                    closureExpr = comparatorExpr
                                case .thenBy:
                                    trampolineName = lookup.kkComparatorThenByTrampolineName
                                    closureExpr = comparatorExpr
                                case .thenByDescending:
                                    trampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                    closureExpr = comparatorExpr
                                case .thenDescending:
                                    trampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                    closureExpr = comparatorExpr
                                case .thenComparator:
                                    trampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                    closureExpr = comparatorExpr
                                case .nullsFirst:
                                    trampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                    closureExpr = comparatorExpr
                                case .nullsLast:
                                    trampolineName = lookup.kkComparatorNullsLastTrampolineName
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
                                case let .reversed(innerExpr):
                                    trampolineName = lookup.kkComparatorReversedTrampolineName
                                    let innerSource = isComparatorFromCall(
                                        exprID: innerExpr,
                                        body: function.body,
                                        ascendingCallee: lookup.kkComparatorFromSelectorName,
                                        descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                                        multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                                        naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                                        reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                                        thenByCallee: lookup.kkComparatorThenByName,
                                        thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                                        thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                                        thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                                        nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                                        nullsLastCallee: lookup.kkComparatorNullsLastName,
                                        multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                                        reversedCallee: lookup.kkComparatorReversedName
                                    )
                                    let innerTrampolineName: InternedString
                                    let innerClosureExpr: KIRExprID
                                    switch innerSource {
                                    case .ascending:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .descending:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .multiSelector:
                                        innerTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenBy:
                                        innerTrampolineName = lookup.kkComparatorThenByTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenByDescending:
                                        innerTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenDescending:
                                        innerTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenComparator:
                                        innerTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .nullsFirst:
                                        innerTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .nullsLast:
                                        innerTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .naturalOrder:
                                        innerTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                        innerClosureExpr = zero
                                    case .reverseOrder:
                                        innerTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                        innerClosureExpr = zero
                                    default:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                        innerClosureExpr = innerExpr
                                    }
                                    let innerTrampolineExpr = module.arena.appendExpr(
                                        .externSymbolAddress(innerTrampolineName), type: nil)
                                    loweredBody.append(.constValue(
                                        result: innerTrampolineExpr,
                                        value: .externSymbolAddress(innerTrampolineName)))
                                    let reversedClosureResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)), type: nil)
                                    loweredBody.append(.call(
                                        symbol: nil,
                                        callee: lookup.kkComparatorReversedName,
                                        arguments: [innerTrampolineExpr, innerClosureExpr],
                                        result: reversedClosureResult,
                                        canThrow: false,
                                        thrownResult: nil
                                    ))
                                    closureExpr = reversedClosureResult
                                default:
                                    trampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                    closureExpr = comparatorExpr
                                }
                                let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
                                loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
                                let hofResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: [receiverID, trampolineExpr, closureExpr],
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

                    // maxOfWith / maxOfWithOrNull / minOfWith / minOfWithOrNull (comparator + selector) (STDLIB-301d)
                    if callee == lookup.maxOfWithName || callee == lookup.maxOfWithOrNullName
                        || callee == lookup.minOfWithName || callee == lookup.minOfWithOrNullName
                    {
                        if arguments.count >= 3 && arguments.count <= 5 {
                            let receiverID = arguments[0]
                            let cmpExpr = arguments[1]
                            let selLambdaID: KIRExprID
                            let selClosureRawID: KIRExprID
                            if listExprIDs.contains(receiverID.rawValue) {
                                // Extract selector and its closure from remaining arguments
                                if arguments.count == 5 {
                                    // [receiver, cmp, cmpClosure, sel, selClosure] — already expanded by VirtualCall path
                                    // Still need to inject trampoline for the comparator
                                    selLambdaID = arguments[3]
                                    selClosureRawID = arguments[4]
                                } else if arguments.count == 4 {
                                    let thirdExpr = module.arena.expr(arguments[2])
                                    let fourthExpr = module.arena.expr(arguments[3])
                                    let thirdLooksCallable: Bool = switch thirdExpr {
                                    case .symbolRef, .externSymbolAddress:
                                        true
                                    default:
                                        false
                                    }
                                    let fourthLooksCallable: Bool = switch fourthExpr {
                                    case .symbolRef, .externSymbolAddress:
                                        true
                                    default:
                                        false
                                    }
                                    if !thirdLooksCallable, fourthLooksCallable {
                                        selLambdaID = arguments[3]
                                        selClosureRawID = {
                                            let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                                            loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                                            return z
                                        }()
                                    } else {
                                        selLambdaID = arguments[2]
                                        selClosureRawID = arguments[3]
                                    }
                                } else {
                                    // arguments.count == 3: [receiver, cmp, sel]
                                    selLambdaID = arguments[2]
                                    selClosureRawID = {
                                        let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                                        loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                                        return z
                                    }()
                                }
                                // Inject trampoline for the comparator argument
                                let cmpSource = isComparatorFromCall(
                                    exprID: cmpExpr,
                                    body: function.body,
                                    ascendingCallee: lookup.kkComparatorFromSelectorName,
                                    descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                                    naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                                    reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                                    thenByCallee: lookup.kkComparatorThenByName,
                                    thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                                    thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                                    thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                                    reversedCallee: lookup.kkComparatorReversedName
                                )
                                let cmpTrampolineName: InternedString
                                let cmpClosureExpr: KIRExprID
                                switch cmpSource {
                                case .descending:
                                    cmpTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .multiSelector:
                                    cmpTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .thenBy:
                                    cmpTrampolineName = lookup.kkComparatorThenByTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .thenByDescending:
                                    cmpTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .thenDescending:
                                    cmpTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .thenComparator:
                                    cmpTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .nullsFirst:
                                    cmpTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .nullsLast:
                                    cmpTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                                    cmpClosureExpr = cmpExpr
                                case .naturalOrder:
                                    cmpTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                    cmpClosureExpr = zero
                                case .reverseOrder:
                                    cmpTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                    cmpClosureExpr = zero
                                case let .reversed(innerExpr):
                                    cmpTrampolineName = lookup.kkComparatorReversedTrampolineName
                                    let innerSource = isComparatorFromCall(
                                        exprID: innerExpr,
                                        body: function.body,
                                        ascendingCallee: lookup.kkComparatorFromSelectorName,
                                        descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                                        multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                                        naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                                        reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                                        thenByCallee: lookup.kkComparatorThenByName,
                                        thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                                        thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                                        thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                                        nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                                        nullsLastCallee: lookup.kkComparatorNullsLastName,
                                        multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                                        reversedCallee: lookup.kkComparatorReversedName
                                    )
                                    let innerTrampolineName: InternedString
                                    let innerClosureExpr: KIRExprID
                                    switch innerSource {
                                    case .ascending:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .descending:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .multiSelector:
                                        innerTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenBy:
                                        innerTrampolineName = lookup.kkComparatorThenByTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenByDescending:
                                        innerTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenDescending:
                                        innerTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .thenComparator:
                                        innerTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .nullsFirst:
                                        innerTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .nullsLast:
                                        innerTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                                        innerClosureExpr = innerExpr
                                    case .naturalOrder:
                                        innerTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                        innerClosureExpr = zero
                                    case .reverseOrder:
                                        innerTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                                        let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                        loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                        innerClosureExpr = zero
                                    default:
                                        innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                        innerClosureExpr = innerExpr
                                    }
                                    let innerTrampolineExpr = module.arena.appendExpr(
                                        .externSymbolAddress(innerTrampolineName), type: nil)
                                    loweredBody.append(.constValue(
                                        result: innerTrampolineExpr,
                                        value: .externSymbolAddress(innerTrampolineName)))
                                    let reversedClosureResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)), type: nil)
                                    loweredBody.append(.call(
                                        symbol: nil,
                                        callee: lookup.kkComparatorReversedName,
                                        arguments: [innerTrampolineExpr, innerClosureExpr],
                                        result: reversedClosureResult,
                                        canThrow: false,
                                        thrownResult: nil
                                    ))
                                    cmpClosureExpr = reversedClosureResult
                                default:
                                    // Unknown or ascending: pass as fnPtr with closureRaw=0
                                    cmpTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                    cmpClosureExpr = cmpExpr
                                }
                                let cmpTrampolineExpr = module.arena.appendExpr(.externSymbolAddress(cmpTrampolineName), type: nil)
                                loweredBody.append(.constValue(result: cmpTrampolineExpr, value: .externSymbolAddress(cmpTrampolineName)))
                                let kkName: InternedString = switch callee {
                                case lookup.maxOfWithName: lookup.kkListMaxOfWithName
                                case lookup.maxOfWithOrNullName: lookup.kkListMaxOfWithOrNullName
                                case lookup.minOfWithName: lookup.kkListMinOfWithName
                                default: lookup.kkListMinOfWithOrNullName
                                }
                                let hofResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: [receiverID, cmpTrampolineExpr, cmpClosureExpr, selLambdaID, selClosureRawID],
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
                    if callee == lookup.foldName, (3 ... 4).contains(arguments.count) {
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
                    if callee == lookup.reduceName, (2 ... 3).contains(arguments.count) {
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
                    // reduceOrNull: args = [receiver, lambda, closureRaw?]
                    if callee == lookup.reduceOrNullName, arguments.count == 2 || arguments.count == 3 {
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
                                callee: lookup.kkListReduceOrNullName,
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

                    // foldIndexed: args = [receiver, initial, lambda, closureRaw?]
                    if (callee == lookup.foldIndexedName || callee == lookup.kkListFoldIndexedName || callee == lookup.kkSequenceFoldIndexedName), (arguments.count == 3 || arguments.count == 4) {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) || sequenceExprIDs.contains(receiverID.rawValue) {
                            let initialID = arguments[1]
                            let lambdaID = arguments[2]
                            let closureRawID: KIRExprID
                            if arguments.count == 4 { closureRawID = arguments[3] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let kkName = sequenceExprIDs.contains(receiverID.rawValue) ? lookup.kkSequenceFoldIndexedName : lookup.kkListFoldIndexedName
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // reduceIndexed: args = [receiver, lambda, closureRaw?]
                    if (callee == lookup.reduceIndexedName || callee == lookup.kkListReduceIndexedName || callee == lookup.kkSequenceReduceIndexedName), (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) || sequenceExprIDs.contains(receiverID.rawValue) {
                            let lambdaID = arguments[1]
                            let closureRawID: KIRExprID
                            if arguments.count == 3 { closureRawID = arguments[2] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let kkName = sequenceExprIDs.contains(receiverID.rawValue) ? lookup.kkSequenceReduceIndexedName : lookup.kkListReduceIndexedName
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // foldRight: args = [receiver, initial, lambda, closureRaw?]
                    if (callee == lookup.foldRightName || callee == lookup.kkListFoldRightName), (arguments.count == 3 || arguments.count == 4) {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let initialID = arguments[1]
                            let lambdaID = arguments[2]
                            let closureRawID: KIRExprID
                            if arguments.count == 4 { closureRawID = arguments[3] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFoldRightName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // foldRightIndexed: args = [receiver, initial, lambda, closureRaw?]
                    if (callee == lookup.foldRightIndexedName || callee == lookup.kkListFoldRightIndexedName), (arguments.count == 3 || arguments.count == 4) {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let initialID = arguments[1]
                            let lambdaID = arguments[2]
                            let closureRawID: KIRExprID
                            if arguments.count == 4 { closureRawID = arguments[3] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFoldRightIndexedName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // reduceRight: args = [receiver, lambda, closureRaw?]
                    if (callee == lookup.reduceRightName || callee == lookup.kkListReduceRightName), (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let lambdaID = arguments[1]
                            let closureRawID: KIRExprID
                            if arguments.count == 3 { closureRawID = arguments[2] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: lookup.kkListReduceRightName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // filterIndexed: args = [receiver, lambda, closureRaw?]
                    if (callee == lookup.filterIndexedName || callee == lookup.kkListFilterIndexedName),
                       (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]; let lambdaID = arguments[1]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let closureRawID: KIRExprID
                            if arguments.count == 3 { closureRawID = arguments[2] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: lookup.kkListFilterIndexedName, arguments: [receiverID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
                            if let result { loweredBody.append(.copy(from: hofResult, to: result)); listExprIDs.insert(result.rawValue) }
                            listExprIDs.insert(hofResult.rawValue); continue
                        }
                    }
                    // reduceIndexedOrNull: args = [receiver, lambda, closureRaw?]
                    if (callee == lookup.reduceIndexedOrNullName
                        || callee == lookup.kkListReduceIndexedOrNullName
                        || callee == lookup.kkSequenceReduceIndexedOrNullName),
                       (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]; let lambdaID = arguments[1]
                        if listExprIDs.contains(receiverID.rawValue) || sequenceExprIDs.contains(receiverID.rawValue) {
                            let closureRawID: KIRExprID
                            if arguments.count == 3 { closureRawID = arguments[2] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let kkName = sequenceExprIDs.contains(receiverID.rawValue)
                                ? lookup.kkSequenceReduceIndexedOrNullName
                                : lookup.kkListReduceIndexedOrNullName
                            let callResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
                            continue
                        }
                    }
                    // runningFoldIndexed / scanIndexed: args = [receiver, initial, lambda, closureRaw?]
                    if (callee == lookup.runningFoldIndexedName
                        || callee == lookup.scanIndexedName
                        || callee == lookup.kkListRunningFoldIndexedName
                        || callee == lookup.kkListScanIndexedName),
                       (3 ... 4).contains(arguments.count) {
                        let receiverID = arguments[0]; let initialID = arguments[1]; let lambdaID = arguments[2]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let closureRawID: KIRExprID
                            if arguments.count == 4 { closureRawID = arguments[3] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let kkName = (callee == lookup.scanIndexedName || callee == lookup.kkListScanIndexedName) ? lookup.kkListScanIndexedName : lookup.kkListRunningFoldIndexedName
                            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: kkName, arguments: [receiverID, initialID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
                            if let result { loweredBody.append(.copy(from: hofResult, to: result)); listExprIDs.insert(result.rawValue) }
                            listExprIDs.insert(hofResult.rawValue); continue
                        }
                    }
                    // runningReduceIndexed: args = [receiver, lambda, closureRaw?]
                    if (callee == lookup.runningReduceIndexedName || callee == lookup.kkListRunningReduceIndexedName),
                       (arguments.count == 2 || arguments.count == 3) {
                        let receiverID = arguments[0]; let lambdaID = arguments[1]
                        if listExprIDs.contains(receiverID.rawValue) {
                            let closureRawID: KIRExprID
                            if arguments.count == 3 { closureRawID = arguments[2] }
                            else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
                            let hofResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)), type: nil)
                            loweredBody.append(.call(symbol: nil, callee: lookup.kkListRunningReduceIndexedName, arguments: [receiverID, lambdaID, closureRawID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
                            if let result { loweredBody.append(.copy(from: hofResult, to: result)); listExprIDs.insert(result.rawValue) }
                            listExprIDs.insert(hofResult.rawValue); continue
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
                        if listExprIDs.contains(receiverID.rawValue) {
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
                            listExprIDs.insert(hofResult.rawValue)
                            if let result { listExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }
                    // runningReduce: args = [receiver, lambda, closureRaw?]
                    if callee == lookup.runningReduceName,
                       (2 ... 3).contains(arguments.count) {
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
                            listExprIDs.insert(hofResult.rawValue)
                            if let result { listExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // scan / runningFold on sequence → kk_sequence_scan / kk_sequence_runningFold (STDLIB-558, 560)
                    if (callee == lookup.scanName || callee == lookup.runningFoldName), (3 ... 4).contains(arguments.count) {
                        let receiverID = arguments[0]
                        let initialID = arguments[1]
                        let lambdaID = arguments[2]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
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
                            listExprIDs.insert(hofResult.rawValue)
                            if let result { listExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }
                    // runningReduce on sequence → kk_sequence_runningReduce (STDLIB-559)
                    if callee == lookup.runningReduceName, (2 ... 3).contains(arguments.count) {
                        let receiverID = arguments[0]
                        let lambdaID = arguments[1]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
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
                            listExprIDs.insert(hofResult.rawValue)
                            if let result { listExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }
                    // scanReduce: args = [receiver, lambda, closureRaw?] — alias for runningReduce
                    if callee == lookup.scanReduceName, (arguments.count == 2 || arguments.count == 3) {
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
                                callee: lookup.kkListScanReduceName,
                                arguments: [receiverID, lambdaID, closureRawID],
                                result: hofResult,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                            if let result {
                                loweredBody.append(.copy(from: hofResult, to: result))
                            }
                            listExprIDs.insert(hofResult.rawValue)
                            if let result { listExprIDs.insert(result.rawValue) }
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

                    // --- sortedWith with Comparator argument (STDLIB-649) ---
                    // When kk_list_sortedWith is emitted as a .call (from synthetic stub),
                    // the comparator argument needs trampoline/closure expansion.
                    // args layout: [receiver, comparatorExpr]
                    if callee == lookup.kkListSortedWithName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        let comparatorExpr = arguments[1]
                        let source = isComparatorFromCall(
                            exprID: comparatorExpr,
                            body: function.body,
                            ascendingCallee: lookup.kkComparatorFromSelectorName,
                            descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                            multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                            naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                            reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                            thenByCallee: lookup.kkComparatorThenByName,
                            thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                            thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                            thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                            nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                            nullsLastCallee: lookup.kkComparatorNullsLastName,
                            multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                            reversedCallee: lookup.kkComparatorReversedName
                        )
                        if case .unknown = source {
                            // Not a recognized comparator factory — likely a direct lambda
                            // comparator (e.g. sortedWith { a, b -> a - b }).
                            // Pass it as fnPtr with closureRaw=0.
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListSortedWithName,
                                arguments: [receiverID, comparatorExpr, zeroExpr, zeroExpr],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                        } else {
                            let trampolineName: InternedString
                            let closureExpr: KIRExprID
                            switch source {
                            case .descending:
                                trampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                closureExpr = comparatorExpr
                            case .multiSelector:
                                trampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                closureExpr = comparatorExpr
                            case .thenBy:
                                trampolineName = lookup.kkComparatorThenByTrampolineName
                                closureExpr = comparatorExpr
                            case .thenByDescending:
                                trampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                closureExpr = comparatorExpr
                            case .thenDescending:
                                trampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                closureExpr = comparatorExpr
                            case .thenComparator:
                                trampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                closureExpr = comparatorExpr
                            case .nullsFirst:
                                trampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                closureExpr = comparatorExpr
                            case .nullsLast:
                                trampolineName = lookup.kkComparatorNullsLastTrampolineName
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
                            case let .reversed(innerExpr):
                                trampolineName = lookup.kkComparatorReversedTrampolineName
                                let innerSource = isComparatorFromCall(
                                    exprID: innerExpr,
                                    body: function.body,
                                    ascendingCallee: lookup.kkComparatorFromSelectorName,
                                    descendingCallee: lookup.kkComparatorFromSelectorDescendingName,
                                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                                    naturalOrderCallee: lookup.kkComparatorNaturalOrderName,
                                    reverseOrderCallee: lookup.kkComparatorReverseOrderName,
                                    thenByCallee: lookup.kkComparatorThenByName,
                                    thenByDescendingCallee: lookup.kkComparatorThenByDescendingName,
                                    thenDescendingCallee: lookup.kkComparatorThenDescendingName,
                                    thenComparatorCallee: lookup.kkComparatorThenComparatorName,
                                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                                    reversedCallee: lookup.kkComparatorReversedName
                                )
                                let innerTrampolineName: InternedString
                                let innerClosureExpr: KIRExprID
                                switch innerSource {
                                case .ascending:
                                    innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                    innerClosureExpr = innerExpr
                                case .descending:
                                    innerTrampolineName = lookup.kkComparatorFromSelectorDescendingTrampolineName
                                    innerClosureExpr = innerExpr
                                case .multiSelector:
                                    innerTrampolineName = lookup.kkComparatorFromMultiSelectorsTrampolineName
                                    innerClosureExpr = innerExpr
                                case .thenBy:
                                    innerTrampolineName = lookup.kkComparatorThenByTrampolineName
                                    innerClosureExpr = innerExpr
                                case .thenByDescending:
                                    innerTrampolineName = lookup.kkComparatorThenByDescendingTrampolineName
                                    innerClosureExpr = innerExpr
                                case .thenDescending:
                                    innerTrampolineName = lookup.kkComparatorThenDescendingTrampolineName
                                    innerClosureExpr = innerExpr
                                case .thenComparator:
                                    innerTrampolineName = lookup.kkComparatorThenComparatorTrampolineName
                                    innerClosureExpr = innerExpr
                                case .nullsFirst:
                                    innerTrampolineName = lookup.kkComparatorNullsFirstTrampolineName
                                    innerClosureExpr = innerExpr
                                case .nullsLast:
                                    innerTrampolineName = lookup.kkComparatorNullsLastTrampolineName
                                    innerClosureExpr = innerExpr
                                case .naturalOrder:
                                    innerTrampolineName = lookup.kkComparatorNaturalOrderTrampolineName
                                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                    innerClosureExpr = zero
                                case .reverseOrder:
                                    innerTrampolineName = lookup.kkComparatorReverseOrderTrampolineName
                                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                                    innerClosureExpr = zero
                                default:
                                    innerTrampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                    innerClosureExpr = innerExpr
                                }
                                let innerTrampolineExpr = module.arena.appendExpr(
                                    .externSymbolAddress(innerTrampolineName), type: nil)
                                loweredBody.append(.constValue(
                                    result: innerTrampolineExpr,
                                    value: .externSymbolAddress(innerTrampolineName)))
                                let reversedClosureResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil)
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: lookup.kkComparatorReversedName,
                                    arguments: [innerTrampolineExpr, innerClosureExpr],
                                    result: reversedClosureResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                closureExpr = reversedClosureResult
                            default:
                                trampolineName = lookup.kkComparatorFromSelectorTrampolineName
                                closureExpr = comparatorExpr
                            }
                            let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
                            loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: lookup.kkListSortedWithName,
                                arguments: [receiverID, trampolineExpr, closureExpr, zeroExpr],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult
                            ))
                        }
                        if let result {
                            listExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    // --- STDLIB-189: String HOF closureRaw injection ---
                    // String higher-order functions (filter, map, count, any, all, none)
                    // are called with args = [receiver, lambdaRef] but the runtime
                    // expects (strRaw, fnPtr, closureRaw, outThrown).  Insert the
                    // missing closureRaw=0 argument so the ABI lowering pass only
                    // needs to append the outThrown slot.
                    if arguments.count == 2,
                       callee == lookup.kkStringFilterName
                        || callee == lookup.kkStringMapName
                        || callee == lookup.kkStringCountName
                        || callee == lookup.kkStringAnyName
                        || callee == lookup.kkStringAllName
                        || callee == lookup.kkStringNoneName
                    {
                        let receiverID = arguments[0]
                        let lambdaID = arguments[1]
                        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        let isStringResult = callee == lookup.kkStringFilterName
                            || callee == lookup.kkStringMapName
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: callee,
                            arguments: [receiverID, lambdaID, zeroExpr],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        if isStringResult, let result {
                            stringExprIDs.insert(result.rawValue)
                        }
                        continue
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
                        context: .init(module: module, lookup: lookup, functionBody: function.body, sema: ctx.sema, interner: ctx.interner),
                        listExprIDs: &listExprIDs,
                        setExprIDs: &setExprIDs,
                        mapExprIDs: &mapExprIDs,
                        arrayExprIDs: &arrayExprIDs,
                        sequenceExprIDs: &sequenceExprIDs,
                        rangeExprIDs: &rangeExprIDs,
                        charRangeExprIDs: &charRangeExprIDs,
                        ulongRangeExprIDs: &ulongRangeExprIDs,
                        fileExprIDs: &fileExprIDs,
                        indexingIterableExprIDs: &indexingIterableExprIDs,
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
                    if charRangeExprIDs.contains(from.rawValue) {
                        charRangeExprIDs.insert(to.rawValue)
                    }
                    if ulongRangeExprIDs.contains(from.rawValue) {
                        ulongRangeExprIDs.insert(to.rawValue)
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
                    if fileExprIDs.contains(from.rawValue) {
                        fileExprIDs.insert(to.rawValue)
                    }
                    if iteratorBuilderExprIDs.contains(from.rawValue) {
                        iteratorBuilderExprIDs.insert(to.rawValue)
                    }
                    if indexingIterableExprIDs.contains(from.rawValue) {
                        indexingIterableExprIDs.insert(to.rawValue)
                    }
                    if indexingIterableIteratorExprIDs.contains(from.rawValue) {
                        indexingIterableIteratorExprIDs.insert(to.rawValue)
                    }
                    if ulongRangeIteratorExprIDs.contains(from.rawValue) {
                        ulongRangeIteratorExprIDs.insert(to.rawValue)
                    }
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.replaceBody(loweredBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
        module.recordLowering(Self.name)
    }
}
