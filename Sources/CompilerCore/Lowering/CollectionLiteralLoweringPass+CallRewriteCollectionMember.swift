import Foundation

extension CollectionLiteralLoweringPass {

    /// Rewrites simple collection member calls that do not require closure ABI expansion.
    func rewriteCollectionMemberCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        let uintType = ctx.sema?.types.uintType

        func isUIntRangeExpr(_ expr: KIRExprID) -> Bool {
            guard let uintType else { return false }
            return module.arena.exprType(expr) == uintType
        }

        // --- Rewrite collection member calls ---
        // Member calls are lowered as call(callee=memberName, args=[receiver, ...])
        // any()/none()/first()/last() with no predicate: args=[receiver], pass fnPtr=0, closure=0
        if callee == lookup.anyName || callee == lookup.noneName || callee == lookup.firstName || callee == lookup.lastName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
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
                    return true
                }
                if state.rangeExprIDs.contains(receiverID.rawValue),
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
                    return true
                }
            }
        }

        if callee == lookup.sizeName || callee == lookup.countName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.arrayExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    let countCallee: InternedString
                    if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
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
                    return true
                }
            }
        }

        if callee == lookup.getName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListGetName,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapGetName,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return true
                }
            }
        }

        if callee == lookup.containsName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListContainsName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetContainsName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.containsAllName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListContainsAllName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetContainsAllName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.containsKeyName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapContainsKeyName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.containsValueName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapContainsValueName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.addName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMutableSetAddName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.removeName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMutableSetRemoveName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.isEmptyName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                // STDLIB-637: UIntRange/ULongRange isEmpty
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    let isUIntRange = isUIntRangeExpr(receiverID)
                    let isEmptyName = state.ulongRangeExprIDs.contains(receiverID.rawValue)
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
                    return true
                }
            }
        }

        // STDLIB-637: range/list sum()
        if callee == lookup.sumName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    let isUIntRange = isUIntRangeExpr(receiverID)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: isUIntRange ? ctx.interner.intern("kk_uint_range_sum") : lookup.kkRangeSumName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.listExprIDs.contains(receiverID.rawValue) || state.arrayExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListSumName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        return false
    }
}
