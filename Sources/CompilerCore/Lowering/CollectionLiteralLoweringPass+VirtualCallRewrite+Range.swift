/// Virtual-call rewrite for `IntRange` / `LongRange` / `CharRange` /
/// `UIntRange` / `ULongRange` receivers (STDLIB-090/091/092/093).
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`.
extension CollectionLiteralLoweringPass {
    // MARK: - IntRange operations (STDLIB-090/091/092/093)

    func rewriteRangeVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        sema: SemaModule?,
        interner: StringInterner,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        listExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        guard rangeExprIDs.contains(receiver.rawValue) else { return false }
        let isCharRange = charRangeExprIDs.contains(receiver.rawValue)
        let isULongRange = ulongRangeExprIDs.contains(receiver.rawValue)
        let isUIntRange = sema.map { module.arena.exprType(receiver) == $0.types.uintType } ?? false
        let isLongRange = sema.map { module.arena.exprType(receiver) == $0.types.longType } ?? false
        let randomName = interner.intern("random")
        let randomOrNullName = interner.intern("randomOrNull")

        // step — simple property access (STDLIB-RANGE-037)
        if callee == lookup.stepName, arguments.isEmpty {
            let stepName = isULongRange ? lookup.kkULongRangeStepName : (isUIntRange ? interner.intern("kk_uint_range_step") : lookup.kkRangeStepName)
            loweredBody.append(.call(
                symbol: nil, callee: stepName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // first / last / start / endInclusive / endExclusive / count — simple property access (STDLIB-092 / STDLIB-RANGE-034)
        if (callee == lookup.firstName || callee == lookup.startName), arguments.isEmpty {
            let firstName = isULongRange ? lookup.kkULongRangeFirstName : (isUIntRange ? interner.intern("kk_uint_range_first") : lookup.kkRangeFirstName)
            loweredBody.append(.call(
                symbol: nil, callee: firstName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if (callee == lookup.lastName || callee == lookup.endInclusiveName), arguments.isEmpty {
            let lastName = isULongRange ? lookup.kkULongRangeLastName : (isUIntRange ? interner.intern("kk_uint_range_last") : lookup.kkRangeLastName)
            loweredBody.append(.call(
                symbol: nil, callee: lastName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.endExclusiveName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeEndExclusiveName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.countName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: isUIntRange ? interner.intern("kk_uint_range_count") : lookup.kkRangeCountName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        // STDLIB-637: isEmpty / sum
        if callee == lookup.isEmptyName, arguments.isEmpty {
            let isEmptyName = isULongRange ? lookup.kkULongRangeIsEmptyName : (isUIntRange ? interner.intern("kk_uint_range_isEmpty") : lookup.kkRangeIsEmptyName)
            loweredBody.append(.call(
                symbol: nil, callee: isEmptyName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.sumName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: isUIntRange ? interner.intern("kk_uint_range_sum") : lookup.kkRangeSumName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // contains — delegate to kk_op_contains (STDLIB-090) or kk_ulong_range_contains (STDLIB-RANGE-037)
        if callee == lookup.containsName, arguments.count == 1 {
            let containsName = isULongRange ? lookup.kkULongRangeContainsName : (isUIntRange ? interner.intern("kk_uint_range_contains") : lookup.kkOpContainsName)
            loweredBody.append(.call(
                symbol: nil, callee: containsName,
                arguments: [receiver, arguments[0]], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toList — returns a List (STDLIB-091 / STDLIB-290 / STDLIB-524)
        if callee == lookup.toListName, arguments.isEmpty {
            let toListCallee: InternedString
            if isCharRange {
                toListCallee = lookup.kkCharRangeToListName
            } else if isULongRange {
                toListCallee = lookup.kkULongRangeToListName
            } else if isUIntRange {
                toListCallee = interner.intern("kk_uint_range_toList")
            } else {
                toListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(
                symbol: nil, callee: toListCallee,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        if callee == interner.intern("toUIntArray"), arguments.isEmpty, isUIntRange {
            loweredBody.append(.call(
                symbol: nil, callee: interner.intern("kk_uint_range_toUIntArray"),
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toULongArray — returns a ULongArray (STDLIB-RANGE-037)
        if callee == lookup.toULongArrayName, arguments.isEmpty, isULongRange {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkULongRangeToULongArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toLongArray — returns a LongArray (STDLIB-RANGE-035)
        if callee == lookup.toLongArrayName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkLongRangeToLongArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toIntArray — returns an IntArray (STDLIB-RANGE-034)
        if callee == lookup.toIntArrayName, arguments.isEmpty, !isCharRange, !isULongRange {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeToIntArrayName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        if callee == lookup.iteratorName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeIteratorName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // forEach — HOF (STDLIB-091 / STDLIB-290)
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let forEachCallee = isCharRange ? lookup.kkCharRangeForEachName
                : (isULongRange ? interner.intern("kk_ulong_range_forEach")
                    : (isUIntRange ? interner.intern("kk_uint_range_forEach") : lookup.kkRangeForEachName))
            _ = emitHOFCall(
                kkName: forEachCallee, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // map — HOF returning List (STDLIB-091)
        if callee == lookup.mapName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_map")
                    : (isUIntRange ? interner.intern("kk_uint_range_map") : lookup.kkRangeMapName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // Additional range HOFs.
        if callee == lookup.mapIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_mapIndexed")
                    : (isUIntRange ? interner.intern("kk_uint_range_mapIndexed") : lookup.kkRangeMapIndexedName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.mapNotNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_mapNotNull")
                    : (isUIntRange ? interner.intern("kk_uint_range_mapNotNull") : lookup.kkRangeMapNotNullName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_filter")
                    : (isUIntRange ? interner.intern("kk_uint_range_filter") : lookup.kkRangeFilterName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_filterIndexed")
                    : (isUIntRange ? interner.intern("kk_uint_range_filterIndexed") : lookup.kkRangeFilterIndexedName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.filterNotName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_filterNot")
                    : (isUIntRange ? interner.intern("kk_uint_range_filterNot") : lookup.kkRangeFilterNotName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            listExprIDs.insert(hofResult.rawValue)
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.reduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_reduce")
                    : (isUIntRange ? interner.intern("kk_uint_range_reduce") : lookup.kkRangeReduceName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.reduceIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_reduceIndexed")
                    : (isUIntRange ? interner.intern("kk_uint_range_reduceIndexed") : lookup.kkRangeReduceIndexedName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_fold")
                    : (isUIntRange ? interner.intern("kk_uint_range_fold") : lookup.kkRangeFoldName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_foldIndexed")
                    : (isUIntRange ? interner.intern("kk_uint_range_foldIndexed") : lookup.kkRangeFoldIndexedName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_find")
                    : (isUIntRange ? interner.intern("kk_uint_range_find") : lookup.kkRangeFindName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findLastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_findLast")
                    : (isUIntRange ? interner.intern("kk_uint_range_findLast") : lookup.kkRangeFindLastName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_first_predicate")
                    : (isUIntRange ? interner.intern("kk_uint_range_first_predicate") : lookup.kkRangeFirstPredicateName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstOrNullName, arguments.isEmpty {
            let firstOrNullName = isULongRange ? interner.intern("kk_ulong_range_firstOrNull")
                : (isUIntRange ? interner.intern("kk_uint_range_firstOrNull") : interner.intern("kk_range_firstOrNull"))
            loweredBody.append(.call(
                symbol: nil, callee: firstOrNullName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.firstOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_firstOrNull_predicate")
                    : (isUIntRange ? interner.intern("kk_uint_range_firstOrNull_predicate") : lookup.kkRangeFirstOrNullPredicateName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_last_predicate")
                    : (isUIntRange ? interner.intern("kk_uint_range_last_predicate") : lookup.kkRangeLastPredicateName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastOrNullName, arguments.isEmpty {
            let lastOrNullName = isULongRange ? interner.intern("kk_ulong_range_lastOrNull")
                : (isUIntRange ? interner.intern("kk_uint_range_lastOrNull") : interner.intern("kk_range_lastOrNull"))
            loweredBody.append(.call(
                symbol: nil, callee: lastOrNullName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.lastOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isULongRange ? interner.intern("kk_ulong_range_lastOrNull_predicate")
                    : (isUIntRange ? interner.intern("kk_uint_range_lastOrNull_predicate") : lookup.kkRangeLastOrNullPredicateName),
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == randomName, arguments.isEmpty || arguments.count == 1 {
            let randomCallee: InternedString
            if isCharRange {
                randomCallee = arguments.isEmpty ? interner.intern("kk_range_random")
                    : interner.intern("kk_char_range_random_random")
            } else if isULongRange {
                randomCallee = arguments.isEmpty ? interner.intern("kk_ulong_range_random")
                    : interner.intern("kk_ulong_range_random_random")
            } else if isUIntRange {
                randomCallee = arguments.isEmpty ? interner.intern("kk_uint_range_random")
                    : interner.intern("kk_uint_range_random_random")
            } else if isLongRange {
                randomCallee = arguments.isEmpty ? interner.intern("kk_long_range_random")
                    : interner.intern("kk_long_range_random_random")
            } else {
                randomCallee = arguments.isEmpty ? interner.intern("kk_range_random")
                    : interner.intern("kk_range_random_random")
            }
            loweredBody.append(.call(
                symbol: nil, callee: randomCallee,
                arguments: [receiver] + arguments, result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            return true
        }
        if callee == randomOrNullName, arguments.isEmpty || arguments.count == 1 {
            let randomOrNullCallee: InternedString
            if isCharRange {
                randomOrNullCallee = arguments.isEmpty ? interner.intern("kk_char_range_randomOrNull")
                    : interner.intern("kk_char_range_randomOrNull_random")
            } else if isULongRange {
                randomOrNullCallee = arguments.isEmpty ? interner.intern("kk_ulong_range_randomOrNull")
                    : interner.intern("kk_ulong_range_randomOrNull_random")
            } else if isUIntRange {
                randomOrNullCallee = arguments.isEmpty ? interner.intern("kk_uint_range_randomOrNull")
                    : interner.intern("kk_uint_range_randomOrNull_random")
            } else if isLongRange {
                randomOrNullCallee = arguments.isEmpty ? interner.intern("kk_long_range_randomOrNull")
                    : interner.intern("kk_long_range_randomOrNull_random")
            } else {
                randomOrNullCallee = arguments.isEmpty ? interner.intern("kk_range_randomOrNull")
                    : interner.intern("kk_range_randomOrNull_random")
            }
            loweredBody.append(.call(
                symbol: nil, callee: randomOrNullCallee,
                arguments: [receiver] + arguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if (callee == lookup.anyName || callee == lookup.allName || callee == lookup.noneName), arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let kkName: InternedString =
                callee == lookup.anyName ? (isULongRange ? interner.intern("kk_ulong_range_any")
                    : (isUIntRange ? interner.intern("kk_uint_range_any") : lookup.kkRangeAnyName))
                    : callee == lookup.allName ? (isULongRange ? interner.intern("kk_ulong_range_all")
                        : (isUIntRange ? interner.intern("kk_uint_range_all") : lookup.kkRangeAllName))
                    : (isULongRange ? interner.intern("kk_ulong_range_none")
                        : (isUIntRange ? interner.intern("kk_uint_range_none") : lookup.kkRangeNoneName))
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.chunkedName, arguments.count == 1 {
            loweredBody.append(.call(
                symbol: nil, callee: isULongRange ? interner.intern("kk_ulong_range_chunked")
                    : (isUIntRange ? interner.intern("kk_uint_range_chunked") : lookup.kkRangeChunkedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.windowedName, arguments.count == 3 {
            loweredBody.append(.call(
                symbol: nil, callee: isULongRange ? interner.intern("kk_ulong_range_windowed")
                    : (isUIntRange ? interner.intern("kk_uint_range_windowed") : lookup.kkRangeWindowedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // take/drop/average/sorted — dispatch by range type (STDLIB-RANGE-TDS)
        if callee == lookup.takeName, arguments.count == 1 {
            let takeName: InternedString
            if isULongRange {
                takeName = interner.intern("kk_ulong_range_take")
            } else if isUIntRange {
                takeName = interner.intern("kk_uint_range_take")
            } else if isLongRange {
                takeName = interner.intern("kk_long_range_take")
            } else if isCharRange {
                takeName = interner.intern("kk_char_range_take")
            } else {
                takeName = lookup.kkRangeTakeName
            }
            loweredBody.append(.call(symbol: nil, callee: takeName,
                arguments: [receiver] + arguments, result: result, canThrow: false, thrownResult: nil))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.dropName, arguments.count == 1 {
            let dropName: InternedString
            if isULongRange {
                dropName = interner.intern("kk_ulong_range_drop")
            } else if isUIntRange {
                dropName = interner.intern("kk_uint_range_drop")
            } else if isLongRange {
                dropName = interner.intern("kk_long_range_drop")
            } else if isCharRange {
                dropName = interner.intern("kk_char_range_drop")
            } else {
                dropName = lookup.kkRangeDropName
            }
            loweredBody.append(.call(symbol: nil, callee: dropName,
                arguments: [receiver] + arguments, result: result, canThrow: false, thrownResult: nil))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }
        if callee == lookup.averageName, arguments.isEmpty {
            let averageName: InternedString
            if isULongRange {
                averageName = interner.intern("kk_ulong_range_average")
            } else if isUIntRange {
                averageName = interner.intern("kk_uint_range_average")
            } else if isLongRange {
                averageName = interner.intern("kk_long_range_average")
            } else {
                averageName = lookup.kkRangeAverageName
            }
            loweredBody.append(.call(symbol: nil, callee: averageName,
                arguments: [receiver], result: result, canThrow: false, thrownResult: nil))
            return true
        }
        if callee == lookup.sortedName, arguments.isEmpty {
            let sortedName: InternedString
            if isULongRange {
                sortedName = interner.intern("kk_ulong_range_sorted")
            } else if isUIntRange {
                sortedName = interner.intern("kk_uint_range_sorted")
            } else if isLongRange {
                sortedName = interner.intern("kk_long_range_sorted")
            } else if isCharRange {
                sortedName = interner.intern("kk_char_range_sorted")
            } else {
                sortedName = lookup.kkRangeSortedName
            }
            loweredBody.append(.call(symbol: nil, callee: sortedName,
                arguments: [receiver], result: result, canThrow: false, thrownResult: nil))
            if let result { listExprIDs.insert(result.rawValue) }
            return true
        }

        // reversed — returns a range (STDLIB-093)
        if callee == lookup.reversedName, arguments.isEmpty {
            let reversedName = isULongRange ? lookup.kkULongRangeReversedName : (isUIntRange ? interner.intern("kk_uint_range_reversed") : lookup.kkRangeReversedName)
            loweredBody.append(.call(
                symbol: nil, callee: reversedName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result {
                rangeExprIDs.insert(result.rawValue)
                // Propagate char range through reversed() (STDLIB-290)
                if isCharRange { charRangeExprIDs.insert(result.rawValue) }
                // Propagate ULong range through reversed() (STDLIB-524)
                if isULongRange { ulongRangeExprIDs.insert(result.rawValue) }
            }
            return true
        }

        return false
    }

    // MARK: - Static type fallback classification (LOWERING-001)

    /// Classify a receiver expression by its static type in the KIR arena.
    /// If the receiver is already in one of the tracking sets, this is a no-op.
    /// Otherwise, look up the expression's TypeID, resolve its class symbol,
    /// and insert it into the appropriate tracking set so that downstream
    /// rewrite logic can match on it.
}
