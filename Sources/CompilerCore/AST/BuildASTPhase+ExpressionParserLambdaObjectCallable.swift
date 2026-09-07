
extension BuildASTPhase.ExpressionParser {
    func parseLambdaLiteral(
        label: InternedString? = nil,
        start: SourceLocation? = nil
    ) -> ExprID? {
        guard matches(.symbol(.lBrace)) else {
            return nil
        }
        let savedIndex = index
        guard let openBrace = consume() else {
            return nil
        }

        let (bodyTokens, end, balanced) = consumeBalancedBraceBody(fallbackEnd: openBrace.range.end)
        guard balanced else {
            index = savedIndex
            return nil
        }

        if let arrowIndex = lambdaArrowIndex(in: bodyTokens) {
            let paramTokens = Array(bodyTokens[..<arrowIndex])
            let lambdaBodySlice = bodyTokens[(arrowIndex + 1)...]

            // Detect lambda destructuring: { (a, b) -> body }
            if let names = extractDestructuringNames(from: paramTokens) {
                let range = SourceRange(start: start ?? openBrace.range.start, end: end)
                return buildDestructuringLambda(
                    names: names, bodySlice: lambdaBodySlice,
                    fallbackStart: openBrace.range.end, range: range, label: label
                )
            }

            let parsedParams = parseLambdaParams(from: paramTokens)
            let bodyExpr = parseLambdaBody(bodySlice: lambdaBodySlice, fallbackStart: openBrace.range.end)
            let range = SourceRange(start: start ?? openBrace.range.start, end: end)
            let lambdaID = astArena.appendExpr(.lambdaLiteral(
                params: parsedParams.map(\.name), body: bodyExpr, label: label, range: range
            ))
            if parsedParams.contains(where: { $0.typeRef != nil }) {
                astArena.setLambdaParamTypeRefs(parsedParams.map(\.typeRef), for: lambdaID)
            }
            return lambdaID
        }

        // No-arrow lambda: `{ body }`.
        //
        // In expression position Kotlin treats bare braces as lambda literals,
        // including zero-argument lambdas like `{ 42 }`. Both trailing-lambda
        // call sites and plain expression contexts accept the same syntax.
        let bodyExpr = parseLambdaBody(bodySlice: bodyTokens[...], fallbackStart: openBrace.range.end)
        let range = SourceRange(start: start ?? openBrace.range.start, end: end)
        return astArena.appendExpr(.lambdaLiteral(params: [], body: bodyExpr, label: label, range: range))
    }

