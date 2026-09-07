/// Array and list conversion call rewrites.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteArrayConversionCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // toMutableList() on array → kk_array_toMutableList (STDLIB-087)
    if callee == lookup.toMutableListName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let toMutableListResult = module.arena.appendTemporary(type: nil
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
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toMutableListResult.rawValue)
                loweredBody.append(.copy(from: toMutableListResult, to: result))
            }
            return true
        }
    }

    // KSP-628 + KSP-629: the List receivers of toTypedArray /
    // to{Char,Boolean,Short,Double,Float,Int,Long,Byte,UByte,UShort,UInt,ULong}Array
    // are source-backed (ArrayConversions.kt) and lower through normal function resolution.

    // toTypedArray() on array → __kk_array_copyOf (STDLIB-087)
    if callee == lookup.toTypedArrayName,
       arguments.count == 1,
       symbol.map({ ctx.sema?.symbols.isSourceBackedSymbol($0) != true }) ?? true
    {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let toArrayResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfName,
                arguments: [receiverID],
                result: toArrayResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.arrayExprIDs.insert(result.rawValue)
                state.arrayExprIDs.insert(toArrayResult.rawValue)
                loweredBody.append(.copy(from: toArrayResult, to: result))
            }
            return true
        }
    }

    // fill on array (STDLIB-089)
    if callee == lookup.fillName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFillName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }
    }

        return false
    }
}
