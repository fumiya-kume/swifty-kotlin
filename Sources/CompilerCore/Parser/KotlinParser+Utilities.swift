extension KotlinParser {
    internal func parseBalancedGroup(opening: Symbol, closing: Symbol) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        guard consumeIfSymbol(opening, into: &children, range: &range) else {
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }

        var depth = 1
        while !stream.atEOF() && depth > 0 {
            let token = stream.peek()
            if case .symbol(let symbol) = token.kind, symbol == closing && depth == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
            }
            if depth == 1 && hasLeadingNewline(token) && isLikelyTopLevelDeclarationStart(token) {
                break
            }

            _ = consumeToken(into: &children, range: &range)
            if case .symbol(opening) = token.kind {
                depth += 1
            } else if case .symbol(closing) = token.kind {
                depth -= 1
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0004",
            "Unterminated '\(opening.rawValue)' group.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
    }

    internal func parseQualifiedPath(into children: inout [SyntaxChild], range: inout RangeAccumulator, allowImportWildcard: Bool, stopAtAs: Bool = false) {
        var consumed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: false) {
                break
            }
            // Package/import paths must not consume declaration starts on the next line.
            if consumed && hasLeadingNewline(token) {
                break
            }
            if stopAtAs, case .keyword(.as) = token.kind {
                break
            }
            if case .symbol(.dot) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if isIdentifierLike(token.kind) {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if allowImportWildcard, case .symbol(.star) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            break
        }
        if !consumed {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0003", message: "Expected name in package/import path.")
        }
    }

    internal func consumeIf(expected: TokenKind, into children: inout [SyntaxChild], range: inout RangeAccumulator, code: String) {
        if stream.peek().kind == expected {
            _ = consumeToken(into: &children, range: &range)
            return
        }
        insertMissingToken(expected: expected, into: &children, range: &range, code: code, message: "Expected \(expected).")
    }

    internal func consumeIfSymbol(_ symbol: Symbol, into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Bool {
        if case .symbol(symbol) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            return true
        }
        return false
    }

    internal func consumeToken(into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Token {
        let token = stream.advance()
        let tokenID = arena.appendToken(token)
        let child: SyntaxChild = .token(tokenID)
        children.append(child)
        range.append(token.range)
        if token.kind != .eof {
            lastConsumedToken = token
        }
        return token
    }

    internal func childRange(_ child: SyntaxChild) -> SourceRange {
        switch child {
        case .token(let tokenID):
            guard let token = arena.token(tokenID) else { return invalidRange }
            return token.range
        case .node(let nodeID):
            return arena.node(nodeID).range
        }
    }

    internal func shouldStopStatementBefore(_ token: Token, inBlock: Bool) -> Bool {
        ParserBoundaryPolicy.shouldStopStatementBefore(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
    }

    static func isDeclarationModifierKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final, .crossinline, .noinline, .tailrec,
             .inline, .suspend, .operator, .infix, .external, .value:
            return true
        default:
            return false
        }
    }

    internal func isDeclarationKeyword(_ keyword: Keyword) -> Bool {
        if Self.isDeclarationModifierKeyword(keyword) {
            return true
        }
        switch keyword {
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import, .companion:
            return true
        default:
            return false
        }
    }

    internal func isDeclarationStart(_ kind: TokenKind) -> Bool {
        if case .keyword(let keyword) = kind, isDeclarationKeyword(keyword) {
            return true
        }
        return false
    }

    internal func isIdentifierLike(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            return true
        default:
            return false
        }
    }

    internal func isLoopStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.for), .keyword(.while), .keyword(.do):
            return true
        default:
            return false
        }
    }

    internal func hasLeadingNewline(_ token: Token) -> Bool {
        return token.leadingTrivia.contains(.newline)
    }

    internal func appendOptionalTerminator(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if !stream.atEOF(), case .symbol(.semicolon) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    internal func zeroWidthRange(at token: Token) -> SourceRange {
        let loc = token.range.start
        return SourceRange(start: loc, end: loc)
    }

    internal func insertMissingToken(
        expected: TokenKind,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        code: String,
        message: String
    ) {
        let missingRange = zeroWidthRange(at: stream.peek())
        diagnostics.warning(code, message, range: missingRange)
        let missingToken = Token(kind: .missing(expected: expected), range: missingRange)
        let tokenID = arena.appendToken(missingToken)
        children.append(.token(tokenID))
        range.append(missingRange)
    }

    internal func isSynchronizationPoint(_ token: Token, inBlock: Bool) -> Bool {
        ParserBoundaryPolicy.isSynchronizationPoint(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
    }

    internal func skipToSynchronizationPoint(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        let skippedStart = stream.peek().range
        var skippedCount = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if isSynchronizationPoint(token, inBlock: inBlock) {
                break
            }
            _ = consumeToken(into: &children, range: &range)
            skippedCount += 1
        }
        if skippedCount > 0 {
            diagnostics.error(
                "KSWIFTK-PARSE-0006",
                "Skipped \(skippedCount) unexpected token(s).",
                range: skippedStart
            )
        }
    }

    internal func isLikelyTopLevelDeclarationStart(_ token: Token) -> Bool {
        if isDeclarationStart(token.kind) {
            return true
        }
        if case .keyword(let keyword) = token.kind {
            return Self.isDeclarationModifierKeyword(keyword) || keyword == .companion
        }
        return false
    }

    internal var invalidRange: SourceRange {
        SourceRange(
            start: SourceLocation(file: FileID.invalid, offset: 0),
            end: SourceLocation(file: FileID.invalid, offset: 0)
        )
    }
}

