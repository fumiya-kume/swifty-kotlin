import Foundation

extension BuildASTPhase.ExpressionParser {
    internal func parseBlockExpression() -> ExprID? {
        guard let openBrace = consume() else {
            return nil
        }
        var depth = 1
        var blockTokens: [Token] = []
        var end = openBrace.range.end

        while let token = current() {
            _ = consume()
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
                blockTokens.append(token)
            case .symbol(.rBrace):
                depth -= 1
                if depth == 0 {
                    end = token.range.end
                    break
                }
                blockTokens.append(token)
            default:
                blockTokens.append(token)
            }
            if depth == 0 {
                break
            }
        }

        let statementGroups = splitBlockTokensIntoStatements(blockTokens)
        if statementGroups.isEmpty {
            let range = SourceRange(start: openBrace.range.start, end: end)
            return astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: range))
        }
        if statementGroups.count == 1 {
            let tokens = statementGroups[0]
            if !isLocalDeclarationTokens(tokens) && !isLocalAssignmentTokens(tokens) {
                if let nestedExpr = BuildASTPhase.ExpressionParser(tokens: tokens, interner: interner, astArena: astArena).parse() {
                    return nestedExpr
                }
            }
        }

        var statements: [ExprID] = []
        for group in statementGroups {
            guard !group.isEmpty else { continue }
            if let localDecl = parseLocalDeclFromTokens(group) {
                statements.append(localDecl)
            } else if let localAssign = parseLocalAssignFromTokens(group) {
                statements.append(localAssign)
            } else if let expr = BuildASTPhase.ExpressionParser(tokens: group, interner: interner, astArena: astArena).parse() {
                statements.append(expr)
            }
        }

        var trailingExpr: ExprID?
        if let lastID = statements.last, let lastExpr = astArena.expr(lastID) {
            switch lastExpr {
            case .localDecl, .localAssign, .compoundAssign, .localFunDecl:
                break
            default:
                trailingExpr = statements.removeLast()
            }
        }

        let range = SourceRange(start: openBrace.range.start, end: end)
        return astArena.appendExpr(.blockExpr(statements: statements, trailingExpr: trailingExpr, range: range))
    }

    internal func splitBlockTokensIntoStatements(_ tokens: [Token]) -> [[Token]] {
        var groups: [[Token]] = []
        var current: [Token] = []
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for token in tokens {
            let isTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if isTopLevel {
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
                    let lastIsContinuation = current.last.map { isBinaryOperatorTokenKind($0.kind) } ?? false
                    let nextIsContinuation = isBinaryOperatorTokenKind(token.kind)
                    if !lastIsContinuation && !nextIsContinuation {
                        groups.append(current)
                        current = []
                    }
                }
            }
            switch token.kind {
            case .symbol(.lParen):    parenDepth += 1
            case .symbol(.rParen):    parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):  bracketDepth += 1
            case .symbol(.rBracket):  bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):    braceDepth += 1
            case .symbol(.rBrace):    braceDepth = max(0, braceDepth - 1)
            default: break
            }
            current.append(token)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    internal func isBinaryOperatorTokenKind(_ kind: TokenKind) -> Bool {
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
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        default:
            return false
        }
    }

    internal func isLocalDeclarationTokens(_ tokens: [Token]) -> Bool {
        guard !tokens.isEmpty else { return false }
        var i = 0
        while i < tokens.count {
            if case .keyword(let kw) = tokens[i].kind,
               KotlinParser.isDeclarationModifierKeyword(kw) {
                i += 1
                continue
            }
            break
        }
        guard i < tokens.count else { return false }
        switch tokens[i].kind {
        case .keyword(.val), .keyword(.var):
            return true
        default:
            return false
        }
    }

    internal func isLocalAssignmentTokens(_ tokens: [Token]) -> Bool {
        guard tokens.count >= 3 else { return false }
        var depth = BuildASTPhase.BracketDepth()
        for token in tokens {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                return true
            }
            depth.track(token.kind)
        }
        return false
    }

    internal func parseLocalDeclFromTokens(_ tokens: [Token]) -> ExprID? {
        guard !tokens.isEmpty else { return nil }
        var startIndex = 0
        while startIndex < tokens.count {
            if case .keyword(let kw) = tokens[startIndex].kind,
               KotlinParser.isDeclarationModifierKeyword(kw) {
                startIndex += 1
                continue
            }
            break
        }
        guard startIndex < tokens.count else { return nil }
        let head = tokens[startIndex]
        let isMutable: Bool
        switch head.kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        let nameToken = tokens.dropFirst(startIndex + 1).first(where: { token in
            switch token.kind {
            case .identifier, .backtickedIdentifier:
                return true
            default:
                return false
            }
        })
        guard let nameToken, let name = tokenText(nameToken) else {
            return nil
        }

        var assignIndex: Int?
        var depth = BuildASTPhase.BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex else { return nil }
        let initializerTokens = Array(tokens[(assignIndex + 1)...])
        guard !initializerTokens.isEmpty else { return nil }
        let parser = BuildASTPhase.ExpressionParser(tokens: initializerTokens, interner: interner, astArena: astArena)
        guard let initializerExpr = parser.parse() else { return nil }
        let rangeEnd = astArena.exprRange(initializerExpr)?.end ?? tokens.last?.range.end ?? head.range.end
        let range = SourceRange(start: tokens[0].range.start, end: rangeEnd)
        return astArena.appendExpr(.localDecl(
            name: name,
            isMutable: isMutable,
            typeAnnotation: nil,
            initializer: initializerExpr,
            range: range
        ))
    }

    internal func parseLocalAssignFromTokens(_ tokens: [Token]) -> ExprID? {
        guard tokens.count >= 3 else { return nil }
        var assignIndex: Int?
        var depth = BuildASTPhase.BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex, assignIndex > 0 else { return nil }
        let lhsTokens = Array(tokens[..<assignIndex])
        guard lhsTokens.count == 1, let name = tokenText(lhsTokens[0]) else {
            return nil
        }
        let valueTokens = Array(tokens[(assignIndex + 1)...])
        guard !valueTokens.isEmpty else { return nil }
        let parser = BuildASTPhase.ExpressionParser(tokens: Array(valueTokens), interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else { return nil }
        let rangeEnd = astArena.exprRange(valueExpr)?.end ?? tokens.last?.range.end ?? lhsTokens[0].range.end
        let range = SourceRange(start: tokens[0].range.start, end: rangeEnd)
        return astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))
    }

    internal func skipBalancedParenthesisIfNeeded() {
        guard matches(.symbol(.lParen)) else {
            return
        }
        _ = consume()
        var depth = 1
        while let token = current(), depth > 0 {
            _ = consume()
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
            default:
                continue
            }
        }
    }
}
