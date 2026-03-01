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

        let ranges = splitBlockTokensIntoStatementRanges(blockTokens)
        if ranges.isEmpty {
            let range = SourceRange(start: openBrace.range.start, end: end)
            return astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: range))
        }

        var statements: [ExprID] = []
        let allTokens = blockTokens[...]
        for (start, rangeEnd) in ranges {
            let group = allTokens[start..<rangeEnd]
            guard !group.isEmpty else { continue }
            if let localDecl = parseLocalDeclFromSlice(group) {
                statements.append(localDecl)
            } else if let localAssign = parseLocalAssignFromSlice(group) {
                statements.append(localAssign)
            } else if let expr = BuildASTPhase.ExpressionParser(tokens: group, interner: interner, astArena: astArena).parse() {
                statements.append(expr)
            }
        }

        var trailingExpr: ExprID?
        if let lastID = statements.last, let lastExpr = astArena.expr(lastID) {
            switch lastExpr {
            case .localDecl, .localAssign, .memberAssign, .indexedAssign, .compoundAssign, .indexedCompoundAssign, .localFunDecl:
                break
            default:
                trailingExpr = statements.removeLast()
            }
        }

        let range = SourceRange(start: openBrace.range.start, end: end)
        return astArena.appendExpr(.blockExpr(statements: statements, trailingExpr: trailingExpr, range: range))
    }

    /// Returns statement boundary ranges as `(startIndex, endIndex)` pairs into `tokens`.
    internal func splitBlockTokensIntoStatementRanges(_ tokens: [Token]) -> [(Int, Int)] {
        var ranges: [(Int, Int)] = []
        var groupStart = 0
        var lastTokenIndex = -1
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for (idx, token) in tokens.enumerated() {
            let isTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if isTopLevel {
                if token.kind == .symbol(.semicolon) {
                    if lastTokenIndex >= groupStart {
                        ranges.append((groupStart, lastTokenIndex + 1))
                    }
                    groupStart = idx + 1
                    switch token.kind {
                    case .symbol(.lParen):    parenDepth += 1
                    case .symbol(.rParen):    parenDepth = max(0, parenDepth - 1)
                    case .symbol(.lBracket):  bracketDepth += 1
                    case .symbol(.rBracket):  bracketDepth = max(0, bracketDepth - 1)
                    case .symbol(.lBrace):    braceDepth += 1
                    case .symbol(.rBrace):    braceDepth = max(0, braceDepth - 1)
                    default: break
                    }
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline && lastTokenIndex >= groupStart {
                    let lastKind = tokens[lastTokenIndex].kind
                    let lastIsContinuation = isBinaryOperatorTokenKind(lastKind)
                    let nextIsContinuation = isBinaryOperatorTokenKind(token.kind)
                    if !lastIsContinuation && !nextIsContinuation {
                        ranges.append((groupStart, lastTokenIndex + 1))
                        groupStart = idx
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
            lastTokenIndex = idx
        }
        if lastTokenIndex >= groupStart {
            ranges.append((groupStart, lastTokenIndex + 1))
        }
        return ranges
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
             .symbol(.doubleColon),
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        default:
            return false
        }
    }

    internal func isLocalDeclarationTokens(_ tokens: [Token]) -> Bool {
        BuildASTPhase.LocalStatementCore.isLocalDeclarationTokens(tokens)
    }

    internal func isLocalAssignmentTokens(_ tokens: [Token]) -> Bool {
        BuildASTPhase.LocalStatementCore.isLocalAssignmentTokens(tokens)
    }

    internal func parseLocalDeclFromTokens(_ tokens: [Token]) -> ExprID? {
        parseLocalDeclFromSlice(tokens[...])
    }

    internal func parseLocalDeclFromSlice(_ tokens: ArraySlice<Token>) -> ExprID? {
        let interner = self.interner
        let astArena = self.astArena
        let context = BuildASTPhase.LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { slice in
                BuildASTPhase.ExpressionParser(tokens: slice, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { typeTokens in
                guard let first = typeTokens.first else {
                    return nil
                }
                let parser = BuildASTPhase.ExpressionParser(
                    tokens: typeTokens,
                    interner: interner,
                    astArena: astArena
                )
                return parser.parseTypeReference(first.range)
            },
            resolveDeclarationName: { token, _ in
                switch token.kind {
                case .identifier(let name), .backtickedIdentifier(let name):
                    return name
                default:
                    return nil
                }
            }
        )
        return BuildASTPhase.LocalStatementCore.parseLocalDeclaration(
            from: tokens,
            context: context,
            options: .blockExpression
        )
    }

    internal func parseLocalAssignFromTokens(_ tokens: [Token]) -> ExprID? {
        parseLocalAssignFromSlice(tokens[...])
    }

    internal func parseLocalAssignFromSlice(_ tokens: ArraySlice<Token>) -> ExprID? {
        let interner = self.interner
        let astArena = self.astArena
        let context = BuildASTPhase.LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { slice in
                BuildASTPhase.ExpressionParser(tokens: slice, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil }
        )
        return BuildASTPhase.LocalStatementCore.parseLocalAssignment(
            from: tokens,
            context: context,
            options: .blockExpression
        )
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
