import Foundation

extension LLVMBackend {
    func cRuntimeExternDeclarations() -> [String] {
        CodegenRuntimeSupport.fixedExternDeclarations
    }

    func cRuntimePreamble() -> [String] {
        CodegenRuntimeSupport.fixedRuntimePreamble
    }
}
