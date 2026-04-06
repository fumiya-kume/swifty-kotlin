@testable import CompilerCore
import Foundation

func makeCompilationContext(
    inputs: [String],
    moduleName: String = "TestModule",
    emit: EmitMode = .kirDump,
    outputPath: String? = nil,
    searchPaths: [String] = [],
    irFlags: [String] = [],
    frontendFlags: [String] = []
) -> CompilationContext {
    let destination = outputPath ?? FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .path
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: destination,
        emit: emit,
        searchPaths: searchPaths,
        target: TargetTriple.hostDefault(),
        frontendFlags: frontendFlags,
        irFlags: irFlags
    )
    return CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
}

func runFrontend(_ ctx: CompilationContext) throws {
    try LoadSourcesPhase().run(ctx)
    try LexPhase().run(ctx)
    try ParsePhase().run(ctx)
    try BuildASTPhase().run(ctx)
}
