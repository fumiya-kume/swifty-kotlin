@testable import LSPServer
import XCTest

final class ServerFlowTests: XCTestCase {
    func testInitializeShutdownAndDiagnosticsLifecycle() {
        let uri = "file:///tmp/LSPServerFlow.kt"
        let source = "fun main() {\n    val x: Int = 1\n}\n"

        let openParams = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: "kotlin", version: 1, text: source)
        )

        let messages: [[String: Any]] = [
            LSPTestSupport.message(id: 1, method: "initialize", params: [String: Any]()),
            LSPTestSupport.message(method: "initialized", params: [String: Any]()),
            LSPTestSupport.message(method: "textDocument/didOpen", params: JSONCoding.toObject(openParams)!),
            LSPTestSupport.message(id: 2, method: "shutdown"),
            LSPTestSupport.message(method: "exit"),
        ]

        let output = MemoryOutputStream()
        let connection = JSONRPCConnection(input: MemoryInputStream(LSPTestSupport.frame(messages)), output: output)
        let server = Server(connection: connection)

        let exitCode = server.run()
        XCTAssertEqual(exitCode, 0, "shutdown followed by exit should yield exit code 0")

        let sent = LSPTestSupport.decodeMessages(from: output)

        // initialize response carries server capabilities.
        let initializeResponse = sent.first { ($0["id"] as? Int) == 1 }
        XCTAssertNotNil(initializeResponse, "Expected an initialize response")
        if let result = initializeResponse?["result"] as? [String: Any],
           let capabilities = result["capabilities"] as? [String: Any]
        {
            XCTAssertEqual(capabilities["hoverProvider"] as? Bool, true)
            XCTAssertEqual(capabilities["definitionProvider"] as? Bool, true)
            XCTAssertEqual(capabilities["documentSymbolProvider"] as? Bool, true)
        } else {
            XCTFail("initialize result should contain capabilities")
        }

        // A publishDiagnostics notification is emitted for the opened document.
        let publish = sent.first { ($0["method"] as? String) == "textDocument/publishDiagnostics" }
        XCTAssertNotNil(publish, "Expected a publishDiagnostics notification")
        if let params = publish?["params"] as? [String: Any] {
            XCTAssertEqual(params["uri"] as? String, uri)
            XCTAssertNotNil(params["diagnostics"])
        }

        // shutdown response present.
        XCTAssertTrue(sent.contains { ($0["id"] as? Int) == 2 }, "Expected a shutdown response")
    }
}
