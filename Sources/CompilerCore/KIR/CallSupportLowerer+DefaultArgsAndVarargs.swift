import Foundation

// Delegate class for KIR lowering: CallSupportLowerer.
// Holds an unowned reference to the driver for mutual recursion.

extension CallSupportLowerer {
    func generateDefaultStubFunction(
        originalSymbol: SymbolID,
        originalName: InternedString,
        signature: FunctionSignature,
        defaultExpressions: [ExprID?],
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID {
        generateDefaultStubFunction(
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
        var legacyInstructions = instructions.instructions
        let result = packVarargArguments(
            argIndices: argIndices,
            providedArguments: providedArguments,
            spreadFlags: spreadFlags,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            instructions: &legacyInstructions
        )
        instructions = KIRLoweringEmitContext(legacyInstructions)
        return result
    }

    func emitArrayNew(
        count: Int,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var legacyInstructions = instructions.instructions
        let result = emitArrayNew(
            count: count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            instructions: &legacyInstructions
        )
        instructions = KIRLoweringEmitContext(legacyInstructions)
        return result
    }

    func syntheticReceiverParameterSymbol(functionSymbol: SymbolID) -> SymbolID {
        SyntheticSymbolScheme.receiverParameterSymbol(for: functionSymbol)
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
            interner.intern("kk_op_ne")
        case .lessThan:
            interner.intern("kk_op_lt")
        case .lessOrEqual:
            interner.intern("kk_op_le")
        case .greaterThan:
            interner.intern("kk_op_gt")
        case .greaterOrEqual:
            interner.intern("kk_op_ge")
        case .logicalAnd:
            interner.intern("kk_op_and")
        case .logicalOr:
            interner.intern("kk_op_or")
        default:
            nil
        }
    }
}
