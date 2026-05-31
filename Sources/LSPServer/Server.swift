import Foundation

/// A minimal Language Server Protocol server for Kotlin built on the KSwiftK
/// compiler frontend.
///
/// Supported requests: `initialize`, `shutdown`, `textDocument/hover`,
/// `textDocument/definition`, `textDocument/documentSymbol`.
/// Supported notifications: `initialized`, `exit`, and the
/// `textDocument/did{Open,Change,Save,Close}` synchronization family.
/// Diagnostics are pushed via `textDocument/publishDiagnostics` whenever a
/// document is opened or changed.
public final class Server {
    private let connection: JSONRPCConnection
    private let store = DocumentStore()
    private let analyzer: Analyzer
    private var shuttingDown = false
    private let log: (String) -> Void

    public init(
        connection: JSONRPCConnection,
        analyzer: Analyzer = Analyzer(),
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.connection = connection
        self.analyzer = analyzer
        self.log = log
    }

    /// Creates a server bound to the process's standard input/output streams.
    public convenience init() {
        self.init(connection: JSONRPCConnection(
            input: StandardInputStream(),
            output: StandardOutputStream()
        ))
    }

    /// Runs the message loop until the stream ends or an `exit` notification is
    /// received. Returns the process exit code.
    @discardableResult
    public func run() -> Int32 {
        while let message = connection.receive() {
            if let exitCode = handle(message) {
                return Int32(exitCode)
            }
        }
        return shuttingDown ? 0 : 1
    }

    /// Handles a single message. Returns a non-nil exit code when the loop
    /// should terminate.
    func handle(_ message: [String: Any]) -> Int? {
        guard let method = message["method"] as? String else {
            return nil // A response to a server-originated request; ignored.
        }
        let id = message["id"]
        let params = message["params"]

        switch method {
        case "initialize":
            handleInitialize(id: id)
        case "initialized":
            break
        case "shutdown":
            shuttingDown = true
            respond(id: id, result: NSNull())
        case "exit":
            return shuttingDown ? 0 : 1
        case "textDocument/didOpen":
            handleDidOpen(params)
        case "textDocument/didChange":
            handleDidChange(params)
        case "textDocument/didSave":
            handleDidSave(params)
        case "textDocument/didClose":
            handleDidClose(params)
        case "textDocument/hover":
            handleHover(id: id, params)
        case "textDocument/definition":
            handleDefinition(id: id, params)
        case "textDocument/documentSymbol":
            handleDocumentSymbol(id: id, params)
        default:
            if id != nil {
                respondError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        }
        return nil
    }

    // MARK: - Lifecycle

    private func handleInitialize(id: Any?) {
        let capabilities = ServerCapabilities(
            textDocumentSync: 1, // full document sync
            hoverProvider: true,
            definitionProvider: true,
            documentSymbolProvider: true
        )
        let result = InitializeResult(
            capabilities: capabilities,
            serverInfo: ServerInfo(name: "kswift-lsp", version: "0.1.0")
        )
        respond(id: id, result: JSONCoding.toObject(result) ?? NSNull())
    }

    // MARK: - Document synchronization

    private func handleDidOpen(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidOpenTextDocumentParams.self, from: params) else {
            return
        }
        let doc = parsed.textDocument
        store.open(uri: doc.uri, languageId: doc.languageId, version: doc.version, text: doc.text)
        analyzeAndPublish(uri: doc.uri, text: doc.text, version: doc.version)
    }

    private func handleDidChange(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidChangeTextDocumentParams.self, from: params) else {
            return
        }
        guard let text = parsed.contentChanges.last?.text else { return }
        let uri = parsed.textDocument.uri
        store.update(uri: uri, version: parsed.textDocument.version, text: text)
        analyzeAndPublish(uri: uri, text: text, version: parsed.textDocument.version)
    }

    private func handleDidSave(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidSaveTextDocumentParams.self, from: params) else {
            return
        }
        let uri = parsed.textDocument.uri
        guard let text = parsed.text ?? store.text(for: uri) else { return }
        if parsed.text != nil {
            store.update(uri: uri, version: store.version(for: uri), text: text)
        }
        analyzeAndPublish(uri: uri, text: text, version: store.version(for: uri))
    }

    private func handleDidClose(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidCloseTextDocumentParams.self, from: params) else {
            return
        }
        let uri = parsed.textDocument.uri
        store.close(uri: uri)
        analyzer.remove(uri: uri)
        sendPublishDiagnostics(uri: uri, version: nil, diagnostics: [])
    }

    // MARK: - Language features

    private func handleHover(id: Any?, _ params: Any?) {
        guard
            let params,
            let parsed = JSONCoding.decode(TextDocumentPositionParams.self, from: params),
            let analysis = ensureAnalysis(uri: parsed.textDocument.uri),
            let hover = HoverFeature.hover(
                for: analysis,
                line: parsed.position.line,
                character: parsed.position.character
            )
        else {
            respond(id: id, result: NSNull())
            return
        }
        respond(id: id, result: JSONCoding.toObject(hover) ?? NSNull())
    }

    private func handleDefinition(id: Any?, _ params: Any?) {
        guard
            let params,
            let parsed = JSONCoding.decode(TextDocumentPositionParams.self, from: params),
            let analysis = ensureAnalysis(uri: parsed.textDocument.uri),
            let location = DefinitionFeature.definition(
                for: analysis,
                line: parsed.position.line,
                character: parsed.position.character
            )
        else {
            respond(id: id, result: NSNull())
            return
        }
        respond(id: id, result: JSONCoding.toObject(location) ?? NSNull())
    }

    private func handleDocumentSymbol(id: Any?, _ params: Any?) {
        guard
            let params,
            let parsed = JSONCoding.decode(DocumentSymbolParams.self, from: params),
            let analysis = ensureAnalysis(uri: parsed.textDocument.uri)
        else {
            respond(id: id, result: [Any]())
            return
        }
        let symbols = DocumentSymbolFeature.documentSymbols(for: analysis)
        respond(id: id, result: JSONCoding.toObject(symbols) ?? [Any]())
    }

    // MARK: - Analysis helpers

    private func ensureAnalysis(uri: String) -> Analyzer.Analysis? {
        if let cached = analyzer.analysis(for: uri) {
            return cached
        }
        if let text = store.text(for: uri) {
            return analyzer.analyze(uri: uri, text: text)
        }
        return nil
    }

    private func analyzeAndPublish(uri: String, text: String, version: Int?) {
        let analysis = analyzer.analyze(uri: uri, text: text)
        let diagnostics = DiagnosticsFeature.lspDiagnostics(for: analysis)
        sendPublishDiagnostics(uri: uri, version: version, diagnostics: diagnostics)
    }

    private func sendPublishDiagnostics(uri: String, version: Int?, diagnostics: [LSPDiagnostic]) {
        let params = PublishDiagnosticsParams(uri: uri, version: version, diagnostics: diagnostics)
        notify(method: "textDocument/publishDiagnostics", params: JSONCoding.toObject(params) ?? [String: Any]())
    }

    // MARK: - Message helpers

    private func respond(id: Any?, result: Any) {
        guard let id else { return }
        connection.send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respondError(id: Any?, code: Int, message: String) {
        guard let id else { return }
        connection.send([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message],
        ])
    }

    private func notify(method: String, params: Any) {
        connection.send(["jsonrpc": "2.0", "method": method, "params": params])
    }
}
