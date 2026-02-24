import Foundation

protocol CodegenBackend {
    func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) throws

    func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) throws
}

extension LLVMBackend: CodegenBackend {}
