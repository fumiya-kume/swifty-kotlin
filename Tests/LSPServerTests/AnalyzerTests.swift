#if canImport(Testing)
@testable import CompilerCore
@testable import LSPServer
import Foundation
import Testing

@Suite("LSP.Analyzer")
struct AnalyzerTests {
    private let uri = "file:///tmp/LSPAnalyzer.kt"

    private func makeEmptyStdlibArtifact() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LSPAnalyzer-\(UUID().uuidString).kklib")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inline-kir", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("metadata.bin"))
        try Data().write(to: root.appendingPathComponent("stdlib.o"))

        let target = TargetTriple.hostDefault()
        let manifest: [String: Any] = [
            "formatVersion": 1,
            "moduleName": "KSwiftKStdlib",
            "libraryKind": "stdlib",
            "stdlibManifestHash": BundledStdlib.manifestHash(),
            "kotlinLanguageVersion": "2.3.10",
            "target": "\(target.arch)-\(target.vendor)-\(target.os)",
            "compilerVersion": "0.1.0",
            "metadata": "metadata.bin",
            "inlineKIRDir": "inline-kir",
            "objects": ["stdlib.o"],
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try manifestData.write(to: root.appendingPathComponent("manifest.json"))
        return root.path
    }

    @Test
    func analyzeValidProgramProducesAST() {
        let source = """
        fun greet(name: String): String {
            return "Hello, " + name
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)

        #expect(analysis.context.ast != nil, "Frontend should build an AST for valid input")
        #expect(analysis.fileID != nil, "The analyzed document should be registered in the source manager")

        let errors = analysis.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Valid program should not produce error diagnostics: \(errors)")
    }

    @Test
    func analyzeReportsDiagnosticsForBrokenProgram() {
        // Unterminated declaration / garbage tokens guarantee parse diagnostics.
        let source = """
        fun broken( {
            val =
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let diagnostics = DiagnosticsFeature.lspDiagnostics(for: analysis)

        #expect(!diagnostics.isEmpty, "Malformed program should produce diagnostics")
        for diagnostic in diagnostics {
            #expect(diagnostic.source == "kswiftk")
            #expect(diagnostic.severity != nil, "Each diagnostic should carry an LSP severity")
            #expect(diagnostic.code != nil, "Each diagnostic should carry a KSWIFTK code")
        }
    }

    @Test
    func removeDropsCachedAnalysis() {
        let analyzer = Analyzer()
        _ = analyzer.analyze(uri: uri, text: "fun main() {}")
        #expect(analyzer.analysis(for: uri) != nil)
        analyzer.remove(uri: uri)
        #expect(analyzer.analysis(for: uri) == nil)
    }

    @Test
    func artifactBackedAnalysisDoesNotInjectBundledStdlibSources() throws {
        let artifactPath = try makeEmptyStdlibArtifact()
        defer { try? FileManager.default.removeItem(atPath: artifactPath) }

        let analysis = Analyzer(stdlibLibraryPath: artifactPath).analyze(
            uri: uri,
            text: "fun main() {}"
        )
        let bundledFileIDs = analysis.context.sourceManager.fileIDs().filter {
            analysis.context.sourceManager.origin(of: $0)?.isBundledStdlib == true
        }

        // An artifact-backed run must keep bundled source files out of Lex.
        #expect(analysis.context.options.stdlibLibraryPath == artifactPath)
        #expect(!analysis.context.options.includeStdlib)
        #expect(bundledFileIDs.isEmpty)
        #expect(analysis.context.sourceManager.fileIDs().count == 1)
    }

    @Test
    func documentURIRoundTrip() {
        let path = "/tmp/some dir/Foo.kt"
        let uri = DocumentURI.uri(fromPath: path)
        #expect(DocumentURI.path(fromURI: uri) == path)
    }
}
#endif
