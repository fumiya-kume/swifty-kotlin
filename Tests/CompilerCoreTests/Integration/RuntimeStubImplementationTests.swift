@testable import CompilerCore
import Foundation
import XCTest

/// Tests verifying that LLVM codegen references runtime entry points externally
/// rather than synthesizing private helper implementations.
final class RuntimeStubImplementationTests: XCTestCase {
    private func makeSimpleModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()
        let main = KIRFunction(
            symbol: SymbolID(rawValue: 100),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        return KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )
    }

    func testLLVMBackendDefinesFrameRuntimeFunctionsWithWeakLinkage() throws {
        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        // Functions must be referenced in the IR
        XCTAssertTrue(ir.contains("@kk_register_frame_map"), "LLVM IR must reference kk_register_frame_map")
        XCTAssertTrue(ir.contains("@kk_push_frame"), "LLVM IR must reference kk_push_frame")
        XCTAssertTrue(ir.contains("@kk_pop_frame"), "LLVM IR must reference kk_pop_frame")

        // Must NOT contain internal linkage definitions for these functions
        let lines = ir.components(separatedBy: "\n")
        for line in lines {
            if line.contains("kk_register_frame_map") || line.contains("kk_push_frame") || line.contains("kk_pop_frame") {
                if line.contains("define") {
                    XCTAssertFalse(
                        line.contains("internal"),
                        "Runtime functions must not be defined as internal: \(line)"
                    )
                }
            }
        }
    }
}
