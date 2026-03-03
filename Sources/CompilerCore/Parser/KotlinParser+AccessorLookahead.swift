extension KotlinParser {
    /// Returns `true` when `token` looks like the start of a property accessor
    /// (`get()` or `set(...)` followed by `=` or `{`). Used to absorb
    /// newline-separated accessor lines into the property declaration CST node.
    func isPropertyAccessorStart(_ token: Token) -> Bool {
        switch token.kind {
        case .softKeyword(.get), .softKeyword(.set):
            isAccessorHeaderFollowedByBody()
        default:
            false
        }
    }

    /// Checks whether the tokens starting at `stream.peek(1)` form a
    /// well-formed accessor header `(...)` followed by `=` or `{`.
    private func isAccessorHeaderFollowedByBody() -> Bool {
        guard stream.peek(1).kind == .symbol(.lParen) else {
            return false
        }
        var offset = 1
        var parenDepth = 0
        let maxLookahead = 64
        while offset <= maxLookahead {
            let nextToken = stream.peek(offset)
            switch nextToken.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth -= 1
                if parenDepth == 0 {
                    return isAccessorBodyStart(stream.peek(offset + 1))
                }
            default:
                break
            }
            if parenDepth < 0 { return false }
            offset += 1
        }
        return false
    }

    /// Returns `true` when the given token can begin an accessor body (`=` or `{`).
    private func isAccessorBodyStart(_ token: Token) -> Bool {
        switch token.kind {
        case .symbol(.assign), .symbol(.lBrace):
            true
        default:
            false
        }
    }
}
