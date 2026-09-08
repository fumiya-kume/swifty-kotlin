import Foundation

/// A minimal Language Server Protocol server for Kotlin built on the KSwiftK
/// compiler frontend.
///
/// Supported requests: `initialize`, `shutdown`, `textDocument/hover`,
/// `textDocument/definition`, `textDocument/documentSymbol`,
/// `textDocument/codeAction`.
/// Supported notifications: `initialized`, `exit`, and the
/// `textDocument/did{Open,Change,Save,Close}` synchronization family.
/// Diagnostics are pushed via `textDocument/publishDiagnostics` whenever a
/// document is opened or changed.
public final class Server: @unchecked Sendable {
    private static let defaultDebounceInterval: DispatchTimeInterval = .milliseconds(150)

    private let connection: JSONRPCConnection
    private let store = DocumentStore()
    private let analyzer: Analyzer
    private let scheduler: any LSPDebounceScheduler
    private let debounceInterval: DispatchTimeInterval
    private let stateLock = NSLock()
    private let publishLock = NSLock()
    private var generations: [String: UInt64] = [:]
    private var pendingChanges: [String: any LSPScheduledTask] = [:]
    private var closedURIs: Set<String> = []
    private var shuttingDown = false

    public convenience init(
        connection: JSONRPCConnection,
        analyzer: Analyzer = Analyzer()
    ) {
        self.init(
            connection: connection,
            analyzer: analyzer,
            scheduler: DispatchLSPDebounceScheduler(),
            debounceInterval: Self.defaultDebounceInterval
        )
    }

    init(
        connection: JSONRPCConnection,
        analyzer: Analyzer = Analyzer(),
        scheduler: any LSPDebounceScheduler,
        debounceInterval: DispatchTimeInterval = Server.defaultDebounceInterval
    ) {
        self.connection = connection
        self.analyzer = analyzer
        self.scheduler = scheduler
        self.debounceInterval = debounceInterval
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
        case "textDocument/codeAction":
            handleCodeAction(id: id, params)
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
            documentSymbolProvider: true,
            codeActionProvider: true
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
        let generation = beginGeneration(for: doc.uri)
        analyzeAndPublish(
            uri: doc.uri,
            text: doc.text,
            version: doc.version,
            generation: generation
        )
    }

    private func handleDidChange(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidChangeTextDocumentParams.self, from: params) else {
            return
        }
        guard let text = parsed.contentChanges.last?.text else { return }
        let uri = parsed.textDocument.uri
        let version = parsed.textDocument.version
        store.update(uri: uri, version: parsed.textDocument.version, text: text)
        let generation = beginGeneration(for: uri)
        let task = scheduler.schedule(after: debounceInterval) { [weak self] in
            self?.runDebouncedChange(
                uri: uri,
                text: text,
                version: version,
                generation: generation
            )
        }

