@testable import CompilerCore
import Foundation

func makeSemaModule() -> (ctx: SemaModule, symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let diagnostics = DiagnosticEngine()
    let ctx = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )
    return (ctx, symbols, types, StringInterner())
}

func defaultTargetTriple() -> TargetTriple {
    TargetTriple.hostDefault()
}

func makeCompilationContext(
    inputs: [String],
    moduleName: String = "TestModule",
    emit: EmitMode = .kirDump,
    outputPath: String? = nil,
    searchPaths: [String] = [],
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
        target: defaultTargetTriple(),
        frontendFlags: frontendFlags
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

func runSema(_ ctx: CompilationContext) throws {
    try runFrontend(ctx)
    try SemaPhase().run(ctx)
}

func runToKIR(_ ctx: CompilationContext) throws {
    try runSema(ctx)
    try BuildKIRPhase().run(ctx)
}

func runToLowering(_ ctx: CompilationContext) throws {
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
}

func makeContextFromSource(_ source: String) -> CompilationContext {
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(inputs: [fakePath])
    _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    return ctx
}

func makeContextFromSources(_ sources: [String]) -> CompilationContext {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fakePaths = sources.indices.map { index in
        tempDir.appendingPathComponent("input\(index).kt").path
    }
    let ctx = makeCompilationContext(inputs: fakePaths)
    for (path, source) in zip(fakePaths, sources) {
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    }
    return ctx
}
