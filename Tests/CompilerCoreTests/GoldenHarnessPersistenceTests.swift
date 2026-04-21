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
        symbol s11 kind=function fq=sample.wrap vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int suspend=0 defaults=[0] vararg=[0]
        symbol s21 kind=valueParameter fq=sample.wrap.$301.value vis=private flags=synthetic
        symbol s31 kind=local fq=__local_27.tmp vis=private flags=_ type=Int
        expr e0 name(value) type=Int ref=s21
        expr e1 name(it) type=Int ref=s-1008960
        expr e2 name(tmp) type=Int ref=s31
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
}
#endif
