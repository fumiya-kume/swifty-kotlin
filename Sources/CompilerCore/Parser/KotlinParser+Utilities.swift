extension KotlinParser {
    func parseLeadingDeclarationPrefix(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var consumedAny = true
        while consumedAny {
            consumedAny = false
            if consumeDeclarationAnnotationPrefixIfPresent(into: &children, range: &range) {
                consumedAny = true
                continue
            }
            if case let .keyword(keyword) = stream.peek().kind,
               Self.isDeclarationModifierKeyword(keyword)
            {
                _ = consumeToken(into: &children, range: &range)
                consumedAny = true
            }
        }
    }

    func consumeDeclarationAnnotationPrefixIfPresent(
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) -> Bool {
        guard stream.peek().kind == .symbol(.at) else {
            return false
        }

        _ = consumeToken(into: &children, range: &range) // '@'

        // Optional use-site target: `@get:`, `@field:`, `@file:`, etc.
        let first = stream.peek()
        if isAnnotationUseSiteTarget(first),
           stream.peek(1).kind == .symbol(.colon)
        {
            _ = consumeToken(into: &children, range: &range)
            _ = consumeToken(into: &children, range: &range)
        }

        // Qualified annotation name: `Foo`, `kotlin.Deprecated`, etc.
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
            while stream.peek().kind == .symbol(.dot),
                  isIdentifierLike(stream.peek(1).kind)
            {
                _ = consumeToken(into: &children, range: &range) // '.'
                _ = consumeToken(into: &children, range: &range) // name segment
            }
        }

        // Optional annotation argument list: `(...)`, allowing nested parens.
        if stream.peek().kind == .symbol(.lParen) {
            var depth = 0
            while !stream.atEOF() {
                let token = consumeToken(into: &children, range: &range)
                if token.kind == .symbol(.lParen) {
                    depth += 1
                } else if token.kind == .symbol(.rParen) {
                    depth -= 1
                    if depth <= 0 {
                        break
                    }
                }
            }
        }

        return true
    }

    func isAnnotationUseSiteTarget(_ token: Token) -> Bool {
        switch token.kind {
        case .softKeyword(.get), .softKeyword(.set), .softKeyword(.field), .softKeyword(.property),
             .softKeyword(.receiver), .softKeyword(.param), .softKeyword(.setparam),
             .softKeyword(.delegate), .softKeyword(.file):
            return true
        case let .identifier(id), let .backtickedIdentifier(id):
            let name = interner.resolve(id)
            return [
                "get", "set", "field", "property", "receiver", "param", "setparam", "delegate", "file",
            ].contains(name)
        case let .keyword(keyword):
            return [
                "get", "set", "field", "property", "receiver", "param", "setparam", "delegate", "file",
            ].contains(keyword.rawValue)
        default:
            return false
        }
    }

    func parseBalancedGroup(opening: Symbol, closing: Symbol) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        guard consumeIfSymbol(opening, into: &children, range: &range) else {
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }

        var depth = 1
        while !stream.atEOF(), depth > 0 {
            let token = stream.peek()
            if case let .symbol(symbol) = token.kind, symbol == closing, depth == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
            }
            if depth == 1, hasLeadingNewline(token), isLikelyTopLevelDeclarationStart(token) {
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

    func parseQualifiedPath(into children: inout [SyntaxChild], range: inout RangeAccumulator, allowImportWildcard: Bool, stopAtAs: Bool = false) {
        var consumed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: false) {
                break
            }
            // Package/import paths must not consume declaration starts on the next line.
            if consumed, hasLeadingNewline(token) {
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

    func consumeIf(expected: TokenKind, into children: inout [SyntaxChild], range: inout RangeAccumulator, code: String) {
        if stream.peek().kind == expected {
            _ = consumeToken(into: &children, range: &range)
            return
        }
        insertMissingToken(expected: expected, into: &children, range: &range, code: code, message: "Expected \(expected).")
    }

    func consumeIfSymbol(_ symbol: Symbol, into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Bool {
        if case .symbol(symbol) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            return true
        }
        return false
    }

    func consumeToken(into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Token {
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

    func childRange(_ child: SyntaxChild) -> SourceRange {
        switch child {
        case let .token(tokenID):
            guard let token = arena.token(tokenID) else { return invalidRange }
            return token.range
        case let .node(nodeID):
            return arena.node(nodeID).range
        }
    }

    func shouldStopStatementBefore(_ token: Token, inBlock: Bool) -> Bool {
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
            true
        default:
            false
        }
    }

    func isDeclarationKeyword(_ keyword: Keyword) -> Bool {
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

    func isDeclarationStart(_ kind: TokenKind) -> Bool {
        if kind == .symbol(.at) {
            return true
        }
        if case let .keyword(keyword) = kind, isDeclarationKeyword(keyword) {
            return true
        }
        if case .softKeyword(.context) = kind {
            return true
        }
        return false
    }

    func isIdentifierLike(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            true
        default:
            false
        }
    }

    func isLoopStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.for), .keyword(.while), .keyword(.do):
            true
        default:
            false
        }
    }

    func hasLeadingNewline(_ token: Token) -> Bool {
        token.leadingTrivia.contains(.newline)
    }

    func appendOptionalTerminator(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if !stream.atEOF(), case .symbol(.semicolon) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    func zeroWidthRange(at token: Token) -> SourceRange {
        let loc = token.range.start
        return SourceRange(start: loc, end: loc)
    }

    func insertMissingToken(
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

    func isSynchronizationPoint(_ token: Token, inBlock: Bool) -> Bool {
        ParserBoundaryPolicy.isSynchronizationPoint(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
    }

    func skipToSynchronizationPoint(
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

    func isLikelyTopLevelDeclarationStart(_ token: Token) -> Bool {
        if token.kind == .symbol(.at) {
            return true
        }
        if isDeclarationStart(token.kind) {
            return true
        }
        if case let .keyword(keyword) = token.kind {
            return Self.isDeclarationModifierKeyword(keyword) || keyword == .companion
        }
        return false
    }

    var invalidRange: SourceRange {
        SourceRange(
            start: SourceLocation(file: FileID.invalid, offset: 0),
            end: SourceLocation(file: FileID.invalid, offset: 0)
        )
    }
}

enum ParserBoundaryPolicy {
    /// Keywords that start declarations or act as statement/synchronization boundaries.
    private static let declarationBoundaryKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import,
    ]

    /// Keywords used as error-recovery synchronization points.
    /// Excludes `.enum` because `enum` is a soft modifier (always followed by `class`)
    /// and was not a synchronization point in the original implementation.
    private static let synchronizationKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .package, .import,
    ]

    private static let nonSplittingNewlineSymbols: Set<Symbol> = [
        .dot, .comma, .questionDot, .questionQuestion,
        .plus, .minus, .star, .slash,
        .equalEqual, .assign, .arrow,
        .rParen, .rBracket, .rBrace,
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
        case let .keyword(kw) where declarationBoundaryKeywords.contains(kw):
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
        case let .keyword(kw) where synchronizationKeywords.contains(kw):
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
        if case let .symbol(symbol) = kind {
            return !nonSplittingNewlineSymbols.contains(symbol)
        }
        return true
    }
}

extension Token {
    var rangeIfAvailable: SourceRange {
        range
    }
}

struct RangeAccumulator {
    var value: SourceRange?

    mutating func append(_ range: SourceRange) {
        if let current = value {
            value = SourceRange(start: current.start, end: range.end)
        } else {
            value = range
        }
    }
}
