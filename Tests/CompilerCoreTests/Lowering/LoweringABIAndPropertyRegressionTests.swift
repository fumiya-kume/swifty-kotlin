@testable import CompilerCore
import Foundation
import XCTest

final class LoweringABIAndPropertyRegressionTests: XCTestCase {
    private func makeContext(
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: emit,
            target: defaultTargetTriple()
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
    }

    @discardableResult
    func runLowering(
        module: KIRModule,
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        sema: SemaModule? = nil,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) throws -> CompilationContext {
        let ctx = makeContext(interner: interner, moduleName: moduleName, emit: emit, diagnostics: diagnostics)
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)
        return ctx
}
}
