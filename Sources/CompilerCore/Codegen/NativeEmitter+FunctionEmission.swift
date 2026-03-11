// swiftlint:disable file_length
import Foundation

extension NativeEmitter {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        diContext: DebugInfoContext? = nil
    ) throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        defer {
            // Clear debug location before disposing the builder.
            if diContext != nil {
                bindings.clearCurrentDebugLocation(builder)
            }
            bindings.disposeBuilder(builder)
        }

        // When debug info is active and the function has a subprogram,
        // set the function-level debug location so the LLVM verifier accepts
        // all instructions emitted under this builder.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            var funcCol: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                let lc = sm.lineColumn(of: sourceRange.start)
                funcLine = UInt32(lc.line)
                funcCol = UInt32(lc.column)
            }
            if let loc = bindings.createDebugLocation(
                context: context,
                line: funcLine,
                column: funcCol,
                scope: subprogram
            ) {
                bindings.setCurrentDebugLocation(builder, location: loc)
            }
        }

        guard let entryBlock = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "entry") else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create entry block")
        }

        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        for instruction in function.body {
            guard case let .label(id) = instruction else {
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

        // Position builder at the entry block before emitting parameter debug
        // info (alloca/store require a valid insert point).
        bindings.positionBuilder(builder, at: entryBlock)

        // Emit DILocalVariable + dbg.declare for each parameter when debug
        // info is active and the required bindings are available.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           let int64DIType = diContext.int64DIType,
           bindings.localVariableAvailable,
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                funcLine = UInt32(sm.lineColumn(of: sourceRange.start).line)
            }
            let funcDIFile: LLVMCAPIBindings.LLVMMetadataRef? = {
                if let sourceRange = function.sourceRange {
                    return diContext.diFiles[sourceRange.start.file] ?? diContext.file
                }
                return diContext.file
            }()
            let emptyExpr = bindings.diBuilderCreateExpression(diContext.diBuilder)
            for (index, parameter) in function.params.enumerated() {
                guard let paramValue = parameterValues[parameter.symbol] else {
                    continue
                }
                let paramName = "arg\(index)"
                guard let diVar = bindings.diBuilderCreateParameterVariable(
                    diContext.diBuilder,
                    scope: subprogram,
                    name: paramName,
                    argNo: UInt32(index + 1),
                    file: funcDIFile,
                    lineNo: funcLine,
                    type: int64DIType
                ) else {
                    continue
                }
                // Create an alloca for the parameter so dbg.declare can reference it.
                let paramAlloca = bindings.buildAlloca(builder, type: int64Type, name: "dbg_\(paramName)")
                if let paramAlloca {
                    _ = bindings.buildStore(builder, value: paramValue, pointer: paramAlloca)
                    if let debugLoc = bindings.createDebugLocation(
                        context: context, line: funcLine, column: 0, scope: subprogram
                    ) {
                        _ = bindings.diBuilderInsertDeclareAtEnd(
                            diContext.diBuilder,
                            storage: paramAlloca,
                            varInfo: diVar,
                            expr: emptyExpr,
                            debugLoc: debugLoc,
                            block: entryBlock
                        )
                    }
                }
            }
        }
        let outThrownParameter = bindings.getParam(
            function: llvmFunction.value,
            index: UInt32(function.params.count)
        )

        guard let zeroValue = bindings.constInt(int64Type, value: 0) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMConstInt returned null")
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        let nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        var currentBlock = entryBlock
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        var generatedStringLiteralCount: Int32 = 0
        let builderState = EmissionBuilderState(builder: builder, int64Type: int64Type, zeroValue: zeroValue)

        func assignmentTargets(for instruction: KIRInstruction) -> [KIRExprID] {
            switch instruction {
            case let .constValue(result, _):
                return [result]
            case let .binary(_, _, _, result):
                return [result]
            case let .unary(_, _, result):
                return [result]
            case let .nullAssert(_, result):
                return [result]
            case let .call(_, _, _, result, _, thrownResult, _):
                let directTargets = result.map { [$0] } ?? []
                let thrownTargets = thrownResult.map { [$0] } ?? []
                return directTargets + thrownTargets
            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                let directTargets = result.map { [$0] } ?? []
                let thrownTargets = thrownResult.map { [$0] } ?? []
                return directTargets + thrownTargets
            case let .copy(_, to):
                return [to]
            case let .loadGlobal(result, _):
                return [result]
            case .jump, .label, .jumpIfEqual, .jumpIfNotNull,
                 .storeGlobal, .rethrow, .returnIfEqual, .returnUnit, .returnValue,
                 .beginBlock, .endBlock, .nop:
                return []
            }
        }

        var assignmentTargetCounts: [Int32: Int] = [:]
        for instruction in function.body {
            for target in assignmentTargets(for: instruction) {
                assignmentTargetCounts[target.rawValue, default: 0] += 1
            }
        }

        let shouldSpillID = Set(assignmentTargetCounts.filter { $0.value > 1 }.map(\.key))

        var copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        for instruction in function.body {
            for target in assignmentTargets(for: instruction) where shouldSpillID.contains(target.rawValue) {
                if copyTargetAllocas[target.rawValue] == nil,
                   let alloca = bindings.buildAlloca(builder, type: int64Type, name: "copy_slot_\(target.rawValue)")
                {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                    copyTargetAllocas[target.rawValue] = alloca
                }
            }
        }

        func declareExternalFunction(
            named calleeName: String,
            argumentCount: Int,
            appendThrownChannel: Bool
        ) -> LLVMFunction? {
            // String.length extension: redirect "length" (1 arg = receiver) to kk_string_length.
            // Lambda bodies may reach codegen with callee "length" when receiver type is not
            // available during KIR lowering (e.g. mapIndexed { _, v -> v.length }).
            let effectiveName: String = if calleeName == "length", argumentCount == 1, !appendThrownChannel {
                "kk_string_length"
            } else {
                calleeName
            }
            if let existing = externalFunctions[effectiveName] {
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
            let externalValue = bindings.getNamedFunction(module: llvmModule, name: effectiveName)
                ?? bindings.addFunction(module: llvmModule, name: effectiveName, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            let declared = LLVMFunction(value: externalValue, type: externalType)
            externalFunctions[effectiveName] = declared
            return declared
        }

        func resolveUnnamedInternalFunction(
            named calleeName: String,
            argumentCount: Int,
            appendThrownChannel: Bool
        ) -> (symbol: SymbolID, function: LLVMFunction)? {
            var match: (symbol: SymbolID, function: LLVMFunction)?
            let expectedParameterCount = argumentCount + (appendThrownChannel ? 1 : 0)
            for declaration in module.arena.declarations {
                guard case let .function(candidate) = declaration,
                      interner.resolve(candidate.name) == calleeName,
                      candidate.params.count == expectedParameterCount,
                      let llvmFunction = internalFunctions[candidate.symbol]
                else {
                    continue
                }
                if match != nil {
                    return nil
                }
                match = (candidate.symbol, llvmFunction)
            }
            return match
        }

        func valueForConstant(_ expression: KIRExprKind, expressionRawID: Int32?) -> LLVMCAPIBindings.LLVMValueRef {
            emitConstantValue(
                expression,
                expressionRawID: expressionRawID,
                state: builderState,
                parameterValues: parameterValues,
                internalFunctions: internalFunctions,
                globalVariables: globalVariables,
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
            let storedValue = value ?? zeroValue
            if let resultExpr = module.arena.expr(result),
               case let .symbolRef(targetSymbol) = resultExpr,
               let globalPointer = globalVariables[targetSymbol]
            {
                _ = bindings.buildStore(builder, value: storedValue, pointer: globalPointer)
            }
            if let alloca = copyTargetAllocas[result.rawValue] {
                _ = bindings.buildStore(builder, value: storedValue, pointer: alloca)
            }
            values[result.rawValue] = storedValue
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
            let normalizedValue: LLVMCAPIBindings.LLVMValueRef = if let unboxBool = declareExternalFunction(
                named: "kk_unbox_bool",
                argumentCount: 1,
                appendThrownChannel: false
            ),
                let unboxed = bindings.buildCall(
                    builder,
                    functionType: unboxBool.type,
                    callee: unboxBool.value,
                    arguments: [value],
                    name: "\(name)_unboxed"
                )
            {
                unboxed
            } else {
                value
            }
            return bindings.buildICmpNotEqual(builder, lhs: normalizedValue, rhs: zeroValue, name: name)
        }

        /// Builds a condition for exception-thrown slot checks. Does NOT call kk_unbox_bool;
        /// thrown slots hold raw integers (0 = no exception, non-zero = exception).
        func buildThrownSlotCondition(
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
                  )
            else {
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
            // Update debug location per-instruction when debug info is active.
            if let diContext,
               let subprogram = diContext.subprograms[function.symbol],
               bindings.debugLocationAvailable
            {
                var instrLine: UInt32 = 0
                var instrCol: UInt32 = 0
                // Try per-instruction source location first, then fall back to
                // function-level source range. Only use per-instruction locations
                // when the parallel array is in sync with body (same count).
                if function.instructionLocations.count == function.body.count,
                   instructionIndex < function.instructionLocations.count,
                   let instrRange = function.instructionLocations[instructionIndex],
                   let sm = sourceManager
                {
                    let lc = sm.lineColumn(of: instrRange.start)
                    instrLine = UInt32(lc.line)
                    instrCol = UInt32(lc.column)
                } else if let sourceRange = function.sourceRange, let sm = sourceManager {
                    let lc = sm.lineColumn(of: sourceRange.start)
                    instrLine = UInt32(lc.line)
                    instrCol = UInt32(lc.column)
                }
                if instrLine > 0,
                   let loc = bindings.createDebugLocation(
                       context: context,
                       line: instrLine,
                       column: instrCol,
                       scope: subprogram
                   )
                {
                    bindings.setCurrentDebugLocation(builder, location: loc)
                }
            }

            switch instruction {
            case .nop, .beginBlock, .endBlock:
                continue

            case let .label(id):
                guard let destination = blockForLabel(id) else {
                    continue
                }
                if !bindings.hasTerminator(currentBlock) {
                    _ = bindings.buildBr(builder, destination: destination)
                }
                currentBlock = destination
                bindings.positionBuilder(builder, at: destination)

            case let .jump(target):
                guard !bindings.hasTerminator(currentBlock),
                      let destination = blockForLabel(target)
                else {
                    continue
                }
                _ = bindings.buildBr(builder, destination: destination)

            case let .jumpIfEqual(lhs, rhs, target):
                guard !bindings.hasTerminator(currentBlock),
                      let thenBlock = blockForLabel(target),
                      let continueBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "if_cont_\(instructionIndex)"
                      )
                else {
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

            case let .constValue(result, value):
                let constLLVMValue = valueForConstant(value, expressionRawID: result.rawValue)
                storeResult(result, constLLVMValue)

                // Emit DIAutoVariable + dbg.declare for local variable bindings
                // when debug info is active. We detect local variables by looking
                // for symbolRef values that have a corresponding symbol name.
                if let diContext,
                   let subprogram = diContext.subprograms[function.symbol],
                   let int64DIType = diContext.int64DIType,
                   bindings.localVariableAvailable,
                   bindings.debugLocationAvailable,
                   case let .symbolRef(localSymbol) = value,
                   !parameterValues.keys.contains(localSymbol)
                {
                    let varName = "local_\(localSymbol.rawValue)"
                    var varLine: UInt32 = 0
                    if function.instructionLocations.count == function.body.count,
                       instructionIndex < function.instructionLocations.count,
                       let instrRange = function.instructionLocations[instructionIndex],
                       let srcMgr = sourceManager
                    {
                        varLine = UInt32(srcMgr.lineColumn(of: instrRange.start).line)
                    } else if let sourceRange = function.sourceRange, let srcMgr = sourceManager {
                        varLine = UInt32(srcMgr.lineColumn(of: sourceRange.start).line)
                    }
                    let varDIFile: LLVMCAPIBindings.LLVMMetadataRef? = {
                        if function.instructionLocations.count == function.body.count,
                           instructionIndex < function.instructionLocations.count,
                           let instrRange = function.instructionLocations[instructionIndex]
                        {
                            return diContext.diFiles[instrRange.start.file] ?? diContext.file
                        }
                        return diContext.file
                    }()
                    if let diVar = bindings.diBuilderCreateAutoVariable(
                        diContext.diBuilder,
                        scope: subprogram,
                        name: varName,
                        file: varDIFile,
                        lineNo: varLine,
                        type: int64DIType
                    ) {
                        let emptyExpr = bindings.diBuilderCreateExpression(diContext.diBuilder)
                        // Use the copy-target alloca if one exists (the copy instruction
                        // will store the real value there), otherwise fall back to a
                        // dedicated debug alloca with the current (possibly zero) value.
                        let localAlloca = copyTargetAllocas[result.rawValue]
                            ?? bindings.buildAlloca(builder, type: int64Type, name: "dbg_\(varName)")
                        if let localAlloca {
                            if copyTargetAllocas[result.rawValue] == nil {
                                _ = bindings.buildStore(builder, value: constLLVMValue, pointer: localAlloca)
                            }
                            if let debugLoc = bindings.createDebugLocation(
                                context: context, line: varLine, column: 0, scope: subprogram
                            ) {
                                _ = bindings.diBuilderInsertDeclareAtEnd(
                                    diContext.diBuilder,
                                    storage: localAlloca,
                                    varInfo: diVar,
                                    expr: emptyExpr,
                                    debugLoc: debugLoc,
                                    block: currentBlock
                                )
                            }
                        }
                    }
                }

            case let .binary(op, lhs, rhs, result):
                let lhsValue = resolveValue(lhs)
                let rhsValue = resolveValue(rhs)
                let lowered: LLVMCAPIBindings.LLVMValueRef? = switch op {
                case .add:
                    bindings.buildAdd(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_add_\(instructionIndex)")
                case .subtract:
                    bindings.buildSub(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_sub_\(instructionIndex)")
                case .multiply:
                    bindings.buildMul(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mul_\(instructionIndex)")
                case .divide:
                    bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_div_\(instructionIndex)")
                case .modulo:
                    if let quotient = bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mod_q_\(instructionIndex)"),
                       let product = bindings.buildMul(builder, lhs: quotient, rhs: rhsValue, name: "bin_mod_p_\(instructionIndex)")
                    {
                        bindings.buildSub(builder, lhs: lhsValue, rhs: product, name: "bin_mod_\(instructionIndex)")
                    } else {
                        nil
                    }
                case .equal:
                    if let compared = bindings.buildICmpEqual(
                        builder,
                        lhs: lhsValue,
                        rhs: rhsValue,
                        name: "bin_eq_\(instructionIndex)"
                    ) {
                        bindings.buildZExt(builder, value: compared, type: int64Type, name: "bin_eq64_\(instructionIndex)")
                    } else {
                        nil
                    }
                case .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                    nil
                case .logicalAnd, .logicalOr:
                    nil
                }
                storeResult(result, lowered)

            case let .unary(_, operand, result):
                storeResult(result, resolveValue(operand))

            case let .nullAssert(operand, result):
                let operandValue = resolveValue(operand)
                if let notNullFunc = declareExternalFunction(
                    named: "kk_op_notnull",
                    argumentCount: 1,
                    appendThrownChannel: true
                ) {
                    let thrownSlot = bindings.buildAlloca(
                        builder,
                        type: int64Type,
                        name: "notnull_thrown_\(instructionIndex)"
                    )
                    if let thrownSlot {
                        _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                        let callValue = bindings.buildCall(
                            builder,
                            functionType: notNullFunc.type,
                            callee: notNullFunc.value,
                            arguments: [operandValue, thrownSlot],
                            name: "notnull_\(instructionIndex)"
                        )
                        storeResult(result, callValue)
                        if let thrownValue = bindings.buildLoad(
                            builder,
                            type: int64Type,
                            pointer: thrownSlot,
                            name: "notnull_thrown_val_\(instructionIndex)"
                        ),
                            let hasThrown = buildThrownSlotCondition(
                                from: thrownValue,
                                name: "notnull_has_thrown_\(instructionIndex)"
                            ),
                            let thrownBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "notnull_thrown_\(instructionIndex)"
                            ),
                            let continueBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "notnull_cont_\(instructionIndex)"
                            )
                        {
                            _ = bindings.buildCondBr(
                                builder,
                                condition: hasThrown,
                                thenBlock: thrownBlock,
                                elseBlock: continueBlock
                            )
                            bindings.positionBuilder(builder, at: thrownBlock)
                            storeOutThrownIfNonNull(thrownValue, suffix: "notnull_throw_\(instructionIndex)")
                            emitFramePop("notnull_throw_\(instructionIndex)")
                            _ = bindings.buildRet(builder, value: zeroValue)
                            currentBlock = continueBlock
                            bindings.positionBuilder(builder, at: continueBlock)
                        }
                    } else {
                        storeResult(result, operandValue)
                    }
                } else {
                    storeResult(result, operandValue)
                }

            case let .call(symbol, callee, arguments, result, usesThrownChannel, thrownResult, isSuperCall):
                // super calls always use direct dispatch – when virtual dispatch
                // is introduced the isSuperCall flag will bypass vtable lookup.
                _ = isSuperCall
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = arguments.map(resolveValue)

                if calleeName == "kk_println_newline" {
                    if let printFunction = declareExternalFunction(
                        named: "kk_println_newline",
                        argumentCount: 0,
                        appendThrownChannel: false
                    ) {
                        _ = bindings.buildCall(
                            builder,
                            functionType: printFunction.type,
                            callee: printFunction.value,
                            arguments: [],
                            name: "println_newline_\(instructionIndex)"
                        )
                    }
                    if usesThrownChannel, let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, zeroValue)
                        }
                    }
                    storeResult(result, zeroValue)
                    continue
                }

                if calleeName == "kk_println_float" || calleeName == "kk_println_double"
                    || calleeName == "kk_println_long" || calleeName == "kk_println_char"
                    || calleeName == "kk_println_bool"
                {
                    let printValue = argumentValues.first ?? zeroValue
                    if let printFunction = declareExternalFunction(
                        named: calleeName,
                        argumentCount: 1,
                        appendThrownChannel: false
                    ) {
                        _ = bindings.buildCall(
                            builder,
                            functionType: printFunction.type,
                            callee: printFunction.value,
                            arguments: [printValue],
                            name: "println_\(calleeName)_\(instructionIndex)"
                        )
                    }
                    if usesThrownChannel, let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, zeroValue)
                        }
                    }
                    storeResult(result, zeroValue)
                    continue
                }

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
                    if usesThrownChannel, let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, zeroValue)
                        }
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

                let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let calleeFunction: LLVMFunction?
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let shouldAppendThrownChannel = usesThrownChannel || isInternalCall

                if let effectiveSymbol,
                   let internalFunction = internalFunctions[effectiveSymbol]
                {
                    calleeFunction = internalFunction
                } else if let fallbackInternal {
                    calleeFunction = fallbackInternal.function
                } else if calleeName.isEmpty {
                    calleeFunction = nil
                } else if calleeName == "length", argumentValues.count == 1 {
                    calleeFunction = declareExternalFunction(
                        named: "kk_string_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
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
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
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
                   let coroutineRegisterRootFunction
                {
                    _ = bindings.buildCall(
                        builder,
                        functionType: coroutineRegisterRootFunction.type,
                        callee: coroutineRegisterRootFunction.value,
                        arguments: [callValue ?? zeroValue],
                        name: "coroutine_root_register_\(instructionIndex)"
                    )
                }
                if calleeName == "kk_coroutine_state_exit",
                   let coroutineUnregisterRootFunction
                {
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
                   )
                {
                    if let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, thrownValue)
                        }
                    } else if let hasThrown = buildThrownSlotCondition(
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
                        )
                    {
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

            case let .virtualCall(symbol, callee, receiver, arguments, result, usesThrownChannel, thrownResult, dispatch):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = [resolveValue(receiver)] + arguments.map(resolveValue)

                let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let shouldAppendThrownChannel = usesThrownChannel || isInternalCall

                let calleeFunction: LLVMFunction? = if let effectiveSymbol,
                                                       let internalFunction = internalFunctions[effectiveSymbol]
                {
                    internalFunction
                } else if let fallbackInternal {
                    fallbackInternal.function
                } else if calleeName.isEmpty {
                    nil
                } else if calleeName == "length", argumentValues.count == 1 {
                    declareExternalFunction(
                        named: "kk_string_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
                } else {
                    declareExternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: shouldAppendThrownChannel
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                let lookupFunction: LLVMFunction?
                var lookupArgs: [LLVMCAPIBindings.LLVMValueRef] = []
                switch dispatch {
                case let .vtable(slot):
                    lookupFunction = declareExternalFunction(named: "kk_vtable_lookup", argumentCount: 2, appendThrownChannel: false)
                    lookupArgs = [
                        resolveValue(receiver),
                        bindings.constInt(int64Type, value: UInt64(slot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                case let .itable(interfaceSlot, methodSlot):
                    lookupFunction = declareExternalFunction(named: "kk_itable_lookup", argumentCount: 3, appendThrownChannel: false)
                    lookupArgs = [
                        resolveValue(receiver),
                        bindings.constInt(int64Type, value: UInt64(interfaceSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                        bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                }

                guard let lookupFn = lookupFunction else { continue }
                guard let fptrRaw = bindings.buildCall(
                    builder,
                    functionType: lookupFn.type,
                    callee: lookupFn.value,
                    arguments: lookupArgs,
                    name: "lookup_raw_\(instructionIndex)"
                ) else { continue }

                // Guard against null vtable/itable lookup: if fptrRaw == 0
                // fall back to the direct callee function.
                let isNonNull = bindings.buildICmpNotEqual(
                    builder,
                    lhs: fptrRaw,
                    rhs: zeroValue,
                    name: "lookup_nonnull_\(instructionIndex)"
                )
                let useVirtualBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "lookup_ok_\(instructionIndex)"
                )
                let fallbackBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "lookup_fallback_\(instructionIndex)"
                )
                let mergeBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "vcall_merge_\(instructionIndex)"
                )

                if let isNonNull, let useVirtualBlock, let fallbackBlock, let mergeBlock {
                    _ = bindings.buildCondBr(
                        builder,
                        condition: isNonNull,
                        thenBlock: useVirtualBlock,
                        elseBlock: fallbackBlock
                    )
                    // Virtual dispatch path: use the looked-up function pointer.
                    bindings.positionBuilder(builder, at: useVirtualBlock)
                    let functionPointerType = bindings.pointerType(calleeFunction.type)
                    let fptr = bindings.buildIntToPtr(
                        builder,
                        value: fptrRaw,
                        type: functionPointerType,
                        name: "lookup_fptr_\(instructionIndex)"
                    )

                    var callArguments = argumentValues
                    var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                    if shouldAppendThrownChannel {
                        if usesThrownChannel {
                            let thrownSlot = bindings.buildAlloca(
                                builder,
                                type: int64Type,
                                name: "vthrown_slot_\(instructionIndex)"
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

                    let vCallValue = bindings.buildCall(
                        builder,
                        functionType: calleeFunction.type,
                        callee: fptr ?? calleeFunction.value,
                        arguments: callArguments,
                        name: "vcall_\(instructionIndex)"
                    )
                    _ = bindings.buildBr(builder, destination: mergeBlock)

                    // Fallback path: use the direct callee.
                    bindings.positionBuilder(builder, at: fallbackBlock)
                    var fbCallArguments = argumentValues
                    if shouldAppendThrownChannel {
                        if usesThrownChannel {
                            let thrownSlot = bindings.buildAlloca(
                                builder,
                                type: int64Type,
                                name: "vthrown_slot_fb_\(instructionIndex)"
                            )
                            if let thrownSlot {
                                _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                                fbCallArguments.append(thrownSlot)
                            } else {
                                fbCallArguments.append(nullThrownPointer)
                            }
                        } else {
                            fbCallArguments.append(nullThrownPointer)
                        }
                    }
                    let fbCallValue = bindings.buildCall(
                        builder,
                        functionType: calleeFunction.type,
                        callee: calleeFunction.value,
                        arguments: fbCallArguments,
                        name: "vcall_fb_\(instructionIndex)"
                    )
                    _ = bindings.buildBr(builder, destination: mergeBlock)

                    // Merge: pick whichever call was taken via PHI.
                    bindings.positionBuilder(builder, at: mergeBlock)
                    currentBlock = mergeBlock
                    // Use the virtual call result as the canonical value
                    // (both paths produce the same type).
                    let mergedValue = vCallValue ?? fbCallValue ?? zeroValue
                    storeResult(result, mergedValue)

                    // Handle thrown channel from virtual dispatch only (fallback
                    // mirror logic left for future improvement).
                    if usesThrownChannel,
                       let thrownSlotPointer,
                       let thrownValue = bindings.buildLoad(
                           builder,
                           type: int64Type,
                           pointer: thrownSlotPointer,
                           name: "vthrown_val_\(instructionIndex)"
                       )
                    {
                        if let thrownResult {
                            if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                                _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                            } else {
                                storeResult(thrownResult, thrownValue)
                            }
                        } else if let hasThrown = buildThrownSlotCondition(
                            from: thrownValue,
                            name: "vhas_thrown_\(instructionIndex)"
                        ),
                            let thrownBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "vthrown_\(instructionIndex)"
                            ),
                            let continueBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "vcall_cont_\(instructionIndex)"
                            )
                        {
                            _ = bindings.buildCondBr(
                                builder,
                                condition: hasThrown,
                                thenBlock: thrownBlock,
                                elseBlock: continueBlock
                            )

                            bindings.positionBuilder(builder, at: thrownBlock)
                            storeOutThrownIfNonNull(thrownValue, suffix: "vthrow_\(instructionIndex)")
                            emitFramePop("vthrow_\(instructionIndex)")
                            _ = bindings.buildRet(builder, value: zeroValue)

                            currentBlock = continueBlock
                            bindings.positionBuilder(builder, at: continueBlock)
                        }
                    }
                } else {
                    // Fallback: no null guard possible – use original direct dispatch.
                    let functionPointerType = bindings.pointerType(calleeFunction.type)
                    let fptr = bindings.buildIntToPtr(
                        builder,
                        value: fptrRaw,
                        type: functionPointerType,
                        name: "lookup_fptr_\(instructionIndex)"
                    )

                    var callArguments = argumentValues
                    var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                    if shouldAppendThrownChannel {
                        if usesThrownChannel {
                            let thrownSlot = bindings.buildAlloca(
                                builder,
                                type: int64Type,
                                name: "vthrown_slot_\(instructionIndex)"
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
                        callee: fptr ?? calleeFunction.value,
                        arguments: callArguments,
                        name: "vcall_\(instructionIndex)"
                    )
                    storeResult(result, callValue)
                    if usesThrownChannel,
                       let thrownSlotPointer,
                       let thrownValue = bindings.buildLoad(
                           builder,
                           type: int64Type,
                           pointer: thrownSlotPointer,
                           name: "vthrown_val_\(instructionIndex)"
                       )
                    {
                        if let thrownResult {
                            if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                                _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                            } else {
                                storeResult(thrownResult, thrownValue)
                            }
                        } else if let hasThrown = buildThrownSlotCondition(
                            from: thrownValue,
                            name: "vhas_thrown_\(instructionIndex)"
                        ),
                            let thrownBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "vthrown_\(instructionIndex)"
                            ),
                            let continueBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "vcall_cont_\(instructionIndex)"
                            )
                        {
                            _ = bindings.buildCondBr(
                                builder,
                                condition: hasThrown,
                                thenBlock: thrownBlock,
                                elseBlock: continueBlock
                            )

                            bindings.positionBuilder(builder, at: thrownBlock)
                            storeOutThrownIfNonNull(thrownValue, suffix: "vthrow_\(instructionIndex)")
                            emitFramePop("vthrow_\(instructionIndex)")
                            _ = bindings.buildRet(builder, value: zeroValue)

                            currentBlock = continueBlock
                            bindings.positionBuilder(builder, at: continueBlock)
                        }
                    }
                }

            case let .jumpIfNotNull(value, target):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                let nullSentinel = bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64.min),
                    signExtend: true
                ) ?? zeroValue
                let isNonZero = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: zeroValue,
                    name: "jnn_nonzero_\(instructionIndex)"
                )
                let isNotSentinel = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: nullSentinel,
                    name: "jnn_nonsentinel_\(instructionIndex)"
                )
                if let isNonZero,
                   let isNotSentinel,
                   let condition = bindings.buildAnd(
                       builder,
                       lhs: isNonZero,
                       rhs: isNotSentinel,
                       name: "jnn_cond_\(instructionIndex)"
                   ),
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                       context: context,
                       function: llvmFunction.value,
                       name: "jnn_cont_\(instructionIndex)"
                   )
                {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                }

            case let .copy(from, to):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let copySource = resolveValue(from)
                // If the copy target is a global symbolRef, store to the
                // LLVM global variable so the write persists across reads.
                if let targetExpr = module.arena.expr(to),
                   case let .symbolRef(targetSymbol) = targetExpr,
                   let globalPtr = globalVariables[targetSymbol]
                {
                    _ = bindings.buildStore(builder, value: copySource, pointer: globalPtr)
                } else if let alloca = copyTargetAllocas[to.rawValue] {
                    _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
                } else {
                    storeResult(to, copySource)
                }

            case let .storeGlobal(value, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                if let globalPtr = globalVariables[symbol] {
                    _ = bindings.buildStore(builder, value: resolved, pointer: globalPtr)
                }

            case let .loadGlobal(result, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                if let globalPtr = globalVariables[symbol] {
                    if let loaded = bindings.buildLoad(
                        builder, type: int64Type, pointer: globalPtr,
                        name: "load_global_\(symbol.rawValue)"
                    ) {
                        storeResult(result, loaded)
                    }
                } else {
                    storeResult(result, zeroValue)
                }

            case let .rethrow(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
                emitFramePop("rethrow_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroValue)

            case let .returnIfEqual(lhs, rhs):
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
                      )
                else {
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

            case let .returnValue(value):
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
