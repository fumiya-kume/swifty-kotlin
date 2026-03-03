// swiftlint:disable file_length
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
                if case let .node(childID) = child, arena.node(childID).kind == .block {
                    let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                    return .block(exprs, arena.node(childID).range)
                }
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
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
            guard case let .node(nodeID) = child else {
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
                if hasNewline, !current.isEmpty {
                    let lastIsContinuation = current.last.map { isBinaryOperatorToken($0.kind) } ?? false
                    let nextIsContinuation = isBinaryOperatorToken(token.kind)
                    if !lastIsContinuation, !nextIsContinuation {
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
            true
        default:
            false
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
            case let .token(tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case let .node(childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        tokenCache[nodeID] = tokens
        return tokens
    }

    func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            guard case let .token(tokenID) = child,
                  let token = resolveToken(tokenID, in: arena)
            else {
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
            true
        default:
            false
        }
    }

    /// Returns true for SyntaxKind values that represent structured control flow
    /// expressions in the CST. These nodes are parsed directly by the parser with
    /// proper sub-node structure, so the AST builder can skip local decl/assign
    /// probing and parse them directly as expressions.
    func isControlFlowExprKind(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .ifExpr, .whenExpr, .tryExpr, .loopStmt:
            true
        default:
            false
        }
    }

    // MARK: - Annotation Parsing

    // Extracts annotation nodes from the leading tokens of a declaration CST node.
    // Annotations appear as `@Name` or `@Name(args)` tokens before the declaration
    // keyword (class, fun, val, var, etc.).  Also handles use-site targets like
    // `@get:Name` or `@field:Name(args)`.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func declarationAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        let tokens = collectTokens(from: nodeID, in: arena)
        var annotations: [AnnotationNode] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            // Stop scanning when we hit a declaration keyword — annotations are before these.
            if isLeadingDeclarationKeyword(token) || isDeclarationStart(token.kind) {
                break
            }
            guard token.kind == .symbol(.at) else {
                index += 1
                continue
            }
            // We have '@'; the next token(s) form the annotation name.
            index += 1
            guard index < tokens.count else { break }

            // Check for use-site target: `@get:`, `@set:`, `@field:`, `@param:`, etc.
            var useSiteTarget: String?
            if index + 1 < tokens.count, tokens[index + 1].kind == .symbol(.colon) {
                let candidate = tokens[index]
                if let candidateName = tokenText(candidate, interner: interner) {
                    let knownTargets: Set<String> = [
                        "get", "set", "field", "param", "setparam",
                        "delegate", "property", "receiver", "file", // swiftlint:disable:this trailing_comma
                    ]
                    if knownTargets.contains(candidateName) {
                        useSiteTarget = candidateName
                        index += 2 // skip target name and colon
                    }
                }
            }

            guard index < tokens.count else { break }
            // Extract the annotation name (may be qualified: `kotlin.Deprecated`)
            var nameParts: [String] = []
            if let firstPart = tokenText(tokens[index], interner: interner) {
                nameParts.append(firstPart)
                index += 1
                // Handle qualified names like `kotlin.jvm.JvmStatic`
                while index + 1 < tokens.count,
                      tokens[index].kind == .symbol(.dot),
                      let nextPart = tokenText(tokens[index + 1], interner: interner)
                { // swiftlint:disable:this opening_brace
                    nameParts.append(nextPart)
                    index += 2
                }
            } else {
                index += 1
                continue
            }
            let annotationName = nameParts.joined(separator: ".")

            // Parse optional argument list: `(arg1, arg2, ...)`
            var arguments: [String] = []
            if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
                index += 1 // skip '('
                var depth = 1
                var currentArg: [String] = []
                while index < tokens.count, depth > 0 {
                    let argToken = tokens[index]
                    if argToken.kind == .symbol(.lParen) {
                        depth += 1
                        currentArg.append("(")
                    } else if argToken.kind == .symbol(.rParen) {
                        depth -= 1
                        if depth == 0 {
                            let trimmed = currentArg.joined().trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                arguments.append(trimmed)
                            }
                        } else {
                            currentArg.append(")")
                        }
                    } else if argToken.kind == .symbol(.comma), depth == 1 {
                        let trimmed = currentArg.joined().trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            arguments.append(trimmed)
                        }
                        currentArg = []
                    } else if let text = tokenText(argToken, interner: interner) {
                        currentArg.append(text)
                    } else {
                        // For string literals and other tokens, extract their raw text
                        currentArg.append(tokenRawText(argToken, interner: interner))
                    }
                    index += 1
                }
            }

            annotations.append(AnnotationNode(
                name: annotationName,
                arguments: arguments,
                useSiteTarget: useSiteTarget
            ))
        }
        return annotations
    }

    /// Returns the text representation of a token for annotation parsing.
    private func tokenText(_ token: Token, interner: StringInterner) -> String? {
        switch token.kind {
        case let .identifier(interned):
            interner.resolve(interned)
        case let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        default:
            nil
        }
    }

    // Returns a raw text representation for any token, used for annotation argument parsing.
    // swiftlint:disable:next cyclomatic_complexity
    private func tokenRawText(_ token: Token, interner: StringInterner) -> String {
        switch token.kind {
        case let .identifier(interned), let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        case let .stringSegment(interned):
            "\"\(interner.resolve(interned))\""
        case .stringQuote:
            "\""
        case let .intLiteral(value):
            "\(value)"
        case let .longLiteral(value):
            "\(value)"
        case let .floatLiteral(value):
            "\(value)"
        case let .doubleLiteral(value):
            "\(value)"
        case let .charLiteral(value):
            "'\(value)'"
        case .keyword(.true):
            "true"
        case .keyword(.false):
            "false"
        case .symbol(.assign):
            "="
        case .symbol(.dot):
            "."
        default:
            ""
        }
    }

    /// Checks if a token represents a declaration start keyword.
    private func isDeclarationStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.class), .keyword(.object), .keyword(.interface),
             .keyword(.fun), .keyword(.val), .keyword(.var),
             .keyword(.typealias), .keyword(.enum), .keyword(.companion):
            true
        default:
            false
        }
    }

    /// Checks if a token is a leading declaration keyword (modifier or declaration start).
    private func isLeadingDeclarationKeyword(_ token: Token) -> Bool {
        guard case let .keyword(keyword) = token.kind else {
            return false
        }
        return isLeadingDeclarationKeyword(keyword)
    }
}
