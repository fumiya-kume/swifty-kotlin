import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseLambdaLiteral(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard matches(.symbol(.lBrace)) else {
            return nil
        }
        let savedIndex = index
        guard let openBrace = consume() else {
            return nil
        }

        var depth = 1
        var bodyTokens: [Token] = []
        var end = openBrace.range.end
        while let token = current() {
            _ = consume()
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
                bodyTokens.append(token)
            case .symbol(.rBrace):
                depth -= 1
                if depth == 0 {
                    end = token.range.end
                    break
                }
                bodyTokens.append(token)
            default:
                bodyTokens.append(token)
            }
            if depth == 0 {
                break
            }
        }

        guard depth == 0, let arrowIndex = lambdaArrowIndex(in: bodyTokens) else {
            index = savedIndex
            return nil
        }

        let paramTokens = Array(bodyTokens[..<arrowIndex])
        let lambdaBodySlice = bodyTokens[(arrowIndex + 1)...]
        let params = parseLambdaParamNames(from: paramTokens)

        let bodyExpr: ExprID
        if let parsedBody = BuildASTPhase.ExpressionParser(tokens: lambdaBodySlice, interner: interner, astArena: astArena).parse() {
            bodyExpr = parsedBody
        } else {
            let bodyRange = if let first = lambdaBodySlice.first, let last = lambdaBodySlice.last {
                SourceRange(start: first.range.start, end: last.range.end)
            } else {
                SourceRange(start: openBrace.range.end, end: openBrace.range.end)
            }
            bodyExpr = astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: bodyRange))
        }

        let range = SourceRange(start: start ?? openBrace.range.start, end: end)
        return astArena.appendExpr(.lambdaLiteral(params: params, body: bodyExpr, label: label, range: range))
    }

    func parseObjectLiteral() -> ExprID? {
        guard let objectToken = consume() else {
            return nil
        }
        var superTypes: [TypeRefID] = []
        var end = objectToken.range.end

        if consumeIf(.symbol(.colon)) != nil {
            if index > 0 {
                end = tokens[index - 1].range.end
            }
            while true {
                guard let superType = parseTypeReference(current()?.range ?? objectToken.range) else {
                    break
                }
                superTypes.append(superType)
                if index > 0 {
                    end = tokens[index - 1].range.end
                }
                if matches(.symbol(.lParen)) {
                    skipBalancedParenthesisIfNeeded()
                    if index > 0 {
                        end = tokens[index - 1].range.end
                    }
                }
                if consumeIf(.symbol(.comma)) != nil {
                    if index > 0 {
                        end = tokens[index - 1].range.end
                    }
                    continue
                }
                break
            }
        }

        if matches(.symbol(.lBrace)), let openBrace = consume() {
            var depth = 1
            end = openBrace.range.end
            while let token = current() {
                _ = consume()
                switch token.kind {
                case .symbol(.lBrace):
                    depth += 1
                case .symbol(.rBrace):
                    depth -= 1
                default:
                    break
                }
                end = token.range.end
                if depth == 0 {
                    break
                }
            }
        }

        let range = SourceRange(start: objectToken.range.start, end: end)
        return astArena.appendExpr(.objectLiteral(superTypes: superTypes, range: range))
    }

    func parseCallableReferenceWithoutReceiver() -> ExprID? {
        let savedIndex = index
        guard let opToken = consume() else {
            return nil
        }
        guard let memberToken = current(),
              let memberName = tokenText(memberToken)
        else {
            index = savedIndex
            return nil
        }
        _ = consume()
        let range = SourceRange(start: opToken.range.start, end: memberToken.range.end)
        return astArena.appendExpr(.callableRef(receiver: nil, member: memberName, range: range))
    }

    private func lambdaArrowIndex(in tokens: [Token]) -> Int? {
        var depth = BuildASTPhase.BracketDepth()
        var candidate: Int?
        for (idx, token) in tokens.enumerated() {
            if token.kind == .symbol(.arrow), depth.isAtTopLevel {
                candidate = idx
            }
            depth.track(token.kind)
        }
        guard let candidate else {
            return nil
        }
        let parameterTokens = Array(tokens[..<candidate])
        guard isPotentialLambdaParameterList(parameterTokens) else {
            return nil
        }
        return candidate
    }

    private func parseLambdaParamNames(from tokens: [Token]) -> [InternedString] {
        let normalized = stripEnclosingParentheses(from: tokens)
        guard !normalized.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var currentSegment: [Token] = []
        var depth = BuildASTPhase.BracketDepth()
        for token in normalized {
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                    currentSegment = []
                }
                continue
            }
            depth.track(token.kind)
            currentSegment.append(token)
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        var params: [InternedString] = []
        for segment in segments {
            if let token = segment.first(where: { token in
                switch token.kind {
                case .identifier, .backtickedIdentifier:
                    true
                default:
                    false
                }
            }), let name = identifierFromToken(token) {
                params.append(name)
            }
        }
        return params
    }

    private func stripEnclosingParentheses(from tokens: [Token]) -> [Token] {
        guard tokens.count >= 2,
              tokens.first?.kind == .symbol(.lParen),
              tokens.last?.kind == .symbol(.rParen)
        else {
            return tokens
        }

        var depth = 0
        for (idx, token) in tokens.enumerated() {
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0, idx != tokens.count - 1 {
                    return tokens
                }
            default:
                break
            }
        }
        return Array(tokens.dropFirst().dropLast())
    }

    private func isPotentialLambdaParameterList(_ tokens: [Token]) -> Bool {
        var depth = BuildASTPhase.BracketDepth()
        for token in tokens {
            if depth.isAtTopLevel {
                switch token.kind {
                case .keyword(.val), .keyword(.var), .keyword(.fun), .keyword(.return),
                     .keyword(.if), .keyword(.when), .keyword(.for), .keyword(.while),
                     .keyword(.do), .keyword(.try), .keyword(.throw),
                     .keyword(.class), .keyword(.object), .keyword(.interface):
                    return false
                case .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
                     .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
                     .symbol(.semicolon):
                    return false
                default:
                    break
                }
            }
            depth.track(token.kind)
        }
        return true
    }
}
