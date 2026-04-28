import Foundation

extension BuildASTPhase {
    func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        let directTokens = collectDirectTokens(from: nodeID, in: arena)
        let hasExpressionBody: Bool = {
            var depth = BracketDepth()
            for token in directTokens {
                if token.kind == .symbol(.assign), depth.isAtTopLevel {
                    return true
                }
                if token.kind == .symbol(.lBrace), depth.isAtTopLevel {
                    return false
                }
                depth.track(token.kind)
            }
            return false
        }()

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
        // Phase 1 – gather per-CST-statement token arrays, merging
        // dot-continuation lines into the previous group.
        // The Kotlin CST parser may split `expr\n  .member()` into
        // separate statement nodes, but `.member()` is a continuation
        // of the previous expression, not a standalone statement.
        var rawGroups: [[Token]] = []
        var filteredGroups: [[Token]] = []
        collectBlockStatementGroups(from: blockNodeID, in: arena,
                                    rawGroups: &rawGroups, filteredGroups: &filteredGroups)

        // Phase 2 – parse each (potentially merged) token group.
        var result: [ExprID] = []
        for idx in rawGroups.indices {
            if let exprID = parseStatementGroup(
                raw: rawGroups[idx], filtered: filteredGroups[idx],
                interner: interner, astArena: astArena
            ) {
                result.append(exprID)
            }
        }
        return result
    }

    /// Collect token groups from CST block children, merging dot-continuation
    /// lines (`.member()`) into the previous statement group.
    private func collectBlockStatementGroups(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        rawGroups: inout [[Token]],
        filteredGroups: inout [[Token]]
    ) {
        for child in arena.children(of: blockNodeID) {
            guard case let .node(nodeID) = child else { continue }
            let node = arena.node(nodeID)
            guard isStatementLikeKind(node.kind) else { continue }

            let rawTokens = collectTokens(from: nodeID, in: arena)
            // Strip only top-level semicolons; keep semicolons inside braces so
            // that nested block expressions (e.g. `if (c) { a; b }`) can still
            // split on them later in ExpressionParser.
            let filtered = filterTopLevelSemicolons(rawTokens)
            guard !filtered.isEmpty else { continue }

            // If the first token is `.` or `?.`, merge into the previous group.
            let isDotContinuation = filtered.first.map {
                $0.kind == .symbol(.dot) || $0.kind == .symbol(.questionDot)
            } ?? false
            let shouldMergeWithPrevious: Bool
            if !rawGroups.isEmpty {
                let previousFiltered = filteredGroups[filteredGroups.count - 1]
                let previousEndsWithContinuation = previousFiltered.last.map {
                    Self.isBinaryOperatorToken($0.kind)
                        || $0.kind == .symbol(.lParen)
                        || $0.kind == .symbol(.comma)
                } ?? false
                let currentStartsWithContinuation = filtered.first.map {
                    Self.isBinaryOperatorToken($0.kind)
                        || $0.kind == .symbol(.comma)
                        || $0.kind == .symbol(.rParen)
                        || $0.kind == .symbol(.rBracket)
                } ?? false
                shouldMergeWithPrevious = isDotContinuation
                    || previousEndsWithContinuation
                    || currentStartsWithContinuation
                    || startsWithTrailingLambdaGroup(filtered)
                        && Self.canAcceptTrailingLambda(on: previousFiltered)
                    || hasUnclosedStatementDelimiter(previousFiltered)
            } else {
                shouldMergeWithPrevious = false
            }
            if shouldMergeWithPrevious {
                rawGroups[rawGroups.count - 1].append(contentsOf: rawTokens)
                filteredGroups[filteredGroups.count - 1].append(contentsOf: filtered)
                continue
            }

            rawGroups.append(rawTokens)
            filteredGroups.append(filtered)
        }
    }

    /// Filter out semicolons that are at the outermost brace level,
    /// preserving those inside nested braces (e.g. lambda bodies).
    private func filterTopLevelSemicolons(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var braceDepth = 0
        for token in tokens {
            switch token.kind {
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
            if token.kind == .symbol(.semicolon), braceDepth == 0 {
                continue
            }
            result.append(token)
        }
        return result
    }

    private func hasUnclosedStatementDelimiter(_ tokens: [Token]) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for token in tokens {
            switch token.kind {
            case .symbol(.lParen): parenDepth += 1
            case .symbol(.rParen): parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket): bracketDepth += 1
            case .symbol(.rBracket): bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
        }
        return parenDepth > 0 || bracketDepth > 0 || braceDepth > 0
    }

    private func startsWithTrailingLambdaGroup(_ tokens: [Token]) -> Bool {
        tokens.first?.kind == .symbol(.lBrace)
    }

    static func canAcceptTrailingLambda<C: BidirectionalCollection>(on tokens: C) -> Bool where C.Element == Token {
        guard let last = tokens.last else {
            return false
        }
        if let first = tokens.first,
           case let .keyword(keyword) = first.kind,
           [.if, .for, .while, .do, .when, .try, .catch, .finally].contains(keyword)
        {
            return false
        }
        switch last.kind {
        case .identifier, .backtickedIdentifier, .softKeyword, .keyword:
            return true
        case .symbol(.rParen), .symbol(.rBracket), .symbol(.greaterThan), .symbol(.bangBang):
            return true
        default:
            return false
        }
    }

    /// Parse a single (possibly merged) statement token group, trying local
    /// fun-decl, local-decl, local-assign, then generic expression.
    private func parseStatementGroup(
        raw: [Token],
        filtered: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        if let expr = parseLocalFunDeclExpr(from: raw, interner: interner, astArena: astArena) {
            return expr
        }
        if let expr = parseLocalDeclarationExpr(from: filtered, interner: interner, astArena: astArena) {
            return expr
        }
        if let expr = parseLocalAssignmentExpr(from: filtered, interner: interner, astArena: astArena) {
            return expr
        }
        let parser = ExpressionParser(tokens: filtered, interner: interner, astArena: astArena)
        return parser.parse()
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
                    let lastIsContinuation = current.last.map { Self.isBinaryOperatorToken($0.kind) } ?? false
                    let nextIsContinuation = Self.isBinaryOperatorToken(token.kind)
                    let nextIsTrailingLambda = token.kind == .symbol(.lBrace) && Self.canAcceptTrailingLambda(on: current)
                    if !lastIsContinuation, !nextIsContinuation, !nextIsTrailingLambda {
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

    static func isBinaryOperatorToken(_ kind: TokenKind) -> Bool {
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

    // MARK: - Annotation Parsing

    // Extracts annotation nodes from the leading tokens of a declaration CST node.
    // Annotations appear as `@Name` or `@Name(args)` tokens before the declaration
    // keyword (class, fun, val, var, etc.).  Also handles use-site targets like
    // `@get:Name` or `@field:Name(args)`.
    func declarationAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        let tokens = collectTokens(from: nodeID, in: arena)
        var annotations: [AnnotationNode] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            // Stop scanning when we hit the declaration introducer keyword
            // (`class`, `fun`, `val`, ...). Modifiers may appear before/after
            // annotations, so they must not terminate the scan.
            if isDeclarationStart(token.kind) {
                break
            }
            guard token.kind == .symbol(.at) else {
                index += 1
                continue
            }
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: tokens,
                start: index,
                interner: interner,
                allowUseSiteTarget: true
            ) else {
                index += 1
                continue
            }
            annotations.append(parsed.annotation)
            index = parsed.nextIndex
        }
        return annotations
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
}
