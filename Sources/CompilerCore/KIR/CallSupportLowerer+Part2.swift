import Foundation

/// Delegate class for KIR lowering: CallSupportLowerer.
/// Holds an unowned reference to the driver for mutual recursion.

extension CallSupportLowerer {
    func generateDefaultStubFunction(
        originalSymbol: SymbolID,
        originalName: InternedString,
        signature: FunctionSignature,
        defaultExpressions: [ExprID?],
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID {
        return generateDefaultStubFunction(
            originalSymbol: originalSymbol,
            originalName: originalName,
            signature: signature,
            defaultExpressions: defaultExpressions,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers
        )
    }

    
    func normalizedCallArguments(
        providedArguments: [KIRExprID],
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        spreadFlags: [Bool],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> NormalizedCallResult {
        normalizedCallArguments(
            providedArguments: providedArguments,
            callBinding: callBinding,
            chosenCallee: chosenCallee,
            spreadFlags: spreadFlags,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func normalizeBoolFlags(_ flags: [Bool], count: Int) -> [Bool] {
        if flags.count == count { return flags }
        if flags.count > count { return Array(flags.prefix(count)) }
        return flags + Array(repeating: false, count: count - flags.count)
    }

    func packVarargArguments(
        argIndices: [Int],
        providedArguments: [KIRExprID],
        spreadFlags: [Bool],
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let hasAnySpread = argIndices.contains { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        let allSpread = !argIndices.isEmpty && argIndices.allSatisfy { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }

        if argIndices.count == 1 && allSpread {
            return providedArguments[argIndices[0]]
        }

        if hasAnySpread {
            let pairsCount = argIndices.count
            let pairsArraySize = pairsCount * 2
            let pairsArray = emitArrayNew(
                count: pairsArraySize,
                arena: arena,
                interner: interner,
                intType: intType,
                anyType: anyType,
                emit: &instructions
            )
            for (pairIdx, idx) in argIndices.enumerated() {
                let isSpread = idx < spreadFlags.count && spreadFlags[idx]
                let markerValue: Int64 = isSpread ? -1 : 1
                let markerExpr = arena.appendExpr(.intLiteral(markerValue), type: intType)
                instructions.append(.constValue(result: markerExpr, value: .intLiteral(markerValue)))
                let markerIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2)), type: intType)
                instructions.append(.constValue(result: markerIdxExpr, value: .intLiteral(Int64(pairIdx * 2))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, markerIdxExpr, markerExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
                let valueIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2 + 1)), type: intType)
                instructions.append(.constValue(result: valueIdxExpr, value: .intLiteral(Int64(pairIdx * 2 + 1))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, valueIdxExpr, providedArguments[idx]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            let pairCountExpr = arena.appendExpr(.intLiteral(Int64(pairsCount)), type: intType)
            instructions.append(.constValue(result: pairCountExpr, value: .intLiteral(Int64(pairsCount))))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_vararg_spread_concat"),
                arguments: [pairsArray, pairCountExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        let count = argIndices.count
        let arrayID = emitArrayNew(
            count: count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            emit: &instructions
        )
        for (slotIndex, argIndex) in argIndices.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(slotIndex)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(slotIndex))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexExpr, providedArguments[argIndex]],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return arrayID
    }

    func emitArrayNew(
        count: Int,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let countExpr = arena.appendExpr(.intLiteral(Int64(count)), type: intType)
        instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
        let arrayID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayID,
            canThrow: false,
            thrownResult: nil
        ))
        return arrayID
    }

    func syntheticReceiverParameterSymbol(functionSymbol: SymbolID) -> SymbolID {
        SymbolID(rawValue: -10_000 - functionSymbol.rawValue)
    }

    func loweredRuntimeBuiltinCallee(
        for callee: InternedString,
        argumentCount: Int,
        interner: StringInterner
    ) -> InternedString? {
        switch interner.resolve(callee) {
        case "IntArray":
            guard argumentCount == 1 else {
                return nil
            }
            return interner.intern("kk_array_new")
        default:
            return nil
        }
    }

    func builtinBinaryRuntimeCallee(for op: BinaryOp, interner: StringInterner) -> InternedString? {
        switch op {
        case .notEqual:
            return interner.intern("kk_op_ne")
        case .lessThan:
            return interner.intern("kk_op_lt")
        case .lessOrEqual:
            return interner.intern("kk_op_le")
        case .greaterThan:
            return interner.intern("kk_op_gt")
        case .greaterOrEqual:
            return interner.intern("kk_op_ge")
        case .logicalAnd:
            return interner.intern("kk_op_and")
        case .logicalOr:
            return interner.intern("kk_op_or")
        default:
            return nil
        }
    }


}
