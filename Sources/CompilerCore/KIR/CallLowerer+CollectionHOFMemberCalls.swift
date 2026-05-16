// swiftlint:disable file_length
import Foundation

/// Collection HOF argument adaptation and comparator trampoline helpers.
extension CallLowerer {
    func isCollectionHOFCallee(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        [
            "map", "filter", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap",
            "any", "none", "all", "fold", "foldRight", "reduce", "reduceRight", "scan", "scanIndexed", "scanReduce",
            "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "groupBy", "groupingBy",
            "aggregate", "aggregateTo",
            "sortedBy", "count", "first", "last", "find", "distinctBy",
            "associateBy", "associateWith", "associate",
            "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "sumOf", "sumBy", "sumByDouble", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
            "getOrElse", "elementAtOrElse", "getOrPut",
            "maxBy", "minBy", "min", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy", "reduceIndexed", "reduceIndexedOrNull", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed",
            "sortedByDescending", "sortedWith", "partition", "zipWithNext",
            "sortedArrayWith",
            "takeWhile", "dropWhile", "dropLastWhile", "filterNot", "findLast", "replaceAll", "removeIf",
            "replaceFirstChar",
            "trim", "trimStart", "trimEnd",
            "sortWith", "sortBy", "sortByDescending",
            "onEach", "onEachIndexed",
            "ifEmpty",
            "ifBlank",
            "chunked", "chunkedSequence", "windowed", "copyOf",
            "toComponents",
            "onSuccess", "onFailure", "recover",
        ].contains(interner.resolve(calleeName))
    }

    func addCollectionHOFClosureArguments(
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard loweredArgIDs.count == argExprIDs.count else {
            return loweredArgIDs
        }
        var finalArgs: [KIRExprID] = []
        finalArgs.reserveCapacity(loweredArgIDs.count + 1)

        for (loweredArgID, argExprID) in zip(loweredArgIDs, argExprIDs) {
            let callableInfo: KIRCallableValueInfo? = {
                if sema.bindings.isCollectionHOFLambdaExpr(argExprID) {
                    return driver.ctx.callableValueInfo(for: loweredArgID) ?? {
                        guard case let .symbolRef(symbol)? = arena.expr(loweredArgID) else {
                            return nil
                        }
                        return KIRCallableValueInfo(
                            symbol: symbol,
                            callee: interner.intern(""),
                            captureArguments: arena.lambdaCaptureArgsBySymbol[symbol] ?? [],
                            hasClosureParam: true
                        )
                    }()
                }
                guard let loweredCallable = driver.ctx.callableValueInfo(for: loweredArgID),
                      !loweredCallable.hasClosureParam,
                      let adapted = makeCollectionHOFCallableAdapter(
                          callableInfo: loweredCallable,
                          loweredArgID: loweredArgID,
                          argExprID: argExprID,
                          sema: sema,
                          arena: arena,
                          interner: interner,
                          namePrefix: "kk_hof_adapter",
                          symbolIDOffsetBase: -700_000
                      )
                else {
                    return nil
                }
                return adapted
            }()
            guard let callableInfo else {
                finalArgs.append(loweredArgID)
                continue
            }

            let fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            finalArgs.append(fnPtrExpr)
            let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
                callableInfo: callableInfo,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            if let boxedCaptureArgument = boxedCaptureArguments.first {
                finalArgs.append(boxedCaptureArgument)
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr)
            }
        }