enum ParserBoundaryPolicy {
    /// Keywords that start declarations or act as statement/synchronization boundaries.
    private static let declarationBoundaryKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import
    ]

    /// Keywords used as error-recovery synchronization points.
    /// Excludes `.enum` because `enum` is a soft modifier (always followed by `class`)
    /// and was not a synchronization point in the original implementation.
    private static let synchronizationKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .package, .import
    ]

    private static let nonSplittingNewlineSymbols: Set<Symbol> = [
        .dot, .comma, .questionDot, .questionQuestion,
        .plus, .minus, .star, .slash,
        .equalEqual, .assign, .arrow,
        .rParen, .rBracket, .rBrace
    ]

    static func shouldStopStatementBefore(
        _ token: Token,
        inBlock: Bool,
        hasLeadingNewline: Bool
    ) -> Bool {
        if token.kind == .eof {
            return true
        }
        switch token.kind {
        case .symbol(.rBrace):
            return true
        case .keyword(let kw) where declarationBoundaryKeywords.contains(kw):
            return !inBlock && hasLeadingNewline
        default:
            return false
        }
    }

    static func isSynchronizationPoint(
        _ token: Token,
        inBlock: Bool,
        hasLeadingNewline: Bool
    ) -> Bool {
        switch token.kind {
        case .eof:
            return true
        case .symbol(.rBrace):
            return true
        case .keyword(let kw) where synchronizationKeywords.contains(kw):
            return true
        default:
            break
        }
        if inBlock {
            switch token.kind {
            case .symbol(.semicolon):
                return true
            case .keyword(.catch), .keyword(.finally), .keyword(.else):
                return true
            default:
                if hasLeadingNewline {
                    return true
                }
            }
        }
        return false
    }

    static func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        if case .symbol(let symbol) = kind {
            return !nonSplittingNewlineSymbols.contains(symbol)
        }
        return true
    }
}

internal extension Token {
    var rangeIfAvailable: SourceRange {
        return range
    }
}

internal struct RangeAccumulator {
    var value: SourceRange?

    mutating func append(_ range: SourceRange) {
        if let current = value {
            value = SourceRange(start: current.start, end: range.end)
        } else {
            value = range
        }
    }
}
