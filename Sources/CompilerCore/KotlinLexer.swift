import Foundation

public final class KotlinLexer {
    let file: FileID
    let bytes: [UInt8]
    let interner: StringInterner
    let diagnostics: DiagnosticEngine

    var offset: Int = 0

    public init(file: FileID, source: Data, interner: StringInterner, diagnostics: DiagnosticEngine) {
        self.file = file
        self.bytes = Array(source)
        self.interner = interner
        self.diagnostics = diagnostics
    }

    public func lexAll() -> [Token] {
        var tokens: [Token] = []
        while offset < bytes.count {
            let leadingTrivia = consumeTrivia()
            if offset >= bytes.count {
                break
            }
            tokens.append(contentsOf: scanNextTokens(leadingTrivia: leadingTrivia))
        }
        let eofLocation = SourceLocation(file: file, offset: bytes.count)
        tokens.append(Token(kind: .eof, range: SourceRange(start: eofLocation, end: eofLocation), leadingTrivia: []))
        return tokens
    }

    func consumeTrivia() -> [TriviaPiece] {
        var trivia: [TriviaPiece] = []
        while offset < bytes.count {
            let ch = bytes[offset]

            if ch == 0x20 {
                let start = offset
                while offset < bytes.count && bytes[offset] == 0x20 {
                    offset += 1
                }
                trivia.append(.spaces(offset - start))
                continue
            }

            if ch == 0x09 {
                let start = offset
                while offset < bytes.count && bytes[offset] == 0x09 {
                    offset += 1
                }
                trivia.append(.tabs(offset - start))
                continue
            }

            if ch == 0x0D {
                if offset + 1 < bytes.count && bytes[offset + 1] == 0x0A {
                    trivia.append(.newline)
                    offset += 2
                    continue
                }
                trivia.append(.newline)
                offset += 1
                continue
            }

            if ch == 0x0A {
                trivia.append(.newline)
                offset += 1
                continue
            }

            if ch == 0x23 && offset == 0 && starts(with: "#!") {
                let start = offset
                while offset < bytes.count && bytes[offset] != 0x0A {
                    offset += 1
                }
                trivia.append(.shebang(text(from: start..<offset)))
                continue
            }

            if starts(with: "//") {
                let start = offset
                offset += 2
                while offset < bytes.count && bytes[offset] != 0x0A {
                    offset += 1
                }
                trivia.append(.lineComment(text(from: start..<offset)))
                continue
            }

            if starts(with: "/*") {
                let start = offset
                offset += 2
                var depth = 1
                while offset < bytes.count && depth > 0 {
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
                            end: SourceLocation(file: file, offset: bytes.count)
                        )
                    )
                    break
                }
                trivia.append(.blockComment(text(from: start..<offset)))
                continue
            }

            break
        }
        return trivia
    }

    func scanNextTokens(leadingTrivia: [TriviaPiece]) -> [Token] {
        guard offset < bytes.count else { return [] }
        let start = offset
        let ch = bytes[offset]

        if ch == 0x22 {
            if starts(with: "\"\"\"") {
                return scanRawString(leadingTrivia: leadingTrivia, start: start)
            }
            return scanString(leadingTrivia: leadingTrivia, start: start)
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
            "Unknown character '\(text(from: start..<(start + 1)))'",
            range: SourceRange(
                start: SourceLocation(file: file, offset: start),
                end: SourceLocation(file: file, offset: min(start + 1, bytes.count))
            )
        )
        offset += 1
        return []
    }
}
