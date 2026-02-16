import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class LLVMCAPIBindings {
    typealias LLVMContextRef = OpaquePointer
    typealias LLVMModuleRef = OpaquePointer
    typealias LLVMTypeRef = OpaquePointer
    typealias LLVMValueRef = OpaquePointer
    typealias LLVMBasicBlockRef = OpaquePointer
    typealias LLVMBuilderRef = OpaquePointer
    typealias LLVMTargetRef = OpaquePointer
    typealias LLVMTargetMachineRef = OpaquePointer
    typealias LLVMTargetDataRef = OpaquePointer
    typealias LLVMBool = Int32

    private typealias LLVMContextCreateFn = @convention(c) () -> LLVMContextRef?
    private typealias LLVMContextDisposeFn = @convention(c) (LLVMContextRef?) -> Void
    private typealias LLVMModuleCreateWithNameInContextFn = @convention(c) (UnsafePointer<CChar>?, LLVMContextRef?) -> LLVMModuleRef?
    private typealias LLVMDisposeModuleFn = @convention(c) (LLVMModuleRef?) -> Void
    private typealias LLVMPrintModuleToStringFn = @convention(c) (LLVMModuleRef?) -> UnsafeMutablePointer<CChar>?
    private typealias LLVMDisposeMessageFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias LLVMSetTargetFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    private typealias LLVMSetDataLayoutFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    private typealias LLVMSetLinkageFn = @convention(c) (LLVMValueRef?, UInt32) -> Void
    private typealias LLVMInt64TypeInContextFn = @convention(c) (LLVMContextRef?) -> LLVMTypeRef?
    private typealias LLVMPointerTypeFn = @convention(c) (LLVMTypeRef?, UInt32) -> LLVMTypeRef?
    private typealias LLVMFunctionTypeFn = @convention(c) (LLVMTypeRef?, UnsafeMutablePointer<LLVMTypeRef?>?, UInt32, LLVMBool) -> LLVMTypeRef?
    private typealias LLVMAddFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?, LLVMTypeRef?) -> LLVMValueRef?
    private typealias LLVMGetNamedFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMGetParamFn = @convention(c) (LLVMValueRef?, UInt32) -> LLVMValueRef?
    private typealias LLVMGetUndefFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    private typealias LLVMAppendBasicBlockInContextFn = @convention(c) (LLVMContextRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMBasicBlockRef?
    private typealias LLVMCreateBuilderInContextFn = @convention(c) (LLVMContextRef?) -> LLVMBuilderRef?
    private typealias LLVMDisposeBuilderFn = @convention(c) (LLVMBuilderRef?) -> Void
    private typealias LLVMPositionBuilderAtEndFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> Void
    private typealias LLVMGetBasicBlockTerminatorFn = @convention(c) (LLVMBasicBlockRef?) -> LLVMValueRef?
    private typealias LLVMBuildRetFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?) -> LLVMValueRef?
    private typealias LLVMBuildRetVoidFn = @convention(c) (LLVMBuilderRef?) -> LLVMValueRef?
    private typealias LLVMBuildBrFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    private typealias LLVMBuildCondBrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMBasicBlockRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    private typealias LLVMBuildAddFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildSubFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildMulFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildSDivFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildICmpFn = @convention(c) (LLVMBuilderRef?, UInt32, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildZExtFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildAllocaFn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildStoreFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?) -> LLVMValueRef?
    private typealias LLVMBuildLoad2Fn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildLoadFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildSelectFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildGlobalStringPtrFn = @convention(c) (LLVMBuilderRef?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildPtrToIntFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    private typealias LLVMBuildCall2Fn = @convention(c) (
        LLVMBuilderRef?,
        LLVMTypeRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    private typealias LLVMBuildCallFn = @convention(c) (
        LLVMBuilderRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    private typealias LLVMConstIntFn = @convention(c) (LLVMTypeRef?, UInt64, LLVMBool) -> LLVMValueRef?
    private typealias LLVMConstPointerNullFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    private typealias LLVMGetDefaultTargetTripleFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
    private typealias LLVMGetTargetFromTripleFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<LLVMTargetRef?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    private typealias LLVMCreateTargetMachineFn = @convention(c) (
        LLVMTargetRef?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt32,
        UInt32,
        UInt32
    ) -> LLVMTargetMachineRef?
    private typealias LLVMDisposeTargetMachineFn = @convention(c) (LLVMTargetMachineRef?) -> Void
    private typealias LLVMTargetMachineEmitToFileFn = @convention(c) (
        LLVMTargetMachineRef?,
        LLVMModuleRef?,
        UnsafeMutablePointer<CChar>?,
        UInt32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    private typealias LLVMCreateTargetDataLayoutFn = @convention(c) (LLVMTargetMachineRef?) -> LLVMTargetDataRef?
    private typealias LLVMCopyStringRepOfTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> UnsafeMutablePointer<CChar>?
    private typealias LLVMDisposeTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> Void
    private typealias LLVMInitializeX86TargetInfoFn = @convention(c) () -> Void
    private typealias LLVMInitializeX86TargetFn = @convention(c) () -> Void
    private typealias LLVMInitializeX86TargetMCFn = @convention(c) () -> Void
    private typealias LLVMInitializeX86AsmPrinterFn = @convention(c) () -> Void
    private typealias LLVMInitializeAArch64TargetInfoFn = @convention(c) () -> Void
    private typealias LLVMInitializeAArch64TargetFn = @convention(c) () -> Void
    private typealias LLVMInitializeAArch64TargetMCFn = @convention(c) () -> Void
    private typealias LLVMInitializeAArch64AsmPrinterFn = @convention(c) () -> Void

    private let handle: UnsafeMutableRawPointer
    private let contextCreateFn: LLVMContextCreateFn
    private let contextDisposeFn: LLVMContextDisposeFn
    private let moduleCreateFn: LLVMModuleCreateWithNameInContextFn
    private let disposeModuleFn: LLVMDisposeModuleFn
    private let printModuleToStringFn: LLVMPrintModuleToStringFn
    private let disposeMessageFn: LLVMDisposeMessageFn
    private let setTargetFn: LLVMSetTargetFn
    private let setDataLayoutFn: LLVMSetDataLayoutFn
    private let setLinkageFn: LLVMSetLinkageFn
    private let int64TypeFn: LLVMInt64TypeInContextFn
    private let pointerTypeFn: LLVMPointerTypeFn
    private let functionTypeFn: LLVMFunctionTypeFn
    private let addFunctionFn: LLVMAddFunctionFn
    private let getNamedFunctionFn: LLVMGetNamedFunctionFn
    private let getParamFn: LLVMGetParamFn
    private let getUndefFn: LLVMGetUndefFn
    private let appendBasicBlockFn: LLVMAppendBasicBlockInContextFn
    private let createBuilderFn: LLVMCreateBuilderInContextFn
    private let disposeBuilderFn: LLVMDisposeBuilderFn
    private let positionBuilderFn: LLVMPositionBuilderAtEndFn
    private let getBasicBlockTerminatorFn: LLVMGetBasicBlockTerminatorFn
    private let buildRetFn: LLVMBuildRetFn
    private let buildRetVoidFn: LLVMBuildRetVoidFn
    private let buildBrFn: LLVMBuildBrFn
    private let buildCondBrFn: LLVMBuildCondBrFn
    private let buildAddFn: LLVMBuildAddFn
    private let buildSubFn: LLVMBuildSubFn
    private let buildMulFn: LLVMBuildMulFn
    private let buildSDivFn: LLVMBuildSDivFn
    private let buildICmpFn: LLVMBuildICmpFn
    private let buildZExtFn: LLVMBuildZExtFn?
    private let buildAllocaFn: LLVMBuildAllocaFn?
    private let buildStoreFn: LLVMBuildStoreFn?
    private let buildLoad2Fn: LLVMBuildLoad2Fn?
    private let buildLoadFn: LLVMBuildLoadFn?
    private let buildSelectFn: LLVMBuildSelectFn?
    private let buildGlobalStringPtrFn: LLVMBuildGlobalStringPtrFn?
    private let buildPtrToIntFn: LLVMBuildPtrToIntFn?
    private let buildCall2Fn: LLVMBuildCall2Fn?
    private let buildCallFn: LLVMBuildCallFn?
    private let constIntFn: LLVMConstIntFn
    private let constPointerNullFn: LLVMConstPointerNullFn?
    private let getDefaultTargetTripleFn: LLVMGetDefaultTargetTripleFn
    private let getTargetFromTripleFn: LLVMGetTargetFromTripleFn
    private let createTargetMachineFn: LLVMCreateTargetMachineFn
    private let disposeTargetMachineFn: LLVMDisposeTargetMachineFn
    private let emitToFileFn: LLVMTargetMachineEmitToFileFn
    private let createTargetDataLayoutFn: LLVMCreateTargetDataLayoutFn
    private let copyStringRepOfTargetDataFn: LLVMCopyStringRepOfTargetDataFn
    private let disposeTargetDataFn: LLVMDisposeTargetDataFn
    private let initializeX86TargetInfoFn: LLVMInitializeX86TargetInfoFn?
    private let initializeX86TargetFn: LLVMInitializeX86TargetFn?
    private let initializeX86TargetMCFn: LLVMInitializeX86TargetMCFn?
    private let initializeX86AsmPrinterFn: LLVMInitializeX86AsmPrinterFn?
    private let initializeAArch64TargetInfoFn: LLVMInitializeAArch64TargetInfoFn?
    private let initializeAArch64TargetFn: LLVMInitializeAArch64TargetFn?
    private let initializeAArch64TargetMCFn: LLVMInitializeAArch64TargetMCFn?
    private let initializeAArch64AsmPrinterFn: LLVMInitializeAArch64AsmPrinterFn?

    private init(
        handle: UnsafeMutableRawPointer,
        contextCreateFn: @escaping LLVMContextCreateFn,
        contextDisposeFn: @escaping LLVMContextDisposeFn,
        moduleCreateFn: @escaping LLVMModuleCreateWithNameInContextFn,
        disposeModuleFn: @escaping LLVMDisposeModuleFn,
        printModuleToStringFn: @escaping LLVMPrintModuleToStringFn,
        disposeMessageFn: @escaping LLVMDisposeMessageFn,
        setTargetFn: @escaping LLVMSetTargetFn,
        setDataLayoutFn: @escaping LLVMSetDataLayoutFn,
        setLinkageFn: @escaping LLVMSetLinkageFn,
        int64TypeFn: @escaping LLVMInt64TypeInContextFn,
        pointerTypeFn: @escaping LLVMPointerTypeFn,
        functionTypeFn: @escaping LLVMFunctionTypeFn,
        addFunctionFn: @escaping LLVMAddFunctionFn,
        getNamedFunctionFn: @escaping LLVMGetNamedFunctionFn,
        getParamFn: @escaping LLVMGetParamFn,
        getUndefFn: @escaping LLVMGetUndefFn,
        appendBasicBlockFn: @escaping LLVMAppendBasicBlockInContextFn,
        createBuilderFn: @escaping LLVMCreateBuilderInContextFn,
        disposeBuilderFn: @escaping LLVMDisposeBuilderFn,
        positionBuilderFn: @escaping LLVMPositionBuilderAtEndFn,
        getBasicBlockTerminatorFn: @escaping LLVMGetBasicBlockTerminatorFn,
        buildRetFn: @escaping LLVMBuildRetFn,
        buildRetVoidFn: @escaping LLVMBuildRetVoidFn,
        buildBrFn: @escaping LLVMBuildBrFn,
        buildCondBrFn: @escaping LLVMBuildCondBrFn,
        buildAddFn: @escaping LLVMBuildAddFn,
        buildSubFn: @escaping LLVMBuildSubFn,
        buildMulFn: @escaping LLVMBuildMulFn,
        buildSDivFn: @escaping LLVMBuildSDivFn,
        buildICmpFn: @escaping LLVMBuildICmpFn,
        buildZExtFn: LLVMBuildZExtFn?,
        buildAllocaFn: LLVMBuildAllocaFn?,
        buildStoreFn: LLVMBuildStoreFn?,
        buildLoad2Fn: LLVMBuildLoad2Fn?,
        buildLoadFn: LLVMBuildLoadFn?,
        buildSelectFn: LLVMBuildSelectFn?,
        buildGlobalStringPtrFn: LLVMBuildGlobalStringPtrFn?,
        buildPtrToIntFn: LLVMBuildPtrToIntFn?,
        buildCall2Fn: LLVMBuildCall2Fn?,
        buildCallFn: LLVMBuildCallFn?,
        constIntFn: @escaping LLVMConstIntFn,
        constPointerNullFn: LLVMConstPointerNullFn?,
        getDefaultTargetTripleFn: @escaping LLVMGetDefaultTargetTripleFn,
        getTargetFromTripleFn: @escaping LLVMGetTargetFromTripleFn,
        createTargetMachineFn: @escaping LLVMCreateTargetMachineFn,
        disposeTargetMachineFn: @escaping LLVMDisposeTargetMachineFn,
        emitToFileFn: @escaping LLVMTargetMachineEmitToFileFn,
        createTargetDataLayoutFn: @escaping LLVMCreateTargetDataLayoutFn,
        copyStringRepOfTargetDataFn: @escaping LLVMCopyStringRepOfTargetDataFn,
        disposeTargetDataFn: @escaping LLVMDisposeTargetDataFn,
        initializeX86TargetInfoFn: LLVMInitializeX86TargetInfoFn?,
        initializeX86TargetFn: LLVMInitializeX86TargetFn?,
        initializeX86TargetMCFn: LLVMInitializeX86TargetMCFn?,
        initializeX86AsmPrinterFn: LLVMInitializeX86AsmPrinterFn?,
        initializeAArch64TargetInfoFn: LLVMInitializeAArch64TargetInfoFn?,
        initializeAArch64TargetFn: LLVMInitializeAArch64TargetFn?,
        initializeAArch64TargetMCFn: LLVMInitializeAArch64TargetMCFn?,
        initializeAArch64AsmPrinterFn: LLVMInitializeAArch64AsmPrinterFn?
    ) {
        self.handle = handle
        self.contextCreateFn = contextCreateFn
        self.contextDisposeFn = contextDisposeFn
        self.moduleCreateFn = moduleCreateFn
        self.disposeModuleFn = disposeModuleFn
        self.printModuleToStringFn = printModuleToStringFn
        self.disposeMessageFn = disposeMessageFn
        self.setTargetFn = setTargetFn
        self.setDataLayoutFn = setDataLayoutFn
        self.setLinkageFn = setLinkageFn
        self.int64TypeFn = int64TypeFn
        self.pointerTypeFn = pointerTypeFn
        self.functionTypeFn = functionTypeFn
        self.addFunctionFn = addFunctionFn
        self.getNamedFunctionFn = getNamedFunctionFn
        self.getParamFn = getParamFn
        self.getUndefFn = getUndefFn
        self.appendBasicBlockFn = appendBasicBlockFn
        self.createBuilderFn = createBuilderFn
        self.disposeBuilderFn = disposeBuilderFn
        self.positionBuilderFn = positionBuilderFn
        self.getBasicBlockTerminatorFn = getBasicBlockTerminatorFn
        self.buildRetFn = buildRetFn
        self.buildRetVoidFn = buildRetVoidFn
        self.buildBrFn = buildBrFn
        self.buildCondBrFn = buildCondBrFn
        self.buildAddFn = buildAddFn
        self.buildSubFn = buildSubFn
        self.buildMulFn = buildMulFn
        self.buildSDivFn = buildSDivFn
        self.buildICmpFn = buildICmpFn
        self.buildZExtFn = buildZExtFn
        self.buildAllocaFn = buildAllocaFn
        self.buildStoreFn = buildStoreFn
        self.buildLoad2Fn = buildLoad2Fn
        self.buildLoadFn = buildLoadFn
        self.buildSelectFn = buildSelectFn
        self.buildGlobalStringPtrFn = buildGlobalStringPtrFn
        self.buildPtrToIntFn = buildPtrToIntFn
        self.buildCall2Fn = buildCall2Fn
        self.buildCallFn = buildCallFn
        self.constIntFn = constIntFn
        self.constPointerNullFn = constPointerNullFn
        self.getDefaultTargetTripleFn = getDefaultTargetTripleFn
        self.getTargetFromTripleFn = getTargetFromTripleFn
        self.createTargetMachineFn = createTargetMachineFn
        self.disposeTargetMachineFn = disposeTargetMachineFn
        self.emitToFileFn = emitToFileFn
        self.createTargetDataLayoutFn = createTargetDataLayoutFn
        self.copyStringRepOfTargetDataFn = copyStringRepOfTargetDataFn
        self.disposeTargetDataFn = disposeTargetDataFn
        self.initializeX86TargetInfoFn = initializeX86TargetInfoFn
        self.initializeX86TargetFn = initializeX86TargetFn
        self.initializeX86TargetMCFn = initializeX86TargetMCFn
        self.initializeX86AsmPrinterFn = initializeX86AsmPrinterFn
        self.initializeAArch64TargetInfoFn = initializeAArch64TargetInfoFn
        self.initializeAArch64TargetFn = initializeAArch64TargetFn
        self.initializeAArch64TargetMCFn = initializeAArch64TargetMCFn
        self.initializeAArch64AsmPrinterFn = initializeAArch64AsmPrinterFn
    }

    deinit {
        dlclose(handle)
    }

    static func candidateLibraryPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var candidates: [String] = []
        if let override = environment["KSWIFTK_LLVM_DYLIB"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/opt/llvm/lib/libLLVM.dylib",
            "/usr/local/opt/llvm/lib/libLLVM.dylib",
            "/Library/Developer/CommandLineTools/usr/lib/libLLVM.dylib",
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/usr/lib/libLLVM.dylib",
            "/Users/kuu/Desktop/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/usr/lib/libLLVM.dylib",
            "libLLVM.dylib",
            "/usr/lib/x86_64-linux-gnu/libLLVM-15.so",
            "/usr/lib/x86_64-linux-gnu/libLLVM.so",
            "libLLVM.so"
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
                  let disposeTargetData = loadSymbol(handle: handle, name: "LLVMDisposeTargetData", as: LLVMDisposeTargetDataFn.self) else {
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
                buildICmpFn: buildICmp,
                buildZExtFn: loadSymbol(handle: handle, name: "LLVMBuildZExt", as: LLVMBuildZExtFn.self),
                buildAllocaFn: loadSymbol(handle: handle, name: "LLVMBuildAlloca", as: LLVMBuildAllocaFn.self),
                buildStoreFn: loadSymbol(handle: handle, name: "LLVMBuildStore", as: LLVMBuildStoreFn.self),
                buildLoad2Fn: loadSymbol(handle: handle, name: "LLVMBuildLoad2", as: LLVMBuildLoad2Fn.self),
                buildLoadFn: loadSymbol(handle: handle, name: "LLVMBuildLoad", as: LLVMBuildLoadFn.self),
                buildSelectFn: loadSymbol(handle: handle, name: "LLVMBuildSelect", as: LLVMBuildSelectFn.self),
                buildGlobalStringPtrFn: loadSymbol(handle: handle, name: "LLVMBuildGlobalStringPtr", as: LLVMBuildGlobalStringPtrFn.self),
                buildPtrToIntFn: loadSymbol(handle: handle, name: "LLVMBuildPtrToInt", as: LLVMBuildPtrToIntFn.self),
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
                initializeAArch64AsmPrinterFn: loadSymbol(handle: handle, name: "LLVMInitializeAArch64AsmPrinter", as: LLVMInitializeAArch64AsmPrinterFn.self)
            )
        }
        return nil
    }

    func smokeTestContextLifecycle() -> Bool {
        guard let context = contextCreateFn() else {
            return false
        }
        contextDisposeFn(context)
        return true
    }

    func createContext() -> LLVMContextRef? {
        contextCreateFn()
    }

    func disposeContext(_ context: LLVMContextRef?) {
        contextDisposeFn(context)
    }

    func createModule(name: String, context: LLVMContextRef?) -> LLVMModuleRef? {
        name.withCString { moduleCreateFn($0, context) }
    }

    func disposeModule(_ module: LLVMModuleRef?) {
        disposeModuleFn(module)
    }

    func printModule(_ module: LLVMModuleRef?) -> String? {
        guard let raw = printModuleToStringFn(module) else {
            return nil
        }
        defer { disposeMessageFn(raw) }
        return String(cString: raw)
    }

    func setTarget(_ module: LLVMModuleRef?, triple: String) {
        triple.withCString { setTargetFn(module, $0) }
    }

    func setDataLayout(_ module: LLVMModuleRef?, dataLayout: String) {
        dataLayout.withCString { setDataLayoutFn(module, $0) }
    }

    func setExternalWeakLinkage(_ value: LLVMValueRef?) {
        // LLVMLinkage enum value for LLVMExternalWeakLinkage.
        setLinkageFn(value, 12)
    }

    func setInternalLinkage(_ value: LLVMValueRef?) {
        // LLVMLinkage enum value for LLVMInternalLinkage.
        setLinkageFn(value, 8)
    }

    func int64Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int64TypeFn(context)
    }

    func pointerType(_ pointee: LLVMTypeRef?, addressSpace: UInt32 = 0) -> LLVMTypeRef? {
        pointerTypeFn(pointee, addressSpace)
    }

    func functionType(returnType: LLVMTypeRef?, parameters: [LLVMTypeRef?], isVarArg: Bool) -> LLVMTypeRef? {
        var mutable = parameters
        return functionTypeFn(returnType, &mutable, UInt32(mutable.count), isVarArg ? 1 : 0)
    }

    func addFunction(module: LLVMModuleRef?, name: String, functionType: LLVMTypeRef?) -> LLVMValueRef? {
        name.withCString { addFunctionFn(module, $0, functionType) }
    }

    func getNamedFunction(module: LLVMModuleRef?, name: String) -> LLVMValueRef? {
        name.withCString { getNamedFunctionFn(module, $0) }
    }

    func getParam(function: LLVMValueRef?, index: UInt32) -> LLVMValueRef? {
        getParamFn(function, index)
    }

    func getUndef(type: LLVMTypeRef?) -> LLVMValueRef? {
        getUndefFn(type)
    }

    func appendBasicBlock(context: LLVMContextRef?, function: LLVMValueRef?, name: String) -> LLVMBasicBlockRef? {
        name.withCString { appendBasicBlockFn(context, function, $0) }
    }

    func createBuilder(context: LLVMContextRef?) -> LLVMBuilderRef? {
        createBuilderFn(context)
    }

    func disposeBuilder(_ builder: LLVMBuilderRef?) {
        disposeBuilderFn(builder)
    }

    func positionBuilder(_ builder: LLVMBuilderRef?, at block: LLVMBasicBlockRef?) {
        positionBuilderFn(builder, block)
    }

    func hasTerminator(_ block: LLVMBasicBlockRef?) -> Bool {
        getBasicBlockTerminatorFn(block) != nil
    }

    @discardableResult
    func buildRet(_ builder: LLVMBuilderRef?, value: LLVMValueRef?) -> LLVMValueRef? {
        buildRetFn(builder, value)
    }

    @discardableResult
    func buildRetVoid(_ builder: LLVMBuilderRef?) -> LLVMValueRef? {
        buildRetVoidFn(builder)
    }

    @discardableResult
    func buildBr(_ builder: LLVMBuilderRef?, destination: LLVMBasicBlockRef?) -> LLVMValueRef? {
        buildBrFn(builder, destination)
    }

    @discardableResult
    func buildCondBr(
        _ builder: LLVMBuilderRef?,
        condition: LLVMValueRef?,
        thenBlock: LLVMBasicBlockRef?,
        elseBlock: LLVMBasicBlockRef?
    ) -> LLVMValueRef? {
        buildCondBrFn(builder, condition, thenBlock, elseBlock)
    }

    func buildICmpEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 32, lhs, rhs, $0) }
    }

    func buildICmpNotEqual(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildICmpFn(builder, 33, lhs, rhs, $0) }
    }

    func buildZExt(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildZExtFn else {
            return nil
        }
        return name.withCString { buildZExtFn(builder, value, type, $0) }
    }

    func buildAlloca(_ builder: LLVMBuilderRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildAllocaFn else {
            return nil
        }
        return name.withCString { buildAllocaFn(builder, type, $0) }
    }

    @discardableResult
    func buildStore(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, pointer: LLVMValueRef?) -> LLVMValueRef? {
        guard let buildStoreFn else {
            return nil
        }
        return buildStoreFn(builder, value, pointer)
    }

    func buildLoad(
        _ builder: LLVMBuilderRef?,
        type: LLVMTypeRef?,
        pointer: LLVMValueRef?,
        name: String
    ) -> LLVMValueRef? {
        if let buildLoad2Fn {
            return name.withCString { buildLoad2Fn(builder, type, pointer, $0) }
        }
        guard let buildLoadFn else {
            return nil
        }
        return name.withCString { buildLoadFn(builder, pointer, $0) }
    }

    func buildSelect(
        _ builder: LLVMBuilderRef?,
        condition: LLVMValueRef?,
        thenValue: LLVMValueRef?,
        elseValue: LLVMValueRef?,
        name: String
    ) -> LLVMValueRef? {
        guard let buildSelectFn else {
            return nil
        }
        return name.withCString { buildSelectFn(builder, condition, thenValue, elseValue, $0) }
    }

    func buildGlobalStringPtr(_ builder: LLVMBuilderRef?, value: String, name: String) -> LLVMValueRef? {
        guard let buildGlobalStringPtrFn else {
            return nil
        }
        return value.withCString { valueCString in
            name.withCString { nameCString in
                buildGlobalStringPtrFn(builder, valueCString, nameCString)
            }
        }
    }

    func buildPtrToInt(_ builder: LLVMBuilderRef?, value: LLVMValueRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let buildPtrToIntFn else {
            return nil
        }
        return name.withCString { buildPtrToIntFn(builder, value, type, $0) }
    }

    func buildAdd(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildAddFn(builder, lhs, rhs, $0) }
    }

    func buildSub(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildSubFn(builder, lhs, rhs, $0) }
    }

    func buildMul(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildMulFn(builder, lhs, rhs, $0) }
    }

    func buildSDiv(_ builder: LLVMBuilderRef?, lhs: LLVMValueRef?, rhs: LLVMValueRef?, name: String) -> LLVMValueRef? {
        name.withCString { buildSDivFn(builder, lhs, rhs, $0) }
    }

    func buildCall(
        _ builder: LLVMBuilderRef?,
        functionType: LLVMTypeRef?,
        callee: LLVMValueRef?,
        arguments: [LLVMValueRef?],
        name: String
    ) -> LLVMValueRef? {
        var mutable = arguments
        return name.withCString { cName in
            if let buildCall2Fn {
                return buildCall2Fn(builder, functionType, callee, &mutable, UInt32(mutable.count), cName)
            }
            guard let buildCallFn else {
                return nil
            }
            return buildCallFn(builder, callee, &mutable, UInt32(mutable.count), cName)
        }
    }

    func constInt(_ type: LLVMTypeRef?, value: UInt64, signExtend: Bool = false) -> LLVMValueRef? {
        constIntFn(type, value, signExtend ? 1 : 0)
    }

    func constPointerNull(_ type: LLVMTypeRef?) -> LLVMValueRef? {
        constPointerNullFn?(type)
    }

    func defaultTargetTriple() -> String? {
        guard let triplePtr = getDefaultTargetTripleFn() else {
            return nil
        }
        defer { disposeMessageFn(triplePtr) }
        return String(cString: triplePtr)
    }

    func createTargetMachine(triple: String, optLevel: OptimizationLevel) -> LLVMTargetMachineRef? {
        initializeTarget(for: triple)

        var target: LLVMTargetRef?
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = triple.withCString { getTargetFromTripleFn($0, &target, &errorMessage) }
        if status != 0 {
            if let errorMessage {
                disposeMessageFn(errorMessage)
            }
            return nil
        }

        let opt = llvmOptLevel(optLevel)
        let reloc: UInt32 = 0
        let codeModel: UInt32 = 0
        return triple.withCString { tripleCStr in
            "generic".withCString { cpuCStr in
                "".withCString { featuresCStr in
                    createTargetMachineFn(target, tripleCStr, cpuCStr, featuresCStr, opt, reloc, codeModel)
                }
            }
        }
    }

    func disposeTargetMachine(_ machine: LLVMTargetMachineRef?) {
        disposeTargetMachineFn(machine)
    }

    func applyTargetMachine(_ machine: LLVMTargetMachineRef?, to module: LLVMModuleRef?) -> Bool {
        guard let machine, let module else {
            return false
        }
        guard let targetData = createTargetDataLayoutFn(machine) else {
            return false
        }
        defer { disposeTargetDataFn(targetData) }
        guard let layoutCString = copyStringRepOfTargetDataFn(targetData) else {
            return false
        }
        defer { disposeMessageFn(layoutCString) }
        setDataLayoutFn(module, layoutCString)
        return true
    }

    func emitObject(targetMachine: LLVMTargetMachineRef?, module: LLVMModuleRef?, outputPath: String) -> String? {
        guard let targetMachine, let module else {
            return "LLVM target machine is not initialized."
        }

        let mutablePath = strdup(outputPath)
        defer { free(mutablePath) }
        guard let mutablePath else {
            return "Unable to allocate output path buffer."
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = emitToFileFn(targetMachine, module, mutablePath, 1, &errorMessage)
        if status == 0 {
            return nil
        }
        defer {
            if let errorMessage {
                disposeMessageFn(errorMessage)
            }
        }
        if let errorMessage {
            return String(cString: errorMessage)
        }
        return "LLVMTargetMachineEmitToFile failed."
    }

    private func initializeTarget(for triple: String) {
        if triple.hasPrefix("x86_64") || triple.hasPrefix("i386") {
            initializeX86TargetInfoFn?()
            initializeX86TargetFn?()
            initializeX86TargetMCFn?()
            initializeX86AsmPrinterFn?()
            return
        }
        if triple.hasPrefix("arm64") || triple.hasPrefix("aarch64") {
            initializeAArch64TargetInfoFn?()
            initializeAArch64TargetFn?()
            initializeAArch64TargetMCFn?()
            initializeAArch64AsmPrinterFn?()
        }
    }

    private func llvmOptLevel(_ level: OptimizationLevel) -> UInt32 {
        switch level {
        case .O0:
            return 0
        case .O1:
            return 1
        case .O2:
            return 2
        case .O3:
            return 3
        }
    }

    private static func loadSymbol<T>(
        handle: UnsafeMutableRawPointer,
        name: String,
        as type: T.Type
    ) -> T? {
        guard let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}
