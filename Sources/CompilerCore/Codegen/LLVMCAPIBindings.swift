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

    typealias LLVMContextCreateFn = @convention(c) () -> LLVMContextRef?
    typealias LLVMContextDisposeFn = @convention(c) (LLVMContextRef?) -> Void
    typealias LLVMModuleCreateWithNameInContextFn = @convention(c) (UnsafePointer<CChar>?, LLVMContextRef?) -> LLVMModuleRef?
    typealias LLVMDisposeModuleFn = @convention(c) (LLVMModuleRef?) -> Void
    typealias LLVMPrintModuleToStringFn = @convention(c) (LLVMModuleRef?) -> UnsafeMutablePointer<CChar>?
    typealias LLVMDisposeMessageFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    typealias LLVMSetTargetFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    typealias LLVMSetDataLayoutFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    typealias LLVMSetLinkageFn = @convention(c) (LLVMValueRef?, UInt32) -> Void
    typealias LLVMInt64TypeInContextFn = @convention(c) (LLVMContextRef?) -> LLVMTypeRef?
    typealias LLVMPointerTypeFn = @convention(c) (LLVMTypeRef?, UInt32) -> LLVMTypeRef?
    typealias LLVMFunctionTypeFn = @convention(c) (LLVMTypeRef?, UnsafeMutablePointer<LLVMTypeRef?>?, UInt32, LLVMBool) -> LLVMTypeRef?
    typealias LLVMAddFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?, LLVMTypeRef?) -> LLVMValueRef?
    typealias LLVMGetNamedFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMGetParamFn = @convention(c) (LLVMValueRef?, UInt32) -> LLVMValueRef?
    typealias LLVMGetUndefFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    typealias LLVMAppendBasicBlockInContextFn = @convention(c) (LLVMContextRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMBasicBlockRef?
    typealias LLVMCreateBuilderInContextFn = @convention(c) (LLVMContextRef?) -> LLVMBuilderRef?
    typealias LLVMDisposeBuilderFn = @convention(c) (LLVMBuilderRef?) -> Void
    typealias LLVMPositionBuilderAtEndFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> Void
    typealias LLVMGetBasicBlockTerminatorFn = @convention(c) (LLVMBasicBlockRef?) -> LLVMValueRef?
    typealias LLVMBuildRetFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?) -> LLVMValueRef?
    typealias LLVMBuildRetVoidFn = @convention(c) (LLVMBuilderRef?) -> LLVMValueRef?
    typealias LLVMBuildBrFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    typealias LLVMBuildCondBrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMBasicBlockRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    typealias LLVMBuildAddFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildSubFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildMulFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildSDivFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    // Bitwise/shift builder function types (P5-103)
    typealias LLVMBuildAndFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildOrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildXorFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildShlFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildAShrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildLShrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildNotFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildICmpFn = @convention(c) (LLVMBuilderRef?, UInt32, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildZExtFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildAllocaFn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildStoreFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?) -> LLVMValueRef?
    typealias LLVMBuildLoad2Fn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildLoadFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildSelectFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildGlobalStringPtrFn = @convention(c) (LLVMBuilderRef?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildPtrToIntFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMBuildCall2Fn = @convention(c) (
        LLVMBuilderRef?,
        LLVMTypeRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    typealias LLVMBuildCallFn = @convention(c) (
        LLVMBuilderRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    typealias LLVMAddGlobalFn = @convention(c) (LLVMModuleRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    typealias LLVMSetInitializerFn = @convention(c) (LLVMValueRef?, LLVMValueRef?) -> Void
    typealias LLVMConstIntFn = @convention(c) (LLVMTypeRef?, UInt64, LLVMBool) -> LLVMValueRef?
    typealias LLVMConstPointerNullFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    typealias LLVMGetDefaultTargetTripleFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias LLVMGetTargetFromTripleFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<LLVMTargetRef?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    typealias LLVMCreateTargetMachineFn = @convention(c) (
        LLVMTargetRef?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt32,
        UInt32,
        UInt32
    ) -> LLVMTargetMachineRef?
    typealias LLVMDisposeTargetMachineFn = @convention(c) (LLVMTargetMachineRef?) -> Void
    typealias LLVMTargetMachineEmitToFileFn = @convention(c) (
        LLVMTargetMachineRef?,
        LLVMModuleRef?,
        UnsafeMutablePointer<CChar>?,
        UInt32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    typealias LLVMCreateTargetDataLayoutFn = @convention(c) (LLVMTargetMachineRef?) -> LLVMTargetDataRef?
    typealias LLVMCopyStringRepOfTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> UnsafeMutablePointer<CChar>?
    typealias LLVMDisposeTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> Void
    typealias LLVMInitializeX86TargetInfoFn = @convention(c) () -> Void
    typealias LLVMInitializeX86TargetFn = @convention(c) () -> Void
    typealias LLVMInitializeX86TargetMCFn = @convention(c) () -> Void
    typealias LLVMInitializeX86AsmPrinterFn = @convention(c) () -> Void
    typealias LLVMInitializeAArch64TargetInfoFn = @convention(c) () -> Void
    typealias LLVMInitializeAArch64TargetFn = @convention(c) () -> Void
    typealias LLVMInitializeAArch64TargetMCFn = @convention(c) () -> Void
    typealias LLVMInitializeAArch64AsmPrinterFn = @convention(c) () -> Void

    typealias LLVMDIBuilderRef = OpaquePointer
    typealias LLVMMetadataRef = OpaquePointer

    typealias LLVMCreateDIBuilderFn = @convention(c) (LLVMModuleRef?) -> LLVMDIBuilderRef?
    typealias LLVMDisposeDIBuilderFn = @convention(c) (LLVMDIBuilderRef?) -> Void
    typealias LLVMDIBuilderFinalizeFn = @convention(c) (LLVMDIBuilderRef?) -> Void
    typealias LLVMDIBuilderCreateFileFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafePointer<CChar>?, Int,
        UnsafePointer<CChar>?, Int
    ) -> LLVMMetadataRef?
    typealias LLVMDIBuilderCreateCompileUnitFn = @convention(c) (
        LLVMDIBuilderRef?,
        UInt32, LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        Int32,
        UnsafePointer<CChar>?, Int,
        UInt32,
        UnsafePointer<CChar>?, Int,
        UInt32, UInt32, Int32, Int32,
        UnsafePointer<CChar>?, Int,
        UnsafePointer<CChar>?, Int
    ) -> LLVMMetadataRef?
    typealias LLVMDIBuilderCreateSubroutineTypeFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafeMutablePointer<LLVMMetadataRef?>?, UInt32,
        UInt32
    ) -> LLVMMetadataRef?
    typealias LLVMDIBuilderCreateFunctionFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?,
        UInt32, LLVMMetadataRef?,
        Int32, Int32, UInt32, UInt32, Int32
    ) -> LLVMMetadataRef?
    typealias LLVMSetSubprogramFn = @convention(c) (LLVMValueRef?, LLVMMetadataRef?) -> Void
    typealias LLVMAddModuleFlagFn = @convention(c) (
        LLVMModuleRef?, UInt32,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?
    ) -> Void
    typealias LLVMValueAsMetadataFn = @convention(c) (LLVMValueRef?) -> LLVMMetadataRef?
    typealias LLVMInt32TypeInContextFn = @convention(c) (LLVMContextRef?) -> LLVMTypeRef?
    typealias LLVMSetCurrentDebugLocation2Fn = @convention(c) (LLVMBuilderRef?, LLVMMetadataRef?) -> Void
    typealias LLVMDIBuilderCreateDebugLocationFn = @convention(c) (
        LLVMContextRef?, UInt32, UInt32, LLVMMetadataRef?, LLVMMetadataRef?
    ) -> LLVMMetadataRef?
    typealias LLVMDIBuilderCreateBasicTypeFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafePointer<CChar>?, Int,
        UInt64, UInt32, UInt32
    ) -> LLVMMetadataRef?
    /// LLVMDIBuilderCreateParameterVariable(
    ///   Builder, Scope, Name, NameLen, ArgNo, File, LineNo, Ty,
    ///   AlwaysPreserve, Flags)
    typealias LLVMDIBuilderCreateParameterVariableFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        UInt32,
        LLVMMetadataRef?,
        UInt32,
        LLVMMetadataRef?,
        Int32, UInt32
    ) -> LLVMMetadataRef?
    /// LLVMDIBuilderCreateAutoVariable(
    ///   Builder, Scope, Name, NameLen, File, LineNo, Ty,
    ///   AlwaysPreserve, Flags, AlignInBits)
    typealias LLVMDIBuilderCreateAutoVariableFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?,
        UInt32,
        LLVMMetadataRef?,
        Int32, UInt32, UInt32
    ) -> LLVMMetadataRef?
    typealias LLVMDIBuilderInsertDeclareAtEndFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMValueRef?,
        LLVMMetadataRef?,
        LLVMMetadataRef?,
        LLVMMetadataRef?,
        LLVMBasicBlockRef?
    ) -> LLVMValueRef?
    typealias LLVMDIBuilderCreateExpressionFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafeMutablePointer<UInt64>?, Int
    ) -> LLVMMetadataRef?

    private let handle: UnsafeMutableRawPointer
    let contextCreateFn: LLVMContextCreateFn
    let contextDisposeFn: LLVMContextDisposeFn
    let moduleCreateFn: LLVMModuleCreateWithNameInContextFn
    let disposeModuleFn: LLVMDisposeModuleFn
    let printModuleToStringFn: LLVMPrintModuleToStringFn
    let disposeMessageFn: LLVMDisposeMessageFn
    let setTargetFn: LLVMSetTargetFn
    let setDataLayoutFn: LLVMSetDataLayoutFn
    let setLinkageFn: LLVMSetLinkageFn
    let int64TypeFn: LLVMInt64TypeInContextFn
    let pointerTypeFn: LLVMPointerTypeFn
    let functionTypeFn: LLVMFunctionTypeFn
    let addFunctionFn: LLVMAddFunctionFn
    let getNamedFunctionFn: LLVMGetNamedFunctionFn
    let getParamFn: LLVMGetParamFn
    let getUndefFn: LLVMGetUndefFn
    let appendBasicBlockFn: LLVMAppendBasicBlockInContextFn
    let createBuilderFn: LLVMCreateBuilderInContextFn
    let disposeBuilderFn: LLVMDisposeBuilderFn
    let positionBuilderFn: LLVMPositionBuilderAtEndFn
    let getBasicBlockTerminatorFn: LLVMGetBasicBlockTerminatorFn
    let buildRetFn: LLVMBuildRetFn
    let buildRetVoidFn: LLVMBuildRetVoidFn
    let buildBrFn: LLVMBuildBrFn
    let buildCondBrFn: LLVMBuildCondBrFn
    let buildAddFn: LLVMBuildAddFn
    let buildSubFn: LLVMBuildSubFn
    let buildMulFn: LLVMBuildMulFn
    let buildSDivFn: LLVMBuildSDivFn
    // Bitwise/shift builder stored properties (P5-103)
    let buildAndFn: LLVMBuildAndFn?
    let buildOrFn: LLVMBuildOrFn?
    let buildXorFn: LLVMBuildXorFn?
    let buildShlFn: LLVMBuildShlFn?
    let buildAShrFn: LLVMBuildAShrFn?
    let buildLShrFn: LLVMBuildLShrFn?
    let buildNotFn: LLVMBuildNotFn?
    let buildICmpFn: LLVMBuildICmpFn
    let buildZExtFn: LLVMBuildZExtFn?
    let buildAllocaFn: LLVMBuildAllocaFn?
    let buildStoreFn: LLVMBuildStoreFn?
    let buildLoad2Fn: LLVMBuildLoad2Fn?
    let buildLoadFn: LLVMBuildLoadFn?
    let buildSelectFn: LLVMBuildSelectFn?
    let buildGlobalStringPtrFn: LLVMBuildGlobalStringPtrFn?
    let buildPtrToIntFn: LLVMBuildPtrToIntFn?
    let buildCall2Fn: LLVMBuildCall2Fn?
    let buildCallFn: LLVMBuildCallFn?
    let constIntFn: LLVMConstIntFn
    let constPointerNullFn: LLVMConstPointerNullFn?
    let getDefaultTargetTripleFn: LLVMGetDefaultTargetTripleFn
    let getTargetFromTripleFn: LLVMGetTargetFromTripleFn
    let createTargetMachineFn: LLVMCreateTargetMachineFn
    let disposeTargetMachineFn: LLVMDisposeTargetMachineFn
    let emitToFileFn: LLVMTargetMachineEmitToFileFn
    let createTargetDataLayoutFn: LLVMCreateTargetDataLayoutFn
    let copyStringRepOfTargetDataFn: LLVMCopyStringRepOfTargetDataFn
    let disposeTargetDataFn: LLVMDisposeTargetDataFn
    let initializeX86TargetInfoFn: LLVMInitializeX86TargetInfoFn?
    let initializeX86TargetFn: LLVMInitializeX86TargetFn?
    let initializeX86TargetMCFn: LLVMInitializeX86TargetMCFn?
    let initializeX86AsmPrinterFn: LLVMInitializeX86AsmPrinterFn?
    let initializeAArch64TargetInfoFn: LLVMInitializeAArch64TargetInfoFn?
    let initializeAArch64TargetFn: LLVMInitializeAArch64TargetFn?
    let initializeAArch64TargetMCFn: LLVMInitializeAArch64TargetMCFn?
    let initializeAArch64AsmPrinterFn: LLVMInitializeAArch64AsmPrinterFn?
    let addGlobalFn: LLVMAddGlobalFn?
    let setInitializerFn: LLVMSetInitializerFn?
    let createDIBuilderFn: LLVMCreateDIBuilderFn?
    let disposeDIBuilderFn: LLVMDisposeDIBuilderFn?
    let diBuilderFinalizeFn: LLVMDIBuilderFinalizeFn?
    let diBuilderCreateFileFn: LLVMDIBuilderCreateFileFn?
    let diBuilderCreateCompileUnitFn: LLVMDIBuilderCreateCompileUnitFn?
    let diBuilderCreateSubroutineTypeFn: LLVMDIBuilderCreateSubroutineTypeFn?
    let diBuilderCreateFunctionFn: LLVMDIBuilderCreateFunctionFn?
    let setSubprogramFn: LLVMSetSubprogramFn?
    let addModuleFlagFn: LLVMAddModuleFlagFn?
    let valueAsMetadataFn: LLVMValueAsMetadataFn?
    let int32TypeFn: LLVMInt32TypeInContextFn?
    let setCurrentDebugLocation2Fn: LLVMSetCurrentDebugLocation2Fn?
    let diBuilderCreateDebugLocationFn: LLVMDIBuilderCreateDebugLocationFn?
    let diBuilderCreateBasicTypeFn: LLVMDIBuilderCreateBasicTypeFn?
    let diBuilderCreateParameterVariableFn: LLVMDIBuilderCreateParameterVariableFn?
    let diBuilderCreateAutoVariableFn: LLVMDIBuilderCreateAutoVariableFn?
    let diBuilderInsertDeclareAtEndFn: LLVMDIBuilderInsertDeclareAtEndFn?
    let diBuilderCreateExpressionFn: LLVMDIBuilderCreateExpressionFn?

    init(
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
        // Bitwise/shift builder init params (P5-103)
        buildAndFn: LLVMBuildAndFn?,
        buildOrFn: LLVMBuildOrFn?,
        buildXorFn: LLVMBuildXorFn?,
        buildShlFn: LLVMBuildShlFn?,
        buildAShrFn: LLVMBuildAShrFn?,
        buildLShrFn: LLVMBuildLShrFn?,
        buildNotFn: LLVMBuildNotFn?,
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
        initializeAArch64AsmPrinterFn: LLVMInitializeAArch64AsmPrinterFn?,
        addGlobalFn: LLVMAddGlobalFn? = nil,
        setInitializerFn: LLVMSetInitializerFn? = nil,
        createDIBuilderFn: LLVMCreateDIBuilderFn?,
        disposeDIBuilderFn: LLVMDisposeDIBuilderFn?,
        diBuilderFinalizeFn: LLVMDIBuilderFinalizeFn?,
        diBuilderCreateFileFn: LLVMDIBuilderCreateFileFn?,
        diBuilderCreateCompileUnitFn: LLVMDIBuilderCreateCompileUnitFn?,
        diBuilderCreateSubroutineTypeFn: LLVMDIBuilderCreateSubroutineTypeFn?,
        diBuilderCreateFunctionFn: LLVMDIBuilderCreateFunctionFn?,
        setSubprogramFn: LLVMSetSubprogramFn?,
        addModuleFlagFn: LLVMAddModuleFlagFn?,
        valueAsMetadataFn: LLVMValueAsMetadataFn?,
        int32TypeFn: LLVMInt32TypeInContextFn?,
        setCurrentDebugLocation2Fn: LLVMSetCurrentDebugLocation2Fn? = nil,
        diBuilderCreateDebugLocationFn: LLVMDIBuilderCreateDebugLocationFn? = nil,
        diBuilderCreateBasicTypeFn: LLVMDIBuilderCreateBasicTypeFn? = nil,
        diBuilderCreateParameterVariableFn: LLVMDIBuilderCreateParameterVariableFn? = nil,
        diBuilderCreateAutoVariableFn: LLVMDIBuilderCreateAutoVariableFn? = nil,
        diBuilderInsertDeclareAtEndFn: LLVMDIBuilderInsertDeclareAtEndFn? = nil,
        diBuilderCreateExpressionFn: LLVMDIBuilderCreateExpressionFn? = nil
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
        // Bitwise/shift builder assignments (P5-103)
        self.buildAndFn = buildAndFn
        self.buildOrFn = buildOrFn
        self.buildXorFn = buildXorFn
        self.buildShlFn = buildShlFn
        self.buildAShrFn = buildAShrFn
        self.buildLShrFn = buildLShrFn
        self.buildNotFn = buildNotFn
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
        self.addGlobalFn = addGlobalFn
        self.setInitializerFn = setInitializerFn
        self.createDIBuilderFn = createDIBuilderFn
        self.disposeDIBuilderFn = disposeDIBuilderFn
        self.diBuilderFinalizeFn = diBuilderFinalizeFn
        self.diBuilderCreateFileFn = diBuilderCreateFileFn
        self.diBuilderCreateCompileUnitFn = diBuilderCreateCompileUnitFn
        self.diBuilderCreateSubroutineTypeFn = diBuilderCreateSubroutineTypeFn
        self.diBuilderCreateFunctionFn = diBuilderCreateFunctionFn
        self.setSubprogramFn = setSubprogramFn
        self.addModuleFlagFn = addModuleFlagFn
        self.valueAsMetadataFn = valueAsMetadataFn
        self.int32TypeFn = int32TypeFn
        self.setCurrentDebugLocation2Fn = setCurrentDebugLocation2Fn
        self.diBuilderCreateDebugLocationFn = diBuilderCreateDebugLocationFn
        self.diBuilderCreateBasicTypeFn = diBuilderCreateBasicTypeFn
        self.diBuilderCreateParameterVariableFn = diBuilderCreateParameterVariableFn
        self.diBuilderCreateAutoVariableFn = diBuilderCreateAutoVariableFn
        self.diBuilderInsertDeclareAtEndFn = diBuilderInsertDeclareAtEndFn
        self.diBuilderCreateExpressionFn = diBuilderCreateExpressionFn
    }

    deinit {
        dlclose(handle)
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

    func setWeakAnyLinkage(_ value: LLVMValueRef?) {
        // LLVMLinkage enum value for LLVMWeakAnyLinkage.
        setLinkageFn(value, 5)
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

    func addGlobal(module: LLVMModuleRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let fn = addGlobalFn else { return nil }
        return name.withCString { fn(module, type, $0) }
    }

    func setInitializer(_ global: LLVMValueRef?, value: LLVMValueRef?) {
        setInitializerFn?(global, value)
    }
}
