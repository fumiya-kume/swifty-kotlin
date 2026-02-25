import Foundation

extension BuildASTPhase {
    func isTypeLikeNameToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier:
            return true
        case .keyword(.in):
            return false
        case .keyword:
            return true
        case .softKeyword(.out):
            return false
        case .softKeyword:
            return true
        default:
            return false
        }
    }

    func stripDefaultValue(_ tokens: [Token]) -> [Token] {
        splitDefaultValue(tokens).withoutDefault
    }

    func splitDefaultValue(_ tokens: [Token]) -> (withoutDefault: [Token], defaultTokens: [Token]?) {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                let defaultStart = tokens.index(after: index)
                let trailing = defaultStart < tokens.endIndex ? Array(tokens[defaultStart...]) : []
                return (Array(tokens[..<index]), trailing)
            }
            depth.track(token.kind)
        }
        return (tokens, nil)
    }

    func declarationFunctionName(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }
        if paramsOpenIndex == 0 {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) {
            let token = tokens[index]
            if !isTypeLikeNameToken(token.kind) {
                continue
            }
            if let name = internedIdentifier(from: token, interner: interner) {
                return name
            }
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }),
              paramsOpenIndex > 0 else {
            return nil
        }

        var nameIndex: Int?
        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) {
            if isTypeLikeNameToken(tokens[index].kind) {
                nameIndex = index
                break
            }
        }
        guard let nameIndex else {
            return nil
        }

        var dotIndex: Int?
        var depth = BracketDepth()
        for index in 0..<nameIndex {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0, token.kind == .symbol(.dot) {
                dotIndex = index
            }
        }
        guard let dotIndex else {
            return nil
        }

        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return nil
        }

        let receiverStart = skipBalancedBracket(
            in: tokens, from: funIndex + 1,
            open: .symbol(.lessThan), close: .symbol(.greaterThan)
        )

        if receiverStart >= dotIndex {
            return nil
        }

        let receiverTokens = Array(tokens[receiverStart..<dotIndex])
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationReturnType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let closeParenIndex = firstFunctionParameterCloseParen(in: tokens) else {
            return nil
        }

        var index = closeParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                return nil
            }
            if token.kind == .symbol(.colon) {
                index += 1
                break
            }
            index += 1
        }

        guard index < tokens.count else {
            return nil
        }

        var typeTokens: [Token] = []
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    func declarationPropertyType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        var sawName = false
        var colonIndex: Int?
        for (index, token) in tokens.enumerated() {
            if !sawName {
                switch token.kind {
                case .keyword(.val), .keyword(.var):
                    continue
                default:
                    if isTypeLikeNameToken(token.kind) {
                        sawName = true
                    }
                    continue
                }
            }

            if token.kind == .symbol(.colon) {
                colonIndex = index
                break
            }
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                return nil
            }
            if case .softKeyword(.by) = token.kind {
                return nil
            }
        }

        guard let colonIndex else {
            return nil
        }

        var typeTokens: [Token] = []
        var depth = BracketDepth()
        var index = colonIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.by) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }


    func propertyHeadTokens(
        from nodeID: NodeID,
        in arena: SyntaxArena
    ) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    // Stop before inline `get(`/`set(` accessor keywords so that
                    // type and initializer parsing don't consume accessor tokens.
                    switch token.kind {
                    case .softKeyword(.get), .softKeyword(.set):
                        if let idx = inlineAccessorStartIndex(in: tokens + [token]) {
                            return Array(tokens.prefix(idx))
                        }
                    default:
                        break
                    }
                    tokens.append(token)
                }
            case .node(let childID):
                if arena.node(childID).kind == .block {
                    return tokens
                }
            }
        }
        // Final check: scan collected tokens for inline accessor start.
        if let idx = inlineAccessorStartIndex(in: tokens) {
            return Array(tokens.prefix(idx))
        }
        return tokens
    }

    func firstFunctionParameterCloseParen(in tokens: [Token]) -> Int? {
        guard let openIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        let afterClose = skipBalancedBracket(in: tokens, from: openIndex, open: .symbol(.lParen), close: .symbol(.rParen))
        guard afterClose > openIndex else {
            return nil
        }
        return afterClose - 1
    }

    func parseTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        if tokens.isEmpty {
            return nil
        }

        // Check for intersection type (T & U) at top level
        let intersectionParts = splitIntersectionParts(tokens)
        if intersectionParts.count > 1 {
            var partRefs: [TypeRefID] = []
            for part in intersectionParts {
                guard let ref = parseSingleTypeRef(from: part, interner: interner, astArena: astArena) else {
                    return nil
                }
                partRefs.append(ref)
            }
            return astArena.appendTypeRef(.intersection(parts: partRefs))
        }

        return parseSingleTypeRef(from: tokens, interner: interner, astArena: astArena)
    }

    /// Splits a token stream on top-level `&` tokens for intersection types.
    /// Returns a single-element array (no splitting) if any segment is empty
    /// (e.g. leading/trailing/consecutive `&`).
    private func splitIntersectionParts(_ tokens: [Token]) -> [[Token]] {
        var parts: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for token in tokens {
            depth.track(token.kind)
            if token.kind == .symbol(.amp) && depth.isAtTopLevel {
                guard !current.isEmpty else {
                    // Empty segment (leading or consecutive &) – treat as non-intersection
                    return [tokens]
                }
                parts.append(current)
                current = []
                continue
            }
            current.append(token)
        }
        guard !current.isEmpty else {
            // Trailing & – treat as non-intersection
            return [tokens]
        }
        parts.append(current)
        return parts
    }

    /// Parses a single (non-intersection) type reference from tokens.
    func parseSingleTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        if tokens.isEmpty {
            return nil
        }

        if let funcTypeRef = parseFunctionTypeRef(from: tokens, interner: interner, astArena: astArena) {
            return funcTypeRef
        }

        var path: [InternedString] = []
        var nullable = false
        var typeArgs: [TypeArgRef] = []
        var depth = BracketDepth()
        var angleStartIndex: Int?

        for (index, token) in tokens.enumerated() {
            if depth.angle == 0 && token.kind == .symbol(.lessThan) {
                angleStartIndex = index
            }
            depth.track(token.kind)
            if depth.angle > 0 {
                continue
            }
            if let startIdx = angleStartIndex, token.kind == .symbol(.greaterThan) {
                typeArgs = parseTypeArgRefs(
                    from: Array(tokens[(startIdx + 1)..<index]),
                    interner: interner,
                    astArena: astArena
                )
                angleStartIndex = nil
                continue
            }
            switch token.kind {
            case .symbol(.question):
                nullable = true
            case .symbol(.dot), .symbol(.greaterThan):
                continue
            default:
                if let name = internedIdentifier(from: token, interner: interner),
                   isTypeLikeNameToken(token.kind) {
                    path.append(name)
                }
            }
        }

        guard !path.isEmpty else {
            return nil
        }
        return astArena.appendTypeRef(.named(path: path, args: typeArgs, nullable: nullable))
    }

    func parseTypeArgRefs(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeArgRef] {
        var args: [TypeArgRef] = []
        var current: [Token] = []
        var depth = BracketDepth()

        for token in tokens {
            depth.track(token.kind)
            if token.kind == .symbol(.comma) && depth.isAtTopLevel {
                guard let argRef = parseSingleTypeArgRef(from: current, interner: interner, astArena: astArena) else {
                    return []
                }
                args.append(argRef)
                current = []
                continue
            }
            current.append(token)
        }
        if !current.isEmpty {
            guard let argRef = parseSingleTypeArgRef(from: current, interner: interner, astArena: astArena) else {
                return []
            }
            args.append(argRef)
        }
        return args
    }

    func parseSingleTypeArgRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeArgRef? {
        guard !tokens.isEmpty else { return nil }

        if tokens.count == 1 && tokens[0].kind == .symbol(.star) {
            return .star
        }

        var variance: TypeVariance = .invariant
        var typeTokens = tokens

        if let first = typeTokens.first {
            if case .softKeyword(.out) = first.kind {
                variance = .out
                typeTokens = Array(typeTokens.dropFirst())
            } else if case .keyword(.in) = first.kind {
                variance = .in
                typeTokens = Array(typeTokens.dropFirst())
            }
        }

        guard let innerRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            return nil
        }

        switch variance {
        case .invariant:
            return .invariant(innerRef)
        case .out:
            return .out(innerRef)
        case .in:
            return .in(innerRef)
        }
    }

    func parseFunctionTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard !tokens.isEmpty else { return nil }

        var isSuspend = false
        var startIndex = 0

        if case .keyword(.suspend) = tokens[0].kind {
            isSuspend = true
            startIndex = 1
        } else if case .softKeyword(let kw) = tokens[0].kind, kw.rawValue == "suspend" {
            isSuspend = true
            startIndex = 1
        }

        guard startIndex < tokens.count,
              tokens[startIndex].kind == .symbol(.lParen) else {
            return nil
        }

        let closeIndex = findMatchingCloseParen(in: tokens, from: startIndex)
        guard let closeIndex else { return nil }

        guard closeIndex + 1 < tokens.count,
              tokens[closeIndex + 1].kind == .symbol(.arrow) else {
            return nil
        }

        let paramTokens = Array(tokens[(startIndex + 1)..<closeIndex])
        var paramRefs: [TypeRefID] = []
        var currentParam: [Token] = []
        var depth = BracketDepth()
        for token in paramTokens {
            depth.track(token.kind)
            if token.kind == .symbol(.comma) && depth.isAtTopLevel {
                guard let ref = parseTypeRef(from: currentParam, interner: interner, astArena: astArena) else {
                    return nil
                }
                paramRefs.append(ref)
                currentParam = []
                continue
            }
            currentParam.append(token)
        }
        if !currentParam.isEmpty {
            guard let ref = parseTypeRef(from: currentParam, interner: interner, astArena: astArena) else {
                return nil
            }
            paramRefs.append(ref)
        }

        let returnTokens = Array(tokens[(closeIndex + 2)...])

        guard let returnRef = parseTypeRef(from: returnTokens, interner: interner, astArena: astArena) else {
            return nil
        }

        return astArena.appendTypeRef(.functionType(
            params: paramRefs,
            returnType: returnRef,
            isSuspend: isSuspend,
            nullable: false
        ))
    }

    func findMatchingCloseParen(in tokens: [Token], from openIndex: Int) -> Int? {
        var depth = 0
        for i in openIndex..<tokens.count {
            if tokens[i].kind == .symbol(.lParen) {
                depth += 1
            } else if tokens[i].kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    return i
                }
            }
        }
        return nil
    }

    func isParameterModifierToken(_ token: Token) -> Bool {
        guard case .keyword(let keyword) = token.kind else {
            return false
        }
        switch keyword {
        case .vararg, .crossinline, .noinline:
            return true
        default:
            return false
        }
    }

}
