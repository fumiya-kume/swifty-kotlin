#if canImport(Testing)
import Foundation
@testable import LSPServer
import Testing

@Suite("LSP.ServerFlow")
struct ServerFlowTests {
    @Test
    func initializeShutdownAndDiagnosticsLifecycle() {
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
        #expect(exitCode == 0, "shutdown followed by exit should yield exit code 0")

        let sent = LSPTestSupport.decodeMessages(from: output)

        // initialize response carries server capabilities.
        let initializeResponse = sent.first { ($0["id"] as? Int) == 1 }
        #expect(initializeResponse != nil, "Expected an initialize response")
        if let result = initializeResponse?["result"] as? [String: Any],
           let capabilities = result["capabilities"] as? [String: Any]
        {
            #expect((capabilities["hoverProvider"] as? Bool) == true)
            #expect((capabilities["definitionProvider"] as? Bool) == true)
            #expect((capabilities["documentSymbolProvider"] as? Bool) == true)
            #expect((capabilities["codeActionProvider"] as? Bool) == true)
        } else {
            Issue.record("initialize result should contain capabilities")
        }

        // A publishDiagnostics notification is emitted for the opened document.
        let publish = sent.first { ($0["method"] as? String) == "textDocument/publishDiagnostics" }
        #expect(publish != nil, "Expected a publishDiagnostics notification")
        if let params = publish?["params"] as? [String: Any] {
            #expect((params["uri"] as? String) == uri)
            #expect(params["diagnostics"] != nil)
        }

        // shutdown response present.
        #expect(sent.contains { ($0["id"] as? Int) == 2 }, "Expected a shutdown response")
    }

