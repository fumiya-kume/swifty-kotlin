extension KotlinParser {
    func parseBlock() -> NodeID {
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
            if isDeclarationStart(token.kind), hasLeadingNewline(token) {
                children.append(.node(parseDeclaration()))
            } else if !shouldStopStatementBefore(token, inBlock: true) {
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

    func parseStatement(inBlock: Bool) -> NodeID {
        if isLoopStart(stream.peek().kind) {
            return parseLoopStatement(inBlock: inBlock)
        }

        // Dispatch to dedicated structured parsers for major constructs
        switch stream.peek().kind {
        case .keyword(.if):
            return parseIfStatement(inBlock: inBlock)
        case .keyword(.when):
            return parseWhenStatement(inBlock: inBlock)
        case .keyword(.try):
            return parseTryStatement(inBlock: inBlock)
        default:
            break
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
               shouldSplitStatementOnNewline(token.kind)
            {
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
            range: range.value ?? invalidRange, children
        )
    }

    // MARK: - Structured Control Flow Parsers

    /// Parse a structured `if` expression: `if (condition) then-branch [else else-branch]`
    func parseIfStatement(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        // Consume 'if'
        _ = consumeToken(into: &children, range: &range)

        // Parse condition '(' ... ')'
        if case .symbol(.lParen) = stream.peek().kind {
            let conditionGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
            children.append(.node(conditionGroup))
            range.append(arena.node(conditionGroup).range)
        }

        // Parse then-branch
        appendBranchBody(inBlock: inBlock, into: &children, range: &range, stopBeforeElse: true)

        // Parse optional 'else' branch
        if case .keyword(.else) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            appendBranchBody(inBlock: inBlock, into: &children, range: &range, stopBeforeElse: false)
        }

        return arena.appendNode(kind: .ifExpr, range: range.value ?? invalidRange, children)
    }

    /// Parse a structured `when` expression: `when [(subject)] { branches }`
    func parseWhenStatement(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        // Consume 'when'
        _ = consumeToken(into: &children, range: &range)

        // Parse optional subject '(' ... ')'
        if case .symbol(.lParen) = stream.peek().kind {
            let subjectGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
            children.append(.node(subjectGroup))
            range.append(arena.node(subjectGroup).range)
        }

        // Parse body as a structured when block so branch conditions remain explicit in CST.
        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseWhenBody(inBlock: inBlock)
            children.append(.node(body))
            range.append(arena.node(body).range)
        }

        return arena.appendNode(kind: .whenExpr, range: range.value ?? invalidRange, children)
    }

    /// Parse a structured `try` expression: `try body [catch (params) body]* [finally body]`
    func parseTryStatement(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        // Consume 'try'
        _ = consumeToken(into: &children, range: &range)

        // Parse try body
        appendTryBody(inBlock: inBlock, into: &children, range: &range)

        // Parse catch clauses
        while case .keyword(.catch) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            if case .symbol(.lParen) = stream.peek().kind {
                let paramGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
                children.append(.node(paramGroup))
                range.append(arena.node(paramGroup).range)
            }
            appendTryBody(inBlock: inBlock, into: &children, range: &range)
        }

        // Parse finally clause
        if case .keyword(.finally) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            appendTryBody(inBlock: inBlock, into: &children, range: &range)
        }

        return arena.appendNode(kind: .tryExpr, range: range.value ?? invalidRange, children)
    }

    // MARK: - Branch Body Helpers

    /// Appends a branch body for if/else. Can be a block, a nested control flow,
    /// or a simple inline expression (stops before `else` if requested).
    func appendBranchBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool
    ) {
        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: stopBeforeElse,
            stopBeforeCatchFinally: false,
            stopBeforeTopLevelComma: false
        )
    }

    /// Appends a try/catch/finally body. Can be a block, a nested control flow,
    /// or inline tokens (stops before `catch`/`finally`).
    func appendTryBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: false,
            stopBeforeCatchFinally: true,
            stopBeforeTopLevelComma: false
        )
    }

    /// Appends a control flow body (if/else branch or try/catch/finally body).
    /// Can be a block, nested control flow, or inline tokens.
    private func appendControlFlowBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool,
        stopBeforeCatchFinally: Bool,
        stopBeforeTopLevelComma: Bool
    ) {
        let token = stream.peek()
        switch token.kind {
        case .symbol(.lBrace):
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
        case .keyword(.if):
            let node = parseIfStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.when):
            let node = parseWhenStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.try):
            let node = parseTryStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.for), .keyword(.while), .keyword(.do):
            let node = parseLoopStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        default:
            consumeInlineBody(
                inBlock: inBlock,
                into: &children,
                range: &range,
                stopBeforeElse: stopBeforeElse,
                stopBeforeCatchFinally: stopBeforeCatchFinally,
                stopBeforeTopLevelComma: stopBeforeTopLevelComma
            )
        }
    }

    /// Consume inline tokens for a non-block body of a control flow construct.
    /// Stops at statement boundaries, and optionally before `else` or `catch`/`finally`.
    func consumeInlineBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool,
        stopBeforeCatchFinally: Bool,
        stopBeforeTopLevelComma: Bool
    ) {
        var parenDepth = 0
        var bracketDepth = 0
        let startChildCount = children.count
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: inBlock) { break }
            if stopBeforeElse, parenDepth == 0, bracketDepth == 0,
               token.kind == .keyword(.else) { break }
            if stopBeforeTopLevelComma, parenDepth == 0, bracketDepth == 0,
               token.kind == .symbol(.comma) { break }
            if stopBeforeCatchFinally, parenDepth == 0, bracketDepth == 0 {
                if case .keyword(.catch) = token.kind { break }
                if case .keyword(.finally) = token.kind { break }
            }
            if inBlock,
               children.count > startChildCount,
               parenDepth == 0,
               bracketDepth == 0,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind)
            {
                break
            }

            // Handle nested blocks (e.g. trailing lambdas)
            if case .symbol(.lBrace) = token.kind, inBlock {
                let block = parseBlock()
                children.append(.node(block))
                range.append(arena.node(block).range)
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            switch token.kind {
            case .symbol(.lParen): parenDepth += 1
            case .symbol(.rParen): parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket): bracketDepth += 1
            case .symbol(.rBracket): bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.semicolon): return
            default: break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) { break }
        }
    }

    // MARK: - when Entry Parsing

    private func parseWhenBody(inBlock: Bool) -> NodeID {
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
            if token.kind == .symbol(.semicolon) || token.kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
                continue
            }

            let entry = parseWhenEntry(inBlock: inBlock)
            children.append(.node(entry))
            range.append(arena.node(entry).range)

            while stream.peek().kind == .symbol(.semicolon) || stream.peek().kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
            }
        }

        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    private func parseWhenEntry(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        if stream.peek().kind == .keyword(.else) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            let conditionList = parseWhenConditionList()
            children.append(.node(conditionList))
            range.append(arena.node(conditionList).range)
        }

        consumeIf(
            expected: .symbol(.arrow),
            into: &children,
            range: &range,
            code: "KSWIFTK-PARSE-0010"
        )

        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: false,
            stopBeforeCatchFinally: false,
            stopBeforeTopLevelComma: true
        )

        return arena.appendNode(kind: .whenEntry, range: range.value ?? invalidRange, children)
    }

    private func parseWhenConditionList() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .symbol(.arrow) || token.kind == .symbol(.rBrace) {
                break
            }

            let condition = parseWhenCondition()
            children.append(.node(condition))
            range.append(arena.node(condition).range)

            if stream.peek().kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
                if stream.peek().kind == .symbol(.arrow) {
                    break
                }
                continue
            }
            break
        }

        return arena.appendNode(kind: .whenConditionList, range: range.value ?? invalidRange, children)
    }

    private func parseWhenCondition() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var parenDepth = 0
        var bracketDepth = 0

        while !stream.atEOF() {
            let token = stream.peek()
            if parenDepth == 0, bracketDepth == 0 {
                if token.kind == .symbol(.comma) || token.kind == .symbol(.arrow) || token.kind == .symbol(.rBrace) {
                    break
                }
                if hasLeadingNewline(token), !children.isEmpty {
                    break
                }
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
        }

        if children.isEmpty {
            insertMissingToken(
                expected: .identifier(.invalid),
                into: &children,
                range: &range,
                code: "KSWIFTK-PARSE-0011",
                message: "Expected when branch condition."
            )
        }

        return arena.appendNode(kind: .whenCondition, range: range.value ?? invalidRange, children)
    }

    // MARK: - Statement Classification (for non-dispatched cases)

    func classifyStatementLeadingToken(_ token: Token) -> SyntaxKind {
        switch token.kind {
        case .keyword(.if):
            .ifExpr
        case .keyword(.when):
            .whenExpr
        case .keyword(.try):
            .tryExpr
        case .identifier, .backtickedIdentifier:
            .callExpr
        case .softKeyword:
            .callExpr
        default:
            .statement
        }
    }

    func resolveStatementKind(_ candidate: SyntaxKind, children: [SyntaxChild]) -> SyntaxKind {
        switch candidate {
        case .ifExpr, .whenExpr, .tryExpr:
            return candidate
        case .callExpr:
            for child in children {
                if case let .node(childID) = child,
                   arena.node(childID).kind == .block
                {
                    return .callExpr
                }
                if case let .token(tokenID) = child,
                   let token = arena.token(tokenID),
                   token.kind == .symbol(.lParen)
                {
                    return .callExpr
                }
            }
            return .statement
        default:
            return .statement
        }
    }

    // MARK: - Loop Parsing

    func parseLoopStatement(inBlock: Bool) -> NodeID {
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
            appendDoWhileBody(into: &children, range: &range)
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

    func appendLoopBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
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

    /// Appends a `do` loop body while keeping the trailing `while (...)`
    /// condition outside of the body node.
    func appendDoWhileBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if case .symbol(.lBrace) = stream.peek().kind {
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
            return
        }

        var bodyChildren: [SyntaxChild] = []
        var bodyRange = RangeAccumulator()
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if atTopLevel, !bodyChildren.isEmpty,
               token.kind == .keyword(.while)
            {
                break
            }
            if shouldStopStatementBefore(token, inBlock: true) {
                break
            }
            if atTopLevel,
               !bodyChildren.isEmpty,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind)
            {
                break
            }

            _ = consumeToken(into: &bodyChildren, range: &bodyRange)
            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if token.kind == .symbol(.semicolon), atTopLevel {
                break
            }
        }

        if bodyChildren.isEmpty {
            let before = stream.index
            let body = parseStatement(inBlock: true)
            children.append(.node(body))
            range.append(arena.node(body).range)
            if stream.index == before, !stream.atEOF() {
                _ = consumeToken(into: &children, range: &range)
            }
            return
        }

        let bodyNode = arena.appendNode(
            kind: .statement,
            range: bodyRange.value ?? invalidRange,
            bodyChildren
        )
        children.append(.node(bodyNode))
        range.append(arena.node(bodyNode).range)
    }

    func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        ParserBoundaryPolicy.shouldSplitStatementOnNewline(kind)
    }

    func parseTail(inBlock: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var progress = false
        var sawTryKeyword = false
        var groupingDepth = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if groupingDepth == 0, shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                let blockID = parseBlock()
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind {
                let blockID = parseBlock()
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                // Continue if next token is catch/finally (try expression continuation)
                if sawTryKeyword {
                    let nextAfterBlock = stream.peek()
                    if case .keyword(.catch) = nextAfterBlock.kind { continue }
                    if case .keyword(.finally) = nextAfterBlock.kind { continue }
                }
                break
            }
            if case .keyword(.try) = token.kind {
                sawTryKeyword = true
            }
            _ = consumeToken(into: &children, range: &range)
            progress = true
            switch token.kind {
            case .symbol(.lParen), .symbol(.lBracket):
                groupingDepth += 1
            case .symbol(.rParen), .symbol(.rBracket):
                groupingDepth = max(0, groupingDepth - 1)
            default:
                break
            }
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                if groupingDepth > 0 {
                    continue
                }
                // After `=`, continue consuming across newlines so that
                // expression bodies like `= \n try { ... } catch { ... }` are
                // captured in the same declaration node.
                if case .symbol(.assign) = token.kind {
                    // But stop if the next line starts a new declaration
                    // (modifier keyword, declaration keyword, or annotation).
                    let nextToken = stream.peek()
                    if case let .keyword(kw) = nextToken.kind,
                       Self.isDeclarationModifierKeyword(kw)
                    {
                        break
                    }
                    if isDeclarationStart(nextToken.kind) {
                        break
                    }
                    continue
                }
                break
            }
        }
        if !progress, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
    }
}
