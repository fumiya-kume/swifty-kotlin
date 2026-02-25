import Foundation

extension BuildASTPhase.ExpressionParser {
    internal func parseWhenExpression() -> ExprID? {
        guard let whenToken = consume() else {
            return nil
        }
        var subject: ExprID?
        if matches(.symbol(.lParen)) {
            _ = consume()
            subject = parseExpression(minPrecedence: 0)
            _ = consumeIf(.symbol(.rParen))
        }
        guard consumeIf(.symbol(.lBrace)) != nil else {
            return nil
        }

        var branches: [WhenBranch] = []
        var elseExpr: ExprID?
        var end = whenToken.range.end

        while let token = current() {
            if token.kind == .symbol(.rBrace) {
                end = token.range.end
                _ = consume()
                break
            }

            let branchStart = token.range.start
            var conditions: [ExprID] = []
            if token.kind == .keyword(.else) {
                _ = consume()
            } else {
                // Parse first condition
                if let firstCond = parseExpression(minPrecedence: 0) {
                    conditions.append(firstCond)
                }
                // Parse additional comma-separated conditions (before ->)
                while matches(.symbol(.comma)) {
                    _ = consume() // consume comma
                    // If we see '->' after comma, it was a trailing comma; stop
                    if matches(.symbol(.arrow)) {
                        break
                    }
                    if let nextCond = parseExpression(minPrecedence: 0) {
                        conditions.append(nextCond)
                    } else {
                        break
                    }
                }
            }

            _ = consumeIf(.symbol(.arrow))
            let body = parseExpression(minPrecedence: 0)
            while matches(.symbol(.semicolon)) || matches(.symbol(.comma)) {
                _ = consume()
            }

            if let body {
                let branchRange = SourceRange(start: branchStart, end: astArena.exprRange(body)?.end ?? branchStart)
                let branch = WhenBranch(conditions: conditions, body: body, range: branchRange)
                if conditions.isEmpty {
                    elseExpr = body
                } else {
                    branches.append(branch)
                }
                end = branchRange.end
            }
        }

        let range = SourceRange(start: whenToken.range.start, end: end)
        return astArena.appendExpr(.whenExpr(subject: subject, branches: branches, elseExpr: elseExpr, range: range))
    }

    internal func parseReturnExpression() -> ExprID? {
        guard let returnToken = consume() else {
            return nil
        }

        var label: InternedString?
        var end = returnToken.range.end
        if let atToken = current(), atToken.kind == .symbol(.at),
           let labelToken = peek(1),
           let labelName = identifierFromToken(labelToken) {
            _ = consume()
            _ = consume()
            label = labelName
            end = labelToken.range.end
        }

        let value = parseExpression(minPrecedence: 0)
        if let value, let valueEnd = astArena.exprRange(value)?.end {
            end = valueEnd
        }
        let range = SourceRange(start: returnToken.range.start, end: end)
        return astArena.appendExpr(.returnExpr(value: value, label: label, range: range))
    }

    internal func parseThrowExpression() -> ExprID? {
        guard let throwToken = consume() else {
            return nil
        }
        guard let value = parseExpression(minPrecedence: 0) else {
            return nil
        }
        let end = astArena.exprRange(value)?.end ?? throwToken.range.end
        let range = SourceRange(start: throwToken.range.start, end: end)
        return astArena.appendExpr(.throwExpr(value: value, range: range))
    }