    @Test
    func didChangeDebouncePublishesOnlyTheLatestVersion() {
        let uri = "file:///tmp/LSPDebounce.kt"
        let initialSource = "fun main() {}\n"
        let intermediateSource = "fun broken( {\n    val =\n}\n"
        let finalSource = "fun main() {\n    val answer: Int = 42\n}\n"
        let scheduler = ManualLSPDebounceScheduler()
        let eventRecorder = LSPAnalysisEventRecorder()
        let analyzer = Analyzer(analysisEvent: { event in
            eventRecorder.record(event)
        })
        let output = MemoryOutputStream()
        let server = Server(
            connection: JSONRPCConnection(input: MemoryInputStream(Data()), output: output),
            analyzer: analyzer,
            scheduler: scheduler,
            debounceInterval: .milliseconds(150)
        )

        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didOpen",
            params: JSONCoding.toObject(DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(
                    uri: uri,
                    languageId: "kotlin",
                    version: 1,
                    text: initialSource
                )
            ))!
        ))
        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 2),
                contentChanges: [TextDocumentContentChangeEvent(text: intermediateSource)]
            ))!
        ))
        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 3),
                contentChanges: [TextDocumentContentChangeEvent(text: finalSource)]
            ))!
        ))

        let beforeDebounce = LSPTestSupport.decodeMessages(from: output)
        let beforePublish = beforeDebounce.filter {
            ($0["method"] as? String) == "textDocument/publishDiagnostics"
        }
        #expect(beforePublish.count == 1, "didChange must not publish before the debounce fires")

        scheduler.runAll()

        let sent = LSPTestSupport.decodeMessages(from: output)
        let publishes = sent.filter {
            ($0["method"] as? String) == "textDocument/publishDiagnostics"
        }
        #expect(publishes.count == 2, "Only didOpen and the final didChange should publish")
        let changedPublishes = publishes.dropFirst()
        #expect(changedPublishes.allSatisfy {
            guard let params = $0["params"] as? [String: Any] else { return false }
            return (params["version"] as? Int) == 3
        }, "An intermediate didChange version must never be published")
        if let params = changedPublishes.first?["params"] as? [String: Any] {
            #expect((params["diagnostics"] as? [Any])?.isEmpty == true)
        } else {
            Issue.record("Expected diagnostics for the final didChange")
        }
        #expect(eventRecorder.startedTexts == [initialSource, finalSource])
        #expect(!eventRecorder.startedTexts.contains(intermediateSource))
    }

    @Test
    func staleAnalysisCannotCacheOrPublishAfterGenerationAdvances() {
        let uri = "file:///tmp/LSPGeneration.kt"
        let staleSource = "fun broken( {\n    val =\n}\n"
        let latestSource = "fun main() {\n    val answer: Int = 42\n}\n"
        let scheduler = ManualLSPDebounceScheduler()
        let analysisEvent = BlockingLSPAnalysisEvent()
        let analyzer = Analyzer(analysisEvent: { event in
            analysisEvent.observe(event)
        })
        let output = MemoryOutputStream()
        let server = Server(
            connection: JSONRPCConnection(input: MemoryInputStream(Data()), output: output),
            analyzer: analyzer,
            scheduler: scheduler
        )

        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 2),
                contentChanges: [TextDocumentContentChangeEvent(text: staleSource)]
            ))!
        ))
        let oldAnalysis = scheduler.runNextAsync()
        analysisEvent.waitUntilStarted()

        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 3),
                contentChanges: [TextDocumentContentChangeEvent(text: latestSource)]
            ))!
        ))
        #expect(analyzer.analysis(for: uri) == nil)

        analysisEvent.release()
        oldAnalysis.wait()
        analysisEvent.waitUntilCompleted()

        let staleMessages = LSPTestSupport.decodeMessages(from: output).filter {
            ($0["method"] as? String) == "textDocument/publishDiagnostics"
        }
        #expect(staleMessages.isEmpty)
        #expect(analyzer.analysis(for: uri) == nil)

        scheduler.runAll()

        let publishes = LSPTestSupport.decodeMessages(from: output).filter {
            ($0["method"] as? String) == "textDocument/publishDiagnostics"
        }
        #expect(publishes.count == 1)
        if let params = publishes.first?["params"] as? [String: Any] {
            #expect((params["version"] as? Int) == 3)
            #expect((params["diagnostics"] as? [Any])?.isEmpty == true)
        } else {
            Issue.record("Expected the latest diagnostics publication")
        }
        #expect(analysisEvent.analyzedTexts == [staleSource, latestSource])
        #expect(analyzer.analysis(for: uri) != nil)
    }

    @Test
    func didCloseInvalidatesPendingChangeAndStalePublish() {
        let uri = "file:///tmp/LSPDebounceClose.kt"
        let scheduler = ManualLSPDebounceScheduler()
        let output = MemoryOutputStream()
        let server = Server(
            connection: JSONRPCConnection(input: MemoryInputStream(Data()), output: output),
            scheduler: scheduler
        )

        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didOpen",
            params: JSONCoding.toObject(DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(
                    uri: uri,
                    languageId: "kotlin",
                    version: 1,
                    text: "fun main() {}\n"
                )
            ))!
        ))
        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 2),
                contentChanges: [TextDocumentContentChangeEvent(text: "fun broken( {\n    val =\n}\n")]
            ))!
        ))
        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didClose",
            params: JSONCoding.toObject(DidCloseTextDocumentParams(
                textDocument: TextDocumentIdentifier(uri: uri)
            ))!
        ))

        scheduler.runAll()

        let publishes = LSPTestSupport.decodeMessages(from: output).filter {
            ($0["method"] as? String) == "textDocument/publishDiagnostics"
        }
        #expect(publishes.count == 2, "didClose should only add the diagnostics clear")
        if let last = publishes.last,
           let params = last["params"] as? [String: Any]
        {
            #expect((params["uri"] as? String) == uri)
            #expect((params["diagnostics"] as? [Any])?.isEmpty == true)
            #expect(params["version"] == nil || params["version"] is NSNull)
        } else {
            Issue.record("Expected a diagnostics clear notification on didClose")
        }
    }
}
#endif
