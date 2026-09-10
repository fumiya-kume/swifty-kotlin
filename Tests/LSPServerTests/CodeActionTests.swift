#if canImport(Testing)
import CompilerCore
import Foundation
@testable import LSPServer
import Testing

@Suite("LSP.CodeAction")
struct CodeActionTests {
    @Test
    func overrideActionAppliesAndReanalysisClearsDiagnostic() throws {
        let uri = "file:///tmp/LSPCodeActionOverride.kt"
        let source = """
        interface Greeter {
            fun greet(): String
        }
        class Impl : Greeter {
            /* 😀 */ fun greet(): String = "ok"
        }
        """
        let (server, analyzer, output, scheduler) = makeServer(uri: uri, source: source)
        _ = scheduler

        let diagnostic = try #require(
            currentDiagnostic(code: "KSWIFTK-SEMA-OVERRIDE", analyzer: analyzer, uri: uri)
        )
        let actions = try requestActions(
            server: server,
            output: output,
            id: 2,
            uri: uri,
            range: diagnostic.range,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["quickfix"])
        )
        let action = try #require(actions.first)
        #expect(action.title == "Add 'override' keyword")
        #expect(action.kind == "quickfix")
        let edits = try #require(action.edit?.changes?[uri])
        let edit = try #require(edits.first)
        #expect(edit.range.start == edit.range.end)
        #expect(edit.newText == "override ")

        let applied = try apply(edits, to: source, uri: uri)
        #expect(applied.contains("/* 😀 */ override fun greet"))

        let updated = Analyzer().analyze(uri: uri, text: applied)
        #expect(
            !updated.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OVERRIDE" },
            "Applying the override edit should remove the original diagnostic: \(updated.diagnostics)"
        )
    }

    @Test
    func constVarActionUsesUTF16RangeAndReanalysisClearsDiagnostic() throws {
        let uri = "file:///tmp/LSPCodeActionConst.kt"
        let source = "/* 😀 */ const var answer: Int = 1\n"
        let (server, analyzer, output, scheduler) = makeServer(uri: uri, source: source)
        _ = scheduler

        let diagnostic = try #require(
            currentDiagnostic(code: "KSWIFTK-SEMA-0080", analyzer: analyzer, uri: uri)
        )
        let actions = try requestActions(
            server: server,
            output: output,
            id: 2,
            uri: uri,
            range: diagnostic.range,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["quickfix"])
        )
        let action = try #require(actions.first)
        #expect(action.title == "Remove 'const' modifier")
        let edits = try #require(action.edit?.changes?[uri])
        let edit = try #require(edits.first)
        #expect(edit.newText.isEmpty)
        #expect(edit.range.start.line == 0)
        #expect(edit.range.start.character == 9, "The emoji must count as two UTF-16 code units")
        #expect(edit.range.end.character == 15)

        let applied = try apply(edits, to: source, uri: uri)
        #expect(applied == "/* 😀 */ var answer: Int = 1\n")

        let updated = Analyzer().analyze(uri: uri, text: applied)
        #expect(
            !updated.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0080" },
            "Applying the const edit should remove the original diagnostic: \(updated.diagnostics)"
        )
    }

    @Test
    func codeActionHonorsRangeContextOnlyAndCurrentDocument() throws {
        let uri = "file:///tmp/LSPCodeActionFiltering.kt"
        let source = "const var answer: Int = 1\n"
        let fixedSource = "var answer: Int = 1\n"
        let (server, analyzer, output, scheduler) = makeServer(uri: uri, source: source)
        let diagnostic = try #require(
            currentDiagnostic(code: "KSWIFTK-SEMA-0080", analyzer: analyzer, uri: uri)
        )

        let wrongKind = try requestActions(
            server: server,
            output: output,
            id: 2,
            uri: uri,
            range: diagnostic.range,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["source.organizeImports"])
        )
        #expect(wrongKind.isEmpty)

        let invalidRange = LSPRange(
            start: LSPPosition(line: -1, character: 0),
            end: diagnostic.range.end
        )
        let invalid = try requestActions(
            server: server,
            output: output,
            id: 3,
            uri: uri,
            range: invalidRange,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["quickfix"])
        )
        #expect(invalid.isEmpty)

        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didChange",
            params: JSONCoding.toObject(DidChangeTextDocumentParams(
                textDocument: VersionedTextDocumentIdentifier(uri: uri, version: 2),
                contentChanges: [TextDocumentContentChangeEvent(text: fixedSource)]
            ))!
        ))
        scheduler.runAll()

        let stale = try requestActions(
            server: server,
            output: output,
            id: 4,
            uri: uri,
            range: diagnostic.range,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["quickfix"])
        )
        #expect(stale.isEmpty, "A code action request carrying an old diagnostic must not edit the new document")
        #expect(analyzer.analysis(for: uri)?.diagnostics.allSatisfy { $0.code != "KSWIFTK-SEMA-0080" } == true)

        let unknown = try requestActions(
            server: server,
            output: output,
            id: 5,
            uri: "file:///tmp/LSPCodeActionUnknown.kt",
            range: diagnostic.range,
            context: CodeActionContext(diagnostics: [diagnostic], only: ["quickfix"])
        )
        #expect(unknown.isEmpty)
    }

    private func makeServer(
        uri: String,
        source: String
    ) -> (
        server: Server,
        analyzer: Analyzer,
        output: MemoryOutputStream,
        scheduler: ManualLSPDebounceScheduler
    ) {
        let analyzer = Analyzer()
        let scheduler = ManualLSPDebounceScheduler()
        let output = MemoryOutputStream()
        let server = Server(
            connection: JSONRPCConnection(input: MemoryInputStream(Data()), output: output),
            analyzer: analyzer,
            scheduler: scheduler
        )
        _ = server.handle(LSPTestSupport.message(
            method: "textDocument/didOpen",
            params: JSONCoding.toObject(DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(uri: uri, languageId: "kotlin", version: 1, text: source)
            ))!
        ))
        return (server, analyzer, output, scheduler)
    }

    private func currentDiagnostic(
        code: String,
        analyzer: Analyzer,
        uri: String
    ) -> LSPDiagnostic? {
        guard let analysis = analyzer.analysis(for: uri) else { return nil }
        return DiagnosticsFeature.lspDiagnostics(for: analysis).first { $0.code == code }
    }

    private func requestActions(
        server: Server,
        output: MemoryOutputStream,
        id: Int,
        uri: String,
        range: LSPRange,
        context: CodeActionContext
    ) throws -> [LSPCodeAction] {
        _ = server.handle(LSPTestSupport.message(
            id: id,
            method: "textDocument/codeAction",
            params: JSONCoding.toObject(CodeActionParams(
                textDocument: TextDocumentIdentifier(uri: uri),
                range: range,
                context: context
            ))!
        ))
        let response = try #require(
            LSPTestSupport.decodeMessages(from: output).last { ($0["id"] as? Int) == id }
        )
        let result = try #require(response["result"])
        return JSONCoding.decode([LSPCodeAction].self, from: result) ?? []
    }

    private func apply(_ edits: [LSPTextEdit], to source: String, uri: String) throws -> String {
        let sourceManager = SourceManager()
        let fileID = sourceManager.addFile(path: Analyzer.path(forURI: uri), contents: Data(source.utf8))
        var data = Data(source.utf8)
        let byteEdits = try edits.map { edit -> (start: Int, end: Int, text: Data) in
            let start = try #require(sourceManager.offset(
                ofLine: edit.range.start.line,
                utf16Character: edit.range.start.character,
                in: fileID
            ))
            let end = try #require(sourceManager.offset(
                ofLine: edit.range.end.line,
                utf16Character: edit.range.end.character,
                in: fileID
            ))
            return (start, end, Data(edit.newText.utf8))
        }.sorted { $0.start > $1.start }
        for edit in byteEdits {
            data.replaceSubrange(edit.start ..< edit.end, with: edit.text)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
