import Foundation
import XCTest
@testable import CompilerCore

func makeRange(file: FileID = FileID(rawValue: 0), start: Int = 0, end: Int = 1) -> SourceRange {
    SourceRange(
        start: SourceLocation(file: file, offset: start),
        end: SourceLocation(file: file, offset: end)
    )
}

func makeToken(
    kind: TokenKind,
    file: FileID = FileID(rawValue: 0),
    start: Int = 0,
    end: Int = 1,
    leadingTrivia: [TriviaPiece] = [],
    trailingTrivia: [TriviaPiece] = []
) -> Token {
    Token(
        kind: kind,
        range: makeRange(file: file, start: start, end: end),
        leadingTrivia: leadingTrivia,
        trailingTrivia: trailingTrivia
    )
}

func withTemporaryFile(
    contents: String,
    fileExtension: String = "kt",
    body: (String) throws -> Void
) throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: fileURL)
    }
    try body(fileURL.path)
}

func withTemporaryFiles(
    contents: [String],
    fileExtension: String = "kt",
    body: ([String]) throws -> Void
) throws {
    var urls: [URL] = []
    for source in contents {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        urls.append(fileURL)
    }
    defer {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
    try body(urls.map(\.path))
}

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
    searchPaths: [String] = []
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
        target: defaultTargetTriple()
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
    try SemaPassesPhase().run(ctx)
}

func runToKIR(_ ctx: CompilationContext) throws {
    try runSema(ctx)
    try BuildKIRPhase().run(ctx)
}

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    XCTAssertTrue(found, "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", file: file, line: line)
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    XCTAssertFalse(found, "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", file: file, line: line)
}

func assertDiagnosticCount(
    _ code: String,
    expected: Int,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let count = ctx.diagnostics.diagnostics.filter { $0.code == code }.count
    XCTAssertEqual(count, expected, "Expected \(expected) diagnostic(s) with code \(code), got \(count). All diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))", file: file, line: line)
}

// MARK: - Pipeline Helpers

func runToLowering(_ ctx: CompilationContext) throws {
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
}

// MARK: - KIR Helpers

/// Type token symbols use this negative offset to avoid collision with real symbol IDs.
let typeTokenSymbolOffset: Int = -20_000

/// Coroutine state machine dispatch labels start at this offset.
let coroutineDispatchLabelBase: Int32 = 1000

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> KIRFunction {
    let function = module.arena.declarations.compactMap { decl -> KIRFunction? in
        guard case .function(let function) = decl else { return nil }
        return interner.resolve(function.name) == name ? function : nil
    }.first
    return try XCTUnwrap(function, "KIR function '\(name)' not found in module", file: file, line: line)
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [KIRInstruction] {
    let function = try findKIRFunction(named: name, in: module, interner: interner, file: file, line: line)
    return function.body
}

func extractCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    body.compactMap { instruction -> String? in
        guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
        return interner.resolve(callee)
    }
}

func extractThrowFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String: [Bool]] {
    body.reduce(into: [:]) { partial, instruction in
        guard case .call(_, let callee, _, _, let canThrow, _, _) = instruction else { return }
        partial[interner.resolve(callee), default: []].append(canThrow)
    }
}

// MARK: - AST Helpers

func firstExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID) else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

// MARK: - Source Context Helpers

func makeContextFromSource(_ source: String) throws -> CompilationContext {
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(inputs: [fakePath])
    _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    return ctx
}

func makeContextFromSources(_ sources: [String]) throws -> CompilationContext {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fakePaths = sources.enumerated().map { index, _ in
        tempDir.appendingPathComponent("input\(index).kt").path
    }
    let ctx = makeCompilationContext(inputs: fakePaths)
    for (path, source) in zip(fakePaths, sources) {
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    }
    return ctx
}

// MARK: - LLVM Helpers

func llvmCapiBindingsAvailable() -> Bool {
    guard let bindings = LLVMCAPIBindings.load() else { return false }
    return bindings.smokeTestContextLifecycle()
}
