import Foundation

extension NativeEmitter {
    struct EmissionBuilderState {
        let builder: LLVMCAPIBindings.LLVMBuilderRef
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let zeroValue: LLVMCAPIBindings.LLVMValueRef
    }

    func lowerBuiltinCall(
        calleeName: String,
        argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        state: EmissionBuilderState,
        instructionIndex: Int
    ) -> (handled: Bool, value: LLVMCAPIBindings.LLVMValueRef?) {
        let lhs = argumentValues.count > 0 ? argumentValues[0] : state.zeroValue
        let rhs = argumentValues.count > 1 ? argumentValues[1] : state.zeroValue

        func boolCondition(
            from value: LLVMCAPIBindings.LLVMValueRef,
            name: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            bindings.buildICmpNotEqual(state.builder, lhs: value, rhs: state.zeroValue, name: name)
        }

        func buildComparisonOperation(
            _ operation: (LLVMCAPIBindings.LLVMBuilderRef, LLVMCAPIBindings.LLVMValueRef, LLVMCAPIBindings.LLVMValueRef, String) -> LLVMCAPIBindings.LLVMValueRef?,
            name: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            if let compared = operation(state.builder, lhs, rhs, name) {
                return bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "\(name)64_\(instructionIndex)")
            }
            return nil
        }