    func parseObjectLiteral() -> ExprID? {
        guard let objectToken = consume() else {
            return nil
        }
        var superTypes: [TypeRefID] = []
        // Only the (at most one) class supertype can carry a constructor
        // call `(args)` — interfaces are listed bare. Kept as a single list
        // rather than per-supertype since that is all `ObjectDecl` needs.
        var superTypeConstructorArgs: [CallArgument] = []
        var end = objectToken.range.end
        var bodyTokens: [Token] = []

        if consumeIf(.symbol(.colon)) != nil {
            while true {
                guard let superType = parseTypeReference(current()?.range ?? objectToken.range) else {
                    break
                }
                superTypes.append(superType)
                if matches(.symbol(.lParen)) {
                    _ = consume()
                    let args = parseCallArguments()
                    _ = consumeIf(.symbol(.rParen))
                    if !args.isEmpty {
                        superTypeConstructorArgs = args
                    }
                }
                if consumeIf(.symbol(.comma)) != nil {
                    continue
                }
                break
            }
            if index > 0 {
                end = tokens[index - 1].range.end
            }
        }

        if matches(.symbol(.lBrace)), let openBrace = consume() {
            (bodyTokens, end, _) = consumeBalancedBraceBody(fallbackEnd: openBrace.range.end)
        }

        let range = SourceRange(start: objectToken.range.start, end: end)
        let declID = parseObjectLiteralDecl(
            superTypes: superTypes,
            superTypeConstructorArgs: superTypeConstructorArgs,
            bodyTokens: bodyTokens,
            range: range
        )
        return astArena.appendExpr(.objectLiteral(superTypes: superTypes, decl: declID, range: range))
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

    /// Consumes tokens up to and including a closing brace matching a
    /// just-consumed opening `{` (depth starts at 1). Returns the tokens
    /// strictly between the braces, the end location reached, and whether
    /// the depth actually returned to 0 before the token stream ran out.
    /// On imbalance, `bodyTokens` holds everything scanned and `end` is the
    /// last token's end (or `fallbackEnd` if nothing was consumed) — the
    /// caller decides whether that's acceptable.
    private func consumeBalancedBraceBody(
        fallbackEnd: SourceLocation
    ) -> (bodyTokens: [Token], end: SourceLocation, balanced: Bool) {
        let bodyStart = index
        var depth = 1
        var end = fallbackEnd
        while let token = current() {
            _ = consume()
            end = token.range.end
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
            default:
                break
            }
            if depth == 0 {
                break
            }
        }
        let bodyEnd = depth == 0 ? index - 1 : index
        return (Array(tokens[bodyStart..<bodyEnd]), end, depth == 0)
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
        guard isPotentialLambdaParameterList(tokens[..<candidate]) else {
            return nil
        }
        return candidate
    }

    struct LambdaParam {
        let name: InternedString
        let typeRef: TypeRefID?
    }

    private func parseLambdaParams(from tokens: [Token]) -> [LambdaParam] {
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

        var params: [LambdaParam] = []
        for segment in segments {
            guard let nameIndex = segment.firstIndex(where: { token in
                switch token.kind {
                case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                    true
                default:
                    false
                }
            }), let name = lambdaParameterName(from: segment[nameIndex]) else {
                continue
            }
            params.append(LambdaParam(
                name: name,
                typeRef: parseLambdaParamTypeAnnotation(in: segment, after: nameIndex)
            ))
        }
        return params
    }

    /// Parses the `: Type` annotation of a lambda parameter segment, if present.
    private func parseLambdaParamTypeAnnotation(in segment: [Token], after nameIndex: Int) -> TypeRefID? {
        let colonIndex = nameIndex + 1
        guard colonIndex < segment.count, segment[colonIndex].kind == .symbol(.colon) else {
            return nil
        }
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
        return TypeRefParserCore.parseTypeRefPrefix(
            segment[(colonIndex + 1)...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics,
            recursionDepth: recursionDepth
        )?.ref
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

    /// Checks whether paramTokens form a `(name, name, ...)` destructuring pattern.
    /// Returns the extracted names (nil for underscore), or nil when not destructuring.
    private func extractDestructuringNames(from paramTokens: [Token]) -> [InternedString?]? {
        let innerTokens = stripEnclosingParentheses(from: paramTokens)
        guard innerTokens.count != paramTokens.count else { return nil }
        let names = parseDestructuringNames(from: innerTokens)
        return names.count >= 2 ? names : nil
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
            case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                guard let name = lambdaParameterName(from: token) else {
                    idx += 1
                    continue
                }
                let nameStr = interner.resolve(name)
                names.append(nameStr == "_" ? nil : name)
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
        let parsedBody = parseLambdaBody(bodySlice: bodySlice, fallbackStart: fallbackStart)
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

    private func isPotentialLambdaParameterList(_ tokens: ArraySlice<Token>) -> Bool {
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

    private func lambdaParameterName(from token: Token) -> InternedString? {
        switch token.kind {
        case let .identifier(name), let .backtickedIdentifier(name):
            name
        case let .keyword(keyword):
            interner.intern(keyword.rawValue)
        case let .softKeyword(keyword):
            interner.intern(keyword.rawValue)
        default:
            nil
        }
    }
}
