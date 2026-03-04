import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

extension LLVMCAPIBindings {
    static func candidateLibraryPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var candidates: [String] = []
        if let override = environment["KSWIFTK_LLVM_DYLIB"], !override.isEmpty {
            let resolved = URL(fileURLWithPath: override).standardized.path
            if FileManager.default.fileExists(atPath: resolved) {
                candidates.append(resolved)
            }
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/opt/llvm/lib/libLLVM.dylib",
            "/usr/local/opt/llvm/lib/libLLVM.dylib",
            "/Library/Developer/CommandLineTools/usr/lib/libLLVM.dylib",
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/usr/lib/libLLVM.dylib",
            "libLLVM.dylib",
            "/usr/lib/x86_64-linux-gnu/libLLVM-15.so",
            "/usr/lib/x86_64-linux-gnu/libLLVM.so",
            "libLLVM.so",
        ])
        return deduplicated(candidates)
    }

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> LLVMCAPIBindings? {
        for candidate in candidateLibraryPaths(environment: environment) {
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }

            guard let contextCreate = loadSymbol(handle: handle, name: "LLVMContextCreate", as: LLVMContextCreateFn.self),
                  let contextDispose = loadSymbol(handle: handle, name: "LLVMContextDispose", as: LLVMContextDisposeFn.self),
                  let moduleCreate = loadSymbol(handle: handle, name: "LLVMModuleCreateWithNameInContext", as: LLVMModuleCreateWithNameInContextFn.self),
                  let disposeModule = loadSymbol(handle: handle, name: "LLVMDisposeModule", as: LLVMDisposeModuleFn.self),
                  let printModule = loadSymbol(handle: handle, name: "LLVMPrintModuleToString", as: LLVMPrintModuleToStringFn.self),
                  let disposeMessage = loadSymbol(handle: handle, name: "LLVMDisposeMessage", as: LLVMDisposeMessageFn.self),
                  let setTarget = loadSymbol(handle: handle, name: "LLVMSetTarget", as: LLVMSetTargetFn.self),
                  let setDataLayout = loadSymbol(handle: handle, name: "LLVMSetDataLayout", as: LLVMSetDataLayoutFn.self),
                  let setLinkage = loadSymbol(handle: handle, name: "LLVMSetLinkage", as: LLVMSetLinkageFn.self),
                  let int64Type = loadSymbol(handle: handle, name: "LLVMInt64TypeInContext", as: LLVMInt64TypeInContextFn.self),
                  let pointerType = loadSymbol(handle: handle, name: "LLVMPointerType", as: LLVMPointerTypeFn.self),
                  let functionType = loadSymbol(handle: handle, name: "LLVMFunctionType", as: LLVMFunctionTypeFn.self),
                  let addFunction = loadSymbol(handle: handle, name: "LLVMAddFunction", as: LLVMAddFunctionFn.self),
                  let getNamedFunction = loadSymbol(handle: handle, name: "LLVMGetNamedFunction", as: LLVMGetNamedFunctionFn.self),
                  let getParam = loadSymbol(handle: handle, name: "LLVMGetParam", as: LLVMGetParamFn.self),
                  let getUndef = loadSymbol(handle: handle, name: "LLVMGetUndef", as: LLVMGetUndefFn.self),
                  let appendBasicBlock = loadSymbol(handle: handle, name: "LLVMAppendBasicBlockInContext", as: LLVMAppendBasicBlockInContextFn.self),
                  let createBuilder = loadSymbol(handle: handle, name: "LLVMCreateBuilderInContext", as: LLVMCreateBuilderInContextFn.self),
                  let disposeBuilder = loadSymbol(handle: handle, name: "LLVMDisposeBuilder", as: LLVMDisposeBuilderFn.self),
                  let positionBuilder = loadSymbol(handle: handle, name: "LLVMPositionBuilderAtEnd", as: LLVMPositionBuilderAtEndFn.self),
                  let getTerminator = loadSymbol(handle: handle, name: "LLVMGetBasicBlockTerminator", as: LLVMGetBasicBlockTerminatorFn.self),
                  let buildRet = loadSymbol(handle: handle, name: "LLVMBuildRet", as: LLVMBuildRetFn.self),
                  let buildRetVoid = loadSymbol(handle: handle, name: "LLVMBuildRetVoid", as: LLVMBuildRetVoidFn.self),
                  let buildBr = loadSymbol(handle: handle, name: "LLVMBuildBr", as: LLVMBuildBrFn.self),
                  let buildCondBr = loadSymbol(handle: handle, name: "LLVMBuildCondBr", as: LLVMBuildCondBrFn.self),
                  let buildAdd = loadSymbol(handle: handle, name: "LLVMBuildAdd", as: LLVMBuildAddFn.self),
                  let buildSub = loadSymbol(handle: handle, name: "LLVMBuildSub", as: LLVMBuildSubFn.self),
                  let buildMul = loadSymbol(handle: handle, name: "LLVMBuildMul", as: LLVMBuildMulFn.self),
                  let buildSDiv = loadSymbol(handle: handle, name: "LLVMBuildSDiv", as: LLVMBuildSDivFn.self),
                  let buildICmp = loadSymbol(handle: handle, name: "LLVMBuildICmp", as: LLVMBuildICmpFn.self),
                  let constInt = loadSymbol(handle: handle, name: "LLVMConstInt", as: LLVMConstIntFn.self),
                  let getDefaultTargetTriple = loadSymbol(handle: handle, name: "LLVMGetDefaultTargetTriple", as: LLVMGetDefaultTargetTripleFn.self),
                  let getTargetFromTriple = loadSymbol(handle: handle, name: "LLVMGetTargetFromTriple", as: LLVMGetTargetFromTripleFn.self),
                  let createTargetMachine = loadSymbol(handle: handle, name: "LLVMCreateTargetMachine", as: LLVMCreateTargetMachineFn.self),
                  let disposeTargetMachine = loadSymbol(handle: handle, name: "LLVMDisposeTargetMachine", as: LLVMDisposeTargetMachineFn.self),
                  let emitToFile = loadSymbol(handle: handle, name: "LLVMTargetMachineEmitToFile", as: LLVMTargetMachineEmitToFileFn.self),
                  let createTargetDataLayout = loadSymbol(handle: handle, name: "LLVMCreateTargetDataLayout", as: LLVMCreateTargetDataLayoutFn.self),
                  let copyStringRepOfTargetData = loadSymbol(handle: handle, name: "LLVMCopyStringRepOfTargetData", as: LLVMCopyStringRepOfTargetDataFn.self),
                  let disposeTargetData = loadSymbol(handle: handle, name: "LLVMDisposeTargetData", as: LLVMDisposeTargetDataFn.self)
            else {
                dlclose(handle)
                continue
            }

            let buildCall2 = loadSymbol(handle: handle, name: "LLVMBuildCall2", as: LLVMBuildCall2Fn.self)
            let buildCall = loadSymbol(handle: handle, name: "LLVMBuildCall", as: LLVMBuildCallFn.self)

            return LLVMCAPIBindings(
                handle: handle,
                contextCreateFn: contextCreate,
                contextDisposeFn: contextDispose,
                moduleCreateFn: moduleCreate,
                disposeModuleFn: disposeModule,
                printModuleToStringFn: printModule,
                disposeMessageFn: disposeMessage,
                setTargetFn: setTarget,
                setDataLayoutFn: setDataLayout,
                setLinkageFn: setLinkage,
                int64TypeFn: int64Type,
                pointerTypeFn: pointerType,
                functionTypeFn: functionType,
                addFunctionFn: addFunction,
                getNamedFunctionFn: getNamedFunction,
                getParamFn: getParam,
                getUndefFn: getUndef,
                appendBasicBlockFn: appendBasicBlock,
                createBuilderFn: createBuilder,
                disposeBuilderFn: disposeBuilder,
                positionBuilderFn: positionBuilder,
                getBasicBlockTerminatorFn: getTerminator,
                buildRetFn: buildRet,
                buildRetVoidFn: buildRetVoid,
                buildBrFn: buildBr,
                buildCondBrFn: buildCondBr,
                buildAddFn: buildAdd,
                buildSubFn: buildSub,
                buildMulFn: buildMul,
                buildSDivFn: buildSDiv,
                // Bitwise/shift builder symbols (P5-103)
                buildAndFn: loadSymbol(handle: handle, name: "LLVMBuildAnd", as: LLVMBuildAndFn.self),
                buildOrFn: loadSymbol(handle: handle, name: "LLVMBuildOr", as: LLVMBuildOrFn.self),
                buildXorFn: loadSymbol(handle: handle, name: "LLVMBuildXor", as: LLVMBuildXorFn.self),
                buildShlFn: loadSymbol(handle: handle, name: "LLVMBuildShl", as: LLVMBuildShlFn.self),
                buildAShrFn: loadSymbol(handle: handle, name: "LLVMBuildAShr", as: LLVMBuildAShrFn.self),
                buildLShrFn: loadSymbol(handle: handle, name: "LLVMBuildLShr", as: LLVMBuildLShrFn.self),
                buildNotFn: loadSymbol(handle: handle, name: "LLVMBuildNot", as: LLVMBuildNotFn.self),
                buildICmpFn: buildICmp,
                buildZExtFn: loadSymbol(handle: handle, name: "LLVMBuildZExt", as: LLVMBuildZExtFn.self),
                buildAllocaFn: loadSymbol(handle: handle, name: "LLVMBuildAlloca", as: LLVMBuildAllocaFn.self),
                buildStoreFn: loadSymbol(handle: handle, name: "LLVMBuildStore", as: LLVMBuildStoreFn.self),
                buildLoad2Fn: loadSymbol(handle: handle, name: "LLVMBuildLoad2", as: LLVMBuildLoad2Fn.self),
                buildLoadFn: loadSymbol(handle: handle, name: "LLVMBuildLoad", as: LLVMBuildLoadFn.self),
                buildSelectFn: loadSymbol(handle: handle, name: "LLVMBuildSelect", as: LLVMBuildSelectFn.self),
                buildGlobalStringPtrFn: loadSymbol(handle: handle, name: "LLVMBuildGlobalStringPtr", as: LLVMBuildGlobalStringPtrFn.self),
                buildPtrToIntFn: loadSymbol(handle: handle, name: "LLVMBuildPtrToInt", as: LLVMBuildPtrToIntFn.self),
                buildIntToPtrFn: loadSymbol(handle: handle, name: "LLVMBuildIntToPtr", as: LLVMBuildIntToPtrFn.self),
                buildCall2Fn: buildCall2,
                buildCallFn: buildCall,
                constIntFn: constInt,
                constPointerNullFn: loadSymbol(handle: handle, name: "LLVMConstPointerNull", as: LLVMConstPointerNullFn.self),
                getDefaultTargetTripleFn: getDefaultTargetTriple,
                getTargetFromTripleFn: getTargetFromTriple,
                createTargetMachineFn: createTargetMachine,
                disposeTargetMachineFn: disposeTargetMachine,
                emitToFileFn: emitToFile,
                createTargetDataLayoutFn: createTargetDataLayout,
                copyStringRepOfTargetDataFn: copyStringRepOfTargetData,
                disposeTargetDataFn: disposeTargetData,
                initializeX86TargetInfoFn: loadSymbol(handle: handle, name: "LLVMInitializeX86TargetInfo", as: LLVMInitializeX86TargetInfoFn.self),
                initializeX86TargetFn: loadSymbol(handle: handle, name: "LLVMInitializeX86Target", as: LLVMInitializeX86TargetFn.self),
                initializeX86TargetMCFn: loadSymbol(handle: handle, name: "LLVMInitializeX86TargetMC", as: LLVMInitializeX86TargetMCFn.self),
                initializeX86AsmPrinterFn: loadSymbol(handle: handle, name: "LLVMInitializeX86AsmPrinter", as: LLVMInitializeX86AsmPrinterFn.self),
                initializeAArch64TargetInfoFn: loadSymbol(handle: handle, name: "LLVMInitializeAArch64TargetInfo", as: LLVMInitializeAArch64TargetInfoFn.self),
                initializeAArch64TargetFn: loadSymbol(handle: handle, name: "LLVMInitializeAArch64Target", as: LLVMInitializeAArch64TargetFn.self),
                initializeAArch64TargetMCFn: loadSymbol(handle: handle, name: "LLVMInitializeAArch64TargetMC", as: LLVMInitializeAArch64TargetMCFn.self),
                initializeAArch64AsmPrinterFn: loadSymbol(handle: handle, name: "LLVMInitializeAArch64AsmPrinter", as: LLVMInitializeAArch64AsmPrinterFn.self),
                addGlobalFn: loadSymbol(handle: handle, name: "LLVMAddGlobal", as: LLVMAddGlobalFn.self),
                setInitializerFn: loadSymbol(handle: handle, name: "LLVMSetInitializer", as: LLVMSetInitializerFn.self),
                createDIBuilderFn: loadSymbol(handle: handle, name: "LLVMCreateDIBuilder", as: LLVMCreateDIBuilderFn.self),
                disposeDIBuilderFn: loadSymbol(handle: handle, name: "LLVMDisposeDIBuilder", as: LLVMDisposeDIBuilderFn.self),
                diBuilderFinalizeFn: loadSymbol(handle: handle, name: "LLVMDIBuilderFinalize", as: LLVMDIBuilderFinalizeFn.self),
                diBuilderCreateFileFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateFile", as: LLVMDIBuilderCreateFileFn.self),
                diBuilderCreateCompileUnitFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateCompileUnit", as: LLVMDIBuilderCreateCompileUnitFn.self),
                diBuilderCreateSubroutineTypeFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateSubroutineType", as: LLVMDIBuilderCreateSubroutineTypeFn.self),
                diBuilderCreateFunctionFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateFunction", as: LLVMDIBuilderCreateFunctionFn.self),
                setSubprogramFn: loadSymbol(handle: handle, name: "LLVMSetSubprogram", as: LLVMSetSubprogramFn.self),
                addModuleFlagFn: loadSymbol(handle: handle, name: "LLVMAddModuleFlag", as: LLVMAddModuleFlagFn.self),
                valueAsMetadataFn: loadSymbol(handle: handle, name: "LLVMValueAsMetadata", as: LLVMValueAsMetadataFn.self),
                int32TypeFn: loadSymbol(handle: handle, name: "LLVMInt32TypeInContext", as: LLVMInt32TypeInContextFn.self),
                setCurrentDebugLocation2Fn: loadSymbol(handle: handle, name: "LLVMSetCurrentDebugLocation2", as: LLVMSetCurrentDebugLocation2Fn.self),
                diBuilderCreateDebugLocationFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateDebugLocation", as: LLVMDIBuilderCreateDebugLocationFn.self),
                diBuilderCreateBasicTypeFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateBasicType", as: LLVMDIBuilderCreateBasicTypeFn.self),
                diBuilderCreateParameterVariableFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateParameterVariable", as: LLVMDIBuilderCreateParameterVariableFn.self),
                diBuilderCreateAutoVariableFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateAutoVariable", as: LLVMDIBuilderCreateAutoVariableFn.self),
                diBuilderInsertDeclareAtEndFn: loadSymbol(handle: handle, name: "LLVMDIBuilderInsertDeclareAtEnd", as: LLVMDIBuilderInsertDeclareAtEndFn.self),
                diBuilderCreateExpressionFn: loadSymbol(handle: handle, name: "LLVMDIBuilderCreateExpression", as: LLVMDIBuilderCreateExpressionFn.self)
            )
        }
        return nil
    }

    static func loadSymbol<T>(
        handle: UnsafeMutableRawPointer,
        name: String,
        as type: T.Type
    ) -> T? {
        guard let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}
