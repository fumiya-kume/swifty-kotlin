// swiftlint:disable file_length
import Foundation

// Rewrites `listOf(...)`, `mapOf(...)`, `arrayOf(...)` and related collection
// factory calls into runtime ABI calls (`kk_list_of`, `kk_map_of`, etc.).
//
// Also rewrites collection member accesses (`.size`, `.get()`, `.contains()`)
// and iterator patterns (`kk_range_iterator`/`kk_range_hasNext`/`kk_range_next`)
// on collection-typed expressions to their collection-specific equivalents.
//
// Must run **before** `ForLoweringPass` so that for-loop desugaring emits
// generic `kk_range_*` calls which this pass can then specialize for collections.
// In practice this pass runs **after** `ForLoweringPass` and rewrites the
// already-emitted `kk_range_*` calls to `kk_list_*` equivalents.
// swiftlint:disable:next type_body_length
final class CollectionLiteralLoweringPass: LoweringPass {
    static let name = "CollectionLiteralLowering"

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func run(module: KIRModule, ctx: KIRContext) throws {
        let interner = ctx.interner

        // Source-level callee names
        let listOfName = interner.intern("listOf")
        let mutableListOfName = interner.intern("mutableListOf")
        let emptyListName = interner.intern("emptyList")
        let listOfNotNullName = interner.intern("listOfNotNull")
        let arrayOfName = interner.intern("arrayOf")
        let intArrayOfName = interner.intern("intArrayOf")
        let longArrayOfName = interner.intern("longArrayOf")
        let mapOfName = interner.intern("mapOf")
        let mutableMapOfName = interner.intern("mutableMapOf")
        let emptyMapName = interner.intern("emptyMap")
        let setOfName = interner.intern("setOf")
        let mutableSetOfName = interner.intern("mutableSetOf")
        let emptySetName = interner.intern("emptySet")

        // Runtime ABI names
        let kkListOfName = interner.intern("kk_list_of")
        let kkListSizeName = interner.intern("kk_list_size")
        let kkListGetName = interner.intern("kk_list_get")
        let kkListContainsName = interner.intern("kk_list_contains")
        let kkListIsEmptyName = interner.intern("kk_list_is_empty")
        let kkListIteratorName = interner.intern("kk_list_iterator")
        let kkListIteratorHasNextName = interner.intern("kk_list_iterator_hasNext")
        let kkListIteratorNextName = interner.intern("kk_list_iterator_next")
        let kkListToStringName = interner.intern("kk_list_to_string")
        // Higher-order collection function ABI names (FUNC-003)
        let kkListMapName = interner.intern("kk_list_map")
        let kkListFilterName = interner.intern("kk_list_filter")
        let kkListForEachName = interner.intern("kk_list_forEach")
        let kkListFlatMapName = interner.intern("kk_list_flatMap")
        let kkListAnyName = interner.intern("kk_list_any")
        let kkListNoneName = interner.intern("kk_list_none")
        let kkListAllName = interner.intern("kk_list_all")

        let kkMapOfName = interner.intern("kk_map_of")
        let kkMapSizeName = interner.intern("kk_map_size")
        let kkMapGetName = interner.intern("kk_map_get")
        let kkMapContainsKeyName = interner.intern("kk_map_contains_key")
        let kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        let kkMapToStringName = interner.intern("kk_map_to_string")
        let kkMapIteratorName = interner.intern("kk_map_iterator")
        let kkMapIteratorHasNextName = interner.intern("kk_map_iterator_hasNext")
        let kkMapIteratorNextName = interner.intern("kk_map_iterator_next")

        _ = interner.intern("kk_array_of")
        let kkArraySizeName = interner.intern("kk_array_size")

        let kkArrayNewName = interner.intern("kk_array_new")
        let kkArraySetName = interner.intern("kk_array_set")

        // Range iterator names (emitted by ForLoweringPass)
        let kkRangeIteratorName = interner.intern("kk_range_iterator")
        let kkRangeHasNextName = interner.intern("kk_range_hasNext")
        let kkRangeNextName = interner.intern("kk_range_next")

        // Member names
        let sizeName = interner.intern("size")
        let getName = interner.intern("get")
        let containsName = interner.intern("contains")
        let containsKeyName = interner.intern("containsKey")
        let isEmptyName = interner.intern("isEmpty")
        let countName = interner.intern("count")
        // Higher-order collection member names (FUNC-003)
        let mapName = interner.intern("map")
        let filterName = interner.intern("filter")
        let forEachName = interner.intern("forEach")
        let flatMapName = interner.intern("flatMap")
        let anyName = interner.intern("any")
        let noneName = interner.intern("none")
        let allName = interner.intern("all")

        // println support
        let printlnName = interner.intern("println")
        let kkPrintlnAnyName = interner.intern("kk_println_any")
        let kkAnyToStringName = interner.intern("kk_any_to_string")

        // Set of all list-factory callee names
        let listFactoryNames: Set<InternedString> = [
            listOfName, mutableListOfName, emptyListName, listOfNotNullName,
            setOfName, mutableSetOfName, emptySetName,
        ]

        // Set of all map-factory callee names
        let mapFactoryNames: Set<InternedString> = [
            mapOfName, mutableMapOfName, emptyMapName,
        ]

        // Set of all arrayOf-factory callee names
        let arrayOfFactoryNames: Set<InternedString> = [
            arrayOfName, intArrayOfName, longArrayOfName,
        ]

        module.arena.transformFunctions { function in
            var updated = function

            // Phase 1: Identify collection-typed expression IDs
            var listExprIDs: Set<Int32> = []
            var mapExprIDs: Set<Int32> = []
            var arrayExprIDs: Set<Int32> = []

            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, _, result, _, _, _):
                    if listFactoryNames.contains(callee) || callee == kkListOfName {
                        if let result { listExprIDs.insert(result.rawValue) }
                    } else if mapFactoryNames.contains(callee) || callee == kkMapOfName {
                        if let result { mapExprIDs.insert(result.rawValue) }
                    } else if arrayOfFactoryNames.contains(callee) {
                        if let result { arrayExprIDs.insert(result.rawValue) }
                    }
                case let .copy(from, to):
                    if listExprIDs.contains(from.rawValue) {
                        listExprIDs.insert(to.rawValue)
                    }
                    if mapExprIDs.contains(from.rawValue) {
                        mapExprIDs.insert(to.rawValue)
                    }
                    if arrayExprIDs.contains(from.rawValue) {
                        arrayExprIDs.insert(to.rawValue)
                    }
                default:
                    break
                }
            }

            // Phase 2: Rewrite instructions
            var listIteratorExprIDs: Set<Int32> = []
            var mapIteratorExprIDs: Set<Int32> = []
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, result, canThrow, thrownResult, _):
                    // --- Rewrite listOf/mutableListOf/emptyList → kk_list_of ---
                    if listFactoryNames.contains(callee) {
                        let count = arguments.count
                        if count == 0 {
                            // emptyList() / listOf() → kk_list_of(0, 0)
                            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListOfName,
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
                                callee: kkArrayNewName,
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
                                    callee: kkArraySetName,
                                    arguments: [arrayExpr, idxExpr, arg],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListOfName,
                                arguments: [arrayExpr, countExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // --- Rewrite mapOf/mutableMapOf/emptyMap → kk_map_of ---
                    if mapFactoryNames.contains(callee) {
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
                                callee: kkMapOfName,
                                arguments: [nullExpr, nullExpr2, zeroExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        } else {
                            // mapOf(pair1, pair2, ...) → kk_map_of(keysArray, valuesArray, count)
                            // For now, treat arguments as alternating key, value pairs
                            // since `to` infix creates Pair which we pass as-is
                            let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                            loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                            let keysArrayExpr = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkArrayNewName,
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
                                callee: kkArrayNewName,
                                arguments: [countExpr],
                                result: valuesArrayExpr,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Each argument is a Pair (passed as an opaque value).
                            // Store into both keys and values arrays so map
                            // operations work for iteration. Full Pair
                            // decomposition is not yet implemented.
                            for (i, arg) in arguments.enumerated() {
                                let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                                loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                                let setResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkArraySetName,
                                    arguments: [keysArrayExpr, idxExpr, arg],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                let setResult2 = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkArraySetName,
                                    arguments: [valuesArrayExpr, idxExpr, arg],
                                    result: setResult2,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                            }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkMapOfName,
                                arguments: [keysArrayExpr, valuesArrayExpr, countExpr],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                        continue
                    }

                    // --- Rewrite arrayOf → kk_array_of ---
                    if arrayOfFactoryNames.contains(callee) {
                        let count = arguments.count
                        let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                        loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                        let arrayExpr = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)), type: nil
                        )
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkArrayNewName,
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
                                callee: kkArraySetName,
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
                    if callee == kkRangeIteratorName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            if let result { listIteratorExprIDs.insert(result.rawValue) }
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListIteratorName,
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
                                callee: kkMapIteratorName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_hasNext on list iterator → kk_list_iterator_hasNext ---
                    if callee == kkRangeHasNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListIteratorHasNextName,
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
                                callee: kkMapIteratorHasNextName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // --- Rewrite kk_range_next on list iterator → kk_list_iterator_next ---
                    if callee == kkRangeNextName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listIteratorExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListIteratorNextName,
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
                                callee: kkMapIteratorNextName,
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
                    if callee == sizeName || callee == countName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkListSizeName,
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
                                    callee: kkMapSizeName,
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
                                    callee: kkArraySizeName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == getName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkListGetName,
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
                                    callee: kkMapGetName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult
                                ))
                                continue
                            }
                        }
                    }

                    if callee == containsName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkListContainsName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == containsKeyName {
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if mapExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkMapContainsKeyName,
                                    arguments: arguments,
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    if callee == isEmptyName {
                        if arguments.count == 1 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkListIsEmptyName,
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
                                    callee: kkMapIsEmptyName,
                                    arguments: [receiverID],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                continue
                            }
                        }
                    }

                    // --- Rewrite higher-order collection member calls (FUNC-003) ---
                    if callee == mapName || callee == filterName || callee == forEachName
                        || callee == flatMapName || callee == anyName || callee == noneName
                        || callee == allName
                    { // swiftlint:disable:this opening_brace
                        // args = [receiver, lambdaFnPtr]
                        if arguments.count == 2 {
                            let receiverID = arguments[0]
                            if listExprIDs.contains(receiverID.rawValue) {
                                let kkName: InternedString = switch callee {
                                case mapName: kkListMapName
                                case filterName: kkListFilterName
                                case forEachName: kkListForEachName
                                case flatMapName: kkListFlatMapName
                                case anyName: kkListAnyName
                                case noneName: kkListNoneName
                                case allName: kkListAllName
                                default: callee
                                }
                                let needsListTag = callee == mapName || callee == flatMapName || callee == filterName
                                let hofResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)), type: nil
                                )
                                loweredBody.append(.call(
                                    symbol: nil,
                                    callee: kkName,
                                    arguments: arguments,
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

                    // Rewrite println on list/map → kk_list_to_string / kk_map_to_string
                    if callee == kkPrintlnAnyName || callee == printlnName, arguments.count == 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            let strResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListToStringName,
                                arguments: [argID],
                                result: strResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkPrintlnAnyName,
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
                                callee: kkMapToStringName,
                                arguments: [argID],
                                result: strResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkPrintlnAnyName,
                                arguments: [strResult],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    if callee == kkAnyToStringName, arguments.count >= 1 {
                        let argID = arguments[0]
                        if listExprIDs.contains(argID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListToStringName,
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
                                callee: kkMapToStringName,
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

                case let .copy(from, to):
                    // Track copies of collection expressions
                    if listExprIDs.contains(from.rawValue) {
                        listExprIDs.insert(to.rawValue)
                    }
                    if mapExprIDs.contains(from.rawValue) {
                        mapExprIDs.insert(to.rawValue)
                    }
                    if arrayExprIDs.contains(from.rawValue) {
                        arrayExprIDs.insert(to.rawValue)
                    }
                    if listIteratorExprIDs.contains(from.rawValue) {
                        listIteratorExprIDs.insert(to.rawValue)
                    }
                    if mapIteratorExprIDs.contains(from.rawValue) {
                        mapIteratorExprIDs.insert(to.rawValue)
                    }
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}
