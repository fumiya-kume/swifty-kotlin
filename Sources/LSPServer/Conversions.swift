import CompilerCore

/// Conversions from compiler source ranges to LSP geometry.
enum LSPConvert {
    /// Converts a compiler `SourceRange` to an LSP range (0-based, UTF-16).
    static func range(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPRange {
        let start = sourceManager.lspPosition(of: sourceRange.start)
        let end = sourceManager.lspPosition(of: sourceRange.end)
        return LSPRange(
            start: LSPPosition(line: start.line, character: start.character),
            end: LSPPosition(line: end.line, character: end.character)
        )
    }

    /// Converts a compiler `SourceRange` to an LSP location, deriving the
    /// document URI from the range's source file.
    static func location(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPLocation {
        let path = sourceManager.path(of: sourceRange.start.file)
        return LSPLocation(uri: DocumentURI.uri(fromPath: path), range: range(sourceRange, sourceManager))
    }
}
