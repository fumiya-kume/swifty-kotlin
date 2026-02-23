import Foundation
import XCTest
@testable import CompilerCore

// MARK: - Multi-file compile benchmarks for frontend parallelization (P5-61)

final class FrontendParallelBenchmarkTests: XCTestCase {

    // MARK: - Helpers

    /// Generate N Kotlin source files with varied declarations.
    private func generateSources(count: Int) -> [String] {
        (0..<count).map { i in
            """
            package bench\(i)

            import kotlin.collections.*

            class Widget\(i)(val id: Int, val label: String) {
                fun describe(): String = "Widget(\(i))"
                fun compute(x: Int): Int = x * \(i + 1)
            }

            interface Renderable\(i) {
                fun render(): String
            }

            object Registry\(i) {
                val items: Int = \(i)
            }

            fun helper\(i)(a: Int, b: Int): Int = a + b + \(i)
            fun transform\(i)(s: String): String = s
            """
        }
    }

    /// Run frontend with the given sources and jobs count, returning elapsed time.
    private func runFrontendTimed(
        sources: [String],
        jobs: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (ctx: CompilationContext, elapsed: Double) {
        var paths: [String] = []
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for (index, source) in sources.enumerated() {
            let fileURL = tempDir.appendingPathComponent("input\(index).kt")
            try source.write(to: fileURL, atomically: true, encoding: .utf8)
            paths.append(fileURL.path)
        }

        let flags = ["jobs=\(jobs)"]
        let ctx = makeCompilationContext(inputs: paths, frontendFlags: flags)

        let start = Date()
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        let elapsed = Date().timeIntervalSince(start)

        return (ctx, elapsed)
    }

    // MARK: - Correctness: fileIR population

    func testFileIRPopulatedForAllFiles() throws {
        let sources = generateSources(count: 5)
        let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 1)

        XCTAssertEqual(ctx.fileIRs.count, 5, "Expected 5 per-file IRs")
        for (fileID, ir) in ctx.fileIRs {
            XCTAssertEqual(ir.fileID, fileID)
            XCTAssertFalse(ir.tokens.isEmpty, "Tokens should be populated for file \(fileID.rawValue)")
            XCTAssertNotNil(ir.syntaxArena, "SyntaxArena should be populated for file \(fileID.rawValue)")
            XCTAssertNotNil(ir.astFile, "ASTFile should be populated for file \(fileID.rawValue)")
            XCTAssertNotNil(ir.astArena, "ASTArena should be populated for file \(fileID.rawValue)")
        }
    }

    func testFileIRPopulatedInParallelMode() throws {
        let sources = generateSources(count: 5)
        let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)

