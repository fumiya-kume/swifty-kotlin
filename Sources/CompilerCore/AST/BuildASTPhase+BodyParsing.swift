import Foundation

extension BuildASTPhase {
    func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        let directTokens = collectDirectTokens(from: nodeID, in: arena)
        let hasExpressionBody = directTokens.contains(where: { token in
            token.kind == .symbol(.assign)
        })

        if !hasExpressionBody {
            for child in arena.children(of: nodeID) {
                if case .node(let childID) = child, arena.node(childID).kind == .block {
                    let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                    return .block(exprs, arena.node(childID).range)
                }
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex else {
            return .unit
        }

        let bodyStartIndex = assignIndex + 1
        if bodyStartIndex >= tokens.count {
            return .unit
        }
        let exprTokens = tokens[bodyStartIndex...]
        let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
        guard let exprID = parser.parse() else {
            return .unit
        }
        guard let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    func blockExpressions(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ExprID] {
        var result: [ExprID] = []
        for child in arena.children(of: blockNodeID) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = arena.node(nodeID)
            guard isStatementLikeKind(node.kind) else {
                continue
            }

            // CST-aware fast path: for structured control flow nodes,
            // skip local decl/assign probing and parse directly as expressions.
            if isControlFlowExprKind(node.kind) {
                let rawTokens = collectTokens(from: nodeID, in: arena)
                let statementTokens = rawTokens.filter { token in
                    token.kind != .symbol(.semicolon)
                }
                guard !statementTokens.isEmpty else {
                    continue
                }
                let parser = ExpressionParser(tokens: statementTokens, interner: interner, astArena: astArena)
                if let exprID = parser.parse() {
                    result.append(exprID)
                }
                continue
            }

            let rawTokens = collectTokens(from: nodeID, in: arena)
            let statementTokens = rawTokens.filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !statementTokens.isEmpty else {
                continue
            }
            if let localFunDeclExpr = parseLocalFunDeclExpr(
                from: rawTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localFunDeclExpr)
                continue
            }
            if let localDeclExpr = parseLocalDeclarationExpr(
                from: statementTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localDeclExpr)
                continue
            }
            if let localAssignExpr = parseLocalAssignmentExpr(
                from: statementTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localAssignExpr)
                continue
            }
            let parser = ExpressionParser(tokens: statementTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse() {
                result.append(exprID)
            }
        }
        return result
    }

    func splitTokensIntoStatements(_ tokens: [Token]) -> [[Token]] {
        var groups: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for token in tokens {
            if depth.isAtTopLevel {
                if token.kind == .symbol(.semicolon) {
                    if !current.isEmpty {
                        groups.append(current)
                        current = []
                    }
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline && !current.isEmpty {
                    let lastIsContinuation = current.last.map { isBinaryOperatorToken($0.kind) } ?? false
                    let nextIsContinuation = isBinaryOperatorToken(token.kind)
                    if !lastIsContinuation && !nextIsContinuation {
                        groups.append(current)
                        current = []
                    }
                }
            }
            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    func isBinaryOperatorToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash), .symbol(.percent),
             .symbol(.ampAmp), .symbol(.barBar),
             .symbol(.equalEqual), .symbol(.bangEqual),
             .symbol(.lessThan), .symbol(.lessOrEqual), .symbol(.greaterThan), .symbol(.greaterOrEqual),
             .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
             .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
             .symbol(.dotDot), .symbol(.dotDotLt),
             .symbol(.questionQuestion), .symbol(.questionColon),
             .symbol(.dot), .symbol(.questionDot),
             .symbol(.doubleColon),
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        default:
            return false
        }
    }

    func skipBalancedBracket(
        in tokens: [Token],
        from startIndex: Int,
        open: TokenKind,
        close: TokenKind
    ) -> Int {
        guard startIndex < tokens.count, tokens[startIndex].kind == open else {
            return startIndex
        }
        var depth = 0
        var index = startIndex
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == open {
                depth += 1
            } else if kind == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return index
    }

    func resolveToken(_ tokenID: TokenID, in arena: SyntaxArena) -> Token? {
        arena.token(tokenID)
    }

    func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        if let cached = tokenCache[nodeID] {
            return cached
        }
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case .node(let childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        tokenCache[nodeID] = tokens
        return tokens
    }

    func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            guard case .token(let tokenID) = child,
                  let token = resolveToken(tokenID, in: arena) else {
                continue
            }
            tokens.append(token)
        }
        return tokens
    }

    func isStatementLikeKind(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .statement, .propertyDecl, .loopStmt,
             .ifExpr, .whenExpr, .tryExpr, .callExpr,
             .funDecl:
            return true
        default:
            return false
        }
    }

    /// Returns true for SyntaxKind values that represent structured control flow
    /// expressions in the CST. These nodes are parsed directly by the parser with
    /// proper sub-node structure, so the AST builder can skip local decl/assign
    /// probing and parse them directly as expressions.
    func isControlFlowExprKind(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .ifExpr, .whenExpr, .tryExpr, .loopStmt:
            return true
        default:
            return false
        }
    }
}
