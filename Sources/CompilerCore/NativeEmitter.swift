import Foundation

struct NativeEmitter {
    struct LLVMFunction {
        let value: LLVMCAPIBindings.LLVMValueRef
        let type: LLVMCAPIBindings.LLVMTypeRef
    }

    struct DebugInfoContext {
        let diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef
        let file: LLVMCAPIBindings.LLVMMetadataRef
        let compileUnit: LLVMCAPIBindings.LLVMMetadataRef
        let subroutineType: LLVMCAPIBindings.LLVMMetadataRef?
        let subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef]
    }

    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let bindings: LLVMCAPIBindings
    let module: KIRModule
    let interner: StringInterner

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        bindings: LLVMCAPIBindings,
        module: KIRModule,
        interner: StringInterner
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
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

    func buildModule() throws -> (
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

        // Create debug info context BEFORE emitting function bodies so that
        // debug locations can be attached to instructions during emission.
        let diContext: DebugInfoContext? = debugInfo
            ? createDebugInfoContext(
                llvmModule: llvmModule,
                context: context,
                internalFunctions: internalFunctions
            )
            : nil

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
                    internalFunctions: internalFunctions,
                    diContext: diContext
                )
            } catch {
                if let diContext {
                    bindings.disposeDIBuilder(diContext.diBuilder)
                }
                bindings.disposeModule(llvmModule)
                bindings.disposeContext(context)
                throw error
            }
        }

        if let diContext {
            finalizeDebugInfo(
                diContext: diContext,
                llvmModule: llvmModule,
                context: context
            )
        }

        return (context: context, module: llvmModule)
    }

    /// Creates debug info metadata (DIBuilder, compile unit, file, subprograms)
    /// BEFORE function bodies are emitted so that debug locations can be set
    /// on instructions during emission.
    func createDebugInfoContext(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> DebugInfoContext? {
        guard bindings.debugInfoAvailable else {
            return nil
        }

        guard let diBuilder = bindings.createDIBuilder(module: llvmModule) else {
            return nil
        }

        guard let diFile = bindings.diBuilderCreateFile(
            diBuilder,
            filename: "kswiftk_module.kt",
            directory: "."
        ) else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let isOptimized = optLevel != .O0
        guard let compileUnit = bindings.diBuilderCreateCompileUnit(
            diBuilder,
            lang: 11,
            file: diFile,
            producer: "kswiftk",
            isOptimized: isOptimized
        ) else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let subroutineType = bindings.diBuilderCreateSubroutineType(
            diBuilder,
            file: diFile,
            parameterTypes: []
        )

        var subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] = [:]

        for declaration in module.arena.declarations {
            guard case .function(let function) = declaration,
                  let llvmFunction = internalFunctions[function.symbol] else {
                continue
            }
            let functionName = LLVMBackend.cFunctionSymbol(for: function, interner: interner)

            guard let subprogram = bindings.diBuilderCreateFunction(
                diBuilder,
                scope: diFile,
                name: interner.resolve(function.name),
                linkageName: functionName,
                file: diFile,
                lineNo: 0,
                type: subroutineType,
                isLocalToUnit: false,
                isDefinition: true,
                scopeLine: 0,
                isOptimized: isOptimized
            ) else {
                continue
            }
            bindings.setSubprogram(llvmFunction.value, subprogram: subprogram)
            subprograms[function.symbol] = subprogram
        }

        return DebugInfoContext(
            diBuilder: diBuilder,
            file: diFile,
            compileUnit: compileUnit,
            subroutineType: subroutineType,
            subprograms: subprograms
        )
    }

    /// Finalizes the DIBuilder, adds module flags, and disposes the DIBuilder.
    func finalizeDebugInfo(
        diContext: DebugInfoContext,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef
    ) {
        bindings.finalizeDIBuilder(diContext.diBuilder)
        bindings.disposeDIBuilder(diContext.diBuilder)

        if let int32Type = bindings.int32Type(context: context),
           let debugVersionConst = bindings.constInt(int32Type, value: 3),
           let debugVersionMD = bindings.valueAsMetadata(debugVersionConst) {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Debug Info Version", value: debugVersionMD)
        }

        if let int32Type = bindings.int32Type(context: context),
           let dwarfVersionConst = bindings.constInt(int32Type, value: 5),
           let dwarfVersionMD = bindings.valueAsMetadata(dwarfVersionConst) {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Dwarf Version", value: dwarfVersionMD)
        }
    }

    func defineFrameRuntimeStubs(
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

    func defineNoOpRuntimeFunction(
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

    func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
