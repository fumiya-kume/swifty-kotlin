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

    internal typealias LLVMContextCreateFn = @convention(c) () -> LLVMContextRef?
    internal typealias LLVMContextDisposeFn = @convention(c) (LLVMContextRef?) -> Void
    internal typealias LLVMModuleCreateWithNameInContextFn = @convention(c) (UnsafePointer<CChar>?, LLVMContextRef?) -> LLVMModuleRef?
    internal typealias LLVMDisposeModuleFn = @convention(c) (LLVMModuleRef?) -> Void
    internal typealias LLVMPrintModuleToStringFn = @convention(c) (LLVMModuleRef?) -> UnsafeMutablePointer<CChar>?
    internal typealias LLVMDisposeMessageFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    internal typealias LLVMSetTargetFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    internal typealias LLVMSetDataLayoutFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> Void
    internal typealias LLVMSetLinkageFn = @convention(c) (LLVMValueRef?, UInt32) -> Void
    internal typealias LLVMInt64TypeInContextFn = @convention(c) (LLVMContextRef?) -> LLVMTypeRef?
    internal typealias LLVMPointerTypeFn = @convention(c) (LLVMTypeRef?, UInt32) -> LLVMTypeRef?
    internal typealias LLVMFunctionTypeFn = @convention(c) (LLVMTypeRef?, UnsafeMutablePointer<LLVMTypeRef?>?, UInt32, LLVMBool) -> LLVMTypeRef?
    internal typealias LLVMAddFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?, LLVMTypeRef?) -> LLVMValueRef?
    internal typealias LLVMGetNamedFunctionFn = @convention(c) (LLVMModuleRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMGetParamFn = @convention(c) (LLVMValueRef?, UInt32) -> LLVMValueRef?
    internal typealias LLVMGetUndefFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    internal typealias LLVMAppendBasicBlockInContextFn = @convention(c) (LLVMContextRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMBasicBlockRef?
    internal typealias LLVMCreateBuilderInContextFn = @convention(c) (LLVMContextRef?) -> LLVMBuilderRef?
    internal typealias LLVMDisposeBuilderFn = @convention(c) (LLVMBuilderRef?) -> Void
    internal typealias LLVMPositionBuilderAtEndFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> Void
    internal typealias LLVMGetBasicBlockTerminatorFn = @convention(c) (LLVMBasicBlockRef?) -> LLVMValueRef?
    internal typealias LLVMBuildRetFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?) -> LLVMValueRef?
    internal typealias LLVMBuildRetVoidFn = @convention(c) (LLVMBuilderRef?) -> LLVMValueRef?
    internal typealias LLVMBuildBrFn = @convention(c) (LLVMBuilderRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    internal typealias LLVMBuildCondBrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMBasicBlockRef?, LLVMBasicBlockRef?) -> LLVMValueRef?
    internal typealias LLVMBuildAddFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildSubFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildMulFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildSDivFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    // Bitwise/shift builder function types (P5-103)
    internal typealias LLVMBuildAndFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildOrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildXorFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildShlFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildAShrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildLShrFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildNotFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildICmpFn = @convention(c) (LLVMBuilderRef?, UInt32, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildZExtFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildAllocaFn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildStoreFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?) -> LLVMValueRef?
    internal typealias LLVMBuildLoad2Fn = @convention(c) (LLVMBuilderRef?, LLVMTypeRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildLoadFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildSelectFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMValueRef?, LLVMValueRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildGlobalStringPtrFn = @convention(c) (LLVMBuilderRef?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildPtrToIntFn = @convention(c) (LLVMBuilderRef?, LLVMValueRef?, LLVMTypeRef?, UnsafePointer<CChar>?) -> LLVMValueRef?
    internal typealias LLVMBuildCall2Fn = @convention(c) (
        LLVMBuilderRef?,
        LLVMTypeRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    internal typealias LLVMBuildCallFn = @convention(c) (
        LLVMBuilderRef?,
        LLVMValueRef?,
        UnsafeMutablePointer<LLVMValueRef?>?,
        UInt32,
        UnsafePointer<CChar>?
    ) -> LLVMValueRef?
    internal typealias LLVMConstIntFn = @convention(c) (LLVMTypeRef?, UInt64, LLVMBool) -> LLVMValueRef?
    internal typealias LLVMConstPointerNullFn = @convention(c) (LLVMTypeRef?) -> LLVMValueRef?
    internal typealias LLVMGetDefaultTargetTripleFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
    internal typealias LLVMGetTargetFromTripleFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<LLVMTargetRef?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    internal typealias LLVMCreateTargetMachineFn = @convention(c) (
        LLVMTargetRef?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt32,
        UInt32,
        UInt32
    ) -> LLVMTargetMachineRef?
    internal typealias LLVMDisposeTargetMachineFn = @convention(c) (LLVMTargetMachineRef?) -> Void
    internal typealias LLVMTargetMachineEmitToFileFn = @convention(c) (
        LLVMTargetMachineRef?,
        LLVMModuleRef?,
        UnsafeMutablePointer<CChar>?,
        UInt32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> LLVMBool
    internal typealias LLVMCreateTargetDataLayoutFn = @convention(c) (LLVMTargetMachineRef?) -> LLVMTargetDataRef?
    internal typealias LLVMCopyStringRepOfTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> UnsafeMutablePointer<CChar>?
    internal typealias LLVMDisposeTargetDataFn = @convention(c) (LLVMTargetDataRef?) -> Void
    internal typealias LLVMInitializeX86TargetInfoFn = @convention(c) () -> Void
    internal typealias LLVMInitializeX86TargetFn = @convention(c) () -> Void
    internal typealias LLVMInitializeX86TargetMCFn = @convention(c) () -> Void
    internal typealias LLVMInitializeX86AsmPrinterFn = @convention(c) () -> Void
    internal typealias LLVMInitializeAArch64TargetInfoFn = @convention(c) () -> Void
    internal typealias LLVMInitializeAArch64TargetFn = @convention(c) () -> Void
    internal typealias LLVMInitializeAArch64TargetMCFn = @convention(c) () -> Void
    internal typealias LLVMInitializeAArch64AsmPrinterFn = @convention(c) () -> Void

    typealias LLVMDIBuilderRef = OpaquePointer
    typealias LLVMMetadataRef = OpaquePointer

    internal typealias LLVMCreateDIBuilderFn = @convention(c) (LLVMModuleRef?) -> LLVMDIBuilderRef?
    internal typealias LLVMDisposeDIBuilderFn = @convention(c) (LLVMDIBuilderRef?) -> Void
    internal typealias LLVMDIBuilderFinalizeFn = @convention(c) (LLVMDIBuilderRef?) -> Void
    internal typealias LLVMDIBuilderCreateFileFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafePointer<CChar>?, Int,
        UnsafePointer<CChar>?, Int
    ) -> LLVMMetadataRef?
    internal typealias LLVMDIBuilderCreateCompileUnitFn = @convention(c) (
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
    internal typealias LLVMDIBuilderCreateSubroutineTypeFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafeMutablePointer<LLVMMetadataRef?>?, UInt32,
        UInt32
    ) -> LLVMMetadataRef?
    internal typealias LLVMDIBuilderCreateFunctionFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?,
        UInt32, LLVMMetadataRef?,
        Int32, Int32, UInt32, UInt32, Int32
    ) -> LLVMMetadataRef?
    internal typealias LLVMSetSubprogramFn = @convention(c) (LLVMValueRef?, LLVMMetadataRef?) -> Void
    internal typealias LLVMAddModuleFlagFn = @convention(c) (
        LLVMModuleRef?, UInt32,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?
    ) -> Void
    internal typealias LLVMValueAsMetadataFn = @convention(c) (LLVMValueRef?) -> LLVMMetadataRef?
    internal typealias LLVMInt32TypeInContextFn = @convention(c) (LLVMContextRef?) -> LLVMTypeRef?
    internal typealias LLVMSetCurrentDebugLocation2Fn = @convention(c) (LLVMBuilderRef?, LLVMMetadataRef?) -> Void
    internal typealias LLVMDIBuilderCreateDebugLocationFn = @convention(c) (
        LLVMContextRef?, UInt32, UInt32, LLVMMetadataRef?, LLVMMetadataRef?
    ) -> LLVMMetadataRef?
    internal typealias LLVMDIBuilderCreateBasicTypeFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafePointer<CChar>?, Int,
        UInt64, UInt32, UInt32
    ) -> LLVMMetadataRef?
    // LLVMDIBuilderCreateParameterVariable(
    //   Builder, Scope, Name, NameLen, ArgNo, File, LineNo, Ty,
    //   AlwaysPreserve, Flags)
    internal typealias LLVMDIBuilderCreateParameterVariableFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        UInt32,
        LLVMMetadataRef?,
        UInt32,
        LLVMMetadataRef?,
        Int32, UInt32
    ) -> LLVMMetadataRef?
    // LLVMDIBuilderCreateAutoVariable(
    //   Builder, Scope, Name, NameLen, File, LineNo, Ty,
    //   AlwaysPreserve, Flags, AlignInBits)
    internal typealias LLVMDIBuilderCreateAutoVariableFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMMetadataRef?,
        UnsafePointer<CChar>?, Int,
        LLVMMetadataRef?,
        UInt32,
        LLVMMetadataRef?,
        Int32, UInt32, UInt32
    ) -> LLVMMetadataRef?
    internal typealias LLVMDIBuilderInsertDeclareAtEndFn = @convention(c) (
        LLVMDIBuilderRef?,
        LLVMValueRef?,
        LLVMMetadataRef?,
        LLVMMetadataRef?,
        LLVMMetadataRef?,
        LLVMBasicBlockRef?
    ) -> LLVMValueRef?
    internal typealias LLVMDIBuilderCreateExpressionFn = @convention(c) (
        LLVMDIBuilderRef?,
        UnsafeMutablePointer<UInt64>?, Int
    ) -> LLVMMetadataRef?

    private let handle: UnsafeMutableRawPointer
    internal let contextCreateFn: LLVMContextCreateFn
    internal let contextDisposeFn: LLVMContextDisposeFn
    internal let moduleCreateFn: LLVMModuleCreateWithNameInContextFn
    internal let disposeModuleFn: LLVMDisposeModuleFn
    internal let printModuleToStringFn: LLVMPrintModuleToStringFn
    internal let disposeMessageFn: LLVMDisposeMessageFn
    internal let setTargetFn: LLVMSetTargetFn
    internal let setDataLayoutFn: LLVMSetDataLayoutFn
    internal let setLinkageFn: LLVMSetLinkageFn
    internal let int64TypeFn: LLVMInt64TypeInContextFn
    internal let pointerTypeFn: LLVMPointerTypeFn
    internal let functionTypeFn: LLVMFunctionTypeFn
    internal let addFunctionFn: LLVMAddFunctionFn
    internal let getNamedFunctionFn: LLVMGetNamedFunctionFn
    internal let getParamFn: LLVMGetParamFn
    internal let getUndefFn: LLVMGetUndefFn
    internal let appendBasicBlockFn: LLVMAppendBasicBlockInContextFn
    internal let createBuilderFn: LLVMCreateBuilderInContextFn
    internal let disposeBuilderFn: LLVMDisposeBuilderFn
    internal let positionBuilderFn: LLVMPositionBuilderAtEndFn
    internal let getBasicBlockTerminatorFn: LLVMGetBasicBlockTerminatorFn
    internal let buildRetFn: LLVMBuildRetFn
    internal let buildRetVoidFn: LLVMBuildRetVoidFn
    internal let buildBrFn: LLVMBuildBrFn
    internal let buildCondBrFn: LLVMBuildCondBrFn
    internal let buildAddFn: LLVMBuildAddFn
    internal let buildSubFn: LLVMBuildSubFn
    internal let buildMulFn: LLVMBuildMulFn
    internal let buildSDivFn: LLVMBuildSDivFn
    // Bitwise/shift builder stored properties (P5-103)
    internal let buildAndFn: LLVMBuildAndFn?
    internal let buildOrFn: LLVMBuildOrFn?
    internal let buildXorFn: LLVMBuildXorFn?
    internal let buildShlFn: LLVMBuildShlFn?
    internal let buildAShrFn: LLVMBuildAShrFn?
    internal let buildLShrFn: LLVMBuildLShrFn?
    internal let buildNotFn: LLVMBuildNotFn?
    internal let buildICmpFn: LLVMBuildICmpFn
    internal let buildZExtFn: LLVMBuildZExtFn?
    internal let buildAllocaFn: LLVMBuildAllocaFn?
    internal let buildStoreFn: LLVMBuildStoreFn?
    internal let buildLoad2Fn: LLVMBuildLoad2Fn?
    internal let buildLoadFn: LLVMBuildLoadFn?
    internal let buildSelectFn: LLVMBuildSelectFn?
    internal let buildGlobalStringPtrFn: LLVMBuildGlobalStringPtrFn?
    internal let buildPtrToIntFn: LLVMBuildPtrToIntFn?
    internal let buildCall2Fn: LLVMBuildCall2Fn?
    internal let buildCallFn: LLVMBuildCallFn?
    internal let constIntFn: LLVMConstIntFn
    internal let constPointerNullFn: LLVMConstPointerNullFn?
    internal let getDefaultTargetTripleFn: LLVMGetDefaultTargetTripleFn
    internal let getTargetFromTripleFn: LLVMGetTargetFromTripleFn
    internal let createTargetMachineFn: LLVMCreateTargetMachineFn
    internal let disposeTargetMachineFn: LLVMDisposeTargetMachineFn
    internal let emitToFileFn: LLVMTargetMachineEmitToFileFn
    internal let createTargetDataLayoutFn: LLVMCreateTargetDataLayoutFn
    internal let copyStringRepOfTargetDataFn: LLVMCopyStringRepOfTargetDataFn
    internal let disposeTargetDataFn: LLVMDisposeTargetDataFn
    internal let initializeX86TargetInfoFn: LLVMInitializeX86TargetInfoFn?
    internal let initializeX86TargetFn: LLVMInitializeX86TargetFn?
    internal let initializeX86TargetMCFn: LLVMInitializeX86TargetMCFn?
    internal let initializeX86AsmPrinterFn: LLVMInitializeX86AsmPrinterFn?
    internal let initializeAArch64TargetInfoFn: LLVMInitializeAArch64TargetInfoFn?
    internal let initializeAArch64TargetFn: LLVMInitializeAArch64TargetFn?
    internal let initializeAArch64TargetMCFn: LLVMInitializeAArch64TargetMCFn?
    internal let initializeAArch64AsmPrinterFn: LLVMInitializeAArch64AsmPrinterFn?
    internal let createDIBuilderFn: LLVMCreateDIBuilderFn?
    internal let disposeDIBuilderFn: LLVMDisposeDIBuilderFn?
    internal let diBuilderFinalizeFn: LLVMDIBuilderFinalizeFn?
    internal let diBuilderCreateFileFn: LLVMDIBuilderCreateFileFn?
    internal let diBuilderCreateCompileUnitFn: LLVMDIBuilderCreateCompileUnitFn?
    internal let diBuilderCreateSubroutineTypeFn: LLVMDIBuilderCreateSubroutineTypeFn?
    internal let diBuilderCreateFunctionFn: LLVMDIBuilderCreateFunctionFn?
    internal let setSubprogramFn: LLVMSetSubprogramFn?
    internal let addModuleFlagFn: LLVMAddModuleFlagFn?
    internal let valueAsMetadataFn: LLVMValueAsMetadataFn?
    internal let int32TypeFn: LLVMInt32TypeInContextFn?
    internal let setCurrentDebugLocation2Fn: LLVMSetCurrentDebugLocation2Fn?
    internal let diBuilderCreateDebugLocationFn: LLVMDIBuilderCreateDebugLocationFn?
    internal let diBuilderCreateBasicTypeFn: LLVMDIBuilderCreateBasicTypeFn?
    internal let diBuilderCreateParameterVariableFn: LLVMDIBuilderCreateParameterVariableFn?
    internal let diBuilderCreateAutoVariableFn: LLVMDIBuilderCreateAutoVariableFn?
    internal let diBuilderInsertDeclareAtEndFn: LLVMDIBuilderInsertDeclareAtEndFn?
    internal let diBuilderCreateExpressionFn: LLVMDIBuilderCreateExpressionFn?

    internal init(
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
}
