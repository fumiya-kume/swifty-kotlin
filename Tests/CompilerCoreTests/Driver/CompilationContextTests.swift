@testable import CompilerCore
import XCTest

final class CompilationContextTests: XCTestCase {
    // MARK: - FileIR

    func testFileIRDefaultInit() {
        let fileID = FileID(rawValue: 1)
        let ir = FileIR(fileID: fileID)
        XCTAssertEqual(ir.fileID, fileID)
        XCTAssertTrue(ir.tokens.isEmpty)
        XCTAssertNil(ir.syntaxArena)
        XCTAssertNil(ir.astFile)
        XCTAssertNil(ir.astArena)
    }

    func testFileIRWithTokens() {
        let fileID = FileID(rawValue: 2)
        let token = makeToken(kind: .keyword(.fun))
        var ir = FileIR(fileID: fileID, tokens: [token])
        XCTAssertEqual(ir.tokens.count, 1)
        XCTAssertEqual(ir.tokens[0].kind, .keyword(.fun))

        // Mutate tokens
        let token2 = makeToken(kind: .keyword(.val))
        ir.tokens.append(token2)
        XCTAssertEqual(ir.tokens.count, 2)
    }

    func testFileIRWithSyntaxArena() {
        let fileID = FileID(rawValue: 3)
        let arena = SyntaxArena()
        let root = NodeID()
        let ir = FileIR(fileID: fileID, syntaxArena: arena, syntaxRoot: root)
        XCTAssertNotNil(ir.syntaxArena)
        XCTAssertEqual(ir.syntaxRoot, root)
    }

    // MARK: - CompilationContext init

    func testCompilationContextInitStoresProperties() {
        let options = CompilerOptions(
            moduleName: "TestMod",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let interner = StringInterner()
        let ctx = CompilationContext(
            options: options,
            sourceManager: sm,
            diagnostics: diag,
            interner: interner
        )
        XCTAssertEqual(ctx.options.moduleName, "TestMod")
        XCTAssertTrue(ctx.tokens.isEmpty)
        XCTAssertNil(ctx.syntaxTree)
        XCTAssertNil(ctx.ast)
        XCTAssertNil(ctx.sema)
        XCTAssertNil(ctx.kir)
        XCTAssertNil(ctx.generatedObjectPath)
        XCTAssertNil(ctx.generatedLLVMIRPath)
        XCTAssertNil(ctx.runtimeStubObjectPath)
        XCTAssertNil(ctx.incrementalCache)
        XCTAssertNil(ctx.incrementalRecompileSet)
        XCTAssertNil(ctx.phaseTimer)
        XCTAssertTrue(ctx.fileIRs.isEmpty)
    }

    // MARK: - isIncremental

    func testIsIncrementalReturnsFalseByDefault() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertFalse(ctx.isIncremental)
    }

    func testIsIncrementalReturnsTrueWhenCacheSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        ctx.incrementalCache = IncrementalCompilationCache(
            cachePath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        )
        XCTAssertTrue(ctx.isIncremental)
    }

    // MARK: - needsRecompilation

    func testNeedsRecompilationReturnsTrueWhenNoRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertTrue(ctx.needsRecompilation(path: "/a.kt"))
        XCTAssertTrue(ctx.needsRecompilation(path: "/anything.kt"))
    }

    func testNeedsRecompilationReturnsTrueForFileInRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt", "/b.kt"])
        ctx.incrementalRecompileSet = Set(["/a.kt"])
        XCTAssertTrue(ctx.needsRecompilation(path: "/a.kt"))
    }

    func testNeedsRecompilationReturnsFalseForFileNotInRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt", "/b.kt"])
        ctx.incrementalRecompileSet = Set(["/a.kt"])
        XCTAssertFalse(ctx.needsRecompilation(path: "/b.kt"))
    }

    func testNeedsRecompilationEmptyRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        ctx.incrementalRecompileSet = Set()
        XCTAssertFalse(ctx.needsRecompilation(path: "/a.kt"))
    }

    // MARK: - frontendJobs

    func testFrontendJobsDefaultIsOne() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertEqual(ctx.frontendJobs, 1)
    }

    func testFrontendJobsReadsFromOptions() {
        let ctx = makeCompilationContext(
            inputs: ["/a.kt"],
            frontendFlags: ["jobs=4"]
        )
        XCTAssertEqual(ctx.frontendJobs, 4)
    }

    // MARK: - fileIRs

    func testFileIRsCanBePopulated() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        let fileID = FileID(rawValue: 0)
        let ir = FileIR(fileID: fileID)
        ctx.fileIRs[fileID] = ir
        XCTAssertNotNil(ctx.fileIRs[fileID])
        XCTAssertEqual(ctx.fileIRs[fileID]?.fileID, fileID)
    }

    // MARK: - phaseTimer

    func testPhaseTimerCanBeSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertNil(ctx.phaseTimer)
        ctx.phaseTimer = PhaseTimer()
        XCTAssertNotNil(ctx.phaseTimer)
    }
}
