import Foundation

enum LLVMEntryPointObjectEmitterError: Error, CustomStringConvertible {
    case bindingsUnavailable
    case invalidIR(String)
    case emissionFailed(String)

    var description: String {
        switch self {
        case .bindingsUnavailable:
            "LLVM backend is unavailable while emitting the entry wrapper object."
        case let .invalidIR(reason):
            reason
        case let .emissionFailed(reason):
            reason
        }
    }
}

struct LLVMEntryPointObjectEmitter {
    private let bindings: LLVMCAPIBindings
    private let target: TargetTriple

    init(target: TargetTriple) throws {
        guard let bindings = LLVMCAPIBindings.loadUsable() else {
            throw LLVMEntryPointObjectEmitterError.bindingsUnavailable
        }
        self.bindings = bindings
        self.target = target
    }

    func emit(entrySymbol: String, outputPath: String) throws -> String {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cacheKey = CodegenRuntimeSupport.stableFNV1a64Hex(
            CodegenRuntimeSupport.targetTripleString(target) + "|" + entrySymbol + "|" + outputPath
        )
        let objectURL = cacheDir.appendingPathComponent("entry_\(cacheKey).o")
        if FileManager.default.fileExists(atPath: objectURL.path) {
            try FileManager.default.removeItem(at: objectURL)
        }

        try emitObject(entrySymbol: entrySymbol, objectURL: objectURL)
        return objectURL.path
    }

    private func emitObject(entrySymbol: String, objectURL: URL) throws {
        guard let context = bindings.createContext() else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMContextCreate returned null")
        }
        defer { bindings.disposeContext(context) }

        guard let module = bindings.createModule(name: "kswiftk_entry_wrapper", context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMModuleCreateWithNameInContext returned null")
        }
        defer { bindings.disposeModule(module) }

        let triple = CodegenRuntimeSupport.targetTripleString(target)
        bindings.setTarget(module, triple: triple)

        guard let targetMachine = bindings.createTargetMachine(triple: triple, optLevel: .O0) else {
            throw LLVMEntryPointObjectEmitterError.emissionFailed("failed to create LLVM target machine for entry wrapper")
        }
        defer { bindings.disposeTargetMachine(targetMachine) }

        guard bindings.applyTargetMachine(targetMachine, to: module) else {
            throw LLVMEntryPointObjectEmitterError.emissionFailed("failed to apply target data layout to entry wrapper")
        }

        guard let int64Type = bindings.int64Type(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMInt64TypeInContext returned null")
        }
        guard let int8Type = bindings.int8Type(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMInt8TypeInContext returned null")
        }
        guard let thrownPointerType = bindings.pointerType(int64Type) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMPointerType returned null for thrown channel")
        }
        guard let cStringPointerType = bindings.pointerType(int8Type) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMPointerType returned null for panic message")
        }
        guard let entryType = bindings.functionType(
            returnType: int64Type,
            parameters: [thrownPointerType],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry function type")
        }
        guard let writeType = bindings.functionType(
            returnType: int64Type,
            parameters: [int64Type, cStringPointerType, int64Type],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create stderr write function type")
        }
        guard let mainType = bindings.functionType(
            returnType: int64Type,
            parameters: [],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create main wrapper type")
        }

        guard let entryFunction = bindings.getNamedFunction(module: module, name: entrySymbol)
            ?? bindings.addFunction(module: module, name: entrySymbol, functionType: entryType)
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare entry function '\(entrySymbol)'")
        }
        guard let writeFunction = bindings.getNamedFunction(module: module, name: "write")
            ?? bindings.addFunction(module: module, name: "write", functionType: writeType)
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare stderr write function")
        }
        guard let mainFunction = bindings.addFunction(module: module, name: "main", functionType: mainType) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare main wrapper function")
        }

        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMCreateBuilderInContext returned null")
        }
        defer { bindings.disposeBuilder(builder) }

        guard let entryBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "entry"),
              let successBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "success"),
              let failureBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "failure")
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry wrapper basic blocks")
        }

        bindings.positionBuilder(builder, at: entryBlock)

        let panicMessageText = "KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception\n"

        guard let thrownSlot = bindings.buildAlloca(builder, type: int64Type, name: "thrown.slot"),
              let zero = bindings.constInt(int64Type, value: 0),
              let one = bindings.constInt(int64Type, value: 1),
              let stderrFD = bindings.constInt(int64Type, value: 2),
              let panicMessageLength = bindings.constInt(
                  int64Type,
                  value: UInt64(panicMessageText.utf8.count)
              )
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry wrapper constants")
        }
        guard bindings.buildStore(builder, value: zero, pointer: thrownSlot) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to initialize thrown channel")
        }

        guard let entryResult = bindings.buildCall(
            builder,
            functionType: entryType,
            callee: entryFunction,
            arguments: [thrownSlot],
            name: "entry.result"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit entry function call")
        }
        guard let thrownValue = bindings.buildLoad(
            builder,
            type: int64Type,
            pointer: thrownSlot,
            name: "thrown.value"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to load thrown channel")
        }
        guard let hasThrown = bindings.buildICmpNotEqual(
            builder,
            lhs: thrownValue,
            rhs: zero,
            name: "has.thrown"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to compare thrown channel")
        }
        guard bindings.buildCondBr(
            builder,
            condition: hasThrown,
            thenBlock: failureBlock,
            elseBlock: successBlock
        ) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit entry wrapper branch")
        }

        bindings.positionBuilder(builder, at: failureBlock)
        guard let panicMessage = bindings.buildGlobalStringPtr(
            builder,
            value: panicMessageText,
            name: "panic.message"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create panic message literal")
        }
        guard bindings.buildCall(
            builder,
            functionType: writeType,
            callee: writeFunction,
            arguments: [stderrFD, panicMessage, panicMessageLength],
            name: "stderr.write"
        ) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit stderr write")
        }
        guard bindings.buildRet(builder, value: one) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit failure return")
        }

        bindings.positionBuilder(builder, at: successBlock)
        guard bindings.buildRet(builder, value: entryResult) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit success return")
        }

        if let errorMessage = bindings.emitObject(
            targetMachine: targetMachine,
            module: module,
            outputPath: objectURL.path
        ) {
            throw LLVMEntryPointObjectEmitterError.emissionFailed(errorMessage)
        }
    }
}
