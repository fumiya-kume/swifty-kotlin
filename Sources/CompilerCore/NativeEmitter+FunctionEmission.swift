import Foundation

extension NativeEmitter {
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction],
        diContext: DebugInfoContext? = nil
    ) throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        defer {
            // Clear debug location before disposing the builder.
            if diContext != nil {
                bindings.clearCurrentDebugLocation(builder)
            }
            bindings.disposeBuilder(builder)
        }

        // When debug info is active and the function has a subprogram,
        // set a dummy debug location (line 0) so the LLVM verifier accepts
        // all instructions emitted under this builder.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           bindings.debugLocationAvailable {
            if let loc = bindings.createDebugLocation(
                context: context,
                line: 0,
                column: 0,
                scope: subprogram
            ) {
                bindings.setCurrentDebugLocation(builder, location: loc)
            }
        }

        guard let entryBlock = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "entry") else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create entry block")
        }

        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        for instruction in function.body {
            guard case .label(let id) = instruction else {
                continue
            }
            if labelBlocks[id] != nil {
                continue
            }
            if let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "L\(id)") {
                labelBlocks[id] = block
            }
        }

        var parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        for (index, parameter) in function.params.enumerated() {
            guard let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index)) else {
                continue
            }
            parameterValues[parameter.symbol] = value
        }
        let outThrownParameter = bindings.getParam(
            function: llvmFunction.value,
            index: UInt32(function.params.count)
        )

        guard let zeroValue = bindings.constInt(int64Type, value: 0) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMConstInt returned null")
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        let nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        var currentBlock = entryBlock
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        var generatedStringLiteralCount: Int32 = 0
        let builderState = EmissionBuilderState(builder: builder, int64Type: int64Type, zeroValue: zeroValue)

        var copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        for instruction in function.body {
            if case .copy(_, let to) = instruction, copyTargetAllocas[to.rawValue] == nil {
                if let alloca = bindings.buildAlloca(builder, type: int64Type, name: "copy_slot_\(to.rawValue)") {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                    copyTargetAllocas[to.rawValue] = alloca
                }
            }
        }

        func declareExternalFunction(
            named calleeName: String,
            argumentCount: Int,
            appendThrownChannel: Bool
        ) -> LLVMFunction? {
            if let existing = externalFunctions[calleeName] {
                return existing
            }
            var callParameterTypes = Array(repeating: int64Type, count: argumentCount)
            if appendThrownChannel {
                callParameterTypes.append(outThrownPointerType)
            }
            guard let externalType = bindings.functionType(
                returnType: int64Type,
                parameters: callParameterTypes,
                isVarArg: false
            ) else {
                return nil
            }
            let externalValue = bindings.getNamedFunction(module: llvmModule, name: calleeName)
                ?? bindings.addFunction(module: llvmModule, name: calleeName, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            let declared = LLVMFunction(value: externalValue, type: externalType)
            externalFunctions[calleeName] = declared
            return declared
        }

        func valueForConstant(_ expression: KIRExprKind, expressionRawID: Int32?) -> LLVMCAPIBindings.LLVMValueRef {
            emitConstantValue(
                expression,
                expressionRawID: expressionRawID,
                state: builderState,
                parameterValues: parameterValues,
                internalFunctions: internalFunctions,
                generatedStringLiteralCount: &generatedStringLiteralCount,
                declareExternalFunction: { name, argCount, appendThrown in
                    declareExternalFunction(named: name, argumentCount: argCount, appendThrownChannel: appendThrown)
                }
            )
        }

        func resolveValue(_ id: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef {
            if let alloca = copyTargetAllocas[id.rawValue] {
                return bindings.buildLoad(builder, type: int64Type, pointer: alloca, name: "load_\(id.rawValue)") ?? zeroValue
            }
            if let value = values[id.rawValue] {
                return value
            }
            if let expression = module.arena.expr(id) {
                let constant = valueForConstant(expression, expressionRawID: id.rawValue)
                values[id.rawValue] = constant
                return constant
            }
            return zeroValue
        }

        func storeResult(_ result: KIRExprID?, _ value: LLVMCAPIBindings.LLVMValueRef?) {
            guard let result else {
                return
            }
            values[result.rawValue] = value ?? zeroValue
        }

        func blockForLabel(_ label: Int32) -> LLVMCAPIBindings.LLVMBasicBlockRef? {
            if let block = labelBlocks[label] {
                return block
            }
            let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "L\(label)")
            if let block {
                labelBlocks[label] = block
            }
            return block
        }

        func buildBoolCondition(
            from value: LLVMCAPIBindings.LLVMValueRef,
            name: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            bindings.buildICmpNotEqual(builder, lhs: value, rhs: zeroValue, name: name)
        }

        func storeOutThrownIfNonNull(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) {
            guard let outThrownParameter,
                  let pointerIsNonNull = bindings.buildICmpNotEqual(
                    builder,
                    lhs: outThrownParameter,
                    rhs: nullThrownPointer,
                    name: "out_nonnull_\(suffix)"
                  ),
                  let storeBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "out_store_\(suffix)"
                  ),
                  let continueBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "out_cont_\(suffix)"
                  ) else {
                return
            }

            _ = bindings.buildCondBr(
                builder,
                condition: pointerIsNonNull,
                thenBlock: storeBlock,
                elseBlock: continueBlock
            )

            bindings.positionBuilder(builder, at: storeBlock)
            _ = bindings.buildStore(builder, value: value, pointer: outThrownParameter)
            _ = bindings.buildBr(builder, destination: continueBlock)

            currentBlock = continueBlock
            bindings.positionBuilder(builder, at: continueBlock)
        }

        let frameRegisterFunction = declareExternalFunction(
            named: "kk_register_frame_map",
            argumentCount: 2,
            appendThrownChannel: false
        )
        let framePushFunction = declareExternalFunction(
            named: "kk_push_frame",
            argumentCount: 2,
            appendThrownChannel: false
        )
        let framePopFunction = declareExternalFunction(
            named: "kk_pop_frame",
            argumentCount: 0,
            appendThrownChannel: false
        )
        let coroutineRegisterRootFunction = declareExternalFunction(
            named: "kk_register_coroutine_root",
            argumentCount: 1,
            appendThrownChannel: false
        )
        let coroutineUnregisterRootFunction = declareExternalFunction(
            named: "kk_unregister_coroutine_root",
            argumentCount: 1,
            appendThrownChannel: false
        )
        let functionIDValue = bindings.constInt(
            int64Type,
            value: UInt64(bitPattern: Int64(max(0, function.symbol.rawValue))),
            signExtend: false
        ) ?? zeroValue

        func emitFramePop(_ suffix: String) {
            guard let framePopFunction else {
                return
            }
            _ = bindings.buildCall(
                builder,
                functionType: framePopFunction.type,
                callee: framePopFunction.value,
                arguments: [],
                name: "frame_pop_\(suffix)"
            )
        }

        if let frameRegisterFunction {
            _ = bindings.buildCall(
                builder,
                functionType: frameRegisterFunction.type,
                callee: frameRegisterFunction.value,
                arguments: [functionIDValue, zeroValue],
                name: "frame_register"
            )
        }
        if let framePushFunction {
            _ = bindings.buildCall(
                builder,
                functionType: framePushFunction.type,
                callee: framePushFunction.value,
                arguments: [functionIDValue, zeroValue],
                name: "frame_push"
            )
        }
        storeOutThrownIfNonNull(zeroValue, suffix: "entry")

        func emitBuiltinCall(
            calleeName: String,
            argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            result: KIRExprID?,
            instructionIndex: Int
        ) -> Bool {
            let builtinResult = lowerBuiltinCall(
                calleeName: calleeName,
                argumentValues: argumentValues,
                state: builderState,
                instructionIndex: instructionIndex
            )
            guard builtinResult.handled else {
                return false
            }
            storeResult(result, builtinResult.value)
            return true
        }

        for (instructionIndex, instruction) in function.body.enumerated() {
            switch instruction {
            case .nop, .beginBlock, .endBlock:
                continue

            case .label(let id):
                guard let destination = blockForLabel(id) else {
                    continue
                }
                if !bindings.hasTerminator(currentBlock) {
                    _ = bindings.buildBr(builder, destination: destination)
                }
                currentBlock = destination
                bindings.positionBuilder(builder, at: destination)

            case .jump(let target):
                guard !bindings.hasTerminator(currentBlock),
                      let destination = blockForLabel(target) else {
                    continue
                }
                _ = bindings.buildBr(builder, destination: destination)

            case .jumpIfEqual(let lhs, let rhs, let target):
                guard !bindings.hasTerminator(currentBlock),
                      let thenBlock = blockForLabel(target),
                      let continueBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "if_cont_\(instructionIndex)"
                      ) else {
                    continue
                }
                let condition = bindings.buildICmpEqual(
                    builder,
                    lhs: resolveValue(lhs),
                    rhs: resolveValue(rhs),
                    name: "if_cmp_\(instructionIndex)"
                )
                _ = bindings.buildCondBr(
                    builder,
                    condition: condition,
                    thenBlock: thenBlock,
                    elseBlock: continueBlock
                )
                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)

            case .constValue(let result, let value):
                values[result.rawValue] = valueForConstant(value, expressionRawID: result.rawValue)

            case .binary(let op, let lhs, let rhs, let result):
                let lhsValue = resolveValue(lhs)
                let rhsValue = resolveValue(rhs)
                let lowered: LLVMCAPIBindings.LLVMValueRef?
                switch op {
                case .add:
                    lowered = bindings.buildAdd(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_add_\(instructionIndex)")
                case .subtract:
                    lowered = bindings.buildSub(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_sub_\(instructionIndex)")
                case .multiply:
                    lowered = bindings.buildMul(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mul_\(instructionIndex)")
                case .divide:
                    lowered = bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_div_\(instructionIndex)")
                case .modulo:
                    if let quotient = bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mod_q_\(instructionIndex)"),
                       let product = bindings.buildMul(builder, lhs: quotient, rhs: rhsValue, name: "bin_mod_p_\(instructionIndex)") {
                        lowered = bindings.buildSub(builder, lhs: lhsValue, rhs: product, name: "bin_mod_\(instructionIndex)")
                    } else {
                        lowered = nil
                    }
                case .equal:
                    if let compared = bindings.buildICmpEqual(
                        builder,
                        lhs: lhsValue,
                        rhs: rhsValue,
                        name: "bin_eq_\(instructionIndex)"
                    ) {
                        lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "bin_eq64_\(instructionIndex)")
                    } else {
                        lowered = nil
                    }
                case .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                    lowered = nil
                case .logicalAnd, .logicalOr:
                    lowered = nil
                }
                storeResult(result, lowered)

            case .unary(_, let operand, let result):
                storeResult(result, resolveValue(operand))

            case .nullAssert(let operand, let result):
                storeResult(result, resolveValue(operand))

            case .call(let symbol, let callee, let arguments, let result, let usesThrownChannel, let thrownResult):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = arguments.map(resolveValue)

                if calleeName == "println" || calleeName == "kk_println_any" {
                    let printValue = argumentValues.first ?? zeroValue
                    if let printFunction = declareExternalFunction(
                        named: "kk_println_any",
                        argumentCount: 1,
                        appendThrownChannel: false
                    ) {
                        _ = bindings.buildCall(
                            builder,
                            functionType: printFunction.type,
                            callee: printFunction.value,
                            arguments: [printValue],
                            name: "println_\(instructionIndex)"
                        )
                    }
                    storeResult(result, zeroValue)
                    continue
                }

                if emitBuiltinCall(
                    calleeName: calleeName,
                    argumentValues: argumentValues,
                    result: result,
                    instructionIndex: instructionIndex
                ) {
                    continue
                }

                let calleeFunction: LLVMFunction?
                let isInternalCall = symbol.flatMap { internalFunctions[$0] } != nil
                let shouldAppendThrownChannel = usesThrownChannel || isInternalCall

                if let symbol,
                   let internalFunction = internalFunctions[symbol] {
                    calleeFunction = internalFunction
                } else if calleeName.isEmpty {
                    calleeFunction = nil
                } else {
                    calleeFunction = declareExternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: shouldAppendThrownChannel
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                var callArguments = argumentValues
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef? = nil
                if shouldAppendThrownChannel {
                    if usesThrownChannel {
                        let thrownSlot = bindings.buildAlloca(
                            builder,
                            type: int64Type,
                            name: "thrown_slot_\(instructionIndex)"
                        )
                        if let thrownSlot {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                            callArguments.append(thrownSlot)
                            thrownSlotPointer = thrownSlot
                        } else {
                            callArguments.append(nullThrownPointer)
                        }
                    } else {
                        callArguments.append(nullThrownPointer)
                    }
                }

                let callValue = bindings.buildCall(
                    builder,
                    functionType: calleeFunction.type,
                    callee: calleeFunction.value,
                    arguments: callArguments,
                    name: "call_\(instructionIndex)"
                )
                storeResult(result, callValue)
                if calleeName == "kk_coroutine_continuation_new",
                   let coroutineRegisterRootFunction {
                    _ = bindings.buildCall(
                        builder,
                        functionType: coroutineRegisterRootFunction.type,
                        callee: coroutineRegisterRootFunction.value,
                        arguments: [callValue ?? zeroValue],
                        name: "coroutine_root_register_\(instructionIndex)"
                    )
                }
                if calleeName == "kk_coroutine_state_exit",
                   let coroutineUnregisterRootFunction {
                    _ = bindings.buildCall(
                        builder,
                        functionType: coroutineUnregisterRootFunction.type,
                        callee: coroutineUnregisterRootFunction.value,
                        arguments: [argumentValues.first ?? zeroValue],
                        name: "coroutine_root_unregister_\(instructionIndex)"
                    )
                }
                if usesThrownChannel,
                   let thrownSlotPointer,
                   let thrownValue = bindings.buildLoad(
                    builder,
                    type: int64Type,
                    pointer: thrownSlotPointer,
                    name: "thrown_val_\(instructionIndex)"
                   ) {
                    if let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, thrownValue)
                        }
                    } else if let hasThrown = buildBoolCondition(
                        from: thrownValue,
                        name: "has_thrown_\(instructionIndex)"
                    ),
                    let thrownBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "thrown_\(instructionIndex)"
                    ),
                    let continueBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "call_cont_\(instructionIndex)"
                    ) {
                        _ = bindings.buildCondBr(
                            builder,
                            condition: hasThrown,
                            thenBlock: thrownBlock,
                            elseBlock: continueBlock
                        )

                        bindings.positionBuilder(builder, at: thrownBlock)
                        storeOutThrownIfNonNull(thrownValue, suffix: "throw_\(instructionIndex)")
                        emitFramePop("throw_\(instructionIndex)")
                        _ = bindings.buildRet(builder, value: zeroValue)

                        currentBlock = continueBlock
                        bindings.positionBuilder(builder, at: continueBlock)
                    }
                }

            case .jumpIfNotNull(let value, let target):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                if let condition = buildBoolCondition(from: resolved, name: "jnn_cond_\(instructionIndex)"),
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "jnn_cont_\(instructionIndex)"
                   ) {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                }

            case .copy(let from, let to):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let copySource = resolveValue(from)
                if let alloca = copyTargetAllocas[to.rawValue] {
                    _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
                } else {
                    storeResult(to, copySource)
                }

            case .rethrow(let value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
                emitFramePop("rethrow_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroValue)

            case .returnIfEqual(let lhs, let rhs):
                guard !bindings.hasTerminator(currentBlock),
                      let trueBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "ret_if_true_\(instructionIndex)"
                      ),
                      let falseBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "ret_if_false_\(instructionIndex)"
                      ) else {
                    continue
                }

                let lhsValue = resolveValue(lhs)
                let rhsValue = resolveValue(rhs)
                let condition = bindings.buildICmpEqual(builder, lhs: lhsValue, rhs: rhsValue, name: "ret_if_cmp_\(instructionIndex)")
                _ = bindings.buildCondBr(builder, condition: condition, thenBlock: trueBlock, elseBlock: falseBlock)

                bindings.positionBuilder(builder, at: trueBlock)
                emitFramePop("ret_if_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: lhsValue)

                currentBlock = falseBlock
                bindings.positionBuilder(builder, at: falseBlock)

            case .returnUnit:
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                emitFramePop("ret_unit_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroValue)

            case .returnValue(let value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                emitFramePop("ret_val_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: resolveValue(value))
            }
        }

        if !bindings.hasTerminator(currentBlock) {
            emitFramePop("ret_fallthrough")
            _ = bindings.buildRet(builder, value: zeroValue)
        }
    }
}
