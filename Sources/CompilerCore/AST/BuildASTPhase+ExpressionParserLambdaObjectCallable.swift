import Foundation

extension BuildASTPhase.ExpressionParser {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func parseLambdaLiteral(
        label: InternedString? = nil,
        start: SourceLocation? = nil,
        allowImplicitEmptyParams: Bool = false
    ) -> ExprID? {
        guard matches(.symbol(.lBrace)) else {
            return nil
        }
        let savedIndex = index
        guard let openBrace = consume() else { return nil }
        guard let (bodyTokens, end) = collectLambdaBodyTokens(openBrace: openBrace) else {
            index = savedIndex
            return nil
        }
        if let arrowIndex = lambdaArrowIndex(in: bodyTokens) {
            let range = SourceRange(start: start ?? openBrace.range.start, end: end)
            return parseLambdaWithArrow(
                bodyTokens: bodyTokens, arrowIndex: arrowIndex,
                label: label, range: range, fallbackStart: openBrace.range.end
            )
        }
        // No-arrow lambda: { body } — check if body references `it` at the top level,
        // OR if this is explicitly a trailing lambda (which must be a lambda, not a block).
        if allowImplicitEmptyParams || containsImplicitItReference(in: bodyTokens) {
            let bodyExpr = parseLambdaBody(bodySlice: bodyTokens[...], fallbackStart: openBrace.range.end)
            let range = SourceRange(start: start ?? openBrace.range.start, end: end)
            return astArena.appendExpr(.lambdaLiteral(params: [], body: bodyExpr, label: label, range: range))
        }
        index = savedIndex
        return nil
    }

    private func collectLambdaBodyTokens(openBrace: Token) -> (tokens: [Token], end: SourceLocation)? {
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
            if depth == 0 { break }
        }
        return depth == 0 ? (bodyTokens, end) : nil
    }

    private func parseLambdaWithArrow(
        bodyTokens: [Token],
        arrowIndex: Int,
        label: InternedString?,
        range: SourceRange,
        fallbackStart: SourceLocation
    ) -> ExprID {
        let paramTokens = Array(bodyTokens[..<arrowIndex])
        let lambdaBodySlice = bodyTokens[(arrowIndex + 1)...]
        // Detect lambda destructuring: { (a, b) -> body }
        if let names = extractDestructuringNames(from: paramTokens), names.count >= 2 {
            return buildDestructuringLambda(
                names: names, bodySlice: lambdaBodySlice,
                fallbackStart: fallbackStart, range: range, label: label
            )
        }
        let params = parseLambdaParamNames(from: paramTokens)
        let bodyExpr = parseLambdaBody(bodySlice: lambdaBodySlice, fallbackStart: fallbackStart)
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

    // MARK: - Lambda Destructuring Helpers

    /// Checks whether paramTokens form a `(name, name, ...)` destructuring pattern.
    /// Returns the extracted names (nil for underscore), or nil when not destructuring.
    private func extractDestructuringNames(from paramTokens: [Token]) -> [InternedString?]? {
        guard hasBalancedEnclosingParens(paramTokens) else { return nil }
        let innerTokens = Array(paramTokens.dropFirst().dropLast())
        let names = parseDestructuringNames(from: innerTokens)
        return names.count >= 2 ? names : nil
    }

    private func hasBalancedEnclosingParens(_ tokens: [Token]) -> Bool {
        guard tokens.count >= 3,
              tokens.first?.kind == .symbol(.lParen),
              tokens.last?.kind == .symbol(.rParen)
        else { return false }
        var depth = 0
        for (idx, token) in tokens.enumerated() {
            switch token.kind {
            case .symbol(.lParen): depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0, idx != tokens.count - 1 { return false }
            default: break
            }
        }
        return true
    }

    private func parseDestructuringNames(from innerTokens: [Token]) -> [InternedString?] {
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
                names.append(nameStr == "_" ? nil : name)
                idx += 1
            case let .backtickedIdentifier(name):
                names.append(name)
                idx += 1
            default:
                idx = skipTypeAnnotationIfPresent(innerTokens, from: idx)
            }
        }
        return names
    }

    private func skipTypeAnnotationIfPresent(_ tokens: [Token], from startIdx: Int) -> Int {
        var idx = startIdx
        guard idx < tokens.count, tokens[idx].kind == .symbol(.colon) else {
            return idx + 1
        }
        idx += 1
        var typeDepth = BuildASTPhase.BracketDepth()
        while idx < tokens.count {
            let current = tokens[idx]
            if typeDepth.isAtTopLevel, current.kind == .symbol(.comma) { break }
            typeDepth.track(current.kind)
            idx += 1
        }
        return idx
    }

    private func buildDestructuringLambda(
        names: [InternedString?],
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation,
        range: SourceRange,
        label: InternedString?
    ) -> ExprID {
        let parsedBody = parseLambdaBody(bodySlice: bodySlice, fallbackStart: fallbackStart, label: label, range: range)
        let syntheticParam = interner.intern("__destructured_0")
        let nameRefExpr = astArena.appendExpr(.nameRef(syntheticParam, range))
        let destructuringExpr = astArena.appendExpr(.destructuringDecl(
            names: names, isMutable: false, initializer: nameRefExpr, range: range
        ))
        let wrappedBody = astArena.appendExpr(.blockExpr(
            statements: [destructuringExpr], trailingExpr: parsedBody, range: range
        ))
        return astArena.appendExpr(.lambdaLiteral(
            params: [syntheticParam], body: wrappedBody, label: label, range: range
        ))
    }

    /// Scans body tokens for a top-level reference to `it` — the implicit single-parameter name
    /// used by Kotlin's no-arrow lambda syntax (`{ it * 2 }`).
    private func containsImplicitItReference(in tokens: [Token]) -> Bool {
        var braceDepth = 0
        for token in tokens {
            // Only consider identifiers at the top brace level; nested lambdas
            // define their own `it` so we must not look inside them.
            if braceDepth == 0 {
                switch token.kind {
                case let .identifier(name) where interner.resolve(name) == "it":
                    return true
                default:
                    break
                }
            }
            switch token.kind {
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
        }
        return false
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
