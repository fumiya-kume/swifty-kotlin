extension KotlinLexer {
    func scanIdentifier(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        scanIdentifierCore(start: start, leadingTrivia: leadingTrivia)
    }

    func scanTemplateName(leadingTrivia: [TriviaPiece], start: Int) -> Token? {
        guard start < byteCount(), isIdentifierStart(byte(at: start)), byte(at: start) != 0x24 else {
            return nil
        }
        return scanTemplateNameCore(start: start, leadingTrivia: leadingTrivia)
    }

    /// Scans an identifier for a simple string template reference (`$name`).
    /// Unlike `scanIdentifierCore`, this stops at `$` so that adjacent
    /// template references like `"$i$j"` are parsed as two separate names.
    private func scanTemplateNameCore(start: Int, leadingTrivia: [TriviaPiece]) -> Token {
        var cursor = start
        while cursor < byteCount(), isIdentifierContinue(byte(at: cursor)), byte(at: cursor) != 0x24 {
            cursor += 1
        }
        let name = text(from: start ..< cursor)
        offset = cursor
        return Token(kind: .identifier(interner.intern(name)), range: makeRange(start: start, end: cursor), leadingTrivia: leadingTrivia)
    }

    private func scanIdentifierCore(start: Int, leadingTrivia: [TriviaPiece]) -> Token {
        var cursor = start
        while cursor < byteCount(), isIdentifierContinue(byte(at: cursor)) {
            cursor += 1
        }
        let name = text(from: start ..< cursor)
        offset = cursor
        let kind: TokenKind
        if let cached = identifierKinds[name] {
            kind = cached
        } else {
            kind = classifyIdentifier(name)
            identifierKinds[name] = kind
        }
        return Token(kind: kind, range: makeRange(start: start, end: cursor), leadingTrivia: leadingTrivia)
    }

    private func classifyIdentifier(_ name: String) -> TokenKind {
        if let keyword = Keyword(rawValue: name) {
            return .keyword(keyword)
        }
        if let softKeyword = SoftKeyword(rawValue: name) {
            return .softKeyword(softKeyword)
        }
        return .identifier(interner.intern(name))
    }

    func scanBacktickedIdentifier(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        offset += 1
        let bodyStart = offset
        while offset < byteCount(), byte(at: offset) != 0x60 {
            offset += 1
        }
        let body = text(from: bodyStart ..< min(offset, byteCount()))
        if offset >= byteCount() {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated backticked identifier.",
                range: makeRange(start: start, end: byteCount())
            )
        } else {
            offset += 1
        }
        return Token(kind: .backtickedIdentifier(interner.intern(body)), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
    }
}
