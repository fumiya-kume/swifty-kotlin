import Foundation

public final class LLVMCAPIBackend: CodegenBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let diagnostics: DiagnosticEngine
    private let strictMode: Bool
    private let bindings: LLVMCAPIBindings?
    private let hasUsableBindings: Bool

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        emitsDebugInfo: Bool,
        diagnostics: DiagnosticEngine,
        strictMode: Bool = false
    ) {
        self.target = target
        self.optLevel = optLevel
        _ = emitsDebugInfo
        self.diagnostics = diagnostics
        self.strictMode = strictMode

        let loadedBindings = LLVMCAPIBindings.load()
        self.bindings = loadedBindings
        self.hasUsableBindings = loadedBindings?.smokeTestContextLifecycle() == true
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner
    ) throws {
        _ = runtime
        try emitNative(
            context: "object",
            nativeEmit: { bindings in
                let emitter = NativeEmitter(
                    target: target,
                    optLevel: optLevel,
                    bindings: bindings,
                    module: module,
                    interner: interner
                )
                try emitter.emitObject(outputPath: outputObjectPath)
            }
        )
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner
    ) throws {
        _ = runtime
        try emitNative(
            context: "LLVM IR",
            nativeEmit: { bindings in
                let emitter = NativeEmitter(
                    target: target,
                    optLevel: optLevel,
                    bindings: bindings,
                    module: module,
                    interner: interner
                )
                try emitter.emitLLVMIR(outputPath: outputIRPath)
            }
        )
    }

    private func emitNative(
        context: String,
        nativeEmit: (LLVMCAPIBindings) throws -> Void
    ) throws {
        guard let bindings, hasUsableBindings else {
            if strictMode {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1003",
                    "LLVM C API backend is requested in strict mode, but LLVM C API bindings are unavailable.",
                    range: nil
                )
                throw LLVMCAPIBackendError.bindingsUnavailable
            }
            diagnostics.error(
                "KSWIFTK-BACKEND-1007",
                "LLVM C API backend is requested, but LLVM C API bindings are unavailable and fallback backend is disabled.",
                range: nil
            )
            throw LLVMCAPIBackendError.bindingsUnavailable
        }

        do {
            try nativeEmit(bindings)
        } catch {
            let reason = describe(error: error)
            if strictMode {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1004",
                    "LLVM C API backend failed to emit \(context) in strict mode: \(reason)",
                    range: nil
                )
                throw LLVMCAPIBackendError.nativeEmissionFailed(reason)
            }
            diagnostics.error(
                "KSWIFTK-BACKEND-1006",
                "LLVM C API backend failed to emit \(context): \(reason)",
                range: nil
            )
            throw LLVMCAPIBackendError.nativeEmissionFailed(reason)
        }
    }

    private func describe(error: Error) -> String {
        if let backendError = error as? LLVMCAPIBackendError {
            switch backendError {
            case .bindingsUnavailable:
                return "backend unavailable"
            case .nativeEmissionFailed(let reason):
                return reason
            }
        }
        return String(describing: error)
    }
}

enum LLVMCAPIBackendError: Error {
    case bindingsUnavailable
    case nativeEmissionFailed(String)
}

