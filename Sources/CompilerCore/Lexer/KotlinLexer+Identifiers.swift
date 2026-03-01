extension KotlinLexer {
    func scanIdentifier(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        return scanIdentifierCore(start: start, leadingTrivia: leadingTrivia)
    }

    func scanTemplateName(leadingTrivia: [TriviaPiece], start: Int) -> Token? {
        guard start < bytes.count && isIdentifierStart(bytes[start]) else {
            return nil
        }
        return scanIdentifierCore(start: start, leadingTrivia: leadingTrivia)
    }

    private func scanIdentifierCore(start: Int, leadingTrivia: [TriviaPiece]) -> Token {
        var cursor = start
        while cursor < bytes.count && isIdentifierContinue(bytes[cursor]) {
            cursor += 1
        }
        let name = text(from: start..<cursor)
        offset = cursor
        if let keyword = Keyword(rawValue: name) {
            return Token(kind: .keyword(keyword), range: makeRange(start: start, end: cursor), leadingTrivia: leadingTrivia)
        }
        if let softKeyword = SoftKeyword(rawValue: name) {
            return Token(kind: .softKeyword(softKeyword), range: makeRange(start: start, end: cursor), leadingTrivia: leadingTrivia)
        }
        return Token(kind: .identifier(interner.intern(name)), range: makeRange(start: start, end: cursor), leadingTrivia: leadingTrivia)
    }

    func scanBacktickedIdentifier(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        offset += 1
        let bodyStart = offset
        while offset < bytes.count && bytes[offset] != 0x60 {
            offset += 1
        }
        let body = text(from: bodyStart..<min(offset, bytes.count))
        if offset >= bytes.count {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated backticked identifier.",
                range: makeRange(start: start, end: bytes.count)
            )
        } else {
            offset += 1
        }
        return Token(kind: .backtickedIdentifier(interner.intern(body)), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
    }
}
