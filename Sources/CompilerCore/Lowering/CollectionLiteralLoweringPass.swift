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

        // Sequence ABI names (STDLIB-003)
        let kkSequenceFromListName = interner.intern("kk_sequence_from_list")
        let kkSequenceMapName = interner.intern("kk_sequence_map")
        let kkSequenceFilterName = interner.intern("kk_sequence_filter")
        let kkSequenceTakeName = interner.intern("kk_sequence_take")
        let kkSequenceToListName = interner.intern("kk_sequence_to_list")
        let kkSequenceBuilderBuildName = interner.intern("kk_sequence_builder_build")
        let kkSequenceBuilderYieldName = interner.intern("kk_sequence_builder_yield")

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

        // Sequence member names (STDLIB-003)
        let asSequenceName = interner.intern("asSequence")
        let toListName = interner.intern("toList")
        let takeName = interner.intern("take")
        let sequenceName = interner.intern("sequence")
        let yieldName = interner.intern("yield")

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

        // Builder DSL names (STDLIB-002)
        let buildStringName = interner.intern("buildString")
        let buildListName = interner.intern("buildList")
        let buildMapName = interner.intern("buildMap")
        let kkBuildStringName = interner.intern("kk_build_string")
        let kkBuildListName = interner.intern("kk_build_list")
        let kkBuildMapName = interner.intern("kk_build_map")
        let builderDSLNames: Set<InternedString> = [buildStringName, buildListName, buildMapName]

        // Builder member function names (STDLIB-002)
        let appendName = interner.intern("append")
        let addName = interner.intern("add")
        let putName = interner.intern("put")
        let kkStringBuilderAppendName = interner.intern("kk_string_builder_append")
        let kkMutableListAddName = interner.intern("kk_mutable_list_add")
        let kkMutableMapPutName = interner.intern("kk_mutable_map_put")

        // Pre-scan: collect function names that are builder lambda bodies (STDLIB-002).
        // We find buildString/buildList/buildMap calls, trace their lambda argument
        // expression IDs back to constValue(.symbolRef(...)) instructions, then resolve
        // the corresponding lambda function names. Maps function name → builder callee
        // name so we only rewrite the correct member functions per builder kind.
        var builderLambdaKinds: [InternedString: InternedString] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            // Collect exprID → symbolID mappings from constValue(.symbolRef(...))
            var exprSymbolMap: [Int32: SymbolID] = [:]
            // Collect lambda argument exprIDs and their builder callee from DSL calls
            var builderLambdaArgEntries: [(argID: Int32, callee: InternedString)] = []
            for instruction in function.body {
                switch instruction {
                case let .constValue(result, .symbolRef(symbol)):
                    exprSymbolMap[result.rawValue] = symbol
                case let .call(_, callee, arguments, _, _, _, _):
                    if builderDSLNames.contains(callee), !arguments.isEmpty {
                        builderLambdaArgEntries.append((argID: arguments[0].rawValue, callee: callee))
                    }
                default:
                    break
                }
            }
            // Resolve lambda argument exprIDs to function names with builder kind
            for entry in builderLambdaArgEntries {
                if let symbol = exprSymbolMap[entry.argID] {
                    // Lambda function name follows kk_lambda_{exprID} convention
                    let lambdaName = interner.intern("kk_lambda_\(entry.argID)")
                    builderLambdaKinds[lambdaName] = entry.callee
                    // Also try the symbol-based lookup for robustness
                    for innerDecl in module.arena.declarations {
                        if case let .function(funcDecl) = innerDecl, funcDecl.symbol == symbol {
                            builderLambdaKinds[funcDecl.name] = entry.callee
                            break
                        }
                    }
                }
            }
        }

        module.arena.transformFunctions { function in
            var updated = function

            // Phase 1: Identify collection-typed expression IDs
            var listExprIDs: Set<Int32> = []
            var mapExprIDs: Set<Int32> = []
            var arrayExprIDs: Set<Int32> = []
            var sequenceExprIDs: Set<Int32> = []

            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, result, _, _, _):
                    let calleStr = interner.resolve(callee)
                    fputs("[P1] .call callee=\(calleStr) args=\(arguments.count) result=\(result?.rawValue as Any)\n", stderr)
                    if listFactoryNames.contains(callee) || callee == kkListOfName {
                        if let result {
                            listExprIDs.insert(result.rawValue)
                            fputs("[P1]   -> listExprIDs += \(result.rawValue)\n", stderr)
                        }
                    } else if mapFactoryNames.contains(callee) || callee == kkMapOfName {
                        if let result { mapExprIDs.insert(result.rawValue) }
                    } else if arrayOfFactoryNames.contains(callee) {
                        if let result { arrayExprIDs.insert(result.rawValue) }
                    }
                    // Track .call sequence operations where receiver is arguments[0]
                    // (sema collection fallback emits .call with receiver prepended).
                    if callee == asSequenceName, arguments.count == 1 {
                        fputs("[P1]   asSequence: arg0=\(arguments[0].rawValue) inList=\(listExprIDs.contains(arguments[0].rawValue))\n", stderr)
                        if listExprIDs.contains(arguments[0].rawValue) {
                            if let result {
                                sequenceExprIDs.insert(result.rawValue)
                                fputs("[P1]   -> sequenceExprIDs += \(result.rawValue)\n", stderr)
                            }
                        }
                    } else if callee == toListName, arguments.count == 1 {
                        fputs("[P1]   toList: arg0=\(arguments[0].rawValue) inSeq=\(sequenceExprIDs.contains(arguments[0].rawValue))\n", stderr)
                        if sequenceExprIDs.contains(arguments[0].rawValue) {
                            if let result { listExprIDs.insert(result.rawValue) }
                        }
                    } else if callee == mapName || callee == filterName || callee == takeName {
                        if !arguments.isEmpty {
                            fputs("[P1]   \(calleStr): arg0=\(arguments[0].rawValue) inSeq=\(sequenceExprIDs.contains(arguments[0].rawValue))\n", stderr)
                        }
                        if !arguments.isEmpty, sequenceExprIDs.contains(arguments[0].rawValue) {
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                        }
                    }
                // Phase 1 also scans .virtualCall for collection member calls
                // that the sema resolved to a symbol (STDLIB-003).
                case let .virtualCall(_, callee, receiver, arguments, result, _, _, _):
                    let vcCalleStr = interner.resolve(callee)
                    fputs("[P1] .virtualCall callee=\(vcCalleStr) receiver=\(receiver.rawValue) args=\(arguments.count) result=\(result?.rawValue as Any)\n", stderr)
                    if callee == asSequenceName {
                        if listExprIDs.contains(receiver.rawValue) {
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                        }
                    } else if callee == toListName {
                        if sequenceExprIDs.contains(receiver.rawValue) {
                            if let result { listExprIDs.insert(result.rawValue) }
                        }
                    } else if callee == mapName || callee == filterName || callee == takeName {
                        if sequenceExprIDs.contains(receiver.rawValue) {
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                        }
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
                    if sequenceExprIDs.contains(from.rawValue) {
                        sequenceExprIDs.insert(to.rawValue)
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

                    // --- Rewrite buildString/buildList/buildMap → kk_build_* (STDLIB-002) ---
                    if builderDSLNames.contains(callee) {
                        let kkCallee: InternedString = switch callee {
                        case buildStringName: kkBuildStringName
                        case buildListName: kkBuildListName
                        case buildMapName: kkBuildMapName
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
                        if callee == buildListName, let result {
                            listExprIDs.insert(result.rawValue)
                            listExprIDs.insert(builderResult.rawValue)
                        }
                        if callee == buildMapName, let result {
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
                        if builderCallee == buildStringName, callee == appendName, arguments.count == 1 {
                            rewrittenCallee = kkStringBuilderAppendName
                        } else if builderCallee == buildListName, callee == addName, arguments.count == 1 {
                            rewrittenCallee = kkMutableListAddName
                        } else if builderCallee == buildMapName, callee == putName, arguments.count == 2 {
                            rewrittenCallee = kkMutableMapPutName
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

                    // --- Rewrite sequence member calls (STDLIB-003) ---
                    // asSequence() on list → kk_sequence_from_list
                    // (Only matches .call; .virtualCall handled in separate case below)
                    if callee == asSequenceName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if listExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceFromListName,
                                arguments: [receiverID],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // map/filter on sequence → kk_sequence_map/kk_sequence_filter
                    if callee == mapName || callee == filterName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let kkName = callee == mapName ? kkSequenceMapName : kkSequenceFilterName
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
                    if callee == takeName, arguments.count == 2 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceTakeName,
                                arguments: arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // toList() on sequence → kk_sequence_to_list
                    if callee == toListName, arguments.count == 1 {
                        let receiverID = arguments[0]
                        if sequenceExprIDs.contains(receiverID.rawValue) {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceToListName,
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

                    // sequence { ... } builder → kk_sequence_builder_build
                    if callee == sequenceName, arguments.count == 1 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkSequenceBuilderBuildName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                        continue
                    }

                    // yield(value) inside sequence builder → kk_sequence_builder_yield
                    if callee == yieldName, arguments.count == 2 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkSequenceBuilderYieldName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
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

                // --- Rewrite .virtualCall sequence member calls (STDLIB-003) ---
                // When the sema resolves collection member calls to a concrete
                // symbol, the CallLowerer emits .virtualCall instead of .call.
                // Handle those here so the sequence chain is properly rewritten.
                case let .virtualCall(_, callee, receiver, arguments, result, origCanThrow, origThrownResult, _):
                    // asSequence() on list → kk_sequence_from_list
                    if callee == asSequenceName, arguments.isEmpty {
                        if listExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceFromListName,
                                arguments: [receiver],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // map/filter on sequence → kk_sequence_map/kk_sequence_filter
                    if callee == mapName || callee == filterName, arguments.count == 1 {
                        if sequenceExprIDs.contains(receiver.rawValue) {
                            let kkName = callee == mapName
                                ? kkSequenceMapName : kkSequenceFilterName
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkName,
                                arguments: [receiver] + arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // take(n) on sequence → kk_sequence_take
                    if callee == takeName, arguments.count == 1 {
                        if sequenceExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceTakeName,
                                arguments: [receiver] + arguments,
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            if let result { sequenceExprIDs.insert(result.rawValue) }
                            continue
                        }
                    }

                    // toList() on sequence → kk_sequence_to_list
                    if callee == toListName, arguments.isEmpty {
                        if sequenceExprIDs.contains(receiver.rawValue) {
                            let toListResult = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)), type: nil
                            )
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkSequenceToListName,
                                arguments: [receiver],
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

                    // Also handle higher-order collection calls that may come
                    // through as .virtualCall (map/filter/forEach on lists).
                    if callee == mapName || callee == filterName || callee == forEachName
                        || callee == flatMapName || callee == anyName || callee == noneName
                        || callee == allName
                    { // swiftlint:disable:this opening_brace
                        if arguments.count == 1 {
                            if listExprIDs.contains(receiver.rawValue) {
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
                                let needsListTag = callee == mapName
                                    || callee == flatMapName || callee == filterName
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
                                continue
                            }
                        }
                    }

                    // Also handle collection member calls (size, get, etc.)
                    // that may arrive as .virtualCall.
                    if callee == sizeName || callee == countName {
                        if listExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListSizeName,
                                arguments: [receiver],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkMapSizeName,
                                arguments: [receiver],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    if callee == isEmptyName {
                        if listExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkListIsEmptyName,
                                arguments: [receiver],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                        if mapExprIDs.contains(receiver.rawValue) {
                            loweredBody.append(.call(
                                symbol: nil,
                                callee: kkMapIsEmptyName,
                                arguments: [receiver],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            continue
                        }
                    }

                    // Default: keep .virtualCall as-is
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
                    if sequenceExprIDs.contains(from.rawValue) {
                        sequenceExprIDs.insert(to.rawValue)
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
