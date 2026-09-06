// swiftlint:disable file_length
import RuntimeABI
import CompilerCore

extension NativeEmitter {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        typeLowering: LLVMTypeLowering?,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction],
        internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)],
        internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        runtimeCallbackRawReturnSymbols: Set<SymbolID> = [],
        usesRuntimeCallbackRawABI: Bool = false,
        returnsRawStringRuntimeCallback: Bool = false,
        nameCounter: GeneratedNameCounter,
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

        // Dedicated builder for stack slots. Slots requested while a loop body is
        // being emitted must be allocated in the entry block, otherwise every
        // iteration allocates a fresh slot and long loops overflow the stack.
        let allocaBuilder = bindings.createBuilder(context: context)
        defer {
            if let allocaBuilder {
                bindings.disposeBuilder(allocaBuilder)
            }
        }

        func buildEntrySlot(name: String, type: LLVMCAPIBindings.LLVMTypeRef? = nil) -> LLVMCAPIBindings.LLVMValueRef? {
            bindings.buildEntryAlloca(
                type: type ?? int64Type,
                name: name,
                entryBlock: entryBlock,
                allocaBuilder: allocaBuilder,
                fallbackBuilder: builder
            )
        }

        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        for instruction in function.body {
            guard case let .label(id) = instruction else {
                continue
            }
            if labelBlocks[id] != nil {
                continue
            }
            if let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: nameCounter.nextName("L")) {
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
                let parameterType = usesRuntimeCallbackRawABI
                    ? int64Type
                    : loweredLLVMType(
                        for: parameter.type,
                        lowering: typeLowering,
                        defaultType: int64Type
                    )
                let paramAlloca = bindings.buildAlloca(builder, type: parameterType, name: "dbg_\(paramName)")
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
        let zeroReturnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
            zeroValue
        } else {
            zeroLLVMValue(
                for: function.returnType,
                lowering: typeLowering,
                int64Type: int64Type,
                context: context
            ) ?? zeroValue
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        let nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        var currentBlock = entryBlock
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var rawResultValues: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        let maxKIRArgumentCountByExternalCallee = Self.maxKIRArgumentCountByExternalCallee(
            body: function.body,
            interner: interner
        )
        let builderState = EmissionBuilderState(
            builder: builder,
            int64Type: int64Type,
            zeroValue: zeroValue,
            context: context,
            module: llvmModule,
            typeLowering: typeLowering,
            entryBlock: entryBlock,
            allocaBuilder: allocaBuilder
        )

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
            case let .call(_, _, _, result, _, thrownResult, _, _):
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
                 .beginBlock, .endBlock, .nop, .nonLocalReturn,
                 .beginFinallyGuard, .endFinallyGuard:
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
                   let alloca = bindings.buildAlloca(
                       builder,
                       type: loweredLLVMType(
                           for: module.arena.exprType(target),
                           lowering: typeLowering,
                           defaultType: int64Type
                       ),
                       name: nameCounter.nextName("copy_slot_")
                   )
                {
                    let initialValue = zeroLLVMValue(
                        for: module.arena.exprType(target),
                        lowering: typeLowering,
                        int64Type: int64Type,
                        context: context
                    ) ?? zeroValue
                    _ = bindings.buildStore(builder, value: initialValue, pointer: alloca)
                    copyTargetAllocas[target.rawValue] = alloca
                }
            }
        }

        func declareExternalFunction(
            named calleeName: String,
            argumentCount: Int,
            appendThrownChannel: Bool
        ) -> LLVMFunction? {
            // String.length extension: redirect "length" (1 arg = receiver) to the
            // aggregate field accessor sentinel. Codegen lowers it to extractvalue.
            // Lambda bodies may reach codegen with callee "length" when receiver type is not
            // available during KIR lowering (e.g. mapIndexed { _, v -> v.length }).
            let effectiveName: String = if Self.isStringLengthAggregateAccessorName(calleeName),
                                           argumentCount == 1,
                                           !appendThrownChannel
            {
                "__kk_string_struct_get_length"
            } else {
                calleeName
            }
            if let existing = externalFunctions[effectiveName] {
                return existing
            }
            let maxArgsSeenInBody = maxKIRArgumentCountByExternalCallee[effectiveName] ?? 0
            let effectiveArgumentCount = max(argumentCount, maxArgsSeenInBody)
            var callParameterTypes = Array(repeating: int64Type, count: effectiveArgumentCount)
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

        func declareExternalFunction(
            named calleeName: String,
            parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?],
            returnType: LLVMCAPIBindings.LLVMTypeRef?
        ) -> LLVMFunction? {
            let key = "\(calleeName)#typed#\(parameterTypes.count)"
            if let existing = externalFunctions[key] {
                return existing
            }
            guard let externalType = bindings.functionType(
                returnType: returnType,
                parameters: parameterTypes,
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
            externalFunctions[key] = declared
            return declared
        }

        func stringAggregateFields(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            // `value`'s KIR-level semantic type may be String (i.e. isStringAggregateExpr
            // returned true) even when this particular expression was materialized as a
            // raw (boxed) Int64 handle rather than a flat struct — e.g. a HOF lambda
            // parameter sourced from a collection element. Extracting a struct field from
            // a non-aggregate LLVM value crashes LLVM, so confirm the actual LLVM value is
            // an aggregate first, bridging from the raw handle when it is not.
            let aggregate: LLVMCAPIBindings.LLVMValueRef
            if bindings.isAggregateStructValue(value) {
                aggregate = value
            } else if let bridged = bridgeRuntimeRawToStringAggregate(value, suffix: "\(suffix)_from_raw") {
                aggregate = bridged
            } else {
                return nil
            }
            guard let data = bindings.buildExtractValue(builder, aggregate: aggregate, index: 0, name: "str_data_\(suffix)"),
                  let length = bindings.buildExtractValue(builder, aggregate: aggregate, index: 1, name: "str_length_\(suffix)"),
                  let byteCount = bindings.buildExtractValue(builder, aggregate: aggregate, index: 2, name: "str_bytes_\(suffix)"),
                  let hash = bindings.buildExtractValue(builder, aggregate: aggregate, index: 3, name: "str_hash_\(suffix)")
            else {
                return nil
            }
            return [data, length, byteCount, hash]
        }

        func bridgeStringAggregateToRuntimeRaw(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering,
                  let fields = stringAggregateFields(value, suffix: "\(suffix)_to_raw"),
                  let bridgeFunction = declareExternalFunction(
                      named: "kk_string_from_flat",
                      parameterTypes: [
                          typeLowering.dataPointerType,
                          int64Type,
                          int64Type,
                          int64Type,
                      ],
                      returnType: int64Type
                  )
            else {
                return nil
            }
            return bindings.buildCall(
                builder,
                functionType: bridgeFunction.type,
                callee: bridgeFunction.value,
                arguments: fields,
                name: "string_raw_\(suffix)"
            ).flatMap { raw in
                // String? uses null data in aggregate form and the runtime null
                // sentinel at erased/raw boundaries.
                guard let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
                      let isNull = bindings.buildICmpEqual(
                          builder,
                          lhs: fields[0],
                          rhs: nullData,
                          name: "string_raw_isnull_\(suffix)"
                      ),
                      let sentinel = bindings.constInt(int64Type, value: UInt64(bitPattern: Int64.min), signExtend: true)
                else {
                    return raw
                }
                return bindings.buildSelect(
                    builder,
                    condition: isNull,
                    thenValue: sentinel,
                    elseValue: raw,
                    name: "string_raw_nullable_\(suffix)"
                ) ?? raw
            }
        }

        func bridgeRuntimeRawToStringAggregate(
            _ raw: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering,
                  let lengthSlot = allocateI64Slot(name: "string_bridge_length_\(suffix)"),
                  let byteCountSlot = allocateI64Slot(name: "string_bridge_bytes_\(suffix)"),
                  let hashSlot = allocateI64Slot(name: "string_bridge_hash_\(suffix)"),
                  let bridgeFunction = declareExternalFunction(
                      named: "kk_string_to_flat",
                      parameterTypes: [
                          int64Type,
                          outThrownPointerType,
                          outThrownPointerType,
                          outThrownPointerType,
                      ],
                      returnType: typeLowering.dataPointerType
                  ),
                  let data = bindings.buildCall(
                      builder,
                      functionType: bridgeFunction.type,
                      callee: bridgeFunction.value,
                      arguments: [raw, lengthSlot, byteCountSlot, hashSlot],
                      name: "string_bridge_data_\(suffix)"
                  ),
                  let length = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: lengthSlot,
                      name: "string_bridge_length_val_\(suffix)"
                  ),
                  let byteCount = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: byteCountSlot,
                      name: "string_bridge_bytes_val_\(suffix)"
                  ),
                  let hash = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: hashSlot,
                      name: "string_bridge_hash_val_\(suffix)"
                  )
            else {
                return nil
            }
            return buildStringAggregate(
                builder: builder,
                lowering: typeLowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: "string_bridge_\(suffix)"
            )
        }

        func isStringAggregateType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: type)
            else {
                return false
            }
            return typeLowering != nil
        }

        func isStringAggregateExpr(_ id: KIRExprID) -> Bool {
            isStringAggregateType(module.arena.exprType(id))
        }

        func isPrimitiveType(_ type: TypeID?) -> Bool {
            guard let type, let typeSystem,
                  case .primitive = typeSystem.kind(of: type)
            else { return false }
            return true
        }

        /// Raw scalar values use Int64.min as the nullable sentinel, so zero
        /// remains a valid value for nullable primitives and enum ordinals.
        /// Reference-like values still use zero as the null representation.
        func nullableRawScalarPreservesZero(_ type: TypeID?) -> Bool {
            guard let type, let typeSystem else { return false }
            switch typeSystem.kind(of: type) {
            case .primitive(_, let nullability):
                return nullability != .nonNull
            case let .classType(classType):
                return symbols?.symbol(classType.classSymbol)?.kind == .enumClass
            case .unit:
                // Safe calls returning Unit use the Int64.min sentinel for
                // null, while the valid Unit value is raw zero.
                return true
            default:
                return false
            }
        }

        func isCharSequenceRuntimeStringType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  let charSequenceSymbol = typeSystem.charSequenceInterfaceSymbol
            else {
                return false
            }
            let nonNullType = typeSystem.makeNonNullable(type)
            guard case let .classType(classType) = typeSystem.kind(of: nonNullType) else {
                return false
            }
            return classType.classSymbol == charSequenceSymbol
        }

        func coerceStringValueForType(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            from fromType: TypeID?,
            to toType: TypeID?,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef {
            if isStringAggregateType(fromType), !isStringAggregateType(toType) {
                return bridgeStringAggregateToRuntimeRaw(value, suffix: suffix) ?? value
            }
            if !isStringAggregateType(fromType), isStringAggregateType(toType) {
                return bridgeRuntimeRawToStringAggregate(value, suffix: suffix) ?? value
            }
            return value
        }

        if usesRuntimeCallbackRawABI {
            for (index, parameter) in function.params.enumerated() where isStringAggregateType(parameter.type) {
                guard let rawValue = parameterValues[parameter.symbol] else {
                    continue
                }
                parameterValues[parameter.symbol] = bridgeRuntimeRawToStringAggregate(
                    rawValue,
                    suffix: "runtime_callback_param_\(index)"
                ) ?? rawValue
            }
        }

        func flattenedRuntimeParameterTypes(
            argumentCount: Int,
            stringArgumentPositions: [Int]
        ) -> [LLVMCAPIBindings.LLVMTypeRef?]? {
            guard let typeLowering else {
                return nil
            }
            let stringPositions = Set(stringArgumentPositions)
            var parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?] = []
            for index in 0..<argumentCount {
                if stringPositions.contains(index) {
                    parameterTypes.append(contentsOf: [
                        typeLowering.dataPointerType,
                        int64Type,
                        int64Type,
                        int64Type,
                    ])
                } else {
                    parameterTypes.append(int64Type)
                }
            }
            return parameterTypes
        }

        func flattenedRuntimeArguments(
            values argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            types argumentTypes: [TypeID?],
            ids argumentIDs: [KIRExprID?],
            argumentCount: Int,
            stringArgumentPositions: [Int],
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            guard argumentValues.count >= argumentCount,
                  argumentTypes.count >= argumentCount,
                  argumentIDs.count >= argumentCount
            else {
                return nil
            }
            let stringPositions = Set(stringArgumentPositions)
            var flattened: [LLVMCAPIBindings.LLVMValueRef] = []
            for index in 0..<argumentCount {
                if stringPositions.contains(index) {
                    let stringValue: LLVMCAPIBindings.LLVMValueRef
                    if let argumentID = argumentIDs[index],
                       isZeroConstant(argumentID),
                       let typeLowering,
                       let nullString = buildNullStringAggregate(
                           builder: builder,
                           lowering: typeLowering,
                           name: "string_null_flat_arg\(suffix)_\(index)"
                       )
                    {
                        stringValue = nullString
                    } else if isStringAggregateType(argumentTypes[index]) {
                        stringValue = argumentValues[index]
                    } else if isCharSequenceRuntimeStringType(argumentTypes[index]),
                              let bridged = bridgeRuntimeRawToStringAggregate(
                                  argumentValues[index],
                                  suffix: "\(suffix)_arg\(index)_charseq"
                              ) {
                        stringValue = bridged
                    } else if !isPrimitiveType(argumentTypes[index]),
                              let bridged = bridgeRuntimeRawToStringAggregate(
                                  argumentValues[index],
                                  suffix: "\(suffix)_arg\(index)_raw"
                              ) {
                        // Fallback for boxed string pointers in any/unknown-typed expressions
                        // (e.g. kk_list_iterator_next result used in a string template).
                        // Excluded: primitive types (Int, Bool, Char…) which are never string boxes.
                        stringValue = bridged
                    } else {
                        return nil
                    }
                    guard let fields = stringAggregateFields(stringValue, suffix: "\(suffix)_arg\(index)") else { return nil }
                    flattened.append(contentsOf: fields)
                } else {
                    flattened.append(argumentValues[index])
                }
            }
            return flattened
        }

        func allocateI64Slot(name: String) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let slot = buildEntrySlot(name: name) else {
                return nil
            }
            _ = bindings.buildStore(builder, value: zeroValue, pointer: slot)
            return slot
        }

        func storeThrownResultZero(_ thrownResult: KIRExprID?) {
            guard let thrownResult else {
                return
            }
            if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
            } else {
                storeResult(thrownResult, zeroValue)
            }
        }

        func handleThrownSlot(
            _ thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?,
            thrownResult: KIRExprID?,
            instructionIndex: Int
        ) {
            guard let thrownSlotPointer,
                  let thrownValue = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: thrownSlotPointer,
                      name: "thrown_val_\(instructionIndex)"
                  )
            else {
                return
            }
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
                _ = bindings.buildRet(builder, value: zeroReturnValue)

                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)
            }
        }

        func emitFlatStringRuntimeCall(
            calleeName: String,
            arguments: [KIRExprID],
            argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            result: KIRExprID?,
            usesThrownChannel: Bool,
            thrownResult: KIRExprID?,
            instructionIndex: Int
        ) -> Bool {
            guard let typeLowering else {
                return false
            }
            let argumentTypes = arguments.map(module.arena.exprType)

            struct FlatStringReturnCallSpec {
                let flatName: String
                let stringArgumentCount: Int
                let extraArgumentCount: Int
                let stringArgumentPositions: [Int]
                let canThrow: Bool

                init(
                    flatName: String,
                    stringArgumentCount: Int,
                    extraArgumentCount: Int,
                    stringArgumentPositions: [Int]? = nil,
                    canThrow: Bool
                ) {
                    self.flatName = flatName
                    self.stringArgumentCount = stringArgumentCount
                    self.extraArgumentCount = extraArgumentCount
                    self.stringArgumentPositions = stringArgumentPositions ?? Array(0..<stringArgumentCount)
                    self.canThrow = canThrow
                }
            }

            struct FlatScalarReturnCallSpec {
                let flatName: String
                let stringArgumentCount: Int
                let extraArgumentCount: Int
                let stringArgumentPositions: [Int]
                let canThrow: Bool
                let defaultMissingClosureRaw: Bool

                init(
                    flatName: String,
                    stringArgumentCount: Int,
                    extraArgumentCount: Int,
                    stringArgumentPositions: [Int]? = nil,
                    canThrow: Bool = false,
                    defaultMissingClosureRaw: Bool = false
                ) {
                    self.flatName = flatName
                    self.stringArgumentCount = stringArgumentCount
                    self.extraArgumentCount = extraArgumentCount
                    self.stringArgumentPositions = stringArgumentPositions ?? Array(0..<stringArgumentCount)
                    self.canThrow = canThrow
                    self.defaultMissingClosureRaw = defaultMissingClosureRaw
                }
            }

            var flatStringReturnCallSpecs: [String: FlatStringReturnCallSpec] = [
                "kk_string_to_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_to_flat",
                    stringArgumentCount: 0,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "kk_string_concat_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_concat_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_trim_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trim_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_trim_predicate_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trim_predicate_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: true
                ),
                "kk_string_trimStart_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trimStart_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_trimStart_predicate_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trimStart_predicate_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: true
                ),
                "kk_string_trimEnd_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trimEnd_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_trimEnd_predicate_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_trimEnd_predicate_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: true
                ),
                "kk_string_lowercase_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_lowercase_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_uppercase_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_uppercase_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "__kk_lowercase_locale_flat": FlatStringReturnCallSpec(
                    flatName: "__kk_lowercase_locale_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "__kk_uppercase_locale_flat": FlatStringReturnCallSpec(
                    flatName: "__kk_uppercase_locale_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "__kk_string_normalize_flat": FlatStringReturnCallSpec(
                    flatName: "__kk_string_normalize_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "kk_string_orEmpty_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_orEmpty_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_reversed_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_reversed_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                // KSP-410: filter/filterNot/filterIndexed are bundled Kotlin
                // source (StringHOF.kt); no flat emission spec.
                "kk_string_ifBlank_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_ifBlank_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: true
                ),
                "kk_string_ifEmpty_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_ifEmpty_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: true
                ),
                // KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin
                // source (StringTakeDrop.kt); no flat emission spec.
                "kk_string_replace_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_replace_flat",
                    stringArgumentCount: 3,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                "kk_string_replace_char_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_replace_char_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: false
                ),
                "kk_string_replace_ignoreCase_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_replace_ignoreCase_flat",
                    stringArgumentCount: 3,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "kk_string_replace_char_ignoreCase_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_replace_char_ignoreCase_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 3,
                    canThrow: false
                ),
                "kk_string_replaceFirst_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_replaceFirst_flat",
                    stringArgumentCount: 3,
                    extraArgumentCount: 0,
                    canThrow: false
                ),
                // KSP-406: substring/subSequence/slice/removeRange/replaceRange are
                // bundled Kotlin source (StringSubstringSlice.kt); no flat emission spec.
                "kk_string_padStart_default_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_padStart_default_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "kk_string_padEnd_default_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_padEnd_default_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: false
                ),
                "kk_string_padStart_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_padStart_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: false
                ),
                "kk_string_padEnd_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_padEnd_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    canThrow: false
                ),
                "kk_string_repeat_flat": FlatStringReturnCallSpec(
                    flatName: "kk_string_repeat_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
                // (StringTakeDrop.kt); no flat emission spec.
                // KSP-404: removePrefix/removeSuffix/removeSurrounding are bundled
                // Kotlin source (StringPrefixSuffix.kt); no flat emission spec.
                // KSP-407: substringBefore/After/BeforeLast/AfterLast and
                // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin
                // source (StringSearchReplace.kt); no flat emission spec.
                "__kk_string_format_flat": FlatStringReturnCallSpec(
                    flatName: "__kk_string_format_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [0],
                    canThrow: false
                ),
                "__kk_string_format_locale_flat": FlatStringReturnCallSpec(
                    flatName: "__kk_string_format_locale_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2,
                    stringArgumentPositions: [1],
                    canThrow: false
                ),
            ]
            for spec in Array(flatStringReturnCallSpecs.values)
            where flatStringReturnCallSpecs[spec.flatName] == nil {
                flatStringReturnCallSpecs[spec.flatName] = spec
            }

            var flatScalarReturnCallSpecs: [String: FlatScalarReturnCallSpec] = [
                "kk_string_from_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_from_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_locale_new_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_locale_new_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_locale_new_language_country_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_locale_new_language_country_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0
                ),
                "kk_string_split_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_split_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0
                ),
                "kk_string_split_limit_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_split_limit_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 2
                ),
                "kk_string_splitToSequence_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_splitToSequence_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0
                ),
                "__kk_regex_create_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_create_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_regex_create_with_option_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_create_with_option_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_regex_create_with_options_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_create_with_options_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_matches_regex_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_matches_regex_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "__kk_string_contains_regex_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_contains_regex_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "__kk_string_split_regex_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_split_regex_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "__kk_string_toRegex_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toRegex_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toRegex_with_option_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toRegex_with_option_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toRegex_with_options_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toRegex_with_options_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_regex_find_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_find_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_regex_findAll_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_findAll_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_regex_matchEntire_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_matchEntire_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_regex_containsMatchIn_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_containsMatchIn_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_regex_from_literal_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_from_literal_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_match_result_group_index_of_name": FlatScalarReturnCallSpec(
                    flatName: "__kk_match_result_group_index_of_name_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_regex_matches_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_regex_matches_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_string_builder_new_from_string_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_builder_new_from_string_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_builder_append_obj": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_builder_append_obj_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    stringArgumentPositions: [1]
                ),
                "__kk_string_builder_toString": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_builder_toString",
                    stringArgumentCount: 0,
                    extraArgumentCount: 1
                ),
                "__kk_bignum_toString": FlatScalarReturnCallSpec(
                    flatName: "__kk_bignum_toString",
                    stringArgumentCount: 0,
                    extraArgumentCount: 1
                ),
                // KSP-404: startsWith/endsWith are bundled Kotlin source
                // (StringPrefixSuffix.kt); no flat emission spec.
                // KSP-408: contains/indexOf/lastIndexOf/indexOfAny/lastIndexOfAny/
                // findAnyOf/findLastAnyOf are bundled Kotlin source (StringIndexOf.kt);
                // no flat emission spec.
                // KSP-413: compareTo(ignoreCase) / contentEquals / equals(ignoreCase)
                // are bundled Kotlin source (StringComparison.kt); no flat emission spec.
                "kk_string_compareTo_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_compareTo_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0
                ),
                "__kk_string_compareTo_locale_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_compareTo_locale_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 1
                ),
                "__kk_string_isNormalized_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_isNormalized_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "kk_string_equals_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_equals_flat",
                    stringArgumentCount: 2,
                    extraArgumentCount: 0
                ),
                "kk_string_isEmpty_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isEmpty_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_isNotEmpty_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isNotEmpty_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_isBlank_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isBlank_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_isNotBlank_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isNotBlank_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_isNullOrEmpty_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isNullOrEmpty_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_isNullOrBlank_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_isNullOrBlank_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_first_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_first_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "kk_string_last_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_last_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "kk_string_single_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_single_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "kk_string_firstOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_firstOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_lastOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_lastOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_singleOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_singleOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "kk_string_getOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_getOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "kk_string_get_flat": FlatScalarReturnCallSpec(
                    flatName: "kk_string_get_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source
                // (StringIndexOf.kt); no flat emission spec.
                // KSP-410: count/any/all/none/find/findLast/partition and
                // map/mapIndexed/mapNotNull/firstNotNullOf(OrNull) are bundled
                // Kotlin source (StringHOF.kt); no flat emission spec.
                // KSP-410: sumBy/sumByDouble/reduceOrNull/reduceRightIndexed/
                // reduceRightIndexedOrNull/reduceRightOrNull are bundled
                // Kotlin source (StringHOF.kt); no flat emission spec.
                "__kk_string_toBoolean_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toBoolean_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toBooleanStrict_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toBooleanStrict_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toBooleanStrictOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toBooleanStrictOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toInt_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toInt_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toInt_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toInt_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toIntOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toIntOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toIntOrNull_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toIntOrNull_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toUByteOrNull_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toUByteOrNull_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toUShortOrNull_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toUShortOrNull_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toUIntOrNull_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toUIntOrNull_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toULongOrNull_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toULongOrNull_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toDouble_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toDouble_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toDoubleOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toDoubleOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toLong_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toLong_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toLongOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toLongOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toFloat_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toFloat_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toFloatOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toFloatOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toShort_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toShort_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toShortOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toShortOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toByte_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toByte_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toByte_radix_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toByte_radix_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1,
                    canThrow: true
                ),
                "__kk_string_toByteOrNull_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toByteOrNull_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toBigDecimal_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toBigDecimal_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0,
                    canThrow: true
                ),
                "__kk_string_toByteArray_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toByteArray_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_toByteArray_charset_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_toByteArray_charset_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "__kk_string_encodeToByteArray_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_encodeToByteArray_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_encodeToByteArray_range_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_encodeToByteArray_range_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 2
                ),
                "__kk_string_encodeToByteArray_charset_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_encodeToByteArray_charset_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
                "__kk_string_byteInputStream_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_byteInputStream_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 0
                ),
                "__kk_string_byteInputStream_charset_flat": FlatScalarReturnCallSpec(
                    flatName: "__kk_string_byteInputStream_charset_flat",
                    stringArgumentCount: 1,
                    extraArgumentCount: 1
                ),
            ]
            for spec in Array(flatScalarReturnCallSpecs.values)
            where flatScalarReturnCallSpecs[spec.flatName] == nil {
                flatScalarReturnCallSpecs[spec.flatName] = spec
            }

            func emitFlatStringReturnCall(_ spec: FlatStringReturnCallSpec) -> Bool {
                let requiredArgumentCount = spec.stringArgumentCount + spec.extraArgumentCount
                guard let result,
                      argumentValues.count >= requiredArgumentCount,
                      spec.stringArgumentPositions.count == spec.stringArgumentCount,
                      let flattenedArgs = flattenedRuntimeArguments(
                          values: argumentValues,
                          types: argumentTypes,
                          ids: arguments.map(Optional.some),
                          argumentCount: requiredArgumentCount,
                          stringArgumentPositions: spec.stringArgumentPositions,
                          suffix: "\(spec.flatName)_\(instructionIndex)"
                      ),
                      var parameterTypes = flattenedRuntimeParameterTypes(
                          argumentCount: requiredArgumentCount,
                          stringArgumentPositions: spec.stringArgumentPositions
                      ),
                      let lengthSlot = allocateI64Slot(name: "\(spec.flatName)_length_\(instructionIndex)"),
                      let byteCountSlot = allocateI64Slot(name: "\(spec.flatName)_bytes_\(instructionIndex)"),
                      let hashSlot = allocateI64Slot(name: "\(spec.flatName)_hash_\(instructionIndex)")
                else {
                    return false
                }

                parameterTypes.append(contentsOf: [
                    outThrownPointerType,
                    outThrownPointerType,
                    outThrownPointerType,
                ])

                let thrownSlot = spec.canThrow && usesThrownChannel
                    ? allocateI64Slot(name: "\(spec.flatName)_thrown_\(instructionIndex)")
                    : nil
                if spec.canThrow {
                    parameterTypes.append(outThrownPointerType)
                }
                guard let runtimeFunction = declareExternalFunction(
                    named: spec.flatName,
                    parameterTypes: parameterTypes,
                    returnType: typeLowering.dataPointerType
                )
                else {
                    return false
                }

                let thrownPointer = thrownSlot ?? nullThrownPointer
                let callArguments = flattenedArgs
                    + [lengthSlot, byteCountSlot, hashSlot]
                    + (spec.canThrow ? [thrownPointer] : [])
                guard let data = bindings.buildCall(
                    builder,
                    functionType: runtimeFunction.type,
                    callee: runtimeFunction.value,
                    arguments: callArguments,
                    name: "\(spec.flatName)_data_\(instructionIndex)"
                ),
                    let length = bindings.buildLoad(
                        builder,
                        type: int64Type,
                        pointer: lengthSlot,
                        name: "\(spec.flatName)_length_val_\(instructionIndex)"
                    ),
                    let byteCount = bindings.buildLoad(
                        builder,
                        type: int64Type,
                        pointer: byteCountSlot,
                        name: "\(spec.flatName)_bytes_val_\(instructionIndex)"
                    ),
                    let hash = bindings.buildLoad(
                        builder,
                        type: int64Type,
                        pointer: hashSlot,
                        name: "\(spec.flatName)_hash_val_\(instructionIndex)"
                    )
                else {
                    return false
                }
                guard let aggregate = buildStringAggregate(
                    builder: builder,
                    lowering: typeLowering,
                    data: data,
                    length: length,
                    byteCount: byteCount,
                    hash: hash,
                    name: "\(spec.flatName)_result_\(instructionIndex)"
                ) else {
                    return false
                }
                let storedValue: LLVMCAPIBindings.LLVMValueRef
                if isStringAggregateType(module.arena.exprType(result)) {
                    storedValue = aggregate
                } else if let raw = bridgeStringAggregateToRuntimeRaw(
                    aggregate,
                    suffix: "\(spec.flatName)_result_\(instructionIndex)"
                ) {
                    storedValue = raw
                } else {
                    return false
                }
                storeResult(result, storedValue)
                if spec.canThrow {
                    if usesThrownChannel {
                        handleThrownSlot(thrownSlot, thrownResult: thrownResult, instructionIndex: instructionIndex)
                    }
                } else if usesThrownChannel {
                    storeThrownResultZero(thrownResult)
                }
                return true
            }

            func emitFlatScalarReturnCall(_ spec: FlatScalarReturnCallSpec) -> Bool {
                let requiredArgumentCount = spec.stringArgumentCount + spec.extraArgumentCount
                var effectiveArgumentValues = argumentValues
                var effectiveArgumentTypes = argumentTypes
                if spec.defaultMissingClosureRaw,
                   effectiveArgumentValues.count == requiredArgumentCount - 1 {
                    effectiveArgumentValues.append(zeroValue)
                    effectiveArgumentTypes.append(nil)
                }
                guard effectiveArgumentValues.count >= requiredArgumentCount,
                      spec.stringArgumentPositions.count == spec.stringArgumentCount,
                      let flattenedArgs = flattenedRuntimeArguments(
                          values: effectiveArgumentValues,
                          types: effectiveArgumentTypes,
                          ids: Array(arguments.map(Optional.some).prefix(effectiveArgumentValues.count))
                              + Array(
                                  repeating: nil,
                                  count: max(0, effectiveArgumentValues.count - arguments.count)
                              ),
                          argumentCount: requiredArgumentCount,
                          stringArgumentPositions: spec.stringArgumentPositions,
                          suffix: "\(spec.flatName)_\(instructionIndex)"
                      ),
                      var parameterTypes = flattenedRuntimeParameterTypes(
                          argumentCount: requiredArgumentCount,
                          stringArgumentPositions: spec.stringArgumentPositions
                      )
                else {
                    return false
                }

                let thrownSlot = spec.canThrow && usesThrownChannel
                    ? allocateI64Slot(name: "\(spec.flatName)_thrown_\(instructionIndex)")
                    : nil
                if spec.canThrow {
                    parameterTypes.append(outThrownPointerType)
                }

                guard let runtimeFunction = declareExternalFunction(
                    named: spec.flatName,
                    parameterTypes: parameterTypes,
                    returnType: int64Type
                )
                else {
                    return false
                }
                let scalarValue = bindings.buildCall(
                    builder,
                    functionType: runtimeFunction.type,
                    callee: runtimeFunction.value,
                    arguments: flattenedArgs
                        + (spec.canThrow ? [thrownSlot ?? nullThrownPointer] : []),
                    name: "\(spec.flatName)_value_\(instructionIndex)"
                )
                let storedScalarValue: LLVMCAPIBindings.LLVMValueRef?
                if let result,
                   isStringAggregateExpr(result),
                   let scalarValue
                {
                    storedScalarValue = bridgeRuntimeRawToStringAggregate(
                        scalarValue,
                        suffix: "\(spec.flatName)_result_\(instructionIndex)"
                    ) ?? scalarValue
                } else {
                    storedScalarValue = scalarValue
                }
                storeResult(result, storedScalarValue)
                if spec.canThrow {
                    if usesThrownChannel {
                        handleThrownSlot(thrownSlot, thrownResult: thrownResult, instructionIndex: instructionIndex)
                    }
                } else if usesThrownChannel {
                    storeThrownResultZero(thrownResult)
                }
                return true
            }

            if let spec = flatStringReturnCallSpecs[calleeName],
               emitFlatStringReturnCall(spec)
            {
                return true
            }
            if let spec = flatScalarReturnCallSpecs[calleeName],
               emitFlatScalarReturnCall(spec)
            {
                return true
            }

            return false
        }

        func resolveUnnamedInternalFunction(
            named calleeName: String,
            argumentCount: Int,
            argumentTypes: [TypeID?],
            appendThrownChannel _: Bool
        ) -> (symbol: SymbolID, function: LLVMFunction)? {
            // Match by KIR param count (user args only); outThrown is appended by codegen.
            let lookupKey = FunctionLookupKey(name: calleeName, parameterCount: argumentCount)
            let candidates = internalFunctionsByLookupKey[lookupKey, default: []].compactMap { candidate -> (symbol: SymbolID, function: LLVMFunction, parameters: [TypeID])? in
                guard let llvmFunction = internalFunctions[candidate.symbol] else {
                    return nil
                }
                return (candidate.symbol, llvmFunction, candidate.params.map(\.type))
            }
            let exactMatches = candidates.filter { candidate in
                guard argumentTypes.count == candidate.parameters.count else {
                    return false
                }
                return zip(argumentTypes, candidate.parameters).allSatisfy { argumentType, parameterType in
                    guard let argumentType else {
                        return false
                    }
                    return argumentType == parameterType
                }
            }
            if exactMatches.count == 1, let match = exactMatches.first {
                return (match.symbol, match.function)
            }
            if candidates.count == 1, let match = candidates.first {
                return (match.symbol, match.function)
            }
            return nil
        }

        func internalSignature(for symbol: SymbolID?) -> (parameters: [TypeID], returnType: TypeID)? {
            guard let symbol else {
                return nil
            }
            return internalSignatures[symbol]
        }

        func sourceExternalSignature(
            for symbol: SymbolID?,
            argumentCount: Int
        ) -> (parameters: [TypeID], returnType: TypeID)? {
            guard let symbol,
                  let symbols,
                  let typeSystem,
                  let signature = symbols.functionSignature(for: symbol),
                  let externalLinkName = symbols.externalLinkName(for: symbol),
                  !externalLinkName.isEmpty
            else {
                return nil
            }
            let parameters = [signature.receiverType].compactMap { $0 } + signature.parameterTypes
            guard parameters.count == argumentCount else {
                return nil
            }

            func isHandleLike(_ type: RuntimeABICType) -> Bool {
                switch type {
                case .intptr, .opaquePointer, .nullableOpaquePointer:
                    return true
                default:
                    return false
                }
            }

            let resolvedParameters: [TypeID]
            let resolvedReturnType: TypeID
            let isRawNumericComparisonHelper = [
                "kk_min_float", "kk_max_float", "kk_min_double", "kk_max_double",
            ].contains(externalLinkName)
            if let spec = NativeEmitter.runtimeABIFunctionByName[externalLinkName] {
                // Runtime callees that throw carry a trailing `outThrown` channel
                // that is not part of the Kotlin parameter list, so exclude it
                // when matching against the source-level signature.
                let abiValueParameters = spec.parameters.filter { parameter in
                    !(spec.isThrowing && parameter.name == "outThrown" && parameter.type == .nullableIntptrPointer)
                }
                if abiValueParameters.count == parameters.count {
                    resolvedParameters = zip(parameters, abiValueParameters).map { kotlinType, abiParam in
                        if isRawNumericComparisonHelper, abiParam.type == .intptr {
                            // These helpers consume IEEE bit patterns even though their
                            // bundled Kotlin declarations are Float/Double-typed.
                            return typeSystem.intType
                        }
                        if isStringAggregateType(kotlinType), isHandleLike(abiParam.type) {
                            return typeSystem.intType
                        }
                        return kotlinType
                    }
                } else {
                    resolvedParameters = parameters
                }
                if isRawNumericComparisonHelper, spec.returnType == .intptr {
                    // Keep the raw-bit return type aligned with RuntimeABI when an
                    // inline precompiled body retains the helper's source symbol.
                    resolvedReturnType = typeSystem.intType
                } else if isStringAggregateType(signature.returnType), isHandleLike(spec.returnType) {
                    resolvedReturnType = typeSystem.intType
                } else {
                    resolvedReturnType = symbols.functionABIReturnType(for: symbol) ?? signature.returnType
                }
            } else {
                resolvedParameters = parameters
                resolvedReturnType = symbols.functionABIReturnType(for: symbol) ?? signature.returnType
            }
            return (resolvedParameters, resolvedReturnType)
        }

        func loweredLLVMTypes(for types: [TypeID]) -> [LLVMCAPIBindings.LLVMTypeRef?] {
            types.map {
                loweredLLVMType(for: $0, lowering: typeLowering, defaultType: int64Type)
            }
        }

        func isZeroConstant(_ id: KIRExprID) -> Bool {
            guard let expression = module.arena.expr(id) else {
                return false
            }
            switch expression {
            case .intLiteral(0), .longLiteral(0), .uintLiteral(0), .ulongLiteral(0), .null:
                return true
            default:
                return false
            }
        }

        func valueForConstant(_ expression: KIRExprKind, expressionRawID: Int32?) -> LLVMCAPIBindings.LLVMValueRef {
            let expectedType = expressionRawID.map { KIRExprID(rawValue: $0) }.flatMap(module.arena.exprType)
            return emitConstantValue(
                expression,
                expectedType: expectedType,
                state: builderState,
                parameterValues: parameterValues,
                internalFunctions: internalFunctions,
                globalVariables: globalVariables,
                nameCounter: nameCounter,
                declareExternalFunction: { name, argCount, appendThrown in
                    declareExternalFunction(named: name, argumentCount: argCount, appendThrownChannel: appendThrown)
                },
                interner: interner
            )
        }

        func resolveValue(_ id: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef {
            if let alloca = copyTargetAllocas[id.rawValue] {
                let loadType = loweredLLVMType(
                    for: module.arena.exprType(id),
                    lowering: typeLowering,
                    defaultType: int64Type
                )
                return bindings.buildLoad(builder, type: loadType, pointer: alloca, name: nameCounter.nextName("load_"))
                    ?? (zeroLLVMValue(
                        for: module.arena.exprType(id),
                        lowering: typeLowering,
                        int64Type: int64Type,
                        context: context
                    ) ?? zeroValue)
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

        func rawComparableValues(
            lhs: KIRExprID,
            rhs: KIRExprID
        ) -> (LLVMCAPIBindings.LLVMValueRef, LLVMCAPIBindings.LLVMValueRef) {
            let lhsValue = resolveValue(lhs)
            let rhsValue = resolveValue(rhs)
            let lhsIsAggregate = bindings.isAggregateStructValue(lhsValue)
            let rhsIsAggregate = bindings.isAggregateStructValue(rhsValue)

            if lhsIsAggregate, !rhsIsAggregate,
               let raw = rawResultValues[lhs.rawValue],
               !bindings.isAggregateStructValue(raw)
            {
                return (raw, rhsValue)
            }
            if rhsIsAggregate, !lhsIsAggregate,
               let raw = rawResultValues[rhs.rawValue],
               !bindings.isAggregateStructValue(raw)
            {
                return (lhsValue, raw)
            }
            return (lhsValue, rhsValue)
        }

        func storeResult(_ result: KIRExprID?, _ value: LLVMCAPIBindings.LLVMValueRef?) {
            guard let result else {
                return
            }
            let storedValue = value ?? zeroLLVMValue(
                for: module.arena.exprType(result),
                lowering: typeLowering,
                int64Type: int64Type,
                context: context
            ) ?? zeroValue
            if let resultExpr = module.arena.expr(result),
               case let .symbolRef(targetSymbol) = resultExpr,
               let globalPointer = globalVariables[targetSymbol]
            {
                // Global slots hold the runtime's raw i64 handle.  A flat
                // string aggregate has to be bridged back first, otherwise the
                // 32-byte struct is written over the slot and its neighbours.
                var globalValue = storedValue
                if isStringAggregateType(module.arena.exprType(result)),
                   bindings.isAggregateStructValue(storedValue)
                {
                    globalValue = bridgeStringAggregateToRuntimeRaw(
                        storedValue,
                        suffix: nameCounter.nextName("store_result_global_")
                    ) ?? storedValue
                }
                _ = bindings.buildStore(builder, value: globalValue, pointer: globalPointer)
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
            let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: nameCounter.nextName("L"))
            if let block {
                labelBlocks[label] = block
            }
            return block
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
            argumentTypes: [TypeID?],
            result: KIRExprID?,
            instructionIndex: Int
        ) -> Bool {
            let builtinResult = lowerBuiltinCall(
                calleeName: calleeName,
                argumentValues: argumentValues,
                argumentTypes: argumentTypes,
                resultType: result.flatMap(module.arena.exprType),
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
            case .nop, .beginBlock, .endBlock, .beginFinallyGuard, .endFinallyGuard:
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
                let (lhsValue, rhsValue) = rawComparableValues(lhs: lhs, rhs: rhs)
                let condition = bindings.buildICmpEqual(
                    builder,
                    lhs: lhsValue,
                    rhs: rhsValue,
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
                    let varName = nameCounter.nextName("local_")
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
                        let debugStorageType = loweredLLVMType(
                            for: module.arena.exprType(result),
                            lowering: typeLowering,
                            defaultType: int64Type
                        )
                        let localAlloca = copyTargetAllocas[result.rawValue]
                            ?? buildEntrySlot(name: "dbg_\(varName)", type: debugStorageType)
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
                    let thrownSlot = buildEntrySlot(name: "notnull_thrown_\(instructionIndex)")
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
                            _ = bindings.buildRet(builder, value: zeroReturnValue)
                            currentBlock = continueBlock
                            bindings.positionBuilder(builder, at: continueBlock)
                        }
                    } else {
                        storeResult(result, operandValue)
                    }
                } else {
                    storeResult(result, operandValue)
                }

            case let .call(symbol, callee, arguments, result, usesThrownChannel, thrownResult, isSuperCall, qualifiedSuperType):
                // super calls always use direct dispatch – when virtual dispatch
                // is introduced the isSuperCall flag will bypass vtable lookup.
                // qualifiedSuperType provides additional context for super<Interface> calls
                _ = (isSuperCall, qualifiedSuperType)
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = arguments.map(resolveValue)
                let argumentTypes = arguments.map(module.arena.exprType)
                let externalCalleeName = Self.runtimePrimitiveAlias(
                    for: calleeName,
                    argumentCount: argumentValues.count
                ) ?? calleeName

                if emitFlatStringRuntimeCall(
                    calleeName: externalCalleeName,
                    arguments: arguments,
                    argumentValues: argumentValues,
                    result: result,
                    usesThrownChannel: usesThrownChannel,
                    thrownResult: thrownResult,
                    instructionIndex: instructionIndex
                ) {
                    continue
                }

                // Keep this collection empty: all print/println calls are lowered
                // through the bundled Kotlin source and the raw print bridge.
                if Self.knownVoidNoArgCallees.contains(calleeName) {
                    if let runtimeFunction = declareExternalFunction(
                        named: calleeName,
                        argumentCount: 0,
                        appendThrownChannel: false
                    ) {
                        _ = bindings.buildCall(
                            builder,
                            functionType: runtimeFunction.type,
                            callee: runtimeFunction.value,
                            arguments: [],
                            name: "\(calleeName)_\(instructionIndex)"
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
                    calleeName: externalCalleeName,
                    argumentValues: argumentValues,
                    argumentTypes: argumentTypes,
                    result: result,
                    instructionIndex: instructionIndex
                ) {
                    continue
                }

                // CORO-001: kk_channel_receive returns status out-of-band; payload via outValue.
                if calleeName == "kk_channel_receive" {
                    let outValueSlot = buildEntrySlot(name: "channel_out_value_\(instructionIndex)")
                    if let outValueSlot {
                        _ = bindings.buildStore(builder, value: zeroValue, pointer: outValueSlot)
                    }
                    if let receiveFunction = declareExternalFunction(
                        named: "kk_channel_receive",
                        argumentCount: 3,
                        appendThrownChannel: false
                    ) {
                        var receiveArgs = argumentValues
                        receiveArgs.append(outValueSlot ?? nullThrownPointer)
                        _ = bindings.buildCall(
                            builder,
                            functionType: receiveFunction.type,
                            callee: receiveFunction.value,
                            arguments: receiveArgs,
                            name: "channel_receive_\(instructionIndex)"
                        )
                        if let outValueSlot,
                           let loadedValue = bindings.buildLoad(
                               builder,
                               type: int64Type,
                               pointer: outValueSlot,
                               name: "channel_recv_val_\(instructionIndex)"
                           )
                        {
                            storeResult(result, loadedValue)
                        } else {
                            storeResult(result, zeroValue)
                        }
                    } else {
                        storeResult(result, zeroValue)
                    }
                    continue
                }

                // Function-value invokes carry the callable value as their first
                // argument.  The KIR symbol is intentionally retained for
                // InlineLoweringPass to match an inline function parameter, but
                // it must not be treated as a direct callee here: doing so turns
                // a captured parameter such as `transform` into an undefined
                // external `_transform` symbol (KSP-499 compiler regression).
                let isFunctionValueInvoke = Self.functionValueInvokeCallees.contains(calleeName)
                let normalizedSymbol: SymbolID? = if !isFunctionValueInvoke,
                                                       let symbol,
                                                       symbol != .invalid
                {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        argumentTypes: argumentTypes,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let calleeFunction: LLVMFunction?
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let effectiveExternalName = effectiveSymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
                let sourceExternalCallSignature = !isInternalCall
                    ? sourceExternalSignature(
                        for: effectiveSymbol,
                        argumentCount: argumentValues.count
                    )
                    : nil
                let shouldAppendThrownChannel = usesThrownChannel || isInternalCall || sourceExternalCallSignature != nil

                if let effectiveSymbol,
                   let internalFunction = internalFunctions[effectiveSymbol]
                {
                    calleeFunction = internalFunction
                } else if let fallbackInternal {
                    calleeFunction = fallbackInternal.function
                } else if calleeName.isEmpty {
                    calleeFunction = nil
                } else if Self.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
                    calleeFunction = declareExternalFunction(
                        named: "__kk_string_struct_get_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
                } else if let sourceExternalCallSignature {
                    var parameterTypes = loweredLLVMTypes(for: sourceExternalCallSignature.parameters)
                    if shouldAppendThrownChannel {
                        parameterTypes.append(outThrownPointerType)
                    }
                    calleeFunction = declareExternalFunction(
                        named: effectiveExternalName,
                        parameterTypes: parameterTypes,
                        returnType: loweredLLVMType(
                            for: sourceExternalCallSignature.returnType,
                            lowering: typeLowering,
                            defaultType: int64Type
                        )
                    )
                } else {
                    calleeFunction = declareExternalFunction(
                        named: externalCalleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: shouldAppendThrownChannel
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                var callArguments = argumentValues
                let internalSignature = internalSignature(for: effectiveSymbol)
                let typedSignature = isInternalCall ? internalSignature : sourceExternalCallSignature
                let isRuntimeCallbackRawABIInternalCall = isInternalCall
                    && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
                if let parameterTypes = typedSignature?.parameters {
                    callArguments = zip(argumentValues, parameterTypes).enumerated().map { index, pair in
                        let (argumentValue, parameterType) = pair
                        let argumentType = argumentTypes.indices.contains(index) ? argumentTypes[index] : nil
                        if isRuntimeCallbackRawABIInternalCall {
                            guard isStringAggregateType(argumentType) else {
                                return argumentValue
                            }
                            return bridgeStringAggregateToRuntimeRaw(
                                argumentValue,
                                suffix: "\(instructionIndex)_runtime_callback_arg\(index)"
                            ) ?? argumentValue
                        }
                        if isStringAggregateType(argumentType), !isStringAggregateType(parameterType) {
                            return bridgeStringAggregateToRuntimeRaw(
                                argumentValue,
                                suffix: "\(instructionIndex)_internal_arg\(index)"
                            ) ?? argumentValue
                        }
                        if !isStringAggregateType(argumentType), isStringAggregateType(parameterType) {
                            if arguments.indices.contains(index),
                               isZeroConstant(arguments[index]),
                               let typeLowering,
                               let nullString = buildNullStringAggregate(
                                   builder: builder,
                                   lowering: typeLowering,
                                   name: "string_null_internal_arg\(instructionIndex)_\(index)"
                               )
                            {
                                return nullString
                            }
                            return bridgeRuntimeRawToStringAggregate(
                                argumentValue,
                                suffix: "\(instructionIndex)_internal_arg\(index)"
                            ) ?? argumentValue
                        }
                        return argumentValue
                    }
                }
                let shouldBridgeExternalStringABI = !isInternalCall && sourceExternalCallSignature == nil && typeLowering != nil
                if shouldBridgeExternalStringABI {
                    callArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_arg\(index)"
                        ) ?? argumentValue
                    }
                }
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                if shouldAppendThrownChannel {
                    if usesThrownChannel {
                        let thrownSlot = buildEntrySlot(name: "thrown_slot_\(instructionIndex)")
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
                if let result, let callValue {
                    rawResultValues[result.rawValue] = callValue
                }
                let storedCallValue: LLVMCAPIBindings.LLVMValueRef?
                if isInternalCall,
                   let effectiveSymbol,
                   runtimeCallbackRawReturnSymbols.contains(effectiveSymbol),
                   let result,
                   isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_runtime_callback_result"
                    ) ?? callValue
                } else if isInternalCall,
                          let effectiveSymbol,
                          runtimeCallbackRawReturnSymbols.contains(effectiveSymbol)
                {
                    storedCallValue = callValue
                } else if isInternalCall,
                   let result,
                   let returnType = internalSignature?.returnType,
                   isStringAggregateType(returnType),
                   !isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeStringAggregateToRuntimeRaw(
                        callValue,
                        suffix: "\(instructionIndex)_internal_result"
                    ) ?? callValue
                } else if isInternalCall,
                          let result,
                          let returnType = internalSignature?.returnType,
                          !isStringAggregateType(returnType),
                          isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_internal_result"
                    ) ?? callValue
                } else if sourceExternalCallSignature != nil,
                          let result,
                          let returnType = sourceExternalCallSignature?.returnType,
                          isStringAggregateType(returnType),
                          !isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeStringAggregateToRuntimeRaw(
                        callValue,
                        suffix: "\(instructionIndex)_source_external_result"
                    ) ?? callValue
                } else if sourceExternalCallSignature != nil,
                          let result,
                          let returnType = sourceExternalCallSignature?.returnType,
                          !isStringAggregateType(returnType),
                          isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_source_external_result"
                    ) ?? callValue
                } else if shouldBridgeExternalStringABI,
                   let result,
                   isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_result"
                    ) ?? callValue
                } else {
                    storedCallValue = callValue
                }
                storeResult(result, storedCallValue)
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
                        _ = bindings.buildRet(builder, value: zeroReturnValue)

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
                let argumentTypes = [module.arena.exprType(receiver)] + arguments.map(module.arena.exprType)
                let isThrowableToStringVirtualCall: Bool = {
                    guard case .vtable = dispatch,
                          let symbols
                    else {
                        return false
                    }
                    let isToString = calleeName == "toString"
                        || symbol.flatMap { symbols.symbol($0) }
                            .map { interner.resolve($0.name) == "toString" } == true
                    guard isToString else {
                        return false
                    }
                    if let symbol,
                       Self.isThrowableToStringSymbol(symbol, interner: interner, symbols: symbols)
                    {
                        return true
                    }
                    guard let typeSystem else {
                        return false
                    }
                    return Self.isThrowableType(
                        module.arena.exprType(receiver),
                        typeSystem: typeSystem,
                        interner: interner,
                        symbols: symbols
                    )
                }()
                let externalCalleeName = Self.runtimePrimitiveAlias(
                    for: calleeName,
                    argumentCount: argumentValues.count
                ) ?? calleeName

                let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        argumentTypes: argumentTypes,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let effectiveExternalName = effectiveSymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
                let sourceExternalCallSignature = !isInternalCall
                    ? sourceExternalSignature(
                        for: effectiveSymbol,
                        argumentCount: argumentValues.count
                    )
                    : nil
                let virtualSourceCallSignature: (parameters: [TypeID], returnType: TypeID)? = {
                    guard !isInternalCall,
                          let effectiveSymbol,
                          let symbols,
                          let signature = symbols.functionSignature(for: effectiveSymbol),
                          let linkName = symbols.externalLinkName(for: effectiveSymbol),
                          linkName.hasPrefix("kk_fn_"),
                          (
                              isStringAggregateType(signature.returnType)
                                  || [signature.receiverType].compactMap { $0 }.contains(where: isStringAggregateType)
                                  || signature.parameterTypes.contains(where: isStringAggregateType)
                          )
                    else {
                        return nil
                    }
                    let parameters = [signature.receiverType].compactMap { $0 } + signature.parameterTypes
                    guard parameters.count == argumentValues.count else {
                        return nil
                    }
                    return (parameters: parameters, returnType: signature.returnType)
                }()
                // An interface declaration imported from a library is not in the
                // consumer's internal function table, but its itable entries point
                // at generated Kotlin functions, which always carry the hidden
                // thrown channel. Keep the indirect function type consistent with
                // that source-backed ABI (KSP-712).
                let shouldAppendThrownChannel = usesThrownChannel
                    || isInternalCall
                    || sourceExternalCallSignature != nil
                    || virtualSourceCallSignature != nil
                let sourceExternalFunction: LLVMFunction? = if let sourceCallSignature =
                    virtualSourceCallSignature ?? sourceExternalCallSignature
                {
                    {
                        var parameterTypes = loweredLLVMTypes(for: sourceCallSignature.parameters)
                        if shouldAppendThrownChannel {
                            parameterTypes.append(outThrownPointerType)
                        }
                        return declareExternalFunction(
                            named: effectiveExternalName,
                            parameterTypes: parameterTypes,
                            returnType: loweredLLVMType(
                                for: sourceCallSignature.returnType,
                                lowering: typeLowering,
                                defaultType: int64Type
                            )
                        )
                    }()
                } else {
                    nil
                }

                let calleeFunction: LLVMFunction? = if let effectiveSymbol,
                                                       let internalFunction = internalFunctions[effectiveSymbol]
                {
                    internalFunction
                } else if let fallbackInternal {
                    fallbackInternal.function
                } else if calleeName.isEmpty {
                    nil
                } else if Self.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
                    declareExternalFunction(
                        named: "__kk_string_struct_get_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
                } else if isThrowableToStringVirtualCall {
                    declareExternalFunction(
                        named: "__kk_throwable_toString",
                        argumentCount: argumentValues.count,
                        appendThrownChannel: true
                    )
                } else if sourceExternalFunction != nil {
                    sourceExternalFunction
                } else {
                    declareExternalFunction(
                        named: externalCalleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: shouldAppendThrownChannel
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                let calleeKIRFunction = effectiveSymbol.flatMap { module.arena.function(for: $0) }
                let isRuntimeCallbackRawABIVirtualCall = isInternalCall
                    && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
                let shouldBridgeVirtualExternalStringABI = !isInternalCall
                    && typeLowering != nil
                    && (virtualSourceCallSignature == nil || isThrowableToStringVirtualCall)
                var virtualCallArguments = argumentValues
                if isRuntimeCallbackRawABIVirtualCall {
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_virtual_callback_arg\(index)"
                        ) ?? argumentValue
                    }
                } else if shouldBridgeVirtualExternalStringABI {
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_virtual_arg\(index)"
                        ) ?? argumentValue
                    }
                } else if isInternalCall,
                          let calleeKIRFunction
                {
                    // Interface dispatch through a KIR-declared function may see a
                    // String aggregate at the call site while the erased interface
                    // parameter is a raw pointer (or vice-versa). Convert across the
                    // boundary so the looked-up function pointer receives/returns the
                    // ABI expected by its KIR signature.
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        let paramType = index < calleeKIRFunction.params.count
                            ? calleeKIRFunction.params[index].type
                            : nil
                        return coerceStringValueForType(
                            argumentValue,
                            from: argumentType,
                            to: paramType,
                            suffix: "\(instructionIndex)_virtual_internal_arg\(index)"
                        )
                    }
                }

                let lookupFunction: LLVMFunction?
                var lookupArgs: [LLVMCAPIBindings.LLVMValueRef] = []
                // The receiver used for the lookup must have the same runtime
                // representation as the indirect getter call. A bundled
                // CharSequence extension may still carry a flat String
                // aggregate at this point; `virtualCallArguments` performs the
                // required boxing before the getter is invoked, while using the
                // original aggregate here makes the runtime look up a bogus
                // object address and report a missing itable entry.
                let lookupReceiver = virtualCallArguments.first ?? resolveValue(receiver)
                switch dispatch {
                case let .vtable(slot):
                    lookupFunction = declareExternalFunction(named: "kk_vtable_lookup", argumentCount: 2, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(slot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                case let .itable(interfaceSlot, methodSlot):
                    lookupFunction = declareExternalFunction(named: "kk_itable_lookup", argumentCount: 3, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(interfaceSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                        bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                case let .itableDynamic(interfaceTypeID, methodSlot):
                    lookupFunction = declareExternalFunction(named: "kk_itable_lookup_dynamic", argumentCount: 3, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(bitPattern: interfaceTypeID)) ?? bindings.constInt(int64Type, value: 0)!,
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
                // call kk_dispatch_error runtime trap instead of falling back
                // to direct dispatch (GEN-002).
                guard let isNonNull = bindings.buildICmpNotEqual(
                    builder,
                    lhs: fptrRaw,
                    rhs: zeroValue,
                    name: "lookup_nonnull_\(instructionIndex)"
                ),
                    let useVirtualBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "lookup_ok_\(instructionIndex)"
                    ),
                    let fallbackBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "lookup_fallback_\(instructionIndex)"
                    ),
                    let mergeBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "vcall_merge_\(instructionIndex)"
                    )
                else {
                    continue
                }

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

                var callArguments = virtualCallArguments
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                if shouldAppendThrownChannel {
                    if usesThrownChannel {
                        let thrownSlot = buildEntrySlot(name: "vthrown_slot_\(instructionIndex)")
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
                if let result, let vCallValue {
                    rawResultValues[result.rawValue] = vCallValue
                }
                _ = bindings.buildBr(builder, destination: mergeBlock)

                // Fallback path: trap on dispatch failure (GEN-002).
                bindings.positionBuilder(builder, at: fallbackBlock)
                if let trapFn = declareExternalFunction(named: "kk_dispatch_error", argumentCount: 0, appendThrownChannel: false) {
                    _ = bindings.buildCall(builder, functionType: trapFn.type, callee: trapFn.value, arguments: [], name: "trap_\(instructionIndex)")
                }
                _ = bindings.buildUnreachable(builder)

                // Merge: use the virtual call result.
                bindings.positionBuilder(builder, at: mergeBlock)
                currentBlock = mergeBlock
                let mergedValue: LLVMCAPIBindings.LLVMValueRef
                if isRuntimeCallbackRawABIVirtualCall,
                   let result,
                   isStringAggregateExpr(result),
                   let vCallValue
                {
                    mergedValue = bridgeRuntimeRawToStringAggregate(
                        vCallValue,
                        suffix: "\(instructionIndex)_virtual_callback_result"
                    ) ?? vCallValue
                } else if shouldBridgeVirtualExternalStringABI,
                          let result,
                          isStringAggregateExpr(result),
                          let vCallValue
                {
                    mergedValue = bridgeRuntimeRawToStringAggregate(
                        vCallValue,
                        suffix: "\(instructionIndex)_virtual_result"
                    ) ?? vCallValue
                } else if isInternalCall,
                          let result,
                          let resultExprType = module.arena.exprType(result),
                          let vCallValue,
                          let calleeKIRFunction
                {
                    mergedValue = coerceStringValueForType(
                        vCallValue,
                        from: calleeKIRFunction.returnType,
                        to: resultExprType,
                        suffix: "\(instructionIndex)_virtual_internal_result"
                    )
                } else {
                    mergedValue = vCallValue ?? zeroValue
                }
                storeResult(result, mergedValue)

                // Handle thrown channel from virtual dispatch.
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
                        _ = bindings.buildRet(builder, value: zeroReturnValue)

                        currentBlock = continueBlock
                        bindings.positionBuilder(builder, at: continueBlock)
                    }
                }

            case let .jumpIfNotNull(value, target):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                let valueType = module.arena.exprType(value)
                if let valueType,
                   let typeLowering,
                   let typeSystem,
                   case .stringStruct = typeSystem.kind(of: valueType),
                   let dataPointer = bindings.buildExtractValue(
                       builder,
                       aggregate: resolved,
                       index: 0,
                       name: "jnn_string_data_\(instructionIndex)"
                   ),
                   let nullPointer = bindings.constPointerNull(typeLowering.dataPointerType),
                   let condition = bindings.buildICmpNotEqual(
                       builder,
                       lhs: dataPointer,
                       rhs: nullPointer,
                       name: "jnn_string_nonnull_\(instructionIndex)"
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
                    continue
                }
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
                let condition: LLVMCAPIBindings.LLVMValueRef? = if nullableRawScalarPreservesZero(valueType) {
                    isNotSentinel
                } else if let isNonZero,
                          let isNotSentinel
                {
                    bindings.buildAnd(
                        builder,
                        lhs: isNonZero,
                        rhs: isNotSentinel,
                        name: "jnn_cond_\(instructionIndex)"
                    )
                } else {
                    nil
                }
                if let condition,
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
                var copySource = resolveValue(from)
                let fromType = module.arena.exprType(from)
                let toType = module.arena.exprType(to)
                // If the copy target is a global symbolRef, store to the
                // LLVM global variable so the write persists across reads.
                if let targetExpr = module.arena.expr(to),
                   case let .symbolRef(targetSymbol) = targetExpr,
                   let globalPtr = globalVariables[targetSymbol]
                {
                    if isStringAggregateType(fromType) {
                        copySource = bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_global_\(instructionIndex)"
                        ) ?? copySource
                    }
                    _ = bindings.buildStore(builder, value: copySource, pointer: globalPtr)
                } else {
                    if isStringAggregateType(fromType), !isStringAggregateType(toType) {
                        copySource = bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    } else if !isStringAggregateType(fromType), isStringAggregateType(toType) {
                        copySource = bridgeRuntimeRawToStringAggregate(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    }
                    if let alloca = copyTargetAllocas[to.rawValue] {
                        _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
                    } else {
                        storeResult(to, copySource)
                    }
                }

            case let .storeGlobal(value, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                var resolved = resolveValue(value)
                if isStringAggregateType(module.arena.exprType(value)) {
                    resolved = bridgeStringAggregateToRuntimeRaw(
                        resolved,
                        suffix: "store_global_\(instructionIndex)"
                    ) ?? resolved
                }
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
                        name: nameCounter.nextName("load_global_")
                    ) {
                        let loadedValue = if isStringAggregateType(module.arena.exprType(result)) {
                            bridgeRuntimeRawToStringAggregate(
                                loaded,
                                suffix: "load_global_\(instructionIndex)"
                            ) ?? loaded
                        } else {
                            loaded
                        }
                        storeResult(result, loadedValue)
                    }
                } else {
                    let missingValue = if isStringAggregateType(module.arena.exprType(result)) {
                        bridgeRuntimeRawToStringAggregate(
                            zeroValue,
                            suffix: "load_global_missing_\(instructionIndex)"
                        ) ?? zeroValue
                    } else {
                        zeroValue
                    }
                    storeResult(result, missingValue)
                }

            case let .rethrow(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
                emitFramePop("rethrow_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroReturnValue)

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

                let (lhsValue, rhsValue) = rawComparableValues(lhs: lhs, rhs: rhs)
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
                _ = bindings.buildRet(builder, value: zeroReturnValue)

            case let .returnValue(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolvedReturnValue = resolveValue(value)
                let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                    bridgeStringAggregateToRuntimeRaw(
                        resolvedReturnValue,
                        suffix: "return_\(instructionIndex)"
                    ) ?? resolvedReturnValue
                } else {
                    coerceStringValueForType(
                        resolvedReturnValue,
                        from: module.arena.exprType(value),
                        to: function.returnType,
                        suffix: "return_\(instructionIndex)"
                    )
                }
                emitFramePop("ret_val_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: returnValue)

            case let .nonLocalReturn(value):
                // Non-local returns should have been lowered by InlineLoweringPass.
                // If one reaches codegen, it indicates a lowering bug. Emit a
                // trap in debug builds; in release builds fall back to a return
                // to avoid crashing the compiler, but the output is incorrect.
                assertionFailure("nonLocalReturn reached codegen -- InlineLoweringPass should have converted it")
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                emitFramePop("ret_nonlocal_\(instructionIndex)")
                if let value {
                    let resolvedReturnValue = resolveValue(value)
                    let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                        bridgeStringAggregateToRuntimeRaw(
                            resolvedReturnValue,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        ) ?? resolvedReturnValue
                    } else {
                        coerceStringValueForType(
                            resolvedReturnValue,
                            from: module.arena.exprType(value),
                            to: function.returnType,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        )
                    }
                    _ = bindings.buildRet(builder, value: returnValue)
                } else {
                    _ = bindings.buildRet(builder, value: zeroReturnValue)
                }
            }
        }

        if !bindings.hasTerminator(currentBlock) {
            emitFramePop("ret_fallthrough")
            _ = bindings.buildRet(builder, value: zeroReturnValue)
        }
    }

    /// Maximum KIR argument count per external callee name within a function body.
    /// Declarations are keyed only by name; if the first emitted call is arity-0 bootstrap noise
    /// (e.g. synthetic kotlin.math loads) and a later call passes arguments, LLVM must still
    /// declare the symbol with the maximum arity seen for declareExternalFunction.
    fileprivate static func maxKIRArgumentCountByExternalCallee(
        body: [KIRInstruction],
        interner: StringInterner
    ) -> [String: Int] {
        var maxCount: [String: Int] = [:]
        for instruction in body {
            switch instruction {
            case let .call(_, callee, arguments, _, _, _, _, _):
                let raw = interner.resolve(callee)
                guard !raw.isEmpty else { continue }
                let effective = effectiveExternalCalleeNameForArity(raw, argumentCount: arguments.count)
                maxCount[effective, default: 0] = max(maxCount[effective, default: 0], arguments.count)
            case let .virtualCall(_, callee, _, arguments, _, _, _, _):
                let name = interner.resolve(callee)
                guard !name.isEmpty else { continue }
                let receiverPlusArgs = 1 + arguments.count
                maxCount[name, default: 0] = max(maxCount[name, default: 0], receiverPlusArgs)
            default:
                break
            }
        }
        return maxCount
    }

    private static func effectiveExternalCalleeNameForArity(_ calleeName: String, argumentCount: Int) -> String {
        if isStringLengthAggregateAccessorName(calleeName), argumentCount == 1 {
            "__kk_string_struct_get_length"
        } else {
            calleeName
        }
    }

    private static func isStringLengthAggregateAccessorName(_ calleeName: String) -> Bool {
        calleeName == "length"
            || calleeName == "__kk_string_struct_get_length"
            || calleeName == "kk_string_struct_get_length"
    }

    private static func runtimePrimitiveAlias(for calleeName: String, argumentCount: Int) -> String? {
        switch calleeName {
        case "and": "kk_bitwise_and"
        case "or": "kk_bitwise_or"
        case "xor": "kk_bitwise_xor"
        case "__doubleRoundToInt": "kk_double_roundToInt"
        case "__floatRoundToInt": "kk_float_roundToInt"
        case "__doubleRoundToLong": "kk_double_roundToLong"
        case "__floatRoundToLong": "kk_float_roundToLong"
        case "__assert": "kk_precondition_assert"
        case "__assertLazy": "kk_precondition_assert_lazy"
        default: nil
        }
    }
}
