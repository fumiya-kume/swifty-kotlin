extension KotlinParser {
    internal func parseBlock() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            if case .keyword(.constructor) = token.kind {
                children.append(.node(parseConstructorDeclaration()))
                continue
            }
            if case .softKeyword(.constructor) = token.kind {
                children.append(.node(parseConstructorDeclaration()))
                continue
            }
            if isDeclarationStart(token.kind) && hasLeadingNewline(token) {
                children.append(.node(parseDeclaration()))
            } else if parseStatementTail(inBlock: true) == .canContinue {
                children.append(.node(parseStatement(inBlock: true)))
            } else {
                let before = stream.index
                skipToSynchronizationPoint(inBlock: true, into: &children, range: &range)
                if stream.index == before, !stream.atEOF() {
                    _ = consumeToken(into: &children, range: &range)
                }
            }
        }

        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    internal func parseStatement(inBlock: Bool) -> NodeID {
        if isLoopStart(stream.peek().kind) {
            return parseLoopStatement(inBlock: inBlock)
        }

        let leadingKind = classifyStatementLeadingToken(stream.peek())

        let startCount = stream.index
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var parenDepth = 0
        var bracketDepth = 0

        while !stream.atEOF() {
            let token = stream.peek()
            if inBlock,
               !children.isEmpty,
               parenDepth == 0,
               bracketDepth == 0,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind) {
                break
            }
            if shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                children.append(.node(parseBlock()))
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            default:
                break
            }
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                break
            }
        }

        if stream.index == startCount, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }

        let nodeKind = resolveStatementKind(leadingKind, children: children)

        return arena.appendNode(
            kind: nodeKind,
            range: range.value ?? invalidRange, children)
    }

    internal func classifyStatementLeadingToken(_ token: Token) -> SyntaxKind {
        switch token.kind {
        case .keyword(.if):
            return .ifExpr
        case .keyword(.when):
            return .whenExpr
        case .keyword(.try):
            return .tryExpr
        case .identifier, .backtickedIdentifier:
            return .callExpr
        case .softKeyword:
            return .callExpr
        default:
            return .statement
        }
    }

    internal func resolveStatementKind(_ candidate: SyntaxKind, children: [SyntaxChild]) -> SyntaxKind {
        switch candidate {
        case .ifExpr, .whenExpr, .tryExpr:
            return candidate
        case .callExpr:
            for child in children {
                if case .node(let childID) = child,
                   arena.node(childID).kind == .block {
                    return .callExpr
                }
                if case .token(let tokenID) = child {
                    let index = Int(tokenID.rawValue)
                    if index >= 0 && index < arena.tokens.count {
                        let token = arena.tokens[index]
                        if token.kind == .symbol(.lParen) {
                            return .callExpr
                        }
                    }
                }
            }
            return .statement
        default:
            return .statement
        }
    }

    internal func parseLoopStatement(inBlock: Bool) -> NodeID {
        _ = inBlock
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        let loopToken = consumeToken(into: &children, range: &range)

        switch loopToken.kind {
        case .keyword(.for), .keyword(.while):
            if case .symbol(.lParen) = stream.peek().kind {
                let header = parseBalancedGroup(opening: .lParen, closing: .rParen)
                children.append(.node(header))
                range.append(arena.node(header).range)
            }
            appendLoopBody(into: &children, range: &range)

        case .keyword(.do):
            appendLoopBody(into: &children, range: &range)
            if case .keyword(.while) = stream.peek().kind {
                _ = consumeToken(into: &children, range: &range)
                if case .symbol(.lParen) = stream.peek().kind {
                    let condition = parseBalancedGroup(opening: .lParen, closing: .rParen)
                    children.append(.node(condition))
                    range.append(arena.node(condition).range)
                }
            }

        default:
            break
        }

        return arena.appendNode(kind: .loopStmt, range: range.value ?? invalidRange, children)
    }

    internal func appendLoopBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if case .symbol(.lBrace) = stream.peek().kind {
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
            return
        }
        let before = stream.index
        let body = parseStatement(inBlock: true)
        children.append(.node(body))
        range.append(arena.node(body).range)
        if stream.index == before, !stream.atEOF() {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    internal func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.dot), .symbol(.comma), .symbol(.questionDot), .symbol(.questionQuestion),
             .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash),
             .symbol(.equalEqual), .symbol(.assign), .symbol(.arrow),
             .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace):
            return false
        default:
            return true
        }
    }

    internal enum StatementTailStatus {
        case noProgress
        case canContinue
    }

    internal func parseStatementTail(inBlock: Bool) -> StatementTailStatus {
        let token = stream.peek()
        if shouldStopStatementBefore(token, inBlock: inBlock) {
            return .noProgress
        }
        if case .symbol(.semicolon) = token.kind {
            return .canContinue
        }
        return .canContinue
    }

    internal func parseTail(inBlock: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var progress = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                children.append(.node(parseBlock()))
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind {
                children.append(.node(parseBlock()))
                break
            }
            _ = consumeToken(into: &children, range: &range)
            progress = true
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                break
            }
        }
        if !progress, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
    }
}
