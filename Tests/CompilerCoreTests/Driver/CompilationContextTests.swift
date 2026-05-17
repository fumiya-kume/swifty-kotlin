@testable import CompilerCore
import XCTest

final class CompilationContextTests: XCTestCase {
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
        XCTAssertNil(ctx.incrementalCache)
        XCTAssertNil(ctx.incrementalRecompileSet)
        XCTAssertFalse(ctx.incrementalOutputRestored)
        XCTAssertNil(ctx.phaseTimer)
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

    func testMarkIncrementalOutputRestored() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertFalse(ctx.incrementalOutputRestored)
        ctx.markIncrementalOutputRestored()
        XCTAssertTrue(ctx.incrementalOutputRestored)
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

    // MARK: - phaseTimer

    func testPhaseTimerCanBeSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        XCTAssertNil(ctx.phaseTimer)
        ctx.phaseTimer = PhaseTimer()
        XCTAssertNotNil(ctx.phaseTimer)
    }
}