private struct NativeEmitter {
    private struct LLVMFunction {
        let value: LLVMCAPIBindings.LLVMValueRef
        let type: LLVMCAPIBindings.LLVMTypeRef
    }

    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let bindings: LLVMCAPIBindings
    private let module: KIRModule
    private let interner: StringInterner

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        bindings: LLVMCAPIBindings,
        module: KIRModule,
        interner: StringInterner
    ) {
        self.target = target
        self.optLevel = optLevel
        self.bindings = bindings
        self.module = module
        self.interner = interner
    }

    func emitLLVMIR(outputPath: String) throws {
        let built = try buildModule()
        defer {
            bindings.disposeModule(built.module)
            bindings.disposeContext(built.context)
        }

        guard let llvmIR = bindings.printModule(built.module) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMPrintModuleToString returned null")
        }
        do {
            try llvmIR.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to write LLVM IR to '\(outputPath)'")
        }
    }

    func emitObject(outputPath: String) throws {
        let built = try buildModule()
        defer {
            bindings.disposeModule(built.module)
            bindings.disposeContext(built.context)
        }

        var triple = targetTripleString()
        bindings.setTarget(built.module, triple: triple)

        var targetMachine = bindings.createTargetMachine(triple: triple, optLevel: optLevel)
        if targetMachine == nil,
           let hostTriple = bindings.defaultTargetTriple(),
           !hostTriple.isEmpty,
           hostTriple != triple {
            triple = hostTriple
            bindings.setTarget(built.module, triple: triple)
            targetMachine = bindings.createTargetMachine(triple: hostTriple, optLevel: optLevel)
        }

        guard let targetMachine else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create LLVM target machine")
        }
        defer { bindings.disposeTargetMachine(targetMachine) }

        guard bindings.applyTargetMachine(targetMachine, to: built.module) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to apply target data layout")
        }

        if let errorMessage = bindings.emitObject(targetMachine: targetMachine, module: built.module, outputPath: outputPath) {
            throw LLVMCAPIBackendError.nativeEmissionFailed(errorMessage)
        }
    }

    private func buildModule() throws -> (
        context: LLVMCAPIBindings.LLVMContextRef,
        module: LLVMCAPIBindings.LLVMModuleRef
    ) {
        guard let context = bindings.createContext() else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMContextCreate returned null")
        }
        guard let llvmModule = bindings.createModule(name: "kswiftk_module", context: context) else {
            bindings.disposeContext(context)
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMModuleCreateWithNameInContext returned null")
        }

        let triple = targetTripleString()
        bindings.setTarget(llvmModule, triple: triple)

        guard let int64Type = bindings.int64Type(context: context) else {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMInt64TypeInContext returned null")
        }
        guard let outThrownPointerType = bindings.pointerType(int64Type, addressSpace: 0) else {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMPointerType returned null")
        }

        var internalFunctions: [SymbolID: LLVMFunction] = [:]

        for declaration in module.arena.declarations {
            guard case .function(let function) = declaration else {
                continue
            }
            let functionName = LLVMBackend.cFunctionSymbol(for: function, interner: interner)
            var parameterTypes = Array(repeating: int64Type, count: function.params.count)
            parameterTypes.append(outThrownPointerType)

            guard let functionType = bindings.functionType(returnType: int64Type, parameters: parameterTypes, isVarArg: false),
                  let functionValue = bindings.addFunction(module: llvmModule, name: functionName, functionType: functionType) else {
                bindings.disposeModule(llvmModule)
                bindings.disposeContext(context)
                throw LLVMCAPIBackendError.nativeEmissionFailed("failed to declare function '\(functionName)'")
            }
            internalFunctions[function.symbol] = LLVMFunction(value: functionValue, type: functionType)
        }

        for declaration in module.arena.declarations {
            guard case .function(let function) = declaration,
                  let llvmFunction = internalFunctions[function.symbol] else {
                continue
            }
            do {
                try emitFunctionBody(
                    function: function,
                    llvmFunction: llvmFunction,
                    llvmModule: llvmModule,
                    context: context,
                    int64Type: int64Type,
                    outThrownPointerType: outThrownPointerType,
                    internalFunctions: internalFunctions
                )
            } catch {
                bindings.disposeModule(llvmModule)
                bindings.disposeContext(context)
                throw error
            }
        }

        return (context: context, module: llvmModule)
    }

    private func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction]
    ) throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        defer { bindings.disposeBuilder(builder) }

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
            switch expression {
            case .intLiteral(let number):
                return bindings.constInt(int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? zeroValue
            case .boolLiteral(let value):
                return bindings.constInt(int64Type, value: value ? 1 : 0) ?? zeroValue
            case .stringLiteral(let interned):
                let text = interner.resolve(interned)
                let literalID: Int32
                if let expressionRawID {
                    literalID = expressionRawID
                } else {
                    literalID = generatedStringLiteralCount
                    generatedStringLiteralCount += 1
                }
                guard let globalStringPointer = bindings.buildGlobalStringPtr(
                    builder,
                    value: text,
                    name: "str_lit_\(literalID)"
                ) else {
                    return zeroValue
                }
                guard let pointerAsInt = bindings.buildPtrToInt(
                    builder,
                    value: globalStringPointer,
                    type: int64Type,
                    name: "str_ptr_\(literalID)"
                ) else {
                    return zeroValue
                }
                let lengthValue = bindings.constInt(int64Type, value: UInt64(text.utf8.count)) ?? zeroValue
                guard let stringFromUTF8 = declareExternalFunction(
                    named: "kk_string_from_utf8",
                    argumentCount: 2,
                    appendThrownChannel: false
                ) else {
                    return zeroValue
                }
                return bindings.buildCall(
                    builder,
                    functionType: stringFromUTF8.type,
                    callee: stringFromUTF8.value,
                    arguments: [pointerAsInt, lengthValue],
                    name: "str_from_utf8_\(literalID)"
                ) ?? zeroValue
            case .symbolRef(let symbol):
                return parameterValues[symbol] ?? zeroValue
            case .temporary(let raw):
                return bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64(raw)),
                    signExtend: true
                ) ?? zeroValue
            case .unit:
                return zeroValue
            }
        }

        func resolveValue(_ id: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef {
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

        func emitBuiltinCall(
            calleeName: String,
            argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            result: KIRExprID?,
            instructionIndex: Int
        ) -> Bool {
            let lhs = argumentValues.count > 0 ? argumentValues[0] : zeroValue
            let rhs = argumentValues.count > 1 ? argumentValues[1] : zeroValue

            let lowered: LLVMCAPIBindings.LLVMValueRef?
            switch calleeName {
            case "kk_op_add":
                lowered = bindings.buildAdd(builder, lhs: lhs, rhs: rhs, name: "add_\(instructionIndex)")
            case "kk_op_sub":
                lowered = bindings.buildSub(builder, lhs: lhs, rhs: rhs, name: "sub_\(instructionIndex)")
            case "kk_op_mul":
                lowered = bindings.buildMul(builder, lhs: lhs, rhs: rhs, name: "mul_\(instructionIndex)")
            case "kk_op_div":
                lowered = bindings.buildSDiv(builder, lhs: lhs, rhs: rhs, name: "div_\(instructionIndex)")
            case "kk_op_eq":
                if let compared = bindings.buildICmpEqual(builder, lhs: lhs, rhs: rhs, name: "eq_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "eq64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            default:
                return false
            }

            storeResult(result, lowered)
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
                }
                storeResult(result, lowered)

            case .call(let symbol, let callee, let arguments, let result, let usesThrownChannel):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = arguments.map(resolveValue)

                if calleeName == "println" || calleeName == "kk_println_any" {
                    storeResult(result, zeroValue)
                    continue
                }

                if calleeName == "kk_when_select" {
                    let selectedValue = argumentValues.dropFirst().first ?? argumentValues.first ?? zeroValue
                    storeResult(result, selectedValue)
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
                if shouldAppendThrownChannel {
                    if usesThrownChannel, let outThrownParameter {
                        callArguments.append(outThrownParameter)
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
                _ = bindings.buildRet(builder, value: lhsValue)

                currentBlock = falseBlock
                bindings.positionBuilder(builder, at: falseBlock)

            case .returnUnit:
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                _ = bindings.buildRet(builder, value: zeroValue)

            case .returnValue(let value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                _ = bindings.buildRet(builder, value: resolveValue(value))
            }
        }

        if !bindings.hasTerminator(currentBlock) {
            _ = bindings.buildRet(builder, value: zeroValue)
        }
    }

    private func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
