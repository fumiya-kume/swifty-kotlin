import Foundation
import XCTest
@testable import CompilerCore

final class FrontendPhasesTests: XCTestCase {

    // MARK: - LoadSourcesPhase

    func testLoadSourcesWithNoInputsEmitsDiagnosticAndThrows() {
        let ctx = makeCompilationContext(inputs: [])
        XCTAssertThrowsError(try LoadSourcesPhase().run(ctx), "LoadSourcesPhase should throw when no inputs")
        assertHasDiagnostic("KSWIFTK-SOURCE-0001", in: ctx)
    }

    func testLoadSourcesWithMissingFileEmitsDiagnosticAndThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let ctx = makeCompilationContext(inputs: [missingPath])
        XCTAssertThrowsError(try LoadSourcesPhase().run(ctx), "LoadSourcesPhase should throw for missing file")
        assertHasDiagnostic("KSWIFTK-SOURCE-0002", in: ctx)
    }

    func testLoadSourcesWithValidFileSucceeds() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            XCTAssertNoThrow(try LoadSourcesPhase().run(ctx))
            XCTAssertFalse(ctx.diagnostics.hasError, "No errors expected for valid input file")
            XCTAssertFalse(ctx.sourceManager.fileIDs().isEmpty, "Source manager should have loaded the file")
        }
    }

    func testLoadSourcesSkipsDuplicatePaths() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path, path])
            XCTAssertNoThrow(try LoadSourcesPhase().run(ctx))
            // File should be loaded only once
            XCTAssertEqual(ctx.sourceManager.fileIDs().count, 1, "Duplicate paths should be loaded only once")
        }
    }

    // MARK: - LexPhase

    func testLexPhasePopulatesTokens() throws {
        let source = "fun main() { println(42) }"
        let ctx = makeContextFromSource(source)
        XCTAssertNoThrow(try LexPhase().run(ctx))
        XCTAssertFalse(ctx.tokens.isEmpty, "LexPhase should populate ctx.tokens")
    }

    func testLexPhasePopulatesFileIRs() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        XCTAssertNoThrow(try LexPhase().run(ctx))
        XCTAssertFalse(ctx.fileIRs.isEmpty, "LexPhase should populate fileIRs")
        let fileID = try XCTUnwrap(ctx.fileIRs.keys.first)
        let fileIR = ctx.fileIRs[fileID]
        XCTAssertNotNil(fileIR, "FileIR should exist for lexed file")
        XCTAssertFalse(fileIR?.tokens.isEmpty ?? true, "FileIR should have tokens")
    }

    func testLexPhaseProducesEOFTokenLast() throws {
        let source = "val x = 1"
        let ctx = makeContextFromSource(source)
        XCTAssertNoThrow(try LexPhase().run(ctx))
        XCTAssertFalse(ctx.tokens.isEmpty)
        let fileTokens = ctx.tokensByFile.first?.1
        XCTAssertEqual(fileTokens?.last?.kind, .eof, "Last token in file should be EOF")
    }

    // MARK: - ParsePhase

    func testParsePhasePopulatesSyntaxTrees() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        XCTAssertNoThrow(try ParsePhase().run(ctx))
        XCTAssertFalse(ctx.syntaxTrees.isEmpty, "ParsePhase should populate syntaxTrees")
    }

    func testParsePhasePopulatesFileIRSyntaxArena() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        XCTAssertNoThrow(try ParsePhase().run(ctx))
        for (_, fileIR) in ctx.fileIRs {
            XCTAssertNotNil(fileIR.syntaxArena, "FileIR should have a SyntaxArena after parsing")
        }
    }

    func testParsePhaseHandlesValidDeclarations() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        XCTAssertNoThrow(try ParsePhase().run(ctx))
        XCTAssertFalse(ctx.diagnostics.hasError, "Valid Kotlin source should parse without errors")
    }

    // MARK: - BuildASTPhase

    func testBuildASTProducesASTModule() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        XCTAssertNoThrow(try BuildASTPhase().run(ctx))
        XCTAssertNotNil(ctx.ast, "BuildASTPhase should produce an ASTModule in ctx.ast")
    }

    func testBuildASTPopulatesTopLevelDecls() throws {
        let source = """
        fun foo() {}
        fun bar() {}
        """
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        let ast = try XCTUnwrap(ctx.ast)
        let totalDecls = ast.sortedFiles.reduce(0) { $0 + $1.topLevelDecls.count }
        XCTAssertGreaterThanOrEqual(totalDecls, 2, "Should have at least 2 top-level declarations")
    }

    func testBuildASTHandlesScriptMode() throws {
        let source = "val x = 42"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        // Script mode may produce diagnostics but should not crash
        XCTAssertNoThrow(try BuildASTPhase().run(ctx))
        XCTAssertNotNil(ctx.ast, "BuildASTPhase should produce an ASTModule even for script-mode source")
    }

    // MARK: - Full frontend pipeline

    func testFullFrontendPipelineSucceeds() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main() {
            val result = add(1, 2)
        }
        """
        let ctx = makeContextFromSource(source)
        XCTAssertNoThrow(try runFrontend(ctx))
        XCTAssertNotNil(ctx.ast, "Full frontend pipeline should produce an ASTModule")
        XCTAssertFalse(ctx.diagnostics.hasError, "Valid Kotlin source should not produce errors")
    }
}
