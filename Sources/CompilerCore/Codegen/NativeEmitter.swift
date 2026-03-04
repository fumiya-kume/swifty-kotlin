import Foundation

struct NativeEmitter {
    /// DWARF constants used across the emitter.
    /// DW_LANG_C99 – used as the compile-unit language tag.
    static let dwarfLangC99: UInt32 = 11
    /// DW_ATE_signed – DWARF attribute encoding for signed integers.
    static let dwarfATESigned: UInt32 = 5

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
        /// Per-file DI file metadata keyed by FileID.
        let diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef]
        /// DI basic type for i64 (used for parameter/variable debug info).
        let int64DIType: LLVMCAPIBindings.LLVMMetadataRef?
    }

    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let bindings: LLVMCAPIBindings
    let module: KIRModule
    let interner: StringInterner
    let sourceManager: SourceManager?

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        bindings: LLVMCAPIBindings,
        module: KIRModule,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.bindings = bindings
        self.module = module
        self.interner = interner
        self.sourceManager = sourceManager
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
            try defineWeakFrameRuntimeStubs(
                module: llvmModule,
                context: context,
                int64Type: int64Type
            )
        } catch {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw error
        }

        // Create LLVM global variables for each KIR global declaration.
        var llvmGlobalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        for declaration in module.arena.declarations {
            guard case let .global(global) = declaration else {
                continue
            }
            let slotName = "kk_global_root_slot_\(max(0, Int(global.symbol.rawValue)))"
            if let llvmGlobal = bindings.addGlobal(module: llvmModule, type: int64Type, name: slotName) {
                if let zero = bindings.constInt(int64Type, value: 0) {
                    bindings.setInitializer(llvmGlobal, value: zero)
                }
                llvmGlobalVariables[global.symbol] = llvmGlobal
            }
        }

        var internalFunctions: [SymbolID: LLVMFunction] = [:]

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else {
                continue
            }
            let functionName = LLVMBackend.cFunctionSymbol(for: function, interner: interner)
            var parameterTypes = Array(repeating: int64Type, count: function.params.count)
            parameterTypes.append(outThrownPointerType)

            guard let functionType = bindings.functionType(returnType: int64Type, parameters: parameterTypes, isVarArg: false),
                  let functionValue = bindings.addFunction(module: llvmModule, name: functionName, functionType: functionType)
            else {
                bindings.disposeModule(llvmModule)
                bindings.disposeContext(context)
                throw LLVMCAPIBackendError.nativeEmissionFailed("failed to declare function '\(functionName)'")
            }
            internalFunctions[function.symbol] = LLVMFunction(value: functionValue, type: functionType)
        }

        // Create debug info context BEFORE emitting function bodies so that
        // debug locations can be attached to instructions during emission.
        let diContext: DebugInfoContext? = (debugInfo && bindings.debugLocationAvailable)
            ? createDebugInfoContext(
                llvmModule: llvmModule,
                context: context,
                internalFunctions: internalFunctions
            )
            : nil

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  let llvmFunction = internalFunctions[function.symbol]
            else {
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
                    globalVariables: llvmGlobalVariables,
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
        context _: LLVMCAPIBindings.LLVMContextRef,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> DebugInfoContext? {
        guard bindings.debugInfoAvailable else {
            return nil
        }

        guard let diBuilder = bindings.createDIBuilder(module: llvmModule) else {
            return nil
        }

        // Determine the primary source file from the SourceManager if available.
        let primaryFilename: String
        let primaryDirectory: String
        if let sourceManager, sourceManager.fileCount > 0 {
            let firstFileID = FileID(rawValue: 0)
            let fullPath = sourceManager.path(of: firstFileID)
            let url = URL(fileURLWithPath: fullPath)
            primaryFilename = url.lastPathComponent
            let directoryPath = url.deletingLastPathComponent().path
            primaryDirectory = directoryPath.isEmpty ? "." : directoryPath
        } else {
            primaryFilename = "kswiftk_module.kt"
            primaryDirectory = "."
        }

        guard let diFile = bindings.diBuilderCreateFile(
            diBuilder,
            filename: primaryFilename,
            directory: primaryDirectory
        ) else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let isOptimized = optLevel != .O0
        guard let compileUnit = bindings.diBuilderCreateCompileUnit(
            diBuilder,
            lang: Self.dwarfLangC99,
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

        // Build per-file DI metadata so that functions can reference their
        // actual source file.
        var diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef] = [:]
        if let sourceManager {
            for fileID in sourceManager.fileIDs() {
                let fullPath = sourceManager.path(of: fileID)
                let url = URL(fileURLWithPath: fullPath)
                let fname = url.lastPathComponent
                let dir = url.deletingLastPathComponent().path
                if let f = bindings.diBuilderCreateFile(diBuilder, filename: fname, directory: dir) {
                    diFiles[fileID] = f
                }
            }
        }

        // Create a DI basic type for i64 (used for parameter debug info).
        let int64DIType = bindings.diBuilderCreateBasicType(
            diBuilder, name: "Int", sizeInBits: 64, encoding: Self.dwarfATESigned
        )

        var subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] = [:]

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  let llvmFunction = internalFunctions[function.symbol]
            else {
                continue
            }
            let functionName = LLVMBackend.cFunctionSymbol(for: function, interner: interner)

            // Determine real line number and file for this function.
            var lineNo: UInt32 = 0
            var funcDIFile = diFile
            if let sourceRange = function.sourceRange, let sourceManager {
                let lc = sourceManager.lineColumn(of: sourceRange.start)
                lineNo = UInt32(lc.line)
                if let perFileDI = diFiles[sourceRange.start.file] {
                    funcDIFile = perFileDI
                }
            }

            guard let subprogram = bindings.diBuilderCreateFunction(
                diBuilder,
                scope: funcDIFile,
                name: interner.resolve(function.name),
                linkageName: functionName,
                file: funcDIFile,
                lineNo: lineNo,
                type: subroutineType,
                isLocalToUnit: false,
                isDefinition: true,
                scopeLine: lineNo,
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
            subprograms: subprograms,
            diFiles: diFiles,
            int64DIType: int64DIType
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

    func defineWeakFrameRuntimeStubs(
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) throws {
        _ = try defineWeakRuntimeFunction(
            named: "kk_register_frame_map",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineWeakRuntimeFunction(
            named: "kk_push_frame",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineWeakRuntimeFunction(
            named: "kk_pop_frame",
            argumentCount: 0,
            module: module,
            context: context,
            int64Type: int64Type
        )
    }

    func defineWeakRuntimeFunction(
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
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to create runtime function type for '\(name)'")
        }
        guard let functionValue = bindings.getNamedFunction(module: module, name: name)
            ?? bindings.addFunction(module: module, name: name, functionType: functionType)
        else {
            throw LLVMCAPIBackendError.nativeEmissionFailed("failed to define weak runtime stub '\(name)'")
        }
        bindings.setWeakAnyLinkage(functionValue)

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