        return finalArgs
    }

    func comparatorTrampolineName(
        comparatorExprID: ExprID?,
        loweredComparatorID: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        instructions: [KIRInstruction]
    ) -> String? {
        func primitiveCompareKind(
            for comparatorExprID: ExprID?,
            loweredComparatorID: KIRExprID
        ) -> PrimitiveCompareABIKind? {
            func comparatorElementType(from type: TypeID) -> TypeID? {
                let nonNullType = sema.types.makeNonNullable(type)
                guard case let .classType(classType) = sema.types.kind(of: nonNullType),
                      let symbol = sema.symbols.symbol(classType.classSymbol),
                      interner.resolve(symbol.name) == "Comparator",
                      let firstArg = classType.args.first
                else {
                    return nil
                }
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return sema.types.anyType
                }
            }

            if let comparatorExprID,
               let exprType = sema.bindings.exprType(for: comparatorExprID),
               let elementType = comparatorElementType(from: exprType),
               let kind = primitiveCompareABIKind(for: elementType, sema: sema)
            {
                return kind
            }
            return nil
        }

        func trampolineName(for externalLinkName: String) -> String? {
            switch externalLinkName {
            case "kk_comparator_from_selector":
                return "kk_comparator_from_selector_trampoline"
            case "kk_comparator_from_selector_descending":
                return "kk_comparator_from_selector_descending_trampoline"
            case "kk_comparator_from_selector_primitive":
                return "kk_comparator_from_selector_primitive_trampoline"
            case "kk_comparator_from_multi_selectors",
                 "kk_comparator_from_multi_selectors3",
                 "kk_comparator_from_multi_selectors_vararg":
                return "kk_comparator_from_multi_selectors_trampoline"
            case "kk_comparator_nulls_first":
                return "kk_comparator_nulls_first_trampoline"
            case "kk_comparator_nulls_last":
                return "kk_comparator_nulls_last_trampoline"
            case "kk_comparator_then_by":
                return "kk_comparator_then_by_trampoline"
            case "kk_comparator_then_by_comparator_selector":
                return "kk_comparator_then_by_comparator_selector_trampoline"
            case "kk_comparator_then_by_descending":
                return "kk_comparator_then_by_descending_trampoline"
            case "kk_comparator_then_by_descending_comparator_selector":
                return "kk_comparator_then_by_descending_comparator_selector_trampoline"
            case "kk_comparator_then_descending":
                return "kk_comparator_then_descending_trampoline"
            case "kk_comparator_then_comparator":
                return "kk_comparator_then_comparator_trampoline"
            case "kk_comparator_reversed":
                return "kk_comparator_reversed_trampoline"
            case "kk_comparator_natural_order":
                return "kk_comparator_natural_order_trampoline"
            case "kk_comparator_reverse_order":
                return "kk_comparator_reverse_order_trampoline"
            default:
                return nil
            }
        }

        func trampolineName(for comparatorSymbol: SymbolID) -> String? {
            guard let symbol = sema.symbols.symbol(comparatorSymbol) else {
                return nil
            }
            switch interner.resolve(symbol.name) {
            case "compareBy":
                return "kk_comparator_from_selector_trampoline"
            case "compareByPrimitive":
                return "kk_comparator_from_selector_primitive_trampoline"
            case "compareByDescending":
                return "kk_comparator_from_selector_descending_trampoline"
            case "compareByDescendingPrimitive":
                return "kk_comparator_from_selector_primitive_descending_trampoline"
            case "thenBy":
                return "kk_comparator_then_by_trampoline"
            case "thenByDescending":
                return "kk_comparator_then_by_descending_trampoline"
            case "thenDescending":
                return "kk_comparator_then_descending_trampoline"
            case "thenComparator":
                return "kk_comparator_then_comparator_trampoline"
            case "nullsFirst":
                return "kk_comparator_nulls_first_trampoline"
            case "nullsLast":
                return "kk_comparator_nulls_last_trampoline"
            case "reversed":
                return "kk_comparator_reversed_trampoline"
            case "naturalOrder":
                return "kk_comparator_natural_order_trampoline"
            case "reverseOrder":
                return "kk_comparator_reverse_order_trampoline"
            default:
                return nil
            }
        }

        if let comparatorExprID,
           let chosenCallee = sema.bindings.callBinding(for: comparatorExprID)?.chosenCallee
        {
            if let primitiveKind = primitiveCompareKind(
                for: comparatorExprID,
                loweredComparatorID: loweredComparatorID
            ) {
                if let symbol = sema.symbols.symbol(chosenCallee) {
                    switch interner.resolve(symbol.name) {
                    case "compareBy":
                        return "kk_comparator_from_selector_primitive_trampoline"
                    case "compareByDescending":
                        return "kk_comparator_from_selector_primitive_descending_trampoline"
                    default:
                        break
                    }
                }
                if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee) {
                    switch externalLinkName {
                    case "kk_comparator_from_selector":
                        _ = primitiveKind
                        return "kk_comparator_from_selector_primitive_trampoline"
                    case "kk_comparator_from_selector_descending":
                        _ = primitiveKind
                        return "kk_comparator_from_selector_primitive_descending_trampoline"
                    default:
                        break
                    }
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               let trampolineName = trampolineName(for: externalLinkName)
            {
                return trampolineName
            }
            if let trampolineName = trampolineName(for: chosenCallee) {
                return trampolineName
            }
        }

        for instruction in instructions.reversed() {
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  result == loweredComparatorID,
                  let trampolineName = trampolineName(for: interner.resolve(callee))
            else {
                continue
            }
            return trampolineName
        }
        return nil
    }

    func makeComparatorTrampolineArgument(
        comparatorExprID: ExprID?,
        loweredComparatorID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID]? {
        let trampolineName = comparatorTrampolineName(
            comparatorExprID: comparatorExprID,
            loweredComparatorID: loweredComparatorID,
            sema: sema,
            interner: interner,
            instructions: instructions
        )
        guard let trampolineName else {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return [loweredComparatorID, zeroExpr]
        }

        let fnPtrExpr = arena.appendExpr(
            .temporary(Int32(clamping: arena.expressions.count)),
            type: sema.types.intType
        )
        instructions.append(.constValue(
            result: fnPtrExpr,
            value: .externSymbolAddress(interner.intern(trampolineName))
        ))
        return [fnPtrExpr, loweredComparatorID]
    }

    func adaptComparatorFactoryArgumentsForCollectionHOF(
        calleeName: InternedString,
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyHOFNames: Set<String> = [
            "sortWith", "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        ]
        guard comparatorOnlyHOFNames.contains(interner.resolve(calleeName)),
              loweredArgIDs.count == 1,
              let comparatorArgID = loweredArgIDs.first,
              let comparatorExprID = argExprIDs.first,
              let comparatorArgs = makeComparatorTrampolineArgument(
                  comparatorExprID: comparatorExprID,
                  loweredComparatorID: comparatorArgID,
                  sema: sema,
                  arena: arena,
                  interner: interner,
                  instructions: &instructions
              )
        else {
            return loweredArgIDs
        }
        return comparatorArgs
    }

    func adaptComparatorBackedCollectionArguments(
        loweredCallee: InternedString,
        finalArguments: [KIRExprID],
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyCallees: Set<InternedString> = [
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_maxWithOrNull"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_minWithOrNull"),
            interner.intern("kk_array_sortedArrayWith"),
            interner.intern("kk_mutable_list_sortWith"),
        ]
        if comparatorOnlyCallees.contains(loweredCallee),
           finalArguments.count == 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs.first,
               loweredComparatorID: finalArguments[1],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return [finalArguments[0]] + comparatorArgs
        }

        if loweredCallee == interner.intern("kk_list_binarySearch_comparator"),
           finalArguments.count == 5,
           sourceArgExprs.count >= 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments[3...])
            return adapted
        }

        let arrayBinarySearchCallee = interner.intern("kk_array_binarySearch_compare")
        if loweredCallee == arrayBinarySearchCallee,
           finalArguments.count >= 3,
           sourceArgExprs.count >= 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            if finalArguments.count > 3 {
                adapted.append(contentsOf: finalArguments.dropFirst(3))
            }
            return adapted
        }

        let comparatorSelectorCallees: Set<InternedString> = [
            interner.intern("kk_list_maxOfWith"),
            interner.intern("kk_list_maxOfWithOrNull"),
            interner.intern("kk_list_minOfWith"),
            interner.intern("kk_list_minOfWithOrNull"),
        ]
        if comparatorSelectorCallees.contains(loweredCallee),
           sourceArgExprs.count == 2
        {
            let hasReceiver = finalArguments.count >= 4
            let receiverArg = hasReceiver ? finalArguments[0] : nil
            let comparatorIndex = hasReceiver ? 1 : 0
            let selectorStartIndex = hasReceiver ? 2 : 1
            guard finalArguments.count >= selectorStartIndex + 2,
                  let comparatorArgs = makeComparatorTrampolineArgument(
                      comparatorExprID: sourceArgExprs.first,
                      loweredComparatorID: finalArguments[comparatorIndex],
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
            else {
                return finalArguments
            }

            var adapted: [KIRExprID] = []
            if let receiverArg {
                adapted.append(receiverArg)
            }
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments[selectorStartIndex...])
            return adapted
        }

        let arrayBinarySearchComparatorCallees: Set<InternedString> = [
            interner.intern("kk_array_binarySearch_compare"),
        ]
        if arrayBinarySearchComparatorCallees.contains(loweredCallee),
           sourceArgExprs.count == 4,
           finalArguments.count >= 5,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments.dropFirst(3))
            return adapted
        }

        return finalArguments
    }
}
