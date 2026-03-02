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

        // Check for lambda destructuring: { (a, b) -> body }
        // In Kotlin, parenthesized params in a lambda mean destructuring of a single parameter.
        if let destructuringResult = parseLambdaDestructuringLiteral(
            paramTokens: paramTokens,
            bodySlice: lambdaBodySlice,
            openBrace: openBrace,
            end: end,
            label: label,
            start: start
        ) {
            return destructuringResult
        }

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

    /// Detect and parse lambda destructuring: `{ (a, b) -> body }`
    /// In Kotlin, a parenthesized parameter list in a lambda means the single parameter
    /// is destructured via componentN(). This desugars to:
    ///   `{ __destructured_N -> val (a, b) = __destructured_N; body }`
    // swiftlint:disable:next function_body_length
    private func parseLambdaDestructuringLiteral(
        paramTokens: [Token],
        bodySlice: ArraySlice<Token>,
        openBrace: Token,
        end: SourceLocation,
        label: InternedString?,
        start: SourceLocation?
    ) -> ExprID? {
        // Must start with `(` and end with `)` to be destructuring
        guard paramTokens.count >= 3,
              paramTokens.first?.kind == .symbol(.lParen),
              paramTokens.last?.kind == .symbol(.rParen)
        else {
            return nil
        }

        // Verify the parens are balanced and enclosing
        var depth = 0
        for (idx, token) in paramTokens.enumerated() {
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0, idx != paramTokens.count - 1 {
                    // Closing paren is not at the end — not a simple destructuring
                    return nil
                }
            default:
                break
            }
        }

        // Parse the names inside the parens
        let innerTokens = Array(paramTokens.dropFirst().dropLast())
        var names: [InternedString?] = []
        var idx = 0
        while idx < innerTokens.count {
            let token = innerTokens[idx]
            switch token.kind {
            case .symbol(.comma):
                idx += 1
                continue
            case let .identifier(name):
                let nameStr = interner.resolve(name)
                if nameStr == "_" {
                    names.append(nil)
                } else {
                    names.append(name)
                }
                idx += 1
            case let .backtickedIdentifier(name):
                names.append(name)
                idx += 1
            default:
                // Skip type annotations (`: Type`) after variable names
                if token.kind == .symbol(.colon) {
                    idx += 1
                    var typeDepth = BuildASTPhase.BracketDepth()
                    while idx < innerTokens.count {
                        let t = innerTokens[idx]
                        if typeDepth.isAtTopLevel, t.kind == .symbol(.comma) {
                            break
                        }
                        typeDepth.track(t.kind)
                        idx += 1
                    }
                    continue
                }
                idx += 1
            }
        }

        // Need at least 2 names for destructuring to make sense
        guard names.count >= 2 else {
            return nil
        }

        // Parse the original body expression
        let parsedBody: ExprID
        if let body = BuildASTPhase.ExpressionParser(tokens: bodySlice, interner: interner, astArena: astArena).parse() {
            parsedBody = body
        } else {
            let bodyRange = if let first = bodySlice.first, let last = bodySlice.last {
                SourceRange(start: first.range.start, end: last.range.end)
            } else {
                SourceRange(start: openBrace.range.end, end: openBrace.range.end)
            }
            parsedBody = astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: bodyRange))
        }

        let range = SourceRange(start: start ?? openBrace.range.start, end: end)

        // Create a synthetic parameter name for the single destructured parameter
        let syntheticParamName = interner.intern("__destructured_0")

        // Create a nameRef for the synthetic parameter to use as the destructuring initializer
        let nameRefExpr = astArena.appendExpr(.nameRef(syntheticParamName, range))

        // Create a destructuringDecl: val (a, b) = __destructured_0
        let destructuringExpr = astArena.appendExpr(.destructuringDecl(
            names: names,
            isMutable: false,
            initializer: nameRefExpr,
            range: range
        ))

        // Wrap: destructuringDecl + original body in a blockExpr
        let wrappedBody = astArena.appendExpr(.blockExpr(
            statements: [destructuringExpr],
            trailingExpr: parsedBody,
            range: range
        ))

        return astArena.appendExpr(.lambdaLiteral(
            params: [syntheticParamName],
            body: wrappedBody,
            label: label,
            range: range
        ))
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
