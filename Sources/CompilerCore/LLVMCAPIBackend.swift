import Foundation

public final class LLVMCAPIBackend: CodegenBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    private let diagnostics: DiagnosticEngine
    private let isStrictMode: Bool
    private let bindings: LLVMCAPIBindings?
    private let hasUsableBindings: Bool

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine,
        isStrictMode: Bool = false
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics
        self.isStrictMode = isStrictMode

        let loadedBindings = LLVMCAPIBindings.load()
        self.bindings = loadedBindings
        self.hasUsableBindings = loadedBindings?.smokeTestContextLifecycle() == true
    }

    @available(*, deprecated, message: "Use init(target:optLevel:debugInfo:diagnostics:isStrictMode:) instead.")
    public convenience init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        emitsDebugInfo: Bool,
        diagnostics: DiagnosticEngine,
        isStrictMode: Bool = false
    ) {
        self.init(
            target: target,
            optLevel: optLevel,
            debugInfo: emitsDebugInfo,
            diagnostics: diagnostics,
            isStrictMode: isStrictMode
        )
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
        _ = debugInfo
        guard let bindings, hasUsableBindings else {
            if isStrictMode {
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
            if isStrictMode {
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

        do {
            try defineFrameRuntimeStubs(
                module: llvmModule,
                context: context,
                int64Type: int64Type
            )
        } catch {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw error
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

    private func defineFrameRuntimeStubs(
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) throws {
        _ = try defineNoOpRuntimeFunction(
            named: "kk_register_frame_map",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineNoOpRuntimeFunction(
            named: "kk_push_frame",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineNoOpRuntimeFunction(
            named: "kk_pop_frame",
            argumentCount: 0,
            module: module,
            context: context,
            int64Type: int64Type
        )
    }

    private func defineNoOpRuntimeFunction(
        named name: String,
        argumentCount: Int,
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) throws -> LLVMFunction {
        let parameterTypes = Array(repeating: int64Type, count: max(0, argumentCount))
        guard let functionType = bindings.functionType(
            returnType: int64Type,
            parameters: parameterTypes,
            isVarArg: false
        ) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create runtime stub type for '\(name)'")
        }
        guard let functionValue = bindings.getNamedFunction(module: module, name: name)
            ?? bindings.addFunction(module: module, name: name, functionType: functionType) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to define runtime stub '\(name)'")
        }
        bindings.setInternalLinkage(functionValue)

        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create builder for runtime stub '\(name)'")
        }
        defer { bindings.disposeBuilder(builder) }

        guard let entry = bindings.appendBasicBlock(context: context, function: functionValue, name: "entry") else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create runtime stub block for '\(name)'")
        }
        bindings.positionBuilder(builder, at: entry)
        let zero = bindings.constInt(int64Type, value: 0) ?? bindings.getUndef(type: int64Type)
        _ = bindings.buildRet(builder, value: zero)
        return LLVMFunction(value: functionValue, type: functionType)
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
            switch expression {
            case .intLiteral(let number):
                return bindings.constInt(int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? zeroValue
            case .longLiteral(let number):
                return bindings.constInt(int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? zeroValue
            case .floatLiteral(let value):
                var f = Float(value)
                var bits: UInt32 = 0
                memcpy(&bits, &f, MemoryLayout<UInt32>.size)
                return bindings.constInt(int64Type, value: UInt64(bits)) ?? zeroValue
            case .doubleLiteral(let value):
                var d = value
                var bits: UInt64 = 0
                memcpy(&bits, &d, MemoryLayout<UInt64>.size)
                return bindings.constInt(int64Type, value: bits) ?? zeroValue
            case .charLiteral(let scalar):
                return bindings.constInt(int64Type, value: UInt64(scalar)) ?? zeroValue
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
                if let parameter = parameterValues[symbol] {
                    return parameter
                }
                if let internalFunction = internalFunctions[symbol],
                   let functionPointer = bindings.buildPtrToInt(
                    builder,
                    value: internalFunction.value,
                    type: int64Type,
                    name: "fn_ptr_\(symbol.rawValue)"
                   ) {
                    return functionPointer
                }
                return zeroValue
            case .temporary(let raw):
                return bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64(raw)),
                    signExtend: true
                ) ?? zeroValue
            case .null:
                return bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64.min),
                    signExtend: true
                ) ?? zeroValue
            case .unit:
                return zeroValue
            }
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
            case "kk_op_ne":
                if let compared = bindings.buildICmpNotEqual(builder, lhs: lhs, rhs: rhs, name: "ne_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "ne64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_lt":
                if let compared = bindings.buildICmpSignedLessThan(builder, lhs: lhs, rhs: rhs, name: "lt_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "lt64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_le":
                if let compared = bindings.buildICmpSignedLessOrEqual(builder, lhs: lhs, rhs: rhs, name: "le_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "le64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_gt":
                if let compared = bindings.buildICmpSignedGreaterThan(builder, lhs: lhs, rhs: rhs, name: "gt_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "gt64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_ge":
                if let compared = bindings.buildICmpSignedGreaterOrEqual(builder, lhs: lhs, rhs: rhs, name: "ge_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: compared, type: int64Type, name: "ge64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_and":
                if let lhsBool = buildBoolCondition(from: lhs, name: "and_lhs_\(instructionIndex)"),
                   let rhsBool = buildBoolCondition(from: rhs, name: "and_rhs_\(instructionIndex)"),
                   let lhsInt = bindings.buildZExt(builder, value: lhsBool, type: int64Type, name: "and_lhs64_\(instructionIndex)"),
                   let rhsInt = bindings.buildZExt(builder, value: rhsBool, type: int64Type, name: "and_rhs64_\(instructionIndex)") {
                    lowered = bindings.buildMul(builder, lhs: lhsInt, rhs: rhsInt, name: "and64_\(instructionIndex)")
                } else {
                    lowered = nil
                }
            case "kk_op_or":
                if let lhsBool = buildBoolCondition(from: lhs, name: "or_lhs_\(instructionIndex)"),
                   let rhsBool = buildBoolCondition(from: rhs, name: "or_rhs_\(instructionIndex)"),
                   let lhsInt = bindings.buildZExt(builder, value: lhsBool, type: int64Type, name: "or_lhs64_\(instructionIndex)"),
                   let rhsInt = bindings.buildZExt(builder, value: rhsBool, type: int64Type, name: "or_rhs64_\(instructionIndex)"),
                   let sum = bindings.buildAdd(builder, lhs: lhsInt, rhs: rhsInt, name: "or_sum_\(instructionIndex)"),
                   let nonZero = bindings.buildICmpNotEqual(builder, lhs: sum, rhs: zeroValue, name: "or_nonzero_\(instructionIndex)") {
                    lowered = bindings.buildZExt(builder, value: nonZero, type: int64Type, name: "or64_\(instructionIndex)")
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

            case .select(let condition, let thenValue, let elseValue, let result):
                let conditionValue = resolveValue(condition)
                guard let loweredCondition = buildBoolCondition(
                    from: conditionValue,
                    name: "select_cond_\(instructionIndex)"
                ) else {
                    storeResult(result, resolveValue(thenValue))
                    continue
                }
                let selected = bindings.buildSelect(
                    builder,
                    condition: loweredCondition,
                    thenValue: resolveValue(thenValue),
                    elseValue: resolveValue(elseValue),
                    name: "select_\(instructionIndex)"
                )
                storeResult(result, selected ?? resolveValue(thenValue))

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
                    lowered = nil
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

                if calleeName == "kk_when_select" {
                    let conditionValue = argumentValues.count > 0 ? argumentValues[0] : zeroValue
                    let thenValue = argumentValues.count > 1 ? argumentValues[1] : zeroValue
                    let elseValue = argumentValues.count > 2 ? argumentValues[2] : zeroValue
                    if let loweredCondition = buildBoolCondition(
                        from: conditionValue,
                        name: "when_cond_\(instructionIndex)"
                    ) {
                        let selected = bindings.buildSelect(
                            builder,
                            condition: loweredCondition,
                            thenValue: thenValue,
                            elseValue: elseValue,
                            name: "when_select_\(instructionIndex)"
                        )
                        storeResult(result, selected ?? thenValue)
                    } else {
                        storeResult(result, thenValue)
                    }
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

    private func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