        stateLock.lock()
        if isCurrentLocked(uri: uri, generation: generation) {
            pendingChanges[uri] = task
        } else {
            task.cancel()
        }
        stateLock.unlock()
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
        let generation = beginGeneration(for: uri)
        analyzeAndPublish(
            uri: uri,
            text: text,
            version: store.version(for: uri),
            generation: generation
        )
    }

    private func handleDidClose(_ params: Any?) {
        guard let params, let parsed = JSONCoding.decode(DidCloseTextDocumentParams.self, from: params) else {
            return
        }
        let uri = parsed.textDocument.uri
        _ = beginGeneration(for: uri, closed: true)
        store.close(uri: uri)

        publishLock.lock()
        sendPublishDiagnostics(uri: uri, version: nil, diagnostics: [])
        publishLock.unlock()
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

    private func handleCodeAction(id: Any?, _ params: Any?) {
        guard
            let params,
            let parsed = JSONCoding.decode(CodeActionParams.self, from: params),
            store.document(for: parsed.textDocument.uri) != nil,
            let analysis = ensureAnalysis(uri: parsed.textDocument.uri)
        else {
            respond(id: id, result: [Any]())
            return
        }
        let actions = CodeActionFeature.codeActions(for: analysis, params: parsed)
        respond(id: id, result: JSONCoding.toObject(actions) ?? [Any]())
    }

    // MARK: - Analysis helpers

    private func ensureAnalysis(uri: String) -> Analyzer.Analysis? {
        stateLock.lock()
        let generation = generations[uri, default: 0]
        stateLock.unlock()

        publishLock.lock()
        stateLock.lock()
        guard isCurrentLocked(uri: uri, generation: generation) else {
            stateLock.unlock()
            publishLock.unlock()
            return nil
        }
        if let cached = analyzer.analysis(for: uri) {
            stateLock.unlock()
            publishLock.unlock()
            return cached
        }
        stateLock.unlock()
        publishLock.unlock()

        guard let text = store.text(for: uri) else { return nil }

        let analysis = analyzer.analyzeWithoutCaching(uri: uri, text: text)
        guard cacheIfCurrent(analysis, uri: uri, generation: generation) else { return nil }
        return analysis
    }

    private func beginGeneration(for uri: String, closed: Bool = false) -> UInt64 {
        publishLock.lock()

        stateLock.lock()
        pendingChanges.removeValue(forKey: uri)?.cancel()
        let generation = generations[uri, default: 0] &+ 1
        generations[uri] = generation
        if closed {
            closedURIs.insert(uri)
        } else {
            closedURIs.remove(uri)
        }
        stateLock.unlock()

        // Cache invalidation is serialized with generation commits, but does
        // not hold stateLock or wait for the frontend analysis lock.
        analyzer.remove(uri: uri)
        publishLock.unlock()
        return generation
    }

    private func runDebouncedChange(
        uri: String,
        text: String,
        version: Int?,
        generation: UInt64
    ) {
        stateLock.lock()
        guard isCurrentLocked(uri: uri, generation: generation) else {
            stateLock.unlock()
            return
        }
        pendingChanges.removeValue(forKey: uri)
        stateLock.unlock()

        let analysis = analyzer.analyzeWithoutCaching(uri: uri, text: text)
        publishIfCurrent(
            analysis,
            uri: uri,
            version: version,
            generation: generation
        )
    }

    private func analyzeAndPublish(
        uri: String,
        text: String,
        version: Int?,
        generation: UInt64
    ) {
        let analysis = analyzer.analyzeWithoutCaching(uri: uri, text: text)
        publishIfCurrent(
            analysis,
            uri: uri,
            version: version,
            generation: generation
        )
    }

    private func publishIfCurrent(
        _ analysis: Analyzer.Analysis,
        uri: String,
        version: Int?,
        generation: UInt64
    ) {
        let diagnostics = DiagnosticsFeature.lspDiagnostics(for: analysis)

        publishLock.lock()
        defer { publishLock.unlock() }

        stateLock.lock()
        guard isCurrentLocked(uri: uri, generation: generation) else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        // Generation validation, cache commit, and publication are ordered
        // against beginGeneration without keeping stateLock across either
        // the cache operation or the transport write.
        analyzer.cache(analysis)
        sendPublishDiagnostics(uri: uri, version: version, diagnostics: diagnostics)
    }

    private func cacheIfCurrent(
        _ analysis: Analyzer.Analysis,
        uri: String,
        generation: UInt64
    ) -> Bool {
        publishLock.lock()
        defer { publishLock.unlock() }

        stateLock.lock()
        guard isCurrentLocked(uri: uri, generation: generation) else {
            stateLock.unlock()
            return false
        }
        stateLock.unlock()

        analyzer.cache(analysis)
        return true
    }

    private func isCurrentLocked(uri: String, generation: UInt64) -> Bool {
        generations[uri] == generation && !closedURIs.contains(uri)
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