    internal func parseForExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let forToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            return nil
        }

        // Check for destructuring: for ((a, b) in iterable)
        if matches(.symbol(.lParen)) {
            let savedIndex = index
            _ = consume() // consume inner `(`

            // Collect names inside parens
            var destructuringNames: [InternedString?] = []
            var foundCloseParen = false
            while let token = current() {
                if token.kind == .symbol(.rParen) {
                    _ = consume()
                    foundCloseParen = true
                    break
                }
                if token.kind == .symbol(.comma) {
                    _ = consume()
                    continue
                }
                if let name = tokenText(token) {
                    let nameStr = interner.resolve(name)
                    if nameStr == "_" {
                        destructuringNames.append(nil)
                    } else {
                        destructuringNames.append(name)
                    }
                    _ = consume()
                    // Skip optional type annotation
                    if matches(.symbol(.colon)) {
                        _ = consume()
                        while let t = current(),
                              t.kind != .symbol(.comma),
                              t.kind != .symbol(.rParen) {
                            _ = consume()
                        }
                    }
                } else {
                    _ = consume()
                }
            }

            if foundCloseParen && !destructuringNames.isEmpty {
                _ = consumeIf(.keyword(.in))
                guard let iterable = parseExpression(minPrecedence: 0) else {
                    index = savedIndex
                    return parseForExpressionFallback(forToken: forToken, label: label, start: start)
                }
                _ = consumeIf(.symbol(.rParen))
                guard let body = parseExpression(minPrecedence: 0) else {
                    index = savedIndex
                    return parseForExpressionFallback(forToken: forToken, label: label, start: start)
                }
                let end = astArena.exprRange(body)?.end ?? forToken.range.end
                let range = SourceRange(start: forToken.range.start, end: end)
                let exprID = astArena.appendExpr(.forDestructuringExpr(
                    names: destructuringNames,
                    iterable: iterable,
                    body: body,
                    range: range
                ))
                if let label {
                    astArena.setLoopLabel(label, for: exprID)
                }
                return exprID
            } else {
                index = savedIndex
            }
        }

        return parseForExpressionFallback(forToken: forToken, label: label, start: start)
    }

    private func parseForExpressionFallback(forToken: Token, label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        var loopVariable: InternedString?
        if let token = current(),
           token.kind != .keyword(.in),
           let name = tokenText(token) {
            loopVariable = name
            _ = consume()
        }

        while let token = current(),
              token.kind != .keyword(.in),
              token.kind != .symbol(.rParen) {
            _ = consume()
        }
        _ = consumeIf(.keyword(.in))

        guard let iterable = parseExpression(minPrecedence: 0) else {
            return nil
        }
        _ = consumeIf(.symbol(.rParen))

        guard let body = parseExpression(minPrecedence: 0) else {
            return nil
        }
        let end = astArena.exprRange(body)?.end ?? forToken.range.end
        let range = SourceRange(start: start ?? forToken.range.start, end: end)
        return astArena.appendExpr(.forExpr(loopVariable: loopVariable, iterable: iterable, body: body, label: label, range: range))
    }

    internal func parseWhileExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let whileToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            return nil
        }
        guard let condition = parseExpression(minPrecedence: 0) else {
            return nil
        }
        _ = consumeIf(.symbol(.rParen))
        guard let body = parseExpression(minPrecedence: 0) else {
            return nil
        }
        let end = astArena.exprRange(body)?.end ?? whileToken.range.end
        let range = SourceRange(start: start ?? whileToken.range.start, end: end)
        return astArena.appendExpr(.whileExpr(condition: condition, body: body, label: label, range: range))
    }

    internal func parseDoWhileExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let doToken = consume() else {
            return nil
        }
        guard let body = parseExpression(minPrecedence: 0) else {
            return nil
        }
        guard matches(.keyword(.while)),
              consume() != nil,
              consumeIf(.symbol(.lParen)) != nil,
              let condition = parseExpression(minPrecedence: 0) else {
            return nil
        }
        _ = consumeIf(.symbol(.rParen))
        let end = astArena.exprRange(condition)?.end ?? astArena.exprRange(body)?.end ?? doToken.range.end
        let range = SourceRange(start: start ?? doToken.range.start, end: end)
        return astArena.appendExpr(.doWhileExpr(body: body, condition: condition, label: label, range: range))
    }

    internal func parseIfExpression() -> ExprID? {
        guard let ifToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            return nil
        }
        guard let condition = parseExpression(minPrecedence: 0) else {
            return nil
        }
        _ = consumeIf(.symbol(.rParen))

        guard let thenExpr = parseExpression(minPrecedence: 0) else {
            return nil
        }

        var elseExpr: ExprID?
        if matches(.keyword(.else)) {
            _ = consume()
            elseExpr = parseExpression(minPrecedence: 0)
        }

        let end = elseExpr
            .flatMap { astArena.exprRange($0)?.end }
            ?? astArena.exprRange(thenExpr)?.end
            ?? ifToken.range.end
        let range = SourceRange(start: ifToken.range.start, end: end)
        return astArena.appendExpr(.ifExpr(condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, range: range))
    }

    internal func parseTryExpression() -> ExprID? {
        guard let tryToken = consume() else {
            return nil
        }
        guard let bodyExpr = parseExpression(minPrecedence: 0) else {
            return nil
        }

        var catchClauses: [CatchClause] = []
        while matches(.keyword(.catch)) {
            let catchToken = consume()!
            let (paramName, paramTypeName) = parseCatchParameter()
            if let catchExpr = parseExpression(minPrecedence: 0) {
                let clauseEnd = astArena.exprRange(catchExpr)?.end ?? catchToken.range.end
                let clauseRange = SourceRange(start: catchToken.range.start, end: clauseEnd)
                catchClauses.append(CatchClause(paramName: paramName, paramTypeName: paramTypeName, body: catchExpr, range: clauseRange))
            } else {
                break
            }
        }

        var finallyExpr: ExprID?
        if matches(.keyword(.finally)) {
            _ = consume()
            finallyExpr = parseExpression(minPrecedence: 0)
        }

        let tailEnd = finallyExpr
            .flatMap { astArena.exprRange($0)?.end }
            ?? catchClauses.last.flatMap { astArena.exprRange($0.body)?.end }
            ?? astArena.exprRange(bodyExpr)?.end
            ?? tryToken.range.end
        let range = SourceRange(start: tryToken.range.start, end: tailEnd)
        return astArena.appendExpr(.tryExpr(body: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, range: range))
    }

    /// Parse a labeled loop: the label name and `@` have already been consumed.
    /// Current token should be `do`, `while`, or `for`.
    internal func parseLabeledLoop(label: InternedString) -> ExprID? {
        guard let token = current() else { return nil }
        let loopExpr: ExprID?
        switch token.kind {
        case .keyword(.do):
            loopExpr = parseDoWhileExpression()
        case .keyword(.while):
            loopExpr = parseWhileExpression()
        case .keyword(.for):
            loopExpr = parseForExpression()
        default:
            // Label@ must be followed by a loop keyword
            return nil
        }
        if let loopExpr {
            astArena.setLoopLabel(label, for: loopExpr)
        }
        return loopExpr
    }

    internal func parseCatchParameter() -> (paramName: InternedString?, paramTypeName: InternedString?) {
        guard matches(.symbol(.lParen)) else {
            return (nil, nil)
        }
        _ = consume()
        var paramName: InternedString?
        var paramTypeName: InternedString?
        if case .identifier(let name) = current()?.kind {
            paramName = name
            _ = consume()
            if matches(.symbol(.colon)) {
                _ = consume()
                if case .identifier(let typeName) = current()?.kind {
                    paramTypeName = typeName
                    _ = consume()
                }
            }
        }
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
        return (paramName, paramTypeName)
    }
}
