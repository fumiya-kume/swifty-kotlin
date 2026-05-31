import Foundation

extension NativeEmitter {
    struct EmissionBuilderState {
        let builder: LLVMCAPIBindings.LLVMBuilderRef
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let zeroValue: LLVMCAPIBindings.LLVMValueRef
        let context: LLVMCAPIBindings.LLVMContextRef?
        let module: LLVMCAPIBindings.LLVMModuleRef?

        init(
            builder: LLVMCAPIBindings.LLVMBuilderRef,
            int64Type: LLVMCAPIBindings.LLVMTypeRef,
            zeroValue: LLVMCAPIBindings.LLVMValueRef,
            context: LLVMCAPIBindings.LLVMContextRef? = nil,
            module: LLVMCAPIBindings.LLVMModuleRef? = nil
        ) {
            self.builder = builder
            self.int64Type = int64Type
            self.zeroValue = zeroValue
            self.context = context
            self.module = module
        }
    }

    // swiftlint:disable cyclomatic_complexity
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

        func buildSignedFloorMod(name: String) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let quotient = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "\(name)_q_\(instructionIndex)"),
                  let product = bindings.buildMul(state.builder, lhs: quotient, rhs: rhs, name: "\(name)_p_\(instructionIndex)"),
                  let remainder = bindings.buildSub(state.builder, lhs: lhs, rhs: product, name: "\(name)_rem_\(instructionIndex)"),
                  let remainderIsNonZero = bindings.buildICmpNotEqual(state.builder, lhs: remainder, rhs: state.zeroValue, name: "\(name)_nonzero_\(instructionIndex)"),
                  let lhsIsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: state.zeroValue, name: "\(name)_lhs_neg_\(instructionIndex)"),
                  let rhsIsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: rhs, rhs: state.zeroValue, name: "\(name)_rhs_neg_\(instructionIndex)"),
                  let signsDiffer = bindings.buildXor(state.builder, lhs: lhsIsNegative, rhs: rhsIsNegative, name: "\(name)_signs_\(instructionIndex)"),
                  let shouldAdjust = bindings.buildAnd(state.builder, lhs: remainderIsNonZero, rhs: signsDiffer, name: "\(name)_adjust_\(instructionIndex)"),
                  let adjusted = bindings.buildAdd(state.builder, lhs: remainder, rhs: rhs, name: "\(name)_adjusted_\(instructionIndex)")
            else {
                return nil
            }
            return bindings.buildSelect(
                state.builder,
                condition: shouldAdjust,
                thenValue: adjusted,
                elseValue: remainder,
                name: "\(name)_\(instructionIndex)"
            )
        }

        // Sign-extend the low 32 bits of a 64-bit slot back into a canonical
        // 64-bit representation of a Kotlin `Int`. Implemented as
        // `(value << 32) >>a 32` so it needs no dedicated i32 type / SExt
        // binding. This enforces Kotlin's two's-complement `Int` wraparound.
        func narrowTo32(_ value: LLVMCAPIBindings.LLVMValueRef?, name: String) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let value,
                  let thirtyTwo = bindings.constInt(state.int64Type, value: 32),
                  let widened = bindings.buildShl(state.builder, lhs: value, rhs: thirtyTwo, name: "\(name)_w_\(instructionIndex)")
            else {
                return nil
            }
            return bindings.buildAShr(state.builder, lhs: widened, rhs: thirtyTwo, name: "\(name)_\(instructionIndex)")
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
        case "kk_op_floor_div", "kk_op_lfloor_div":
            if let quotient = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "floordiv_q_\(instructionIndex)"),
               let product = bindings.buildMul(state.builder, lhs: quotient, rhs: rhs, name: "floordiv_p_\(instructionIndex)"),
               let remainder = bindings.buildSub(state.builder, lhs: lhs, rhs: product, name: "floordiv_r_\(instructionIndex)"),
               let remainderNonZero = bindings.buildICmpNotEqual(state.builder, lhs: remainder, rhs: state.zeroValue, name: "floordiv_rnz_\(instructionIndex)"),
               let lhsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: state.zeroValue, name: "floordiv_lneg_\(instructionIndex)"),
               let rhsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: rhs, rhs: state.zeroValue, name: "floordiv_rneg_\(instructionIndex)"),
               let signsDiffer = bindings.buildXor(state.builder, lhs: lhsNegative, rhs: rhsNegative, name: "floordiv_sdiff_\(instructionIndex)"),
               let shouldAdjust = bindings.buildAnd(state.builder, lhs: remainderNonZero, rhs: signsDiffer, name: "floordiv_adj_\(instructionIndex)"),
               let one = bindings.constInt(state.int64Type, value: 1),
               let adjustedQuotient = bindings.buildSub(state.builder, lhs: quotient, rhs: one, name: "floordiv_dec_\(instructionIndex)")
            {
                lowered = bindings.buildSelect(
                    state.builder,
                    condition: shouldAdjust,
                    thenValue: adjustedQuotient,
                    elseValue: quotient,
                    name: "floordiv_\(instructionIndex)"
                )
            } else {
                lowered = nil
            }
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
        case "kk_op_floor_mod":
            lowered = buildSignedFloorMod(name: "floor_mod")
        case "kk_op_lfloor_mod":
            lowered = buildSignedFloorMod(name: "lfloor_mod")
        case "kk_op_urem":
            lowered = bindings.buildURem(state.builder, lhs: lhs, rhs: rhs, name: "urem_\(instructionIndex)")
        case "kk_op_eq":
            if let compared = bindings.buildICmpEqual(state.builder, lhs: lhs, rhs: rhs, name: "eq_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "eq64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ne":
            if let compared = bindings.buildICmpNotEqual(state.builder, lhs: lhs, rhs: rhs, name: "ne_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ne64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lt":
            if let compared = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: rhs, name: "lt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "lt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_le":
            if let compared = bindings.buildICmpSignedLessOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "le_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "le64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_gt":
            if let compared = bindings.buildICmpSignedGreaterThan(state.builder, lhs: lhs, rhs: rhs, name: "gt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "gt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ge":
            if let compared = bindings.buildICmpSignedGreaterOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "ge_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ge64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ult":
            if let compared = bindings.buildICmpUnsignedLessThan(state.builder, lhs: lhs, rhs: rhs, name: "ult_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ult64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ule":
            if let compared = bindings.buildICmpUnsignedLessOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "ule_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ule64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ugt":
            if let compared = bindings.buildICmpUnsignedGreaterThan(state.builder, lhs: lhs, rhs: rhs, name: "ugt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ugt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_uge":
            if let compared = bindings.buildICmpUnsignedGreaterOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "uge_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "uge64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_and":
            if let lhsBool = boolCondition(from: lhs, name: "and_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "and_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "and_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "and_rhs64_\(instructionIndex)")
            {
                lowered = bindings.buildMul(state.builder, lhs: lhsInt, rhs: rhsInt, name: "and64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_or":
            if let lhsBool = boolCondition(from: lhs, name: "or_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "or_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "or_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "or_rhs64_\(instructionIndex)"),
               let sum = bindings.buildAdd(state.builder, lhs: lhsInt, rhs: rhsInt, name: "or_sum_\(instructionIndex)"),
               let nonZero = bindings.buildICmpNotEqual(state.builder, lhs: sum, rhs: state.zeroValue, name: "or_nonzero_\(instructionIndex)")
            {
                lowered = bindings.buildZExt(state.builder, value: nonZero, type: state.int64Type, name: "or64_\(instructionIndex)")
            } else {
                lowered = nil
            }
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
        case "kk_int_narrow":
            // Wrap a 64-bit arithmetic result to Kotlin's 32-bit `Int`.
            lowered = narrowTo32(lhs, name: "narrow")
        case "kk_op_ishl":
            // Kotlin `Int.shl`: shift distance is `rhs and 31`; result wraps to 32 bits.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "ishl_amt_\(instructionIndex)"),
               let shifted = bindings.buildShl(state.builder, lhs: lhs, rhs: amount, name: "ishl_s_\(instructionIndex)")
            {
                lowered = narrowTo32(shifted, name: "ishl")
            } else {
                lowered = nil
            }
        case "kk_op_ishr":
            // Kotlin `Int.shr`: arithmetic (sign-propagating) shift by `rhs and 31`.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "ishr_amt_\(instructionIndex)"),
               let signExtended = narrowTo32(lhs, name: "ishr_in")
            {
                lowered = bindings.buildAShr(state.builder, lhs: signExtended, rhs: amount, name: "ishr_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_iushr":
            // Kotlin `Int.ushr`: logical shift of the 32-bit value by `rhs and 31`.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let lowMask = bindings.constInt(state.int64Type, value: 0xFFFF_FFFF),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "iushr_amt_\(instructionIndex)"),
               let zeroExtended = bindings.buildAnd(state.builder, lhs: lhs, rhs: lowMask, name: "iushr_in_\(instructionIndex)"),
               let shifted = bindings.buildLShr(state.builder, lhs: zeroExtended, rhs: amount, name: "iushr_s_\(instructionIndex)")
            {
                lowered = narrowTo32(shifted, name: "iushr")
            } else {
                lowered = nil
            }
        case "kk_op_lshl":
            // Kotlin `Long.shl`: shift distance is `rhs and 63` (64-bit result).
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lshl_amt_\(instructionIndex)")
            {
                lowered = bindings.buildShl(state.builder, lhs: lhs, rhs: amount, name: "lshl_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lshr":
            // Kotlin `Long.shr`: arithmetic shift by `rhs and 63`.
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lshr_amt_\(instructionIndex)")
            {
                lowered = bindings.buildAShr(state.builder, lhs: lhs, rhs: amount, name: "lshr_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lushr":
            // Kotlin `Long.ushr`: logical shift by `rhs and 63`.
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lushr_amt_\(instructionIndex)")
            {
                lowered = bindings.buildLShr(state.builder, lhs: lhs, rhs: amount, name: "lushr_\(instructionIndex)")
            } else {
                lowered = nil
            }
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

    // swiftlint:enable cyclomatic_complexity

    func emitConstantValue(
        _ expression: KIRExprKind,
        expressionRawID: Int32?,
        state: EmissionBuilderState,
        parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
        internalFunctions: [SymbolID: LLVMFunction],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        generatedStringLiteralCount: inout Int32,
        declareExternalFunction: (String, Int, Bool) -> LLVMFunction?,
        interner: StringInterner
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
            guard let globalStringPointer = bindings.buildGlobalStringPtrNullSafe(
                state.builder,
                context: state.context,
                module: state.module,
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
        case let .externSymbolAddress(symbolName):
            let symbolStr = interner.resolve(symbolName)
            if let externFn = declareExternalFunction(symbolStr, 4, false) {
                return bindings.buildPtrToInt(
                    state.builder,
                    value: externFn.value,
                    type: state.int64Type,
                    name: "extern_addr_\(symbolStr)"
                ) ?? state.zeroValue
            }
            return state.zeroValue
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
