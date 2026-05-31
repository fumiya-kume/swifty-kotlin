import Foundation

// MARK: - Core geometry

/// A 0-based position in a text document. `character` counts UTF-16 code units.
public struct LSPPosition: Codable, Equatable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct LSPRange: Codable, Equatable {
    public var start: LSPPosition
    public var end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

public struct LSPLocation: Codable, Equatable {
    public var uri: String
    public var range: LSPRange

    public init(uri: String, range: LSPRange) {
        self.uri = uri
        self.range = range
    }
}

// MARK: - Text document identifiers

public struct TextDocumentIdentifier: Codable {
    public var uri: String
}

public struct VersionedTextDocumentIdentifier: Codable {
    public var uri: String
    public var version: Int?
}

public struct TextDocumentItem: Codable {
    public var uri: String
    public var languageId: String?
    public var version: Int?
    public var text: String
}

public struct TextDocumentPositionParams: Codable {
    public var textDocument: TextDocumentIdentifier
    public var position: LSPPosition
}

// MARK: - Synchronization params

public struct DidOpenTextDocumentParams: Codable {
    public var textDocument: TextDocumentItem
}

/// A single content change. With full document sync (the mode this server
/// advertises) `text` carries the entire new document and `range` is absent.
public struct TextDocumentContentChangeEvent: Codable {
    public var text: String
}

public struct DidChangeTextDocumentParams: Codable {
    public var textDocument: VersionedTextDocumentIdentifier
    public var contentChanges: [TextDocumentContentChangeEvent]
}

public struct DidCloseTextDocumentParams: Codable {
    public var textDocument: TextDocumentIdentifier
}

public struct DidSaveTextDocumentParams: Codable {
    public var textDocument: TextDocumentIdentifier
    public var text: String?
}

public struct DocumentSymbolParams: Codable {
    public var textDocument: TextDocumentIdentifier
}

// MARK: - Diagnostics

/// LSP diagnostic severity codes.
public enum LSPDiagnosticSeverity: Int {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

public struct LSPDiagnostic: Codable, Equatable {
    public var range: LSPRange
    public var severity: Int?
    public var code: String?
    public var source: String?
    public var message: String

    public init(
        range: LSPRange,
        severity: Int?,
        code: String?,
        source: String?,
        message: String
    ) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
    }
}

public struct PublishDiagnosticsParams: Codable {
    public var uri: String
    public var version: Int?
    public var diagnostics: [LSPDiagnostic]

    public init(uri: String, version: Int?, diagnostics: [LSPDiagnostic]) {
        self.uri = uri
        self.version = version
        self.diagnostics = diagnostics
    }
}

// MARK: - Hover

public struct MarkupContent: Codable {
    /// `"markdown"` or `"plaintext"`.
    public var kind: String
    public var value: String

    public init(kind: String = "markdown", value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct Hover: Codable {
    public var contents: MarkupContent
    public var range: LSPRange?

    public init(contents: MarkupContent, range: LSPRange?) {
        self.contents = contents
        self.range = range
    }
}

// MARK: - Document symbols

/// LSP `SymbolKind` numeric codes.
public enum LSPSymbolKind: Int {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case number = 16
    case boolean = 17
    case array = 18
    case object = 19
    case key = 20
    case null = 21
    case enumMember = 22
    case `struct` = 23
    case event = 24
    case `operator` = 25
    case typeParameter = 26
}

public struct DocumentSymbol: Codable {
    public var name: String
    public var detail: String?
    public var kind: Int
    public var range: LSPRange
    public var selectionRange: LSPRange
    public var children: [DocumentSymbol]?

    public init(
        name: String,
        detail: String?,
        kind: Int,
        range: LSPRange,
        selectionRange: LSPRange,
        children: [DocumentSymbol]?
    ) {
        self.name = name
        self.detail = detail
        self.kind = kind
        self.range = range
        self.selectionRange = selectionRange
        self.children = children
    }
}

// MARK: - Lifecycle

public struct ServerInfo: Codable {
    public var name: String
    public var version: String?
}

public struct ServerCapabilities: Codable {
    /// Text document sync kind: 0 = none, 1 = full, 2 = incremental.
    public var textDocumentSync: Int
    public var hoverProvider: Bool
    public var definitionProvider: Bool
    public var documentSymbolProvider: Bool
}

public struct InitializeResult: Codable {
    public var capabilities: ServerCapabilities
    public var serverInfo: ServerInfo?
}