        func buildLogicalAnd() -> LLVMCAPIBindings.LLVMValueRef? {
            if let lhsBool = boolCondition(from: lhs, name: "and_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "and_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "and_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "and_rhs64_\(instructionIndex)")
            {
                return bindings.buildMul(state.builder, lhs: lhsInt, rhs: rhsInt, name: "and64_\(instructionIndex)")
            }
            return nil
        }

        func buildLogicalOr() -> LLVMCAPIBindings.LLVMValueRef? {
            if let lhsBool = boolCondition(from: lhs, name: "or_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "or_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "or_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "or_rhs64_\(instructionIndex)"),
               let sum = bindings.buildAdd(state.builder, lhs: lhsInt, rhs: rhsInt, name: "or_sum_\(instructionIndex)"),
               let nonZero = bindings.buildICmpNotEqual(state.builder, lhs: sum, rhs: state.zeroValue, name: "or_nonzero_\(instructionIndex)")
            {
                return bindings.buildZExt(state.builder, value: nonZero, type: state.int64Type, name: "or64_\(instructionIndex)")
            }
            return nil
        }

        let lowered: LLVMCAPIBindings.LLVMValueRef?
        switch calleeName {
        case "kk_op_add":
            lowered = bindings.buildAdd(state.builder, lhs: lhs, rhs: rhs, name: "add_\(instructionIndex)")
        case "kk_op_sub":
            lowered = bindings.buildSub(state.builder, lhs: lhs, rhs: rhs, name: "sub_\(instructionIndex)")
        case "kk_op_mul":
            lowered = bindings.buildMul(state.builder, lhs: lhs, rhs: rhs, name: "mul_\(instructionIndex)")
        case "kk_op_div":
            lowered = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "div_\(instructionIndex)")
        case "kk_op_udiv":
            lowered = bindings.buildUDiv(state.builder, lhs: lhs, rhs: rhs, name: "udiv_\(instructionIndex)")
        case "kk_op_mod":
            if let quotient = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "mod_q_\(instructionIndex)"),
               let product = bindings.buildMul(state.builder, lhs: quotient, rhs: rhs, name: "mod_p_\(instructionIndex)")
            {
                lowered = bindings.buildSub(state.builder, lhs: lhs, rhs: product, name: "mod_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_urem":
            lowered = bindings.buildURem(state.builder, lhs: lhs, rhs: rhs, name: "urem_\(instructionIndex)")
        case "kk_op_eq":
            lowered = buildComparisonOperation(bindings.buildICmpEqual, name: "eq")
        case "kk_op_ne":
            lowered = buildComparisonOperation(bindings.buildICmpNotEqual, name: "ne")
        case "kk_op_lt":
            lowered = buildComparisonOperation(bindings.buildICmpSignedLessThan, name: "lt")
        case "kk_op_le":
            lowered = buildComparisonOperation(bindings.buildICmpSignedLessOrEqual, name: "le")
        case "kk_op_gt":
            lowered = buildComparisonOperation(bindings.buildICmpSignedGreaterThan, name: "gt")
        case "kk_op_ge":
            lowered = buildComparisonOperation(bindings.buildICmpSignedGreaterOrEqual, name: "ge")
        case "kk_op_ult":
            lowered = buildComparisonOperation(bindings.buildICmpUnsignedLessThan, name: "ult")
        case "kk_op_ule":
            lowered = buildComparisonOperation(bindings.buildICmpUnsignedLessOrEqual, name: "ule")
        case "kk_op_ugt":
            lowered = buildComparisonOperation(bindings.buildICmpUnsignedGreaterThan, name: "ugt")
        case "kk_op_uge":
            lowered = buildComparisonOperation(bindings.buildICmpUnsignedGreaterOrEqual, name: "uge")
        case "kk_op_and":
            lowered = buildLogicalAnd()
        case "kk_op_or":
            lowered = buildLogicalOr()
        case "kk_bitwise_and":
            lowered = bindings.buildAnd(state.builder, lhs: lhs, rhs: rhs, name: "bitand_\(instructionIndex)")
        case "kk_bitwise_or":
            lowered = bindings.buildOr(state.builder, lhs: lhs, rhs: rhs, name: "bitor_\(instructionIndex)")
        case "kk_bitwise_xor":
            lowered = bindings.buildXor(state.builder, lhs: lhs, rhs: rhs, name: "bitxor_\(instructionIndex)")
        case "kk_op_shl":
            lowered = bindings.buildShl(state.builder, lhs: lhs, rhs: rhs, name: "shl_\(instructionIndex)")
        case "kk_op_shr":
            lowered = bindings.buildAShr(state.builder, lhs: lhs, rhs: rhs, name: "shr_\(instructionIndex)")
        case "kk_op_ushr":
            lowered = bindings.buildLShr(state.builder, lhs: lhs, rhs: rhs, name: "ushr_\(instructionIndex)")
        case "kk_op_inv":
            lowered = bindings.buildNot(state.builder, value: lhs, name: "inv_\(instructionIndex)")
        case "kk_op_elvis":
            let sentinel = bindings.constInt(state.int64Type, value: UInt64(bitPattern: Int64.min), signExtend: true) ?? state.zeroValue
            if let isNull = bindings.buildICmpEqual(state.builder, lhs: lhs, rhs: sentinel, name: "elvis_isnull_\(instructionIndex)") {
                lowered = bindings.buildSelect(state.builder, condition: isNull, thenValue: rhs, elseValue: lhs, name: "elvis_\(instructionIndex)")
            } else {
                lowered = nil
            }
        default:
            return (false, nil)
        }
        return (true, lowered)
    }

    func emitConstantValue(
        _ expression: KIRExprKind,
        expressionRawID: Int32?,
        state: EmissionBuilderState,
        parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
        internalFunctions: [SymbolID: LLVMFunction],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        generatedStringLiteralCount: inout Int32,
        declareExternalFunction: (String, Int, Bool) -> LLVMFunction?
    ) -> LLVMCAPIBindings.LLVMValueRef {
        switch expression {
        case let .intLiteral(number):
            return bindings.constInt(state.int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? state.zeroValue
        case let .longLiteral(number):
            return bindings.constInt(state.int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? state.zeroValue
        case let .uintLiteral(number):
            return bindings.constInt(state.int64Type, value: number, signExtend: false) ?? state.zeroValue
        case let .ulongLiteral(number):
            return bindings.constInt(state.int64Type, value: number, signExtend: false) ?? state.zeroValue
        case let .floatLiteral(value):
            var f = Float(value)
            var bits: UInt32 = 0
            memcpy(&bits, &f, MemoryLayout<UInt32>.size)
            return bindings.constInt(state.int64Type, value: UInt64(bits)) ?? state.zeroValue
        case let .doubleLiteral(value):
            var d = value
            var bits: UInt64 = 0
            memcpy(&bits, &d, MemoryLayout<UInt64>.size)
            return bindings.constInt(state.int64Type, value: bits) ?? state.zeroValue
        case let .charLiteral(scalar):
            return bindings.constInt(state.int64Type, value: UInt64(scalar)) ?? state.zeroValue
        case let .boolLiteral(value):
            return bindings.constInt(state.int64Type, value: value ? 1 : 0) ?? state.zeroValue
        case let .stringLiteral(interned):
            let text = interner.resolve(interned)
            let literalID: Int32
            if let expressionRawID {
                literalID = expressionRawID
            } else {
                literalID = generatedStringLiteralCount
                generatedStringLiteralCount += 1
            }
            guard let globalStringPointer = bindings.buildGlobalStringPtr(
                state.builder,
                value: text,
                name: "str_lit_\(literalID)"
            ) else {
                return state.zeroValue
            }
            guard let pointerAsInt = bindings.buildPtrToInt(
                state.builder,
                value: globalStringPointer,
                type: state.int64Type,
                name: "str_ptr_\(literalID)"
            ) else {
                return state.zeroValue
            }
            let lengthValue = bindings.constInt(state.int64Type, value: UInt64(text.utf8.count)) ?? state.zeroValue
            guard let stringFromUTF8 = declareExternalFunction(
                "kk_string_from_utf8",
                2,
                false
            ) else {
                return state.zeroValue
            }
            return bindings.buildCall(
                state.builder,
                functionType: stringFromUTF8.type,
                callee: stringFromUTF8.value,
                arguments: [pointerAsInt, lengthValue],
                name: "str_from_utf8_\(literalID)"
            ) ?? state.zeroValue
        case let .symbolRef(symbol):
            if let parameter = parameterValues[symbol] {
                return parameter
            }
            if let internalFunction = internalFunctions[symbol],
               let functionPointer = bindings.buildPtrToInt(
                   state.builder,
                   value: internalFunction.value,
                   type: state.int64Type,
                   name: "fn_ptr_\(symbol.rawValue)"
               )
            {
                return functionPointer
            }
            // Load from LLVM global variable if this symbol refers to a global.
            if let globalPtr = globalVariables[symbol] {
                return bindings.buildLoad(
                    state.builder,
                    type: state.int64Type,
                    pointer: globalPtr,
                    name: "global_load_\(symbol.rawValue)"
                ) ?? state.zeroValue
            }
            return state.zeroValue
        case let .temporary(raw):
            return bindings.constInt(
                state.int64Type,
                value: UInt64(bitPattern: Int64(raw)),
                signExtend: true
            ) ?? state.zeroValue
        case .null:
            return bindings.constInt(
                state.int64Type,
                value: UInt64(bitPattern: Int64.min),
                signExtend: true
            ) ?? state.zeroValue
        case .unit:
            return state.zeroValue
        }
    }
}