        XCTAssertEqual(ctx.fileIRs.count, 5, "Expected 5 per-file IRs in parallel mode")
        for (fileID, ir) in ctx.fileIRs {
            XCTAssertEqual(ir.fileID, fileID)
            XCTAssertFalse(ir.tokens.isEmpty)
            XCTAssertNotNil(ir.syntaxArena)
            XCTAssertNotNil(ir.astFile)
            XCTAssertNotNil(ir.astArena)
        }
    }

    // MARK: - Deterministic output ordering

    func testParallelOutputIsDeterministic() throws {
        let sources = generateSources(count: 20)

        // Run multiple times with jobs=4 and verify identical AST structure.
        var previousDeclNames: [String]?

        for iteration in 0..<3 {
            let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)
            let ast = try XCTUnwrap(ctx.ast, "AST should be non-nil (iteration \(iteration))")

            // Collect all declaration names in file order.
            let declNames: [String] = ast.files.flatMap { file in
                file.topLevelDecls.compactMap { declID -> String? in
                    guard let decl = ast.arena.decl(declID) else { return nil }
                    switch decl {
                    case .classDecl(let c): return ctx.interner.resolve(c.name)
                    case .interfaceDecl(let i): return ctx.interner.resolve(i.name)
                    case .objectDecl(let o): return ctx.interner.resolve(o.name)
                    case .funDecl(let f): return ctx.interner.resolve(f.name)
                    default: return nil
                    }
                }
            }

            if let prev = previousDeclNames {
                XCTAssertEqual(
                    prev, declNames,
                    "Declaration order must be deterministic across parallel runs (iteration \(iteration))"
                )
            }
            previousDeclNames = declNames
        }
    }

    // MARK: - Diagnostic order stability

    func testDiagnosticOrderIsStableAcrossParallelRuns() throws {
        // Intentionally include some files with parse warnings/issues.
        var sources = generateSources(count: 10)
        // Add a file with a trailing comma to trigger a diagnostic.
        sources.append("""
        package diag
        fun broken(a: Int,): Int = a
        """)

        var previousDiagCodes: [String]?

        for iteration in 0..<3 {
            let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)

            let diagCodes = ctx.diagnostics.diagnostics.map(\.code)

            if let prev = previousDiagCodes {
                XCTAssertEqual(
                    prev, diagCodes,
                    "Diagnostic order must be stable across parallel runs (iteration \(iteration))"
                )
            }
            previousDiagCodes = diagCodes
        }
    }

    // MARK: - Benchmarks: 10 / 50 / 100 files

    func testBenchmark10Files() throws {
        let sources = generateSources(count: 10)
        let (seqCtx, seqTime) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, parTime) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try XCTUnwrap(seqCtx.ast)
        let parAST = try XCTUnwrap(parCtx.ast)
        XCTAssertEqual(seqAST.files.count, parAST.files.count, "File count must match")
        XCTAssertEqual(seqAST.declarationCount, parAST.declarationCount, "Declaration count must match")

        let speedup = seqTime / max(parTime, 0.000001)
        print("[Benchmark 10 files] sequential=\(String(format: "%.4f", seqTime))s parallel(4)=\(String(format: "%.4f", parTime))s speedup=\(String(format: "%.2f", speedup))x")
    }

    func testBenchmark50Files() throws {
        let sources = generateSources(count: 50)
        let (seqCtx, seqTime) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, parTime) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try XCTUnwrap(seqCtx.ast)
        let parAST = try XCTUnwrap(parCtx.ast)
        XCTAssertEqual(seqAST.files.count, parAST.files.count)
        XCTAssertEqual(seqAST.declarationCount, parAST.declarationCount)

        let speedup = seqTime / max(parTime, 0.000001)
        print("[Benchmark 50 files] sequential=\(String(format: "%.4f", seqTime))s parallel(4)=\(String(format: "%.4f", parTime))s speedup=\(String(format: "%.2f", speedup))x")
    }

    func testBenchmark100Files() throws {
        let sources = generateSources(count: 100)
        let (seqCtx, seqTime) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, parTime) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try XCTUnwrap(seqCtx.ast)
        let parAST = try XCTUnwrap(parCtx.ast)
        XCTAssertEqual(seqAST.files.count, parAST.files.count)
        XCTAssertEqual(seqAST.declarationCount, parAST.declarationCount)

        let speedup = seqTime / max(parTime, 0.000001)
        print("[Benchmark 100 files] sequential=\(String(format: "%.4f", seqTime))s parallel(4)=\(String(format: "%.4f", parTime))s speedup=\(String(format: "%.2f", speedup))x")
    }

    // MARK: - frontendJobs parsing

    func testFrontendJobsParsing() {
        let opts1 = CompilerOptions(
            moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
            target: defaultTargetTriple(), frontendFlags: ["jobs=4"]
        )
        XCTAssertEqual(opts1.frontendJobs, 4)

        let opts2 = CompilerOptions(
            moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
            target: defaultTargetTriple(), frontendFlags: []
        )
        XCTAssertEqual(opts2.frontendJobs, ProcessInfo.processInfo.activeProcessorCount,
                       "Default should use active processor count")

        let opts3 = CompilerOptions(
            moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
            target: defaultTargetTriple(), frontendFlags: ["jobs=0"]
        )
        XCTAssertEqual(opts3.frontendJobs, ProcessInfo.processInfo.activeProcessorCount,
                       "jobs=0 should fall back to processor count default")

        let opts5 = CompilerOptions(
            moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
            target: defaultTargetTriple(), frontendFlags: ["jobs=1"]
        )
        XCTAssertEqual(opts5.frontendJobs, 1, "jobs=1 should explicitly serialize")

        let opts4 = CompilerOptions(
            moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
            target: defaultTargetTriple(), frontendFlags: ["other-flag", "jobs=8"]
        )
        XCTAssertEqual(opts4.frontendJobs, 8)
    }

    // MARK: - Sequential vs parallel AST equivalence

    func testSequentialAndParallelProduceSameAST() throws {
        let sources = generateSources(count: 15)

        let (seqCtx, _) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, _) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try XCTUnwrap(seqCtx.ast)
        let parAST = try XCTUnwrap(parCtx.ast)

        XCTAssertEqual(seqAST.files.count, parAST.files.count)
        XCTAssertEqual(seqAST.declarationCount, parAST.declarationCount)

        // Verify file order matches.
        for (seqFile, parFile) in zip(seqAST.files, parAST.files) {
            XCTAssertEqual(seqFile.fileID, parFile.fileID, "File order must be deterministic")
            XCTAssertEqual(seqFile.topLevelDecls.count, parFile.topLevelDecls.count,
                           "Declaration count must match for file \(seqFile.fileID.rawValue)")

            // Verify declaration names match in order.
            let seqNames = seqFile.topLevelDecls.compactMap { declID -> String? in
                guard let decl = seqAST.arena.decl(declID) else { return nil }
                switch decl {
                case .classDecl(let c): return seqCtx.interner.resolve(c.name)
                case .interfaceDecl(let i): return seqCtx.interner.resolve(i.name)
                case .objectDecl(let o): return seqCtx.interner.resolve(o.name)
                case .funDecl(let f): return seqCtx.interner.resolve(f.name)
                default: return nil
                }
            }
            let parNames = parFile.topLevelDecls.compactMap { declID -> String? in
                guard let decl = parAST.arena.decl(declID) else { return nil }
                switch decl {
                case .classDecl(let c): return parCtx.interner.resolve(c.name)
                case .interfaceDecl(let i): return parCtx.interner.resolve(i.name)
                case .objectDecl(let o): return parCtx.interner.resolve(o.name)
                case .funDecl(let f): return parCtx.interner.resolve(f.name)
                default: return nil
                }
            }
            XCTAssertEqual(seqNames, parNames,
                           "Declaration names must match between sequential and parallel for file \(seqFile.fileID.rawValue)")
        }
    }
}
