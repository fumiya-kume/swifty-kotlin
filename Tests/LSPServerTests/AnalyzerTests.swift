@testable import CompilerCore
@testable import LSPServer
import XCTest

final class AnalyzerTests: XCTestCase {
    private let uri = "file:///tmp/LSPAnalyzer.kt"

    func testAnalyzeValidProgramProducesAST() {
        let source = """
        fun greet(name: String): String {
            return "Hello, " + name
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)

        XCTAssertNotNil(analysis.context.ast, "Frontend should build an AST for valid input")
        XCTAssertNotNil(analysis.fileID, "The analyzed document should be registered in the source manager")

        let errors = analysis.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "Valid program should not produce error diagnostics: \(errors)")
    }

    func testAnalyzeReportsDiagnosticsForBrokenProgram() {
        // Unterminated declaration / garbage tokens guarantee parse diagnostics.
        let source = """
        fun broken( {
            val =
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let diagnostics = DiagnosticsFeature.lspDiagnostics(for: analysis)

        XCTAssertFalse(diagnostics.isEmpty, "Malformed program should produce diagnostics")
        for diagnostic in diagnostics {
            XCTAssertEqual(diagnostic.source, "kswiftk")
            XCTAssertNotNil(diagnostic.severity, "Each diagnostic should carry an LSP severity")
            XCTAssertNotNil(diagnostic.code, "Each diagnostic should carry a KSWIFTK code")
        }
    }

    func testRemoveDropsCachedAnalysis() {
        let analyzer = Analyzer()
        _ = analyzer.analyze(uri: uri, text: "fun main() {}")
        XCTAssertNotNil(analyzer.analysis(for: uri))
        analyzer.remove(uri: uri)
        XCTAssertNil(analyzer.analysis(for: uri))
    }

    func testDocumentURIRoundTrip() {
        let path = "/tmp/some dir/Foo.kt"
        let uri = DocumentURI.uri(fromPath: path)
        XCTAssertEqual(DocumentURI.path(fromURI: uri), path)
    }
}
