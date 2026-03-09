extension KotlinParser {
    func parseTypeArguments() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = 1

        guard consumeIfSymbol(.lessThan, into: &children, range: &range) else {
            return arena.appendNode(
                kind: .typeArgs,
                range: range.value ?? invalidRange,
                []
            )
        }

        while !stream.atEOF(), depth > 0 {
            let next = stream.peek()
            if depth == 1, hasLeadingNewline(next), isLikelyTopLevelDeclarationStart(next) {
                break
            }

            let token = consumeToken(into: &children, range: &range)
            if token.kind == .eof {
                break
            }

            switch token.kind {
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    return arena.appendNode(kind: .typeArgs, range: range.value ?? invalidRange, children)
                }
            default:
                break
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0005",
            "Unterminated '<' type argument list.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.appendNode(
            kind: .typeArgs,
            range: range.value ?? invalidRange,
            children
        )
    }

    func canStartTypeArgumentsInternal(hasAnchorToken: Bool) -> Bool {
        guard hasAnchorToken else { return false }
        guard case .symbol(.lessThan) = stream.peek().kind else { return false }

        var depth = 1
        var projectionExpected = true
        var sawProjection = false

        for lookahead in 1 ... 32 {
            let token = stream.peek(lookahead)
            switch token.kind {
            case .eof:
                return depth == 1 && sawProjection && !projectionExpected
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    if projectionExpected { return false }
                    return followsTypeArgs(stream.peek(lookahead + 1))
                }
            case .symbol(.comma):
                if depth == 1 {
                    if !sawProjection { return false }
                    projectionExpected = true
                }
            case .identifier, .backtickedIdentifier:
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                }
            case .symbol(.star):
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                }
            case .keyword(.in), .softKeyword(.out):
                if depth == 1, projectionExpected {
                    break
                }
                if depth == 1 {
                    projectionExpected = true
                }
            case .symbol(.dot), .symbol(.question), .symbol(.questionDot),
                 .symbol(.doubleColon), .symbol(.colon):
                if depth == 1, projectionExpected {
                    return false
                }
            default:
                if depth == 0 {
                    return false
                }
            }
        }

        return false
    }

    func followsTypeArgs(_ token: Token) -> Bool {
        switch token.kind {
        case .symbol(.lParen), .symbol(.dot), .symbol(.questionDot), .symbol(.bangBang),
             .symbol(.doubleColon), .symbol(.lessThan), .symbol(.colon), .symbol(.comma),
             .symbol(.lBrace), .symbol(.rParen), .symbol(.rBrace), .symbol(.question),
             .symbol(.assign):
            true
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            true
        case .eof:
            true
        default:
            false
        }
    }

    public func canStartTypeArguments(after token: Token) -> Bool {
        _ = token
        return canStartTypeArgumentsInternal(hasAnchorToken: true)
    }

    public func canStartTypeArguments(after node: NodeID) -> Bool {
        guard Int(node.rawValue) >= 0, Int(node.rawValue) < arena.nodes.count else { return false }
        let nodeKind = arena.node(node).kind
        if case .typeArgs = nodeKind {
            return false
        }
        return canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil)
    }
}
