import Foundation

protocol CodegenBackend {
    func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner
    ) throws

    func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner
    ) throws
}

extension LLVMBackend: CodegenBackend {}
