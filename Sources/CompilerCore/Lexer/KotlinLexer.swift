import Foundation

final class KotlinLexer {
    let file: FileID
    let bytes: Data
    let interner: StringInterner
    let diagnostics: DiagnosticEngine

    var offset: Int = 0
    // Keep classification and interned IDs local to this lexer and its interner.
    var identifierKinds: [String: TokenKind] = [:]

    init(file: FileID, source: Data, interner: StringInterner, diagnostics: DiagnosticEngine) {
        self.file = file
        bytes = source
        self.interner = interner
        self.diagnostics = diagnostics
    }

    func lexAll() -> [Token] {
        var tokens: [Token] = []
        while offset < byteCount() {
            let leadingTrivia = consumeTrivia()
            if offset >= byteCount() {
                break
            }
            tokens.append(contentsOf: scanNextTokens(leadingTrivia: leadingTrivia))
        }
        let eofLocation = SourceLocation(file: file, offset: byteCount())
        tokens.append(Token(kind: .eof, range: SourceRange(start: eofLocation, end: eofLocation), leadingTrivia: []))
        return tokens
    }

    func consumeTrivia() -> [TriviaPiece] {
        var trivia: [TriviaPiece] = []
        while offset < byteCount() {
            if let piece = consumeWhitespaceTrivia() {
                trivia.append(piece)
                continue
            }

            if let piece = consumeLineBreakTrivia() {
                trivia.append(piece)
                continue
            }

            if let piece = consumeShebangTrivia() {
                trivia.append(piece)
                continue
            }

            if let piece = consumeLineCommentTrivia() {
                trivia.append(piece)
                continue
            }

            if let blockComment = consumeBlockCommentTrivia() {
                switch blockComment {
                case let .consumed(piece):
                    trivia.append(piece)
                case .unterminated:
                    return trivia
                }
                continue
            }

            break
        }
        return trivia
    }

    private func consumeWhitespaceTrivia() -> TriviaPiece? {
        guard offset < byteCount() else { return nil }
        let ch = byte(at: offset)
        if ch == 0x20 {
            let start = offset
            while offset < byteCount(), byte(at: offset) == 0x20 {
                offset += 1
            }
            return .spaces(offset - start)
        }
        if ch == 0x09 {
            let start = offset
            while offset < byteCount(), byte(at: offset) == 0x09 {
                offset += 1
            }
            return .tabs(offset - start)
        }
        return nil
    }

    private func consumeLineBreakTrivia() -> TriviaPiece? {
        guard offset < byteCount() else { return nil }
        let ch = byte(at: offset)
        if ch == 0x0D {
            if offset + 1 < byteCount(), byte(at: offset + 1) == 0x0A {
                offset += 2
                return .newline
            }
            offset += 1
            return .newline
        }
        if ch == 0x0A {
            offset += 1
            return .newline
        }
        return nil
    }

    private func consumeShebangTrivia() -> TriviaPiece? {
        guard offset < byteCount() else { return nil }
        guard byte(at: offset) == 0x23, offset == 0, starts(with: "#!") else {
            return nil
        }
        let start = offset
        while offset < byteCount(), byte(at: offset) != 0x0A {
            offset += 1
        }
        return .shebang(text(from: start ..< offset))
    }

    private func consumeLineCommentTrivia() -> TriviaPiece? {
        guard starts(with: "//") else {
            return nil
        }
        let start = offset
        offset += 2
        while offset < byteCount(), byte(at: offset) != 0x0A {
            offset += 1
        }
        return .lineComment(text(from: start ..< offset))
    }

    private enum BlockCommentTriviaResult {
        case consumed(TriviaPiece)
        case unterminated
    }

    private func consumeBlockCommentTrivia() -> BlockCommentTriviaResult? {
        guard starts(with: "/*") else {
            return nil
        }

        let start = offset
        offset += 2
        var depth = 1
        while offset < byteCount(), depth > 0 {
            if starts(with: "/*") {
                depth += 1
                offset += 2
                continue
            }
            if starts(with: "*/") {
                depth -= 1
                offset += 2
                if depth == 0 {
                    break
                }
                continue
            }
            offset += 1
        }

        if depth > 0 {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated block comment.",
                range: SourceRange(
                    start: SourceLocation(file: file, offset: start),
                    end: SourceLocation(file: file, offset: byteCount())
                )
            )
            return .unterminated
        }

        return .consumed(.blockComment(text(from: start ..< offset)))
    }

    func scanNextTokens(leadingTrivia: [TriviaPiece]) -> [Token] {
        guard offset < byteCount() else { return [] }
        let start = offset
        let ch = byte(at: offset)

        if ch == 0x22 {
            if starts(with: "\"\"\"") {
                return scanRawString(leadingTrivia: leadingTrivia, start: start)
            }
            return scanString(leadingTrivia: leadingTrivia, start: start)
        }

        // Multi-dollar string prefix: $$"...", $$$"...", etc.
        if ch == 0x24 {
            let dollarCount = countConsecutiveDollars(at: offset)
            if dollarCount >= 2 {
                let afterDollars = offset + dollarCount
                if afterDollars < byteCount(), byte(at: afterDollars) == 0x22 {
                    if starts(with: "\"\"\"", at: afterDollars) {
                        return scanMultiDollarRawString(leadingTrivia: leadingTrivia, start: start, dollarCount: dollarCount)
                    }
                    return scanMultiDollarString(leadingTrivia: leadingTrivia, start: start, dollarCount: dollarCount)
                }
            }
        }

        if isIdentifierStart(ch) {
            return [scanIdentifier(leadingTrivia: leadingTrivia, start: start)]
        }

        if ch == 0x60 {
            return [scanBacktickedIdentifier(leadingTrivia: leadingTrivia, start: start)]
        }

        if isDigit(ch) {
            return [scanNumber(leadingTrivia: leadingTrivia, start: start)]
        }

        if ch == 0x27 {
            return [scanCharLiteral(leadingTrivia: leadingTrivia, start: start)]
        }

        if let resolved = symbolKind() {
            return [Token(
                kind: .symbol(resolved),
                range: makeRange(start: start, end: offset),
                leadingTrivia: leadingTrivia
            )]
        }

        diagnostics.error(
            "KSWIFTK-LEX-0001",
            "Unknown character '\(text(from: start ..< (start + 1)))'",
            range: SourceRange(
                start: SourceLocation(file: file, offset: start),
                end: SourceLocation(file: file, offset: min(start + 1, byteCount()))
            )
        )
        offset += 1
        return []
    }
}
