final class TokenStream {
    let tokens: [Token]
    private(set) var index: Int = 0

    private var syntheticEOFToken: Token {
        Token(
            kind: .eof,
            range: SourceRange(
                start: SourceLocation(file: FileID.invalid, offset: 0),
                end: SourceLocation(file: FileID.invalid, offset: 0)
            )
        )
    }

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    func peek(_ offset: Int = 0) -> Token {
        if tokens.isEmpty || offset < 0 {
            return syntheticEOFToken
        }
        let target = index + offset
        if target < tokens.count {
            return tokens[target]
        }
        return syntheticEOFToken
    }

    func advance() -> Token {
        let token = peek()
        if index < tokens.count {
            index += 1
        }
        return token
    }

    func atEOF() -> Bool {
        peek().kind == .eof
    }

    func consumeIf(_ predicate: (Token) -> Bool) -> Token? {
        let token = peek()
        if predicate(token) {
            return advance()
        }
        return nil
    }
}
