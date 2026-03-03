import Foundation

extension LLVMBackend {
    func cRuntimeExternDeclarations() -> [String] {
        Self.fixedExternDeclarations
    }

    func cRuntimePreamble() -> [String] {
        Self.fixedRuntimePreamble
    }
}
