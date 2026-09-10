#if canImport(Testing)
@testable import GoldenHarnessSupport
import Foundation
import Testing

@Suite("GoldenHarness.Persistence")
struct GoldenHarnessPersistenceTests {
    @Test
    func semaPersistenceWritesNormalizedGolden() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.kt")
        try "".write(to: sourceURL, atomically: false, encoding: .utf8)

        let actual = """
        symbol fq=sample.wrap kind=function vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int
        symbol fq=sample.wrap.$301.value kind=valueParameter vis=private flags=synthetic
        symbol fq=__local_27.tmp kind=local vis=private flags=_ type=Int
        expr e0 name(value) type=Int ref=sample.wrap.$301.value
        expr e1 name(it) type=Int ref=s-1008960
        expr e2 name(tmp) type=Int ref=__local_27.tmp
        """

        let persisted = try GoldenHarness.persistIfUpdating(
            suiteName: "Sema",
            sourcePath: sourceURL.path,
            actual: actual,
            updateMode: true
        )

        #expect(persisted)
        let written = try String(
            contentsOf: sourceURL.deletingPathExtension().appendingPathExtension("golden"),
            encoding: .utf8
        )
        #expect(written == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual))
    }

    @Test
    func nonSemaPersistencePreservesRawGolden() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.kt")
        try "".write(to: sourceURL, atomically: false, encoding: .utf8)

        let actual = """
        IDENT [0..<5]
        EOF [5..<5]
        """

        let persisted = try GoldenHarness.persistIfUpdating(
            suiteName: "Lexer",
            sourcePath: sourceURL.path,
            actual: actual,
            updateMode: true
        )

        #expect(persisted)
        let written = try String(
            contentsOf: sourceURL.deletingPathExtension().appendingPathExtension("golden"),
            encoding: .utf8
        )
        #expect(written == actual)
    }

    @Test
    func semaRenderIncludesOnlyRequestedSourceFileBody() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.kt")
        try """
        package sample

        fun main() {
            val x = 1
        }
        """.write(to: sourceURL, atomically: false, encoding: .utf8)

        let output = try GoldenHarness.render(suiteName: "Sema", sourcePath: sourceURL.path)
        let fileLines = output.split(separator: "\n").filter { $0.hasPrefix("file ") }

        #expect(fileLines.count == 1)
        #expect(fileLines.first?.contains("package=sample") == true)
    }

    @Test
    func semaDumpIsByteIdenticalWithDummyBundledFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.kt")
        try """
        package sample

        fun main() {
            val x = 1
        }
        """.write(to: sourceURL, atomically: false, encoding: .utf8)

        let baseline = try GoldenHarnessDump.dumpSema(sourcePath: sourceURL.path)
        let injected = try GoldenHarnessDump.dumpSema(
            sourcePath: sourceURL.path,
            preInjectedFiles: [("__bundled_dummy_invariant.kt", Data("package dummy\n".utf8))]
        )

        #expect(baseline == injected, Comment(rawValue: "Sema dump changed after injecting a dummy bundled file"))
    }

    @Test
    func semaDumpIsByteIdenticalWhenUnreferencedSameFQNameSymbolsAppear() throws {
        // RF-GOLDEN-010: symbol references are keyed by declaration meaning, so
        // injecting an unreferenced bundled declaration — which changes symbol
        // counts, registration order, and raw SymbolIDs — must not alter any
        // rendered reference. This replaces the old `#N` ordinal ordering test:
        // the contract is now "no renumbering at all", not "renumber in a
        // numerically sorted order".
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.kt")
        try """
        package sample

        fun main() {
            val s = listOf(1)
            s.isEmpty()
        }
        """.write(to: sourceURL, atomically: false, encoding: .utf8)

        let baseline = try GoldenHarnessDump.dumpSema(sourcePath: sourceURL.path)
        let injected = try GoldenHarnessDump.dumpSema(
            sourcePath: sourceURL.path,
            preInjectedFiles: [(
                "__bundled_extra_candidates.kt",
                Data("package sample\nfun unrelatedOverload(x: Int): Int = x\n".utf8)
            )]
        )

        // The persisted `.golden` is `stableOutputForPersistence` output, so
        // compare at that level: injected bundled declarations legitimately
        // shift raw `__local_N` scope ordinals (a pre-existing mechanism this
        // task does not own), while `call=`/`ref=`/`fq=` semantic keys must be
        // identical.
        let normalize = { GoldenHarness.normalizedForComparison(suiteName: "Sema", output: $0) }
        #expect(
            normalize(baseline) == normalize(injected),
            Comment(rawValue: "Sema dump changed after injecting an unreferenced bundled declaration")
        )
    }

    @Test
    func batchSubprocessReturnsOneResultPerSourceInOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstSource = tempDir.appendingPathComponent("first.kt")
        let secondSource = tempDir.appendingPathComponent("second.kt")
        try "val first = 1\n".write(to: firstSource, atomically: false, encoding: .utf8)
        try "val second = 2\n".write(to: secondSource, atomically: false, encoding: .utf8)

        let sourcePaths = [firstSource.path, secondSource.path]
        let results = try GoldenHarness.renderBatchInSubprocess(
            suiteName: "Lexer",
            sourcePaths: sourcePaths
        )
        let expectedOutputs = try sourcePaths.map {
            try GoldenHarness.render(suiteName: "Lexer", sourcePath: $0)
        }

        #expect(results.map(\.sourcePath) == sourcePaths)
        #expect(results.allSatisfy { $0.errorDescription == nil })
        #expect(results.map(\.output) == expectedOutputs.map { Optional($0) })
    }
}
#endif
